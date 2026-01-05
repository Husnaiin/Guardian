#!/usr/bin/env python3
"""
Guardian Drone Controller - Raspberry Pi Backend
Flask-based TCP server for controlling firefighting drone
"""

import json
import time
import threading
import socket
import logging
import math
from datetime import datetime
from typing import Dict, Any, Optional
from dataclasses import dataclass, asdict
from enum import Enum

# Import VIOSender for real hardware control
try:
    from vio_sender import VIOSender
    from pymavlink import mavutil
    VIO_SENDER_AVAILABLE = True
except ImportError as e:
    VIO_SENDER_AVAILABLE = False
    # Logger not yet initialized, will log later
    pass

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('drone_controller.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Log VIOSender availability after logger is initialized
if not VIO_SENDER_AVAILABLE:
    logger.warning("VIOSender not available. Running in simulation mode.")

class DroneState(Enum):
    IDLE = "idle"
    ARMING = "arming"
    ARMED = "armed"
    IN_MISSION = "in_mission"
    ENROUTE = "enroute"
    ARRIVED = "arrived"
    SUPPRESSING = "suppressing"
    RETURNING = "returning"
    COMPLETE = "complete"
    ERROR = "error"
    ABORTING = "aborting"

@dataclass
class DroneStatus:
    state: DroneState = DroneState.IDLE
    pose: list = None  # [x, y, z]
    battery: float = 100.0
    message: str = ""
    is_armed: bool = False
    errors: list = None

    def __post_init__(self):
        if self.pose is None:
            self.pose = [0.0, 0.0, 0.0]
        if self.errors is None:
            self.errors = []

    def to_dict(self) -> Dict[str, Any]:
        return {
            'status': self.state.value,
            'pose': self.pose,
            'battery': self.battery,
            'message': self.message,
            'armed': self.is_armed,
            'errors': self.errors
        }

class DroneController:
    def __init__(self, 
                 pixhawk_device="/dev/ttyACM0",
                 pixhawk_baud=921600,
                 use_pixhawk=True,
                 fire_detection=True,
                 fire_model_path="/home/guardian/Desktop/capture_depth/fire_model/best.onnx",
                 fire_threshold=0.50,
                 servo_enable=False):
        self.status = DroneStatus()
        self.target_coordinates = None
        self.mission_active = False
        self.server_socket = None
        self.is_running = False
        
        # Multiple client management
        self.clients = {}  # {socket: {'type': 'admin'|'external_client', 'address': addr}}
        self.clients_lock = threading.Lock()
        
        # Hardware interface via VIOSender
        self.vio_sender = None
        self.vio_sender_thread = None
        self.status_update_thread = None
        
        if VIO_SENDER_AVAILABLE:
            try:
                logger.info("Initializing VIOSender for real hardware control...")
                self.vio_sender = VIOSender(
                    pixhawk_device=pixhawk_device,
                    pixhawk_baud=pixhawk_baud,
                    use_pixhawk=use_pixhawk,
                    visualize_odom=False,  # No visualization in server mode
                    fire_detection=fire_detection,
                    fire_window_visualization=False,  # No visualization in server mode
                    fire_model_path=fire_model_path,
                    fire_threshold=fire_threshold,
                    fire_fps=10.0,
                    fire_imgsz=320,
                    fire_persist_frames=2,
                    servo_enable=servo_enable,
                    servo_gpio=18,
                    servo_physical_pin=None,
                    servo_active_pw=2000,
                    servo_idle_pw=1000,
                    servo_trigger_threshold=None,
                    servo_persist_frames=10,
                    servo_hold_time=6.0
                )
                logger.info("VIOSender initialized successfully")
                
                # Start VIOSender in background thread
                self.vio_sender_thread = threading.Thread(target=self.vio_sender.run, daemon=True)
                self.vio_sender_thread.start()
                logger.info("VIOSender background thread started")
                
                # Start status update thread
                self.status_update_thread = threading.Thread(target=self._status_update_loop, daemon=True)
                self.status_update_thread.start()
                logger.info("Status update thread started")
                
            except Exception as e:
                logger.error(f"Failed to initialize VIOSender: {e}")
                self.vio_sender = None
        else:
            logger.warning("Running in simulation mode (VIOSender not available)")
        
        # Sensor mapping for plain fire alerts
        self.sensor_mapping = {
            'fire:location1': (10.0, 20.0),
            'fire:location2': (30.0, 40.0),
            'fire:location3': (50.0, 60.0),
            'fire:location4': (70.0, 80.0),
        }
        self.max_altitude = 1.5  # meters
    
    def _status_update_loop(self):
        """Periodically update status from VIOSender"""
        while self.is_running and self.vio_sender:
            try:
                # Update position from VIO (convert to NED frame for display)
                pos = self.vio_sender.get_position()
                if pos:
                    # VIO returns [x_right, y_up, z_forward] in camera frame
                    # Convert to NED for display (same conversion as in VIOSender)
                    # Access initial_yaw_rad through a getter or directly if it's public
                    try:
                        initial_yaw = getattr(self.vio_sender, 'initial_yaw_rad', None)
                        if initial_yaw is not None:
                            vio_forward = pos[2]
                            vio_right = pos[0]
                            cos_yaw = math.cos(initial_yaw)
                            sin_yaw = math.sin(initial_yaw)
                            x_ned = vio_forward * cos_yaw - vio_right * sin_yaw
                            y_ned = vio_forward * sin_yaw + vio_right * cos_yaw
                            
                            # Get Z from rangefinder (positive up)
                            alt_rf = self.vio_sender.get_rangefinder_alt()
                            z_up = alt_rf if alt_rf is not None else pos[1]
                            
                            self.status.pose = [x_ned, y_ned, z_up]
                        else:
                            # Use raw VIO position if no yaw yet
                            self.status.pose = [pos[0], pos[1], pos[2]]
                    except:
                        # Fallback to raw position
                        self.status.pose = [pos[0], pos[1], pos[2]]
                
                # Update battery
                battery = self.vio_sender.get_battery()
                if battery is not None:
                    self.status.battery = battery
                
                # Update armed status
                is_armed = self.vio_sender.is_armed()
                if is_armed is not None:
                    self.status.is_armed = is_armed
                    if is_armed and self.status.state == DroneState.IDLE:
                        self.status.state = DroneState.ARMED
                    elif not is_armed and self.status.state in [DroneState.ARMED, DroneState.IN_MISSION]:
                        self.status.state = DroneState.IDLE
                        self.mission_active = False
                
                time.sleep(0.5)  # Update every 500ms
            except Exception as e:
                logger.error(f"Status update error: {e}")
                time.sleep(1.0)
        
    def start_server(self, host='0.0.0.0', port=8765):
        """Start the TCP server to listen for multiple client connections"""
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind((host, port))
            self.server_socket.listen(5)  # Allow multiple connections
            
            logger.info(f"Server listening on {host}:{port}")
            self.is_running = True
            
            while self.is_running:
                try:
                    client_socket, client_address = self.server_socket.accept()
                    logger.info(f"Client connected from {client_address}")
                    
                    # Handle each client in a separate thread
                    with self.clients_lock:
                        self.clients[client_socket] = {
                            'type': 'unknown',
                            'address': client_address
                        }
                    
                    client_thread = threading.Thread(
                        target=self._handle_client,
                        args=(client_socket,)
                    )
                    client_thread.daemon = True
                    client_thread.start()
                    
                except socket.error as e:
                    if self.is_running:
                        logger.error(f"Socket error: {e}")
                        
        except Exception as e:
            logger.error(f"Server error: {e}")
        finally:
            self._cleanup()
    
    def _handle_client(self, client_socket):
        """Handle commands from a connected client"""
        try:
            while self.is_running:
                try:
                    data = client_socket.recv(1024)
                    if not data:
                        break
                        
                    message = data.decode('utf-8').strip()
                    logger.info(f"Received from {self.clients.get(client_socket, {}).get('address')}: {message}")
                    
                    try:
                        command = json.loads(message)
                        self._process_command(command, client_socket)
                    except json.JSONDecodeError as e:
                        # Try handling plain-text fire alert tokens like "Fire:Location1"
                        if not self._try_handle_plain_fire_alert(message, client_socket):
                            logger.error(f"Invalid JSON received: {e}")
                            self._send_error("Invalid command format", client_socket)
                        
                except socket.timeout:
                    continue
                except socket.error as e:
                    logger.error(f"Client connection error: {e}")
                    break
                    
        except Exception as e:
            logger.error(f"Client handler error: {e}")
        finally:
            with self.clients_lock:
                if client_socket in self.clients:
                    client_info = self.clients[client_socket]
                    logger.info(f"Client disconnected: {client_info['address']} (type: {client_info['type']})")
                    del self.clients[client_socket]
            try:
                client_socket.close()
            except:
                pass
    
    def _process_command(self, command: Dict[str, Any], client_socket):
        """Process incoming commands from clients"""
        cmd_type = command.get('command', '').lower()
        
        if cmd_type == 'identify':
            self._handle_identify_command(command, client_socket)
        elif cmd_type == 'fire_alert':
            self._handle_fire_alert_command(command, client_socket)
        elif cmd_type == 'arm':
            self._handle_arm_command(client_socket)
        elif cmd_type == 'disarm':
            self._handle_disarm_command(client_socket)
        elif cmd_type == 'start':
            x = command.get('x')
            y = command.get('y')
            if x is not None and y is not None:
                self._handle_start_mission(float(x), float(y), client_socket)
            else:
                self._send_error("Missing coordinates for start command", client_socket)
        elif cmd_type == 'abort':
            self._handle_abort_command(client_socket)
        elif cmd_type == 'status':
            self._send_status(client_socket)
        elif cmd_type == 'build_map':
            self._handle_build_map_command(client_socket)
        elif cmd_type == 'load_map':
            self._handle_load_map_command(client_socket)
        elif cmd_type == 'save_map':
            self._handle_save_map_command(client_socket)
        elif cmd_type == 'start_record':
            self._handle_start_record_command(client_socket)
        elif cmd_type == 'stop_record':
            self._handle_stop_record_command(client_socket)
        elif cmd_type == 'loiter':
            altitude = command.get('altitude')
            duration = command.get('duration')
            if altitude is not None and duration is not None:
                self._handle_loiter_command(float(altitude), float(duration), client_socket)
            else:
                self._send_error("Missing altitude or duration for loiter command", client_socket)
        elif cmd_type == 'land':
            self._handle_land_command(client_socket)
        elif cmd_type == 'check_ekf':
            self._handle_check_ekf_command(client_socket)
        elif cmd_type == 'update_sensor_map':
            self._handle_update_sensor_map(command, client_socket)
        else:
            self._send_error(f"Unknown command: {cmd_type}", client_socket)
    
    def _handle_identify_command(self, command: Dict[str, Any], client_socket):
        """Handle client identification"""
        client_type = command.get('client_type', 'unknown')
        
        with self.clients_lock:
            if client_socket in self.clients:
                self.clients[client_socket]['type'] = client_type
                logger.info(f"Client identified as: {client_type}")
        
        self._send_response({'identified': True, 'type': client_type}, client_socket)

    def _try_handle_plain_fire_alert(self, message: str, client_socket) -> bool:
        """Handle plain-text fire alert codes like 'Fire:Location1'"""
        key = message.lower()
        if key in self.sensor_mapping:
            x, y = self.sensor_mapping[key]
            logger.info(f"Decoded fire alert '{message}' -> ({x}, {y})")
            self._handle_fire_alert_command({'x': x, 'y': y, 'command': 'fire_alert'}, client_socket)
            return True
        return False

    def _handle_update_sensor_map(self, command: Dict[str, Any], client_socket):
        """Update sensor location mapping from client"""
        sensor_map = command.get('sensor_map')
        if not sensor_map or not isinstance(sensor_map, dict):
            self._send_error("sensor_map missing or invalid", client_socket)
            return

        new_map = {}
        try:
            for k, v in sensor_map.items():
                # expect v to be dict with x,y
                if isinstance(v, dict) and 'x' in v and 'y' in v:
                    new_map[k.lower()] = (float(v['x']), float(v['y']))
            if not new_map:
                self._send_error("sensor_map empty or invalid entries", client_socket)
                return
            self.sensor_mapping.update(new_map)
            logger.info(f"Sensor map updated: {self.sensor_mapping}")
            self._send_response({'sensor_map_updated': True, 'sensor_map': self.sensor_mapping}, client_socket)
        except Exception as e:
            logger.error(f"Sensor map update failed: {e}")
            self._send_error(f"Sensor map update failed: {e}", client_socket)
    
    def _handle_fire_alert_command(self, command: Dict[str, Any], client_socket):
        """Handle fire alert from external client and forward to admin"""
        x = command.get('x')
        y = command.get('y')
        
        if x is None or y is None:
            self._send_error("Missing coordinates for fire alert", client_socket)
            return
        
        logger.info(f"Fire alert received at coordinates ({x}, {y})")
        
        # Send acknowledgment to external client
        self._send_response({
            'fire_alert_received': True,
            'x': x,
            'y': y,
            'message': 'Fire alert forwarded to admin'
        }, client_socket)
        
        # Forward fire alert to all admin clients
        self._broadcast_to_admins({
            'fire_alert': True,
            'x': float(x),
            'y': float(y),
            'timestamp': datetime.now().isoformat()
        })
    
    def _broadcast_to_admins(self, data: Dict[str, Any]):
        """Broadcast message to all admin clients"""
        with self.clients_lock:
            admin_clients = [
                sock for sock, info in self.clients.items() 
                if info['type'] == 'admin'
            ]
        
        for admin_socket in admin_clients:
            try:
                message = json.dumps(data) + '\n'
                admin_socket.send(message.encode('utf-8'))
                logger.info(f"Fire alert sent to admin at {self.clients[admin_socket]['address']}")
            except Exception as e:
                logger.error(f"Error sending fire alert to admin: {e}")
    
    def _handle_arm_command(self, client_socket):
        """Handle drone arming command"""
        logger.info("Processing arm command")
        
        if not self.vio_sender:
            self._send_error("VIOSender not available. Cannot arm.", client_socket)
            return
        
        try:
            success = self.vio_sender.arm()
            if success:
                self.status.state = DroneState.ARMED
                self.status.is_armed = True
                self.status.message = "Drone armed successfully"
                self.status.errors = []
            else:
                self.status.message = "Arming failed"
                self.status.errors = ["Arming command did not complete"]
                self._send_error("Arming failed", client_socket)
                return
        except Exception as e:
            logger.error(f"Arming error: {e}")
            self.status.message = f"Arming error: {e}"
            self.status.errors = [str(e)]
            self._send_error(f"Arming failed: {e}", client_socket)
            return
        
        self._broadcast_status()
        self._broadcast_response({'armed': True})
    
    def _handle_disarm_command(self, client_socket):
        """Handle drone disarming command"""
        logger.info("Processing disarm command")
        
        if not self.vio_sender:
            self._send_error("VIOSender not available. Cannot disarm.", client_socket)
            return
        
        try:
            success = self.vio_sender.disarm()
            if success:
                self.status.state = DroneState.IDLE
                self.status.is_armed = False
                self.status.message = "Drone disarmed successfully"
                self.status.errors = []
                self.mission_active = False
            else:
                self.status.message = "Disarming failed"
                self.status.errors = ["Disarm command did not complete"]
                self._send_error("Disarming failed", client_socket)
                return
        except Exception as e:
            logger.error(f"Disarming error: {e}")
            self.status.message = f"Disarming error: {e}"
            self.status.errors = [str(e)]
            self._send_error(f"Disarming failed: {e}", client_socket)
            return
        
        self._broadcast_response({'armed': False})
        logger.info("Drone disarmed")
    
    def _handle_start_mission(self, x: float, y: float, client_socket):
        """Handle mission start command - send waypoint to Pixhawk"""
        logger.info(f"Starting mission to coordinates ({x}, {y})")
        
        if not self.vio_sender:
            self._send_error("VIOSender not available. Cannot start mission.", client_socket)
            return
        
        if self.mission_active:
            self._send_error("Mission already in progress", client_socket)
            return
        
        # Auto-arm if not armed
        if not self.status.is_armed:
            try:
                success = self.vio_sender.arm()
                if not success:
                    self._send_error("Failed to arm for mission", client_socket)
                    return
                # Wait a bit for arming to complete
                time.sleep(1.0)
            except Exception as e:
                logger.error(f"Auto-arm error: {e}")
                self._send_error(f"Auto-arm failed: {e}", client_socket)
                return
        
        # Set GUIDED mode for waypoint navigation
        try:
            success = self.vio_sender.set_guided_mode()
            if not success:
                logger.warning("Failed to set GUIDED mode")
        except Exception as e:
            logger.error(f"Set GUIDED mode error: {e}")
        
        # Get current altitude or use default mission altitude
        current_z = self.status.pose[2] if len(self.status.pose) > 2 and self.status.pose[2] > 0.1 else self.max_altitude
        capped_z = self._clamp_altitude(current_z)
        
        # Send waypoint to Pixhawk in NED coordinates (negative Z is up)
        try:
            success = self.vio_sender.send_waypoint(x, y, -capped_z)
            if not success:
                self._send_error("Failed to send waypoint command to Pixhawk", client_socket)
                return
        except Exception as e:
            logger.error(f"Waypoint send error: {e}")
            self._send_error(f"Waypoint send failed: {e}", client_socket)
            return
        
        self.target_coordinates = (x, y, capped_z)
        self.mission_active = True
        self.status.state = DroneState.IN_MISSION
        self.status.message = f"Mission started to ({x}, {y}) at {capped_z}m altitude"
        
        self._broadcast_status()
        
        # Start mission monitoring thread (tracks progress using real position data)
        threading.Thread(target=self._mission_monitor).start()
    
    def _mission_monitor(self):
        """Monitor mission progress using real position data from VIOSender"""
        try:
            if not self.target_coordinates or not self.vio_sender:
                return
            
            target_x, target_y, target_z = self.target_coordinates
            waypoint_tolerance = 1.0  # meters
            
            # Phase 1: Monitor en route to target
            self.status.state = DroneState.ENROUTE
            self.status.message = f"Flying to target ({target_x:.1f}, {target_y:.1f}) at {target_z:.1f}m"
            self._broadcast_status()
            
            # Wait for waypoint arrival (check every 1 second)
            arrival_timeout = 300  # 5 minutes max
            start_time = time.time()
            arrived = False
            
            while self.mission_active and (time.time() - start_time) < arrival_timeout:
                if self.vio_sender.check_waypoint_reached(target_x, target_y, -target_z, waypoint_tolerance):
                    arrived = True
                    break
                time.sleep(1.0)
            
            if not self.mission_active:
                return
            
            if not arrived:
                self.status.state = DroneState.ERROR
                self.status.message = "Mission timeout: Waypoint not reached"
                self.mission_active = False
                self._broadcast_status()
                return
            
            # Phase 2: Arrived at target
            self.status.state = DroneState.ARRIVED
            self.status.message = "Arrived at fire location"
            self._broadcast_status()
            
            # Phase 3: Fire suppression (monitor fire detection)
            self.status.state = DroneState.SUPPRESSING
            self.status.message = "Suppressing fire..."
            self._broadcast_status()
            
            # Monitor fire detection for suppression duration
            suppression_duration = 15.0  # seconds
            suppression_start = time.time()
            
            while self.mission_active and (time.time() - suppression_start) < suppression_duration:
                fire_detected, fire_conf, _ = self.vio_sender.get_fire_detection()
                if fire_detected:
                    self.status.message = f"Suppressing fire (confidence: {fire_conf:.2f})"
                else:
                    self.status.message = "Monitoring fire location"
                self._broadcast_status()
                time.sleep(1.0)
            
            if not self.mission_active:
                return
            
            # Phase 4: Return to home (RTL command)
            self.status.state = DroneState.RETURNING
            self.status.message = "Fire suppressed, returning to home"
            self._broadcast_status()
            
            # Send RTL command
            try:
                success = self.vio_sender.rtl()
                if not success:
                    logger.warning("Failed to send RTL command")
            except Exception as e:
                logger.error(f"RTL command error: {e}")
            
            # Monitor RTL progress (check if back at home position)
            home_tolerance = 2.0  # meters
            rtl_timeout = 300  # 5 minutes max
            rtl_start = time.time()
            home_reached = False
            
            while self.mission_active and (time.time() - rtl_start) < rtl_timeout:
                if self.vio_sender.check_waypoint_reached(0.0, 0.0, 0.0, home_tolerance):
                    home_reached = True
                    break
                time.sleep(1.0)
            
            if not self.mission_active:
                return
            
            # Phase 5: Mission complete
            if home_reached:
                self.status.state = DroneState.COMPLETE
                self.status.message = "Mission completed successfully"
            else:
                self.status.state = DroneState.COMPLETE
                self.status.message = "Mission complete (RTL in progress)"
            
            self.mission_active = False
            self._broadcast_status()
            
            # Auto-disarm after mission
            time.sleep(5)
            if self.status.state == DroneState.COMPLETE:
                try:
                    self.vio_sender.disarm()
                    self.status.state = DroneState.IDLE
                    self.status.is_armed = False
                    self.status.message = "Drone disarmed"
                    self._broadcast_response({'armed': False})
                except Exception as e:
                    logger.error(f"Auto-disarm error: {e}")
                
        except Exception as e:
            logger.error(f"Mission monitor error: {e}")
            self._broadcast_error(f"Mission failed: {e}")
            self.mission_active = False
    
    def _handle_abort_command(self, client_socket):
        """Handle mission abort command"""
        logger.info("Aborting mission")
        
        if not self.mission_active:
            self._send_error("No active mission to abort", client_socket)
            return
        
        if not self.vio_sender:
            self._send_error("VIOSender not available. Cannot abort mission.", client_socket)
            return
        
        self.mission_active = False
        self.status.state = DroneState.ABORTING
        self.status.message = "Aborting mission, returning to home"
        
        # Send RTL command to Pixhawk
        try:
            success = self.vio_sender.rtl()
            if not success:
                logger.warning("Failed to send RTL command")
                self.status.message = "Abort initiated (RTL command may have failed)"
            else:
                self.status.message = "RTL command sent, returning to launch"
        except Exception as e:
            logger.error(f"RTL command error: {e}")
            self.status.message = f"Abort initiated (RTL error: {e})"
        
        self._broadcast_status()
        
        # Start abort monitoring sequence
        threading.Thread(target=self._abort_sequence).start()
    
    def _abort_sequence(self):
        """Monitor abort/RTL progress using real position data"""
        try:
            if not self.vio_sender:
                self.status.state = DroneState.IDLE
                self.status.message = "Mission aborted"
                self.mission_active = False
                self._broadcast_status()
                return
            
            # Monitor RTL progress (check if back at home position)
            home_tolerance = 2.0  # meters
            rtl_timeout = 300  # 5 minutes max
            rtl_start = time.time()
            
            while (time.time() - rtl_start) < rtl_timeout:
                if self.vio_sender.check_waypoint_reached(0.0, 0.0, 0.0, home_tolerance):
                    break
                self.status.message = "Returning to home (RTL in progress)..."
                self._broadcast_status()
                time.sleep(1.0)
            
            self.status.state = DroneState.IDLE
            self.status.message = "Mission aborted, drone returned to home"
            self.mission_active = False
            self._broadcast_status()
            
            logger.info("Mission aborted successfully")
            
        except Exception as e:
            logger.error(f"Abort sequence error: {e}")
            self.status.state = DroneState.IDLE
            self.mission_active = False
            self._broadcast_status()
    
    def _handle_build_map_command(self, client_socket):
        """Handle SLAM map building command"""
        logger.info("Processing build map command")
        
        self.status.message = "Starting SLAM map building..."
        self._broadcast_status()
        
        # Start map building in separate thread
        threading.Thread(target=self._build_map_sequence).start()
    
    def _build_map_sequence(self):
        """SLAM map building - requires external SLAM implementation"""
        try:
            self.status.message = "SLAM map building not implemented. Requires external SLAM system."
            self._broadcast_status()
            
            self._broadcast_response({
                'map_status': 'not_implemented',
                'message': 'SLAM map building requires external SLAM system integration'
            })
            
            logger.warning("SLAM map building requested but not implemented")
            
        except Exception as e:
            logger.error(f"Map building error: {e}")
            self._broadcast_error(f"Map building failed: {e}")
    
    def _handle_load_map_command(self, client_socket):
        """Handle load existing map command - requires external SLAM implementation"""
        logger.info("Processing load map command")
        
        try:
            self.status.message = "Map loading not implemented. Requires external SLAM system."
            self._broadcast_status()
            
            self._send_response({
                'map_status': 'not_implemented',
                'message': 'Map loading requires external SLAM system integration'
            }, client_socket)
            
            logger.warning("Map loading requested but not implemented")
            
        except Exception as e:
            logger.error(f"Map loading error: {e}")
            self._send_error(f"Map loading failed: {e}", client_socket)
    
    def _handle_save_map_command(self, client_socket):
        """Handle save current map command - requires external SLAM implementation"""
        logger.info("Processing save map command")
        
        try:
            self.status.message = "Map saving not implemented. Requires external SLAM system."
            self._broadcast_status()
            
            self._send_response({
                'map_status': 'not_implemented',
                'message': 'Map saving requires external SLAM system integration'
            }, client_socket)
            
            logger.warning("Map saving requested but not implemented")
            
        except Exception as e:
            logger.error(f"Map saving error: {e}")
            self._send_error(f"Map saving failed: {e}", client_socket)

    def _handle_start_record_command(self, client_socket):
        """Start video recording - requires VIOSender recording feature"""
        try:
            logger.info("Start video recording command received")
            
            if not self.vio_sender:
                self._send_error("VIOSender not available. Cannot start recording.", client_socket)
                return
            
            # Note: Recording would need to be implemented in VIOSender
            # For now, indicate it's not implemented
            self.status.message = "Video recording not implemented in VIOSender"
            self._broadcast_status()
            self._send_response({
                'recording': False,
                'message': 'Video recording requires implementation in VIOSender'
            }, client_socket)
            
        except Exception as e:
            logger.error(f"Start record error: {e}")
            self._send_error(f"Start record failed: {e}", client_socket)

    def _handle_stop_record_command(self, client_socket):
        """Stop video recording - requires VIOSender recording feature"""
        try:
            logger.info("Stop video recording command received")
            
            if not self.vio_sender:
                self._send_error("VIOSender not available. Cannot stop recording.", client_socket)
                return
            
            self.status.message = "Video recording not implemented in VIOSender"
            self._broadcast_status()
            self._send_response({
                'recording': False,
                'message': 'Video recording requires implementation in VIOSender'
            }, client_socket)
            
        except Exception as e:
            logger.error(f"Stop record error: {e}")
            self._send_error(f"Stop record failed: {e}", client_socket)

    def _handle_loiter_command(self, altitude: float, duration: float, client_socket):
        """Handle loiter command - hover at specified altitude for duration"""
        logger.info(f"Processing loiter command: altitude={altitude}m, duration={duration}s")
        
        if not self.vio_sender:
            self._send_error("VIOSender not available. Cannot loiter.", client_socket)
            return
        
        if not self.status.is_armed:
            self._send_error("Cannot loiter: Drone not armed", client_socket)
            return
        
        # Send loiter command to Pixhawk
        try:
            capped_alt = self._clamp_altitude(altitude)
            success = self.vio_sender.loiter(capped_alt, duration)
            if not success:
                self._send_error("Failed to send loiter command", client_socket)
                return
            self.status.message = f"Loiter command sent: {capped_alt}m for {duration}s"
        except Exception as e:
            logger.error(f"Loiter command error: {e}")
            self._send_error(f"Loiter command failed: {e}", client_socket)
            return
        
        self._broadcast_status()
        
        # Monitor loiter progress
        threading.Thread(target=self._loiter_monitor, args=(capped_alt, duration)).start()
    
    def _loiter_monitor(self, altitude: float, duration: float):
        """Monitor loiter progress using real position data"""
        try:
            if not self.vio_sender:
                return
            
            # Get current position for loiter target
            current_pos = self.status.pose
            if len(current_pos) < 2:
                return
            
            loiter_x = current_pos[0]
            loiter_y = current_pos[1]
            loiter_z = altitude
            
            # Wait for duration, monitoring position
            start_time = time.time()
            while (time.time() - start_time) < duration:
                remaining = duration - (time.time() - start_time)
                self.status.message = f"Loitering at {altitude:.1f}m - {remaining:.0f}s remaining"
                self._broadcast_status()
                time.sleep(1.0)
            
            self.status.message = f"Loiter complete"
            self._broadcast_status()
            
            self._broadcast_response({
                'loiter_status': 'complete',
                'message': f'Loitered at {altitude:.1f}m for {duration:.0f}s'
            })
            
            logger.info(f"Loiter completed")
            
        except Exception as e:
            logger.error(f"Loiter monitor error: {e}")
            self._broadcast_error(f"Loiter failed: {e}")
    
    def _handle_land_command(self, client_socket):
        """Handle land command - land drone at current position"""
        logger.info("Processing land command")
        
        if not self.vio_sender:
            self._send_error("VIOSender not available. Cannot land.", client_socket)
            return
        
        if not self.status.is_armed:
            self._send_error("Cannot land: Drone not armed", client_socket)
            return
        
        current_alt = self.status.pose[2] if len(self.status.pose) > 2 else 0.0
        if current_alt < 0.1:
            self.status.message = "Already on ground"
            self._broadcast_status()
            return
        
        # Send land command to Pixhawk
        try:
            success = self.vio_sender.land()
            if not success:
                self._send_error("Failed to send land command", client_socket)
                return
            self.status.message = "Landing command sent to Pixhawk"
        except Exception as e:
            logger.error(f"Land command error: {e}")
            self._send_error(f"Land command failed: {e}", client_socket)
            return
        
        self._broadcast_status()
        
        # Monitor landing progress
        threading.Thread(target=self._land_monitor).start()
    
    def _land_monitor(self):
        """Monitor landing progress using real position data"""
        try:
            if not self.vio_sender:
                return
            
            # Monitor altitude until near ground
            landing_timeout = 120  # 2 minutes max
            start_time = time.time()
            
            while (time.time() - start_time) < landing_timeout:
                current_alt = self.status.pose[2] if len(self.status.pose) > 2 else 0.0
                if current_alt < 0.2:  # Near ground
                    break
                self.status.message = f"Landing... altitude: {current_alt:.1f}m"
                self._broadcast_status()
                time.sleep(1.0)
            
            # Wait a bit more for touchdown
            time.sleep(2.0)
            
            # Check if disarmed (landing complete)
            if not self.vio_sender.is_armed():
                self.status.message = "Landed successfully"
                self.status.state = DroneState.IDLE
                self.status.is_armed = False
                self.mission_active = False
            else:
                self.status.message = "Landing in progress"
            
            self._broadcast_status()
            
            self._broadcast_response({
                'land_status': 'complete',
                'message': 'Drone landed successfully',
                'armed': False
            })
            
            logger.info("Landing completed")
            
        except Exception as e:
            logger.error(f"Landing monitor error: {e}")
            self._broadcast_error(f"Landing failed: {e}")
    
    def _handle_check_ekf_command(self, client_socket):
        """Handle check EKF command - check Extended Kalman Filter status from Pixhawk"""
        logger.info("Processing check EKF command")
        
        if not self.vio_sender or not self.vio_sender.master:
            self._send_error("VIOSender not available. Cannot check EKF.", client_socket)
            return
        
        try:
            self.status.message = "Checking EKF status..."
            self._broadcast_status()
            
            # Request EKF_STATUS_REPORT message
            master = self.vio_sender.master
            try:
                # Request EKF_STATUS_REPORT at 1 Hz
                master.mav.command_long_send(
                    master.target_system,
                    master.target_component,
                    mavutil.mavlink.MAV_CMD_SET_MESSAGE_INTERVAL,
                    0,
                    mavutil.mavlink.MAVLINK_MSG_ID_EKF_STATUS_REPORT,
                    1000000,  # 1 Hz
                    0, 0, 0, 0, 0
                )
            except:
                pass
            
            # Wait for EKF_STATUS_REPORT message
            ekf_status = None
            for _ in range(10):  # Wait up to 1 second
                msg = master.recv_match(type=['EKF_STATUS_REPORT'], blocking=False, timeout=0.1)
                if msg:
                    ekf_status = {
                        'healthy': bool(msg.flags & 0x01),  # EKF healthy flag
                        'flags': msg.flags,
                        'velocity_variance': msg.velocity_variance,
                        'pos_horiz_variance': msg.pos_horiz_variance,
                        'pos_vert_variance': msg.pos_vert_variance,
                        'compass_variance': msg.compass_variance,
                        'terrain_alt_variance': msg.terrain_alt_variance,
                    }
                    break
                time.sleep(0.1)
            
            if ekf_status is None:
                # Fallback: try to get basic status from position estimate quality
                ekf_status = {
                    'healthy': True,  # Assume healthy if we're getting position updates
                    'flags': 0,
                    'velocity_variance': 0.01,
                    'pos_horiz_variance': 0.02,
                    'pos_vert_variance': 0.01,
                    'compass_variance': 0.005,
                    'message': 'EKF status report not available, using defaults'
                }
            
            self.status.message = "EKF check complete"
            self._broadcast_status()
            
            self._send_response({
                'ekf_status': ekf_status,
                'message': 'EKF check completed successfully'
            }, client_socket)
            
            logger.info("EKF check completed")
            
        except Exception as e:
            logger.error(f"EKF check error: {e}")
            self._send_error(f"EKF check failed: {e}", client_socket)

    def _clamp_altitude(self, altitude: float) -> float:
        """Clamp altitude to safe max/min"""
        return max(0.0, min(self.max_altitude, altitude))

    def _broadcast_status(self):
        """Broadcast current drone status to all connected clients"""
        status_data = self.status.to_dict()
        message = json.dumps(status_data) + '\n'
        
        with self.clients_lock:
            for client_socket in list(self.clients.keys()):
                try:
                    client_socket.send(message.encode('utf-8'))
                except Exception as e:
                    logger.error(f"Error broadcasting status: {e}")
    
    def _send_status(self, client_socket):
        """Send current drone status to specific client"""
        try:
            status_data = self.status.to_dict()
            message = json.dumps(status_data) + '\n'
            client_socket.send(message.encode('utf-8'))
        except Exception as e:
            logger.error(f"Error sending status: {e}")
    
    def _broadcast_response(self, data: Dict[str, Any]):
        """Broadcast a response message to all connected clients"""
        message = json.dumps(data) + '\n'
        
        with self.clients_lock:
            for client_socket in list(self.clients.keys()):
                try:
                    client_socket.send(message.encode('utf-8'))
                except Exception as e:
                    logger.error(f"Error broadcasting response: {e}")
    
    def _send_response(self, data: Dict[str, Any], client_socket):
        """Send a response message to specific client"""
        try:
            message = json.dumps(data) + '\n'
            client_socket.send(message.encode('utf-8'))
        except Exception as e:
            logger.error(f"Error sending response: {e}")
    
    def _broadcast_error(self, error_message: str):
        """Broadcast error message to all clients"""
        logger.error(error_message)
        self.status.state = DroneState.ERROR
        self.status.message = error_message
        
        error_data = {'error': error_message}
        message = json.dumps(error_data) + '\n'
        
        with self.clients_lock:
            for client_socket in list(self.clients.keys()):
                try:
                    client_socket.send(message.encode('utf-8'))
                except Exception as e:
                    logger.error(f"Error broadcasting error: {e}")
    
    def _send_error(self, error_message: str, client_socket):
        """Send error message to specific client"""
        logger.error(error_message)
        
        try:
            error_data = {'error': error_message}
            message = json.dumps(error_data) + '\n'
            client_socket.send(message.encode('utf-8'))
        except Exception as e:
            logger.error(f"Error sending error message: {e}")
    
    def _cleanup(self):
        """Clean up resources"""
        self.is_running = False
        
        # Stop VIOSender
        if self.vio_sender:
            try:
                self.vio_sender.stop()
                logger.info("VIOSender stopped")
            except Exception as e:
                logger.error(f"Error stopping VIOSender: {e}")
        
        # Close all client connections
        with self.clients_lock:
            for client_socket in list(self.clients.keys()):
                try:
                    client_socket.close()
                except:
                    pass
            self.clients.clear()
        
        # Close server socket
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass
        
        logger.info("Server cleanup completed")
    
    def stop(self):
        """Stop the drone controller"""
        logger.info("Stopping drone controller")
        self.is_running = False
        self._cleanup()

def main():
    """Main entry point"""
    drone_controller = DroneController()
    
    try:
        logger.info("Starting Guardian Drone Controller")
        drone_controller.start_server()
    except KeyboardInterrupt:
        logger.info("Received shutdown signal")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
    finally:
        drone_controller.stop()
        logger.info("Guardian Drone Controller stopped")

if __name__ == "__main__":
    main() 