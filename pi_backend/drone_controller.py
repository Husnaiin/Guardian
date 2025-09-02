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
from datetime import datetime
from typing import Dict, Any, Optional
from dataclasses import dataclass, asdict
from enum import Enum

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
    def __init__(self):
        self.status = DroneStatus()
        self.target_coordinates = None
        self.mission_active = False
        self.client_socket = None
        self.server_socket = None
        self.is_running = False
        
        # Simulated hardware interface
        self.pixhawk_connected = True
        self.rtab_map_active = False
        
    def start_server(self, host='0.0.0.0', port=8765):
        """Start the TCP server to listen for Flutter app connections"""
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind((host, port))
            self.server_socket.listen(1)
            
            logger.info(f"Server listening on {host}:{port}")
            self.is_running = True
            
            while self.is_running:
                try:
                    client_socket, client_address = self.server_socket.accept()
                    logger.info(f"Client connected from {client_address}")
                    
                    self.client_socket = client_socket
                    self._handle_client()
                    
                except socket.error as e:
                    if self.is_running:
                        logger.error(f"Socket error: {e}")
                        
        except Exception as e:
            logger.error(f"Server error: {e}")
        finally:
            self._cleanup()
    
    def _handle_client(self):
        """Handle commands from the connected Flutter client"""
        try:
            while self.is_running and self.client_socket:
                try:
                    data = self.client_socket.recv(1024)
                    if not data:
                        break
                        
                    message = data.decode('utf-8').strip()
                    logger.info(f"Received: {message}")
                    
                    try:
                        command = json.loads(message)
                        self._process_command(command)
                    except json.JSONDecodeError as e:
                        logger.error(f"Invalid JSON received: {e}")
                        self._send_error("Invalid command format")
                        
                except socket.timeout:
                    continue
                except socket.error as e:
                    logger.error(f"Client connection error: {e}")
                    break
                    
        except Exception as e:
            logger.error(f"Client handler error: {e}")
        finally:
            if self.client_socket:
                self.client_socket.close()
                self.client_socket = None
                logger.info("Client disconnected")
    
    def _process_command(self, command: Dict[str, Any]):
        """Process incoming commands from the Flutter app"""
        cmd_type = command.get('command', '').lower()
        
        if cmd_type == 'arm':
            self._handle_arm_command()
        elif cmd_type == 'disarm':
            self._handle_disarm_command()
        elif cmd_type == 'start':
            x = command.get('x')
            y = command.get('y')
            if x is not None and y is not None:
                self._handle_start_mission(float(x), float(y))
            else:
                self._send_error("Missing coordinates for start command")
        elif cmd_type == 'abort':
            self._handle_abort_command()
        elif cmd_type == 'status':
            self._send_status()
        elif cmd_type == 'build_map':
            self._handle_build_map_command()
        elif cmd_type == 'load_map':
            self._handle_load_map_command()
        elif cmd_type == 'save_map':
            self._handle_save_map_command()
        else:
            self._send_error(f"Unknown command: {cmd_type}")
    
    def _handle_arm_command(self):
        """Handle drone arming command"""
        logger.info("Processing arm command")
        
        if self.status.state != DroneState.IDLE:
            self._send_error("Cannot arm: Drone not in idle state")
            return
        
        self.status.state = DroneState.ARMING
        self.status.message = "Arming drone..."
        self.status.errors = []
        self._send_status()
        
        # Simulate arming process with hardware checks
        threading.Thread(target=self._arm_sequence).start()
    
    def _arm_sequence(self):
        """Simulate the arming sequence with hardware checks"""
        try:
            time.sleep(2)  # Simulate arming time
            
            # Simulate hardware checks
            errors = []
            
            if not self.pixhawk_connected:
                errors.append("Pixhawk not connected")
            
            # Simulate other potential errors
            if self.status.battery < 20:
                errors.append("Battery too low for flight")
                
            # Add more realistic checks here for actual implementation
            # - GPS signal quality
            # - Compass calibration
            # - ESC status
            # - etc.
            
            if errors:
                self.status.state = DroneState.ERROR
                self.status.errors = errors
                self.status.message = f"Arming failed: {', '.join(errors)}"
                self.status.is_armed = False
                self._send_response({'arm_errors': errors})
            else:
                self.status.state = DroneState.ARMED
                self.status.is_armed = True
                self.status.message = "Drone armed successfully"
                logger.info("Drone armed successfully")
                self._send_response({'armed': True})
                
        except Exception as e:
            logger.error(f"Arming sequence error: {e}")
            self._send_error(f"Arming failed: {e}")
    
    def _handle_disarm_command(self):
        """Handle drone disarming command"""
        logger.info("Processing disarm command")
        
        self.status.state = DroneState.IDLE
        self.status.is_armed = False
        self.status.message = "Drone disarmed"
        self.status.errors = []
        self.mission_active = False
        
        self._send_response({'armed': False})
        logger.info("Drone disarmed")
    
    def _handle_start_mission(self, x: float, y: float):
        """Handle mission start command"""
        logger.info(f"Starting mission to coordinates ({x}, {y})")
        
        if not self.status.is_armed:
            self._send_error("Cannot start mission: Drone not armed")
            return
            
        if self.mission_active:
            self._send_error("Mission already in progress")
            return
        
        self.target_coordinates = (x, y)
        self.mission_active = True
        self.status.state = DroneState.IN_MISSION
        self.status.message = f"Mission started to ({x}, {y})"
        
        self._send_status()
        
        # Start mission sequence in separate thread
        threading.Thread(target=self._mission_sequence).start()
    
    def _mission_sequence(self):
        """Simulate the complete mission sequence"""
        try:
            if not self.target_coordinates:
                return
                
            target_x, target_y = self.target_coordinates
            
            # Phase 1: En route to target
            self.status.state = DroneState.ENROUTE
            self.status.message = f"Flying to target ({target_x}, {target_y})"
            self._send_status()
            
            # Simulate flight to target with position updates
            for i in range(10):
                if not self.mission_active:
                    return
                    
                # Simulate position updates during flight
                progress = (i + 1) / 10
                current_x = self.status.pose[0] + (target_x - self.status.pose[0]) * progress
                current_y = self.status.pose[1] + (target_y - self.status.pose[1]) * progress
                current_z = 10.0  # Flight altitude
                
                self.status.pose = [current_x, current_y, current_z]
                self.status.battery -= 1.0  # Simulate battery drain
                
                self._send_status()
                time.sleep(2)
            
            if not self.mission_active:
                return
            
            # Phase 2: Arrived at target
            self.status.state = DroneState.ARRIVED
            self.status.pose = [target_x, target_y, 10.0]
            self.status.message = "Arrived at fire location"
            self._send_status()
            time.sleep(3)
            
            if not self.mission_active:
                return
            
            # Phase 3: Fire suppression
            self.status.state = DroneState.SUPPRESSING
            self.status.message = "Suppressing fire..."
            self._send_status()
            
            # Simulate fire suppression
            for i in range(5):
                if not self.mission_active:
                    return
                self.status.battery -= 2.0
                self._send_status()
                time.sleep(3)
            
            if not self.mission_active:
                return
            
            # Phase 4: Returning home
            self.status.state = DroneState.RETURNING
            self.status.message = "Fire suppressed, returning to home"
            self._send_status()
            
            # Simulate return flight
            for i in range(8):
                if not self.mission_active:
                    return
                    
                progress = (i + 1) / 8
                current_x = target_x + (0 - target_x) * progress
                current_y = target_y + (0 - target_y) * progress
                current_z = 10.0 - (10.0 * progress)  # Descending
                
                self.status.pose = [current_x, current_y, current_z]
                self.status.battery -= 1.0
                
                self._send_status()
                time.sleep(2)
            
            # Phase 5: Mission complete
            if self.mission_active:
                self.status.state = DroneState.COMPLETE
                self.status.pose = [0.0, 0.0, 0.0]
                self.status.message = "Mission completed successfully"
                self.mission_active = False
                self._send_status()
                
                # Auto-disarm after mission
                time.sleep(5)
                if self.status.state == DroneState.COMPLETE:
                    self._handle_disarm_command()
                
        except Exception as e:
            logger.error(f"Mission sequence error: {e}")
            self._send_error(f"Mission failed: {e}")
            self.mission_active = False
    
    def _handle_abort_command(self):
        """Handle mission abort command"""
        logger.info("Aborting mission")
        
        if not self.mission_active:
            self._send_error("No active mission to abort")
            return
        
        self.mission_active = False
        self.status.state = DroneState.ABORTING
        self.status.message = "Aborting mission, returning to home"
        
        self._send_status()
        
        # Start abort sequence
        threading.Thread(target=self._abort_sequence).start()
    
    def _abort_sequence(self):
        """Handle mission abort and return to home"""
        try:
            # Simulate return to home after abort
            for i in range(5):
                progress = (i + 1) / 5
                current_x = self.status.pose[0] * (1 - progress)
                current_y = self.status.pose[1] * (1 - progress)
                current_z = max(0, self.status.pose[2] * (1 - progress))
                
                self.status.pose = [current_x, current_y, current_z]
                self.status.battery -= 1.0
                
                self._send_status()
                time.sleep(2)
            
            self.status.state = DroneState.IDLE
            self.status.message = "Mission aborted, drone returned to home"
            self.status.is_armed = False
            self._send_status()
            
            logger.info("Mission aborted successfully")
            
        except Exception as e:
            logger.error(f"Abort sequence error: {e}")
    
    def _handle_build_map_command(self):
        """Handle SLAM map building command"""
        logger.info("Processing build map command")
        
        self.status.message = "Starting SLAM map building..."
        self._send_status()
        
        # Start map building in separate thread
        threading.Thread(target=self._build_map_sequence).start()
    
    def _build_map_sequence(self):
        """Simulate SLAM map building process"""
        try:
            self.status.message = "Recording SLAM map data..."
            self._send_status()
            
            # Simulate map building process
            for i in range(10):
                time.sleep(2)
                progress = (i + 1) * 10
                self.status.message = f"Building map... {progress}%"
                self._send_status()
            
            self.status.message = "Map built successfully. Ready to save."
            self._send_status()
            
            self._send_response({
                'map_status': 'built',
                'message': 'SLAM map building completed'
            })
            
            logger.info("Map building completed")
            
        except Exception as e:
            logger.error(f"Map building error: {e}")
            self._send_error(f"Map building failed: {e}")
    
    def _handle_load_map_command(self):
        """Handle load existing map command"""
        logger.info("Processing load map command")
        
        try:
            # Simulate loading map from storage
            self.status.message = "Loading saved map..."
            self._send_status()
            
            time.sleep(3)  # Simulate loading time
            
            self.status.message = "Map loaded successfully"
            self._send_status()
            
            self._send_response({
                'map_status': 'loaded',
                'message': 'Saved map loaded from Pi storage'
            })
            
            logger.info("Map loaded successfully")
            
        except Exception as e:
            logger.error(f"Map loading error: {e}")
            self._send_error(f"Map loading failed: {e}")
    
    def _handle_save_map_command(self):
        """Handle save current map command"""
        logger.info("Processing save map command")
        
        try:
            self.status.message = "Saving map to Pi storage..."
            self._send_status()
            
            # Simulate saving map to file
            time.sleep(2)
            
            self.status.message = "Map saved successfully"
            self._send_status()
            
            self._send_response({
                'map_status': 'saved',
                'message': 'Map saved to Raspberry Pi storage'
            })
            
            logger.info("Map saved successfully")
            
        except Exception as e:
            logger.error(f"Map saving error: {e}")
            self._send_error(f"Map saving failed: {e}")
    
    def _send_status(self):
        """Send current drone status to client"""
        if self.client_socket:
            try:
                status_data = self.status.to_dict()
                message = json.dumps(status_data) + '\n'
                self.client_socket.send(message.encode('utf-8'))
            except Exception as e:
                logger.error(f"Error sending status: {e}")
    
    def _send_response(self, data: Dict[str, Any]):
        """Send a response message to client"""
        if self.client_socket:
            try:
                message = json.dumps(data) + '\n'
                self.client_socket.send(message.encode('utf-8'))
            except Exception as e:
                logger.error(f"Error sending response: {e}")
    
    def _send_error(self, error_message: str):
        """Send error message to client"""
        logger.error(error_message)
        self.status.state = DroneState.ERROR
        self.status.message = error_message
        
        if self.client_socket:
            try:
                error_data = {'error': error_message}
                message = json.dumps(error_data) + '\n'
                self.client_socket.send(message.encode('utf-8'))
            except Exception as e:
                logger.error(f"Error sending error message: {e}")
    
    def _cleanup(self):
        """Clean up resources"""
        self.is_running = False
        if self.client_socket:
            self.client_socket.close()
        if self.server_socket:
            self.server_socket.close()
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