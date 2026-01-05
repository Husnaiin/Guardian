#!/usr/bin/env python3
"""
VIOSender - Real VO to Pixhawk sender library for ArduPilot EKF3

- Uses VISION_POSITION_ESTIMATE (the message used in official T265 script)
- X, Y from VO (horizontal only)
- Z from rangefinder (z_ned = -alt_rf)
- Neutral orientation (roll=pitch=yaw=0)
- At ~12 Hz (same as working dummy)

Can be used as a library or standalone script.
"""

import time
import math
import threading
import argparse
from pymavlink import mavutil

# Try to import RealSense and VIO
try:
    import pyrealsense2 as rs
    import numpy as np
    import cv2
    from vio_navigation import VIONavigator
    from collections import deque
    REALSENSE_AVAILABLE = True
except ImportError as e:
    REALSENSE_AVAILABLE = False

# Try to import optional dependencies (checked at runtime)
try:
    from ultralytics import YOLO
    YOLO_AVAILABLE = True
except ImportError:
    YOLO_AVAILABLE = False

try:
    import onnxruntime as ort
    ORT_AVAILABLE = True
except ImportError:
    ORT_AVAILABLE = False

try:
    import pigpio
    PIGPIO_AVAILABLE = True
except ImportError:
    PIGPIO_AVAILABLE = False


class VIOSender:
    """
    VIO to Pixhawk sender library.
    Handles camera/VIO processing, Pixhawk communication, fire detection, and servo control.
    """
    
    def __init__(self, 
                 pixhawk_device="/dev/ttyACM0",
                 pixhawk_baud=921600,
                 use_pixhawk=True,
                 visualize_odom=False,
                 fire_detection=False,
                 fire_window_visualization=False,
                 fire_model_path="/home/guardian/Desktop/capture_depth/fire_model/best.onnx",
                 fire_threshold=0.50,
                 fire_fps=10.0,
                 fire_imgsz=320,
                 fire_persist_frames=2,
                 servo_enable=False,
                 servo_gpio=18,
                 servo_physical_pin=None,
                 servo_active_pw=2000,
                 servo_idle_pw=1000,
                 servo_trigger_threshold=None,
                 servo_persist_frames=10,
                 servo_hold_time=6.0):
        """Initialize VIOSender with configuration"""
        # Store configuration
        self.use_pixhawk = use_pixhawk
        self.visualize_odom = visualize_odom
        self.fire_detection = fire_detection
        self.fire_window_visualization = fire_window_visualization
        self.fire_model_path = fire_model_path
        self.fire_threshold = fire_threshold
        self.fire_fps = fire_fps
        self.fire_imgsz = fire_imgsz
        self.fire_persist_frames = fire_persist_frames
        self.servo_enable = servo_enable
        self.servo_gpio = servo_gpio
        self.servo_physical_pin = servo_physical_pin
        self.servo_active_pw = servo_active_pw
        self.servo_idle_pw = servo_idle_pw
        self.servo_trigger_threshold = servo_trigger_threshold if servo_trigger_threshold is not None else fire_threshold
        self.servo_persist_frames = servo_persist_frames
        self.servo_hold_time = servo_hold_time
        
        # Hardware connections
        self.master = None
        self.camera_pipeline = None
        self.vo = None
        self.pi_servo = None
        
        # Data structures
        self.vio_pos = [0.0, 0.0, 0.0]  # [x_right, y_up, z_forward]
        self.vio_lock = threading.Lock()
        self.vio_trajectory = deque(maxlen=1000) if REALSENSE_AVAILABLE else deque(maxlen=1000)
        self.vio_trajectory_lock = threading.Lock()
        
        # Fire detection
        self.latest_color_frame = None
        self.color_frame_lock = threading.Lock()
        self.fire_detected = False
        self.fire_confidence = 0.0
        self.fire_detections = []
        self.fire_data_lock = threading.Lock()
        
        # Pixhawk data
        self.last_range_m = None
        self.range_lock = threading.Lock()
        self.last_yaw_rad = None
        self.initial_yaw_rad = None
        self.yaw_lock = threading.Lock()
        self.last_battery = 100.0
        self.battery_lock = threading.Lock()
        self.is_armed_flag = False
        self.armed_lock = threading.Lock()
        self.flight_mode = None
        self.flight_mode_lock = threading.Lock()
        
        # Threads
        self.running = False
        self.stop_event = threading.Event()
        
        # Initialize hardware
        self._init_pixhawk(pixhawk_device, pixhawk_baud)
        self._init_camera_vio()
        if self.fire_detection:
            self._init_fire_detection()
        if self.servo_enable:
            self._init_servo()
    
    def _init_pixhawk(self, device, baud):
        """Initialize Pixhawk connection"""
        if not self.use_pixhawk:
            print("Running in VIO-only mode (no Pixhawk connection)")
            self.initial_yaw_rad = 0.0
            return
        
        try:
            print(f"Connecting to Pixhawk on {device} @ {baud}")
            self.master = mavutil.mavlink_connection(
                device,
                baud=baud,
                source_system=200,
                source_component=197
            )
            
            print("Waiting for heartbeat...")
            self.master.wait_heartbeat()
            print(f"Heartbeat from system {self.master.target_system} component {self.master.target_component}")
            
            # Request rangefinder stream
            print("Requesting DISTANCE_SENSOR stream at 10 Hz...")
            try:
                interval_us = int(1_000_000 / 10)
                self.master.mav.command_long_send(
                    self.master.target_system,
                    self.master.target_component,
                    mavutil.mavlink.MAV_CMD_SET_MESSAGE_INTERVAL,
                    0,
                    mavutil.mavlink.MAVLINK_MSG_ID_DISTANCE_SENSOR,
                    interval_us,
                    0, 0, 0, 0, 0
                )
                print("  ✓ Requested DISTANCE_SENSOR at 10 Hz")
            except Exception as e:
                print(f"  ⚠ Could not set message interval ({e}) - falling back to data stream request")
                try:
                    self.master.mav.request_data_stream_send(
                        self.master.target_system,
                        self.master.target_component,
                        mavutil.mavlink.MAV_DATA_STREAM_EXTRA3,
                        10,
                        1
                    )
                    print("  ✓ Requested data stream EXTRA3 at 10 Hz")
                except Exception as inner_e:
                    print(f"  ⚠ Could not request data stream: {inner_e}")
            
            # Request ATTITUDE stream
            print("Requesting ATTITUDE stream at 10 Hz...")
            try:
                interval_us = int(1_000_000 / 10)
                self.master.mav.command_long_send(
                    self.master.target_system,
                    self.master.target_component,
                    mavutil.mavlink.MAV_CMD_SET_MESSAGE_INTERVAL,
                    0,
                    mavutil.mavlink.MAVLINK_MSG_ID_ATTITUDE,
                    interval_us,
                    0, 0, 0, 0, 0
                )
                print("  ✓ Requested ATTITUDE at 10 Hz")
            except Exception as e:
                print(f"  ⚠ Could not set ATTITUDE message interval ({e}) - falling back to data stream request")
                try:
                    self.master.mav.request_data_stream_send(
                        self.master.target_system,
                        self.master.target_component,
                        mavutil.mavlink.MAV_DATA_STREAM_EXTRA1,
                        10,
                        1
                    )
                    print("  ✓ Requested data stream EXTRA1 at 10 Hz")
                except Exception as inner_e:
                    print(f"  ⚠ Could not request data stream: {inner_e}")
            
            # Start background threads
            self._start_pixhawk_threads()
            
        except Exception as e:
            print(f"WARNING: Failed to connect to Pixhawk: {e}")
            self.use_pixhawk = False
            self.initial_yaw_rad = 0.0
    
    def _start_pixhawk_threads(self):
        """Start Pixhawk reader threads"""
        if not self.use_pixhawk or not self.master:
            return
        
        def _rangefinder_reader():
            while not self.stop_event.is_set():
                try:
                    msg = self.master.recv_match(
                        type=['DISTANCE_SENSOR', 'RANGEFINDER'],
                        blocking=True,
                        timeout=0.2
                    )
                    if msg:
                        msg_type = msg.get_type()
                        if msg_type == 'DISTANCE_SENSOR':
                            with self.range_lock:
                                self.last_range_m = msg.current_distance / 100.0
                        elif msg_type == 'RANGEFINDER':
                            with self.range_lock:
                                self.last_range_m = msg.distance
                except Exception:
                    pass
                time.sleep(0.01)
        
        def _yaw_reader():
            while not self.stop_event.is_set():
                try:
                    msg = self.master.recv_match(
                        type=['ATTITUDE'],
                        blocking=True,
                        timeout=0.2
                    )
                    if msg:
                        with self.yaw_lock:
                            self.last_yaw_rad = msg.yaw
                            if self.initial_yaw_rad is None:
                                self.initial_yaw_rad = msg.yaw
                                print(f"Initial yaw captured: {math.degrees(self.initial_yaw_rad):.1f} degrees")
                except Exception:
                    pass
                time.sleep(0.01)
        
        def _battery_reader():
            while not self.stop_event.is_set():
                try:
                    msg = self.master.recv_match(
                        type=['SYS_STATUS', 'BATTERY_STATUS'],
                        blocking=True,
                        timeout=0.5
                    )
                    if msg:
                        msg_type = msg.get_type()
                        if msg_type == 'SYS_STATUS':
                            with self.battery_lock:
                                # battery_remaining is 0-100
                                self.last_battery = float(msg.battery_remaining)
                        elif msg_type == 'BATTERY_STATUS':
                            with self.battery_lock:
                                # battery_remaining is 0-100
                                if hasattr(msg, 'battery_remaining'):
                                    self.last_battery = float(msg.battery_remaining)
                except Exception:
                    pass
                time.sleep(1.0)
        
        def _armed_status_reader():
            while not self.stop_event.is_set():
                try:
                    msg = self.master.recv_match(
                        type=['HEARTBEAT'],
                        blocking=True,
                        timeout=0.5
                    )
                    if msg:
                        with self.armed_lock:
                            # Check if armed (base_mode has MAV_MODE_FLAG_SAFETY_ARMED bit set)
                            self.is_armed_flag = bool(msg.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED)
                        with self.flight_mode_lock:
                            # Extract flight mode from custom_mode
                            # ArduPilot uses custom_mode to store flight mode
                            self.flight_mode = msg.custom_mode
                except Exception:
                    pass
                time.sleep(0.5)
        
        threading.Thread(target=_rangefinder_reader, daemon=True).start()
        threading.Thread(target=_yaw_reader, daemon=True).start()
        threading.Thread(target=_battery_reader, daemon=True).start()
        threading.Thread(target=_armed_status_reader, daemon=True).start()
    
    def _init_camera_vio(self):
        """Initialize RealSense camera and VIO"""
        if not REALSENSE_AVAILABLE:
            print("WARNING: RealSense/VIO not available")
            return
        
        try:
            print("Initializing RealSense camera and VO...")
            camera_connected = False
            import gc
            while not camera_connected:
                try:
                    time.sleep(0.5)
                    gc.collect()
                    
                    pipeline = rs.pipeline()
                    config = rs.config()
                    
                    WIDTH, HEIGHT, FPS = 424, 240, 15
                    config.disable_all_streams()
                    config.enable_stream(rs.stream.depth, WIDTH, HEIGHT, rs.format.z16, FPS)
                    config.enable_stream(rs.stream.color, WIDTH, HEIGHT, rs.format.bgr8, FPS)
                    
                    print(f"  Starting pipeline at {WIDTH}x{HEIGHT} @ {FPS} FPS...")
                    profile = pipeline.start(config)
                    self.camera_pipeline = pipeline
                    
                    depth_sensor = profile.get_device().first_depth_sensor()
                    depth_scale = depth_sensor.get_depth_scale()
                    
                    color_stream = profile.get_stream(rs.stream.color)
                    camera_intrinsics = color_stream.as_video_stream_profile().get_intrinsics()
                    
                    camera_connected = True
                    
                except Exception as e:
                    print(f"  Failed to start pipeline: {e}")
                    time.sleep(0.5)
                    gc.collect()
            
            print(f"  ✓ Pipeline started")
            print(f"  Depth scale: {depth_scale}")
            
            # Warm up camera
            print(f"  Warming up camera (30 frames)...")
            for i in range(30):
                pipeline.wait_for_frames(timeout_ms=2000)
            print(f"  ✓ Camera warmed up")
            
            # Initialize VIO
            self.vo = VIONavigator(feature_mode='sift', use_imu_validation=False)
            self.vo.set_camera_intrinsics(camera_intrinsics, depth_scale)
            print("  ✓ VIO navigator initialized")
            
            # Initialize trajectory
            if self.visualize_odom:
                with self.vio_trajectory_lock:
                    self.vio_trajectory.append([0.0, 0.0, 0.0])
            
            # Start VO processing thread
            self._start_vo_thread()
            
        except Exception as e:
            print(f"WARNING: Failed to initialize camera/VO: {e}")
            import traceback
            traceback.print_exc()
            if self.camera_pipeline:
                try:
                    self.camera_pipeline.stop()
                except:
                    pass
                self.camera_pipeline = None
    
    def _start_vo_thread(self):
        """Start VIO processing thread"""
        if not self.camera_pipeline or not self.vo:
            return
        
        def _vo_processor():
            while not self.stop_event.is_set():
                try:
                    frames = self.camera_pipeline.wait_for_frames(timeout_ms=1000)
                    depth_frame = frames.get_depth_frame()
                    color_frame = frames.get_color_frame()
                    
                    if depth_frame and color_frame:
                        depth_image = np.asanyarray(depth_frame.get_data())
                        color_image = np.asanyarray(color_frame.get_data())
                        
                        # Share color frame with fire detection
                        if self.fire_detection:
                            with self.color_frame_lock:
                                self.latest_color_frame = color_image.copy()
                        
                        # Process with VIO
                        pos, vel, _, _, _, _, _ = self.vo.process_frame(
                            color_image, depth_image, record_viz=False, imu_data=None
                        )
                        
                        if pos is not None:
                            with self.vio_lock:
                                self.vio_pos = pos.copy()
                            
                            if self.visualize_odom:
                                with self.vio_trajectory_lock:
                                    self.vio_trajectory.append(pos.copy())
                except Exception:
                    pass
                time.sleep(0.05)  # ~20 Hz
        
        threading.Thread(target=_vo_processor, daemon=True).start()
        print("✓ VO processing started")
    
    def _init_fire_detection(self):
        """Initialize fire detection"""
        if not REALSENSE_AVAILABLE:
            return
        
        use_onnx = str(self.fire_model_path).lower().endswith(".onnx")
        
        fire_model = None
        fire_ort_sess = None
        fire_ort_in = None
        fire_ort_out = None
        
        try:
            if use_onnx:
                if not ORT_AVAILABLE:
                    print("WARNING: ONNX Runtime not available for fire detection")
                    return
                fire_ort_sess = ort.InferenceSession(self.fire_model_path, providers=["CPUExecutionProvider"])
                fire_ort_in = fire_ort_sess.get_inputs()[0].name
                fire_ort_out = fire_ort_sess.get_outputs()[0].name
                print(f"  ✓ Using ONNX Runtime model: {self.fire_model_path}")
            else:
                if not YOLO_AVAILABLE:
                    print("WARNING: Ultralytics YOLO not available for fire detection")
                    return
                fire_model = YOLO(self.fire_model_path)
                print(f"  ✓ Using Ultralytics model: {self.fire_model_path}")
            
            def _nms_xyxy(boxes, scores, iou_thr=0.45):
                if boxes.shape[0] == 0:
                    return []
                idxs = scores.argsort()[::-1]
                keep = []
                while idxs.size > 0:
                    i = int(idxs[0])
                    keep.append(i)
                    if idxs.size == 1:
                        break
                    rest = idxs[1:]
                    xx1 = np.maximum(boxes[i, 0], boxes[rest, 0])
                    yy1 = np.maximum(boxes[i, 1], boxes[rest, 1])
                    xx2 = np.minimum(boxes[i, 2], boxes[rest, 2])
                    yy2 = np.minimum(boxes[i, 3], boxes[rest, 3])
                    w = np.maximum(0.0, xx2 - xx1)
                    h = np.maximum(0.0, yy2 - yy1)
                    inter = w * h
                    a1 = (boxes[i, 2] - boxes[i, 0]) * (boxes[i, 3] - boxes[i, 1])
                    a2 = (boxes[rest, 2] - boxes[rest, 0]) * (boxes[rest, 3] - boxes[rest, 1])
                    iou = inter / (a1 + a2 - inter + 1e-9)
                    idxs = rest[iou <= iou_thr]
                return keep
            
            def _fire_detector():
                while not self.stop_event.is_set():
                    try:
                        with self.color_frame_lock:
                            if self.latest_color_frame is None:
                                time.sleep(0.2)
                                continue
                            frame = self.latest_color_frame.copy()
                        
                        detected_now = False
                        best_conf = 0.0
                        detections = []
                        
                        if use_onnx:
                            h0, w0 = frame.shape[:2]
                            img = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                            img = cv2.resize(img, (320, 320), interpolation=cv2.INTER_LINEAR)
                            img = (img.astype(np.float32) / 255.0).transpose(2, 0, 1)[None, ...]
                            
                            out = fire_ort_sess.run([fire_ort_out], {fire_ort_in: img})[0]
                            pred = out[0]
                            scores = pred[:, 4]
                            mask = scores >= float(self.fire_threshold)
                            pred = pred[mask]
                            
                            if pred.shape[0] > 0:
                                boxes = pred[:, 0:4].copy()
                                scores = pred[:, 4].copy()
                                clss = pred[:, 5].astype(np.int32)
                                
                                sx = w0 / 320.0
                                sy = h0 / 320.0
                                boxes[:, [0, 2]] *= sx
                                boxes[:, [1, 3]] *= sy
                                
                                keep = _nms_xyxy(boxes, scores, iou_thr=0.45)
                                for i in keep:
                                    conf = float(scores[i])
                                    if conf > best_conf:
                                        best_conf = conf
                                    detected_now = True
                                    x1, y1, x2, y2 = boxes[i]
                                    cls = int(clss[i])
                                    detections.append((int(x1), int(y1), int(x2), int(y2), conf, str(cls)))
                        else:
                            results = fire_model.predict(
                                source=frame,
                                conf=self.fire_threshold,
                                imgsz=self.fire_imgsz,
                                verbose=False,
                                device="cpu",
                            )
                            for r in results:
                                for box in r.boxes:
                                    conf = float(box.conf[0])
                                    if conf > best_conf:
                                        best_conf = conf
                                    detected_now = True
                                    x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
                                    cls = int(box.cls[0]) if box.cls is not None else 0
                                    cls_name = fire_model.names.get(cls, str(cls))
                                    detections.append((x1, y1, x2, y2, conf, cls_name))
                        
                        with self.fire_data_lock:
                            self.fire_detected = detected_now
                            self.fire_confidence = best_conf
                            self.fire_detections = detections
                    
                    except Exception:
                        time.sleep(0.1)
                    
                    time.sleep(1.0 / max(0.1, self.fire_fps))
            
            threading.Thread(target=_fire_detector, daemon=True).start()
            print(f"✓ Fire detection processing started at {self.fire_fps} Hz")
            
        except Exception as e:
            print(f"WARNING: Failed to initialize fire detection: {e}")
            import traceback
            traceback.print_exc()
    
    def _init_servo(self):
        """Initialize servo control"""
        if not PIGPIO_AVAILABLE:
            print("WARNING: pigpio not available. Servo disabled.")
            self.servo_enable = False
            return
        
        try:
            print("Initializing servo control...")
            self.pi_servo = pigpio.pi()
            if not self.pi_servo.connected:
                print("WARNING: pigpio daemon not running. Servo disabled.")
                print("  Start it: sudo pigpiod")
                self.servo_enable = False
                return
            
            # Map physical pin to BCM if needed
            if self.servo_physical_pin is not None:
                phys_to_bcm = {
                    3: 2, 5: 3, 7: 4, 8: 14, 10: 15,
                    11: 17, 12: 18, 13: 27, 15: 22,
                    16: 23, 18: 24, 19: 10, 21: 9, 22: 25, 23: 11, 24: 8, 26: 7,
                    29: 5, 31: 6, 32: 12, 33: 13, 35: 19, 36: 16, 37: 26, 38: 20, 40: 21,
                }
                if self.servo_physical_pin in phys_to_bcm:
                    self.servo_gpio = phys_to_bcm[self.servo_physical_pin]
                    print(f"  Using physical pin {self.servo_physical_pin} -> BCM GPIO {self.servo_gpio}")
            
            self.pi_servo.set_mode(self.servo_gpio, pigpio.OUTPUT)
            self.pi_servo.set_servo_pulsewidth(self.servo_gpio, self.servo_idle_pw)
            print(f"  ✓ Servo ready on GPIO {self.servo_gpio}")
            
            def _servo_controller():
                consecutive = 0
                active_until = 0.0
                while not self.stop_event.is_set():
                    try:
                        now = time.time()
                        with self.fire_data_lock:
                            conf = float(self.fire_confidence)
                            fire_now = conf >= float(self.servo_trigger_threshold)
                        
                        if fire_now:
                            consecutive += 1
                        else:
                            consecutive = 0
                        
                        if consecutive >= int(self.servo_persist_frames):
                            active_until = now + float(self.servo_hold_time)
                            consecutive = 0
                            print("== FIRE PERSISTENT: ACTIVATING SERVO ==")
                        
                        if now < active_until:
                            self.pi_servo.set_servo_pulsewidth(self.servo_gpio, self.servo_active_pw)
                        else:
                            self.pi_servo.set_servo_pulsewidth(self.servo_gpio, self.servo_idle_pw)
                    except Exception:
                        pass
                    time.sleep(0.05)
            
            threading.Thread(target=_servo_controller, daemon=True).start()
            print("✓ Servo control thread started")
            
        except Exception as e:
            print(f"WARNING: Failed to initialize servo: {e}")
            self.servo_enable = False
    
    # ==================== Public API Methods ====================
    
    def get_position(self):
        """Get current VIO position [x_right, y_up, z_forward] in meters"""
        with self.vio_lock:
            return self.vio_pos.copy()
    
    def get_battery(self):
        """Get battery percentage (0-100)"""
        with self.battery_lock:
            return self.last_battery
    
    def is_armed(self):
        """Check if drone is armed"""
        with self.armed_lock:
            return self.is_armed_flag
    
    def get_rangefinder_alt(self):
        """Get rangefinder altitude in meters (UP direction)"""
        with self.range_lock:
            return self.last_range_m
    
    def get_yaw(self):
        """Get current yaw from Pixhawk in radians"""
        with self.yaw_lock:
            return self.last_yaw_rad
    
    def get_fire_detection(self):
        """Get fire detection status: (detected: bool, confidence: float, detections: list)"""
        with self.fire_data_lock:
            return (self.fire_detected, self.fire_confidence, self.fire_detections.copy())
    
    def get_flight_mode(self):
        """Get current flight mode (ArduPilot custom_mode value)"""
        with self.flight_mode_lock:
            return self.flight_mode
    
    def set_flight_mode(self, mode):
        """
        Set flight mode using pymavlink mode_mapping
        mode can be a string like 'GUIDED', 'AUTO', 'RTL', 'LAND', 'LOITER'
        or a mode ID from mode_mapping()
        """
        if not self.use_pixhawk or not self.master:
            return False
        
        try:
            # Use pymavlink's mode_mapping to get mode ID
            mode_mapping = self.master.mode_mapping()
            if isinstance(mode, str):
                if mode not in mode_mapping:
                    print(f"Unknown flight mode: {mode}")
                    return False
                mode_id = mode_mapping[mode]
            else:
                mode_id = mode
            
            # Set mode using set_mode helper (handles base_mode automatically)
            self.master.set_mode(mode_id)
            return True
        except Exception as e:
            print(f"Error setting flight mode: {e}")
            return False
    
    def set_guided_mode(self):
        """Set flight mode to GUIDED"""
        return self.set_flight_mode('GUIDED')
    
    def check_waypoint_reached(self, target_x, target_y, target_z, tolerance=1.0):
        """
        Check if current position is within tolerance of target waypoint
        Returns True if within tolerance, False otherwise
        """
        pos = self.get_position()
        if not pos:
            return False
        
        # Get current position in NED frame (same as waypoint)
        initial_yaw = self.initial_yaw_rad
        if initial_yaw is None:
            return False
        
        # Convert VIO position to NED
        vio_forward = pos[2]
        vio_right = pos[0]
        cos_yaw = math.cos(initial_yaw)
        sin_yaw = math.sin(initial_yaw)
        current_x_ned = vio_forward * cos_yaw - vio_right * sin_yaw
        current_y_ned = vio_forward * sin_yaw + vio_right * cos_yaw
        
        # Get Z from rangefinder
        alt_rf = self.get_rangefinder_alt()
        current_z_ned = -alt_rf if alt_rf is not None else pos[1]
        
        # Calculate distance
        dx = target_x - current_x_ned
        dy = target_y - current_y_ned
        dz = target_z - current_z_ned
        distance = math.sqrt(dx*dx + dy*dy + dz*dz)
        
        return distance <= tolerance
    
    def arm(self):
        """Arm the drone via MAVLink"""
        if not self.use_pixhawk or not self.master:
            return False
        
        try:
            self.master.arducopter_arm()
            print("Arming command sent")
            # Wait for confirmation
            for _ in range(50):  # 5 seconds max
                if self.is_armed():
                    return True
                time.sleep(0.1)
            return False
        except Exception as e:
            print(f"Error arming: {e}")
            return False
    
    def disarm(self):
        """Disarm the drone via MAVLink"""
        if not self.use_pixhawk or not self.master:
            return False
        
        try:
            self.master.arducopter_disarm()
            print("Disarm command sent")
            # Wait for confirmation
            for _ in range(50):  # 5 seconds max
                if not self.is_armed():
                    return True
                time.sleep(0.1)
            return False
        except Exception as e:
            print(f"Error disarming: {e}")
            return False
    
    def send_waypoint(self, x, y, z, frame=mavutil.mavlink.MAV_FRAME_LOCAL_NED):
        """Send waypoint command to Pixhawk (NED coordinates)"""
        if not self.use_pixhawk or not self.master:
            return False
        
        try:
            # Use SET_POSITION_TARGET_LOCAL_NED for GUIDED mode
            self.master.mav.set_position_target_local_ned_send(
                0,  # time_boot_ms (not used)
                self.master.target_system,
                self.master.target_component,
                frame,
                0b110111111000,  # type_mask (ignore velocity, accel, yaw_rate, use position + yaw)
                x, y, z,  # position in NED
                0, 0, 0,  # velocity
                0, 0, 0,  # acceleration
                0, 0  # yaw, yaw_rate
            )
            return True
        except Exception as e:
            print(f"Error sending waypoint: {e}")
            return False
    
    def land(self):
        """Send land command"""
        if not self.use_pixhawk or not self.master:
            return False
        
        try:
            self.master.mav.command_long_send(
                self.master.target_system,
                self.master.target_component,
                mavutil.mavlink.MAV_CMD_NAV_LAND,
                0,
                0, 0, 0, 0, 0, 0, 0
            )
            return True
        except Exception as e:
            print(f"Error sending land command: {e}")
            return False
    
    def loiter(self, altitude, duration=None):
        """Send loiter command at specified altitude"""
        if not self.use_pixhawk or not self.master:
            return False
        
        try:
            if duration is not None:
                # Loiter for specific duration
                self.master.mav.command_long_send(
                    self.master.target_system,
                    self.master.target_component,
                    mavutil.mavlink.MAV_CMD_NAV_LOITER_TIME,
                    0,
                    duration, 0, 0, 0, 0, 0, altitude
                )
            else:
                # Loiter indefinitely at altitude
                self.send_waypoint(0, 0, -altitude)  # NED: negative is up
            return True
        except Exception as e:
            print(f"Error sending loiter command: {e}")
            return False
    
    def rtl(self):
        """Send Return to Launch (RTL) command"""
        if not self.use_pixhawk or not self.master:
            return False
        
        try:
            self.master.mav.command_long_send(
                self.master.target_system,
                self.master.target_component,
                mavutil.mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH,
                0,
                0, 0, 0, 0, 0, 0, 0
            )
            return True
        except Exception as e:
            print(f"Error sending RTL command: {e}")
            return False
    
    def send_vision_pose(self):
        """Send VISION_POSITION_ESTIMATE to Pixhawk (called automatically in run loop)"""
        if not self.use_pixhawk or not self.master:
            return
        
        t_usec = int(time.time() * 1e6)
        
        initial_yaw = self.initial_yaw_rad
        if initial_yaw is None:
            return
        
        with self.vio_lock:
            vio_forward = self.vio_pos[2]
            vio_right = self.vio_pos[0]
        
        cos_yaw = math.cos(initial_yaw)
        sin_yaw = math.sin(initial_yaw)
        x_ned = vio_forward * cos_yaw - vio_right * sin_yaw
        y_ned = vio_forward * sin_yaw + vio_right * cos_yaw
        
        alt_rf = self.get_rangefinder_alt()
        z_ned = -alt_rf if alt_rf is not None else 0.0
        
        yaw = self.get_yaw()
        if yaw is None:
            yaw = 0.0
        
        cov = [float('nan')] * 21
        cov[0] = 0.05
        cov[6] = 0.05
        cov[11] = 0.05
        cov[15] = 0.5
        cov[18] = 0.5
        cov[20] = 1.0
        
        self.master.mav.vision_position_estimate_send(
            t_usec,
            x_ned, y_ned, z_ned,
            0.0, 0.0, yaw,
            cov
        )
    
    def send_heartbeat(self):
        """Send heartbeat to Pixhawk"""
        if not self.use_pixhawk or not self.master:
            return
        
        self.master.mav.heartbeat_send(
            mavutil.mavlink.MAV_TYPE_ONBOARD_CONTROLLER,
            mavutil.mavlink.MAV_AUTOPILOT_GENERIC,
            0, 0, 0
        )
    
    def run(self):
        """Main run loop (blocks until stop_event is set)"""
        if self.use_pixhawk:
            print("Starting real VO external vision: ~12 Hz VISION_POSITION_ESTIMATE")
            print("Waiting for initial yaw capture...")
            while self.initial_yaw_rad is None and not self.stop_event.is_set():
                time.sleep(0.1)
            if self.stop_event.is_set():
                return
            print("Initial yaw captured, starting vision stream...")
        
        if self.visualize_odom and REALSENSE_AVAILABLE:
            cv2.namedWindow('VIO Trajectory', cv2.WINDOW_AUTOSIZE)
        
        if self.fire_window_visualization and self.fire_detection and REALSENSE_AVAILABLE:
            cv2.namedWindow('Fire Detection', cv2.WINDOW_AUTOSIZE)
        
        self.running = True
        last_hb = 0.0
        last_viz_update = 0.0
        
        try:
            period = 1.0 / 12.0
            while not self.stop_event.is_set():
                start = time.time()
                
                self.send_vision_pose()
                
                now = time.time()
                if now - last_hb > 1.0:
                    self.send_heartbeat()
                    last_hb = now
                
                if (self.visualize_odom or self.fire_window_visualization) and REALSENSE_AVAILABLE and now - last_viz_update > 0.1:
                    last_viz_update = now
                    self._update_visualizations()
                
                dt = time.time() - start
                if dt < period:
                    time.sleep(period - dt)
        
        except KeyboardInterrupt:
            self.stop_event.set()
        finally:
            self.cleanup()
    
    def _update_visualizations(self):
        """Update visualization windows"""
        if not REALSENSE_AVAILABLE:
            return
        
        if self.visualize_odom:
            with self.vio_lock:
                current_pos = self.vio_pos.copy()
            with self.vio_trajectory_lock:
                if len(self.vio_trajectory) > 0:
                    traj_plot = self._create_trajectory_plot(self.vio_trajectory, current_pos)
                    alt_rf = self.get_rangefinder_alt()
                    if alt_rf is not None:
                        font = cv2.FONT_HERSHEY_SIMPLEX
                        cv2.putText(traj_plot, f"Rangefinder: {alt_rf:.2f}m",
                                  (10, 490), font, 0.4, (255, 0, 0), 2)
                    cv2.imshow('VIO Trajectory', traj_plot)
        
        if self.fire_window_visualization and self.fire_detection:
            with self.color_frame_lock:
                if self.latest_color_frame is not None:
                    display_frame = self.latest_color_frame.copy()
                    with self.fire_data_lock:
                        is_fire = self.fire_detected
                        confidence = self.fire_confidence
                        detections = self.fire_detections.copy()
                    
                    for det in detections:
                        if len(det) == 6:
                            x1, y1, x2, y2, conf, cls_name = det
                        else:
                            x1, y1, x2, y2, conf = det
                            cls_name = "Fire"
                        cv2.rectangle(display_frame, (x1, y1), (x2, y2), (0, 0, 255), 2)
                        cv2.putText(display_frame, f"{cls_name} {conf:.2f}",
                                  (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 2)
                    
                    font = cv2.FONT_HERSHEY_SIMPLEX
                    color = (0, 0, 255) if is_fire else (0, 255, 0)
                    cv2.putText(display_frame, f"Fire Prob: {confidence:.3f}",
                              (10, 30), font, 0.7, color, 2)
                    if is_fire:
                        cv2.putText(display_frame, "FIRE DETECTED!",
                                  (10, 60), font, 0.7, (0, 0, 255), 2)
                    cv2.imshow('Fire Detection', display_frame)
        
        key = cv2.waitKey(1) & 0xFF
        if key == ord('q') or key == 27:
            self.stop_event.set()
    
    def _create_trajectory_plot(self, trajectory, current_pos, scale=50):
        """Create top-down trajectory view"""
        plot_size = 500
        plot = np.ones((plot_size, plot_size, 3), dtype=np.uint8) * 255
        
        for i in range(0, plot_size, 50):
            cv2.line(plot, (i, 0), (i, plot_size), (220, 220, 220), 1)
            cv2.line(plot, (0, i), (plot_size, i), (220, 220, 220), 1)
        
        center = plot_size // 2
        cv2.line(plot, (center, 0), (center, plot_size), (100, 100, 100), 2)
        cv2.line(plot, (0, center), (plot_size, center), (100, 100, 100), 2)
        cv2.circle(plot, (center, center), 8, (0, 200, 0), 2)
        
        if len(trajectory) > 1:
            points = []
            for pos in trajectory:
                x = int(center + pos[0] * scale)
                z = int(center - pos[2] * scale)
                x = max(0, min(plot_size - 1, x))
                z = max(0, min(plot_size - 1, z))
                points.append([x, z])
            
            points = np.array(points, dtype=np.int32)
            for i in range(1, len(points)):
                ratio = i / len(points)
                color = (int(255 * ratio), 0, int(255 * (1 - ratio)))
                cv2.line(plot, tuple(points[i-1]), tuple(points[i]), color, 2)
            
            if len(points) > 0:
                cv2.circle(plot, tuple(points[-1]), 8, (0, 0, 255), -1)
        
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(plot, "VIO Trajectory", (10, 25), font, 0.6, (0, 0, 0), 2)
        cv2.putText(plot, "LEFT", (10, center - 10), font, 0.5, (0, 0, 0), 2)
        cv2.putText(plot, "RIGHT", (plot_size - 70, center - 10), font, 0.5, (0, 0, 0), 2)
        cv2.putText(plot, "FWD", (center - 25, 20), font, 0.5, (0, 0, 0), 2)
        cv2.putText(plot, "BACK", (center - 30, plot_size - 10), font, 0.5, (0, 0, 0), 2)
        
        pos_text = f"X:{current_pos[0]:+.2f}m Y:{current_pos[1]:+.2f}m Z:{current_pos[2]:+.2f}m"
        cv2.putText(plot, pos_text, (10, plot_size - 10), font, 0.4, (0, 0, 0), 2)
        
        return plot
    
    def stop(self):
        """Stop the VIO sender"""
        self.stop_event.set()
        self.running = False
    
    def cleanup(self):
        """Clean up resources"""
        self.stop_event.set()
        if self.camera_pipeline:
            try:
                self.camera_pipeline.stop()
            except:
                pass
        if self.pi_servo is not None:
            try:
                self.pi_servo.set_servo_pulsewidth(self.servo_gpio, 0)
                self.pi_servo.stop()
            except:
                pass
        if (self.visualize_odom or self.fire_window_visualization) and REALSENSE_AVAILABLE:
            try:
                cv2.destroyAllWindows()
            except:
                pass
        print("✓ Cleanup complete")


# Standalone script execution
if __name__ == "__main__":
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description='Real VO to Pixhawk sender for ArduPilot EKF3')
    parser.add_argument('--pixhawk_device', type=str, default="/dev/ttyACM0",
                        help='Pixhawk device path (default: /dev/ttyACM0)')
    parser.add_argument('--pixhawk_baud', type=int, default=921600,
                        help='Pixhawk baud rate (default: 921600)')
    parser.add_argument('--pixhawk', type=lambda x: x.lower() in ['true', '1', 'yes'],
                        default=True,
                        help='Connect to Pixhawk (default: true). Use --pixhawk false to run VIO only.')
    parser.add_argument('--visualize_odom', type=lambda x: x.lower() in ['true', '1', 'yes'],
                        default=False,
                        help='Show odometry visualization windows (default: false)')
    parser.add_argument('--fire_detection', type=lambda x: x.lower() in ['true', '1', 'yes'],
                        default=False,
                        help='Enable fire detection (default: false)')
    parser.add_argument('--fire_window_visualization', type=lambda x: x.lower() in ['true', '1', 'yes'],
                        default=False,
                        help='Show fire detection visualization window (default: false)')
    parser.add_argument('--fire_model_path', type=str,
                        default="/home/guardian/Desktop/capture_depth/fire_model/best.onnx",
                        help='Path to a fire detection model (.onnx recommended, or .pt)')
    parser.add_argument('--fire_threshold', type=float, default=0.50,
                        help='Fire detection confidence threshold (default: 0.50)')
    parser.add_argument('--fire_fps', type=float, default=10.0,
                        help='Fire detection rate in Hz (default: 10.0)')
    parser.add_argument('--fire_imgsz', type=int, default=320,
                        help='Inference image size (default: 320). ONNX model is fixed at 320.')
    parser.add_argument('--fire_persist_frames', type=int, default=2,
                        help='Require fire detection for N consecutive fire frames before flagging (default: 2)')
    parser.add_argument('--servo_enable', type=lambda x: x.lower() in ['true', '1', 'yes'],
                        default=False,
                        help='Enable servo control via pigpio (default: false)')
    parser.add_argument('--servo_gpio', type=int, default=18,
                        help='Servo GPIO pin (default: 18)')
    parser.add_argument('--servo_physical_pin', type=int, default=None,
                        help='Optional 40-pin header PHYSICAL pin (overrides --servo_gpio). Example: 12 maps to BCM 18.')
    parser.add_argument('--servo_active_pw', type=int, default=2000,
                        help='Servo active pulsewidth in us (default: 2000)')
    parser.add_argument('--servo_idle_pw', type=int, default=1000,
                        help='Servo idle pulsewidth in us (default: 1000)')
    parser.add_argument('--servo_trigger_threshold', type=float, default=None,
                        help='Confidence threshold to trigger servo. Default: uses --fire_threshold')
    parser.add_argument('--servo_persist_frames', type=int, default=10,
                        help='Consecutive fire frames required before activating servo (default: 10)')
    parser.add_argument('--servo_hold_time', type=float, default=6.0,
                        help='Seconds to keep servo active after trigger (default: 6.0)')
    args = parser.parse_args()
    
    # Create and run VIOSender
    try:
        sender = VIOSender(
            pixhawk_device=args.pixhawk_device,
            pixhawk_baud=args.pixhawk_baud,
            use_pixhawk=args.pixhawk,
            visualize_odom=args.visualize_odom,
            fire_detection=args.fire_detection,
            fire_window_visualization=args.fire_window_visualization,
            fire_model_path=args.fire_model_path,
            fire_threshold=args.fire_threshold,
            fire_fps=args.fire_fps,
            fire_imgsz=args.fire_imgsz,
            fire_persist_frames=args.fire_persist_frames,
            servo_enable=args.servo_enable,
            servo_gpio=args.servo_gpio,
            servo_physical_pin=args.servo_physical_pin,
            servo_active_pw=args.servo_active_pw,
            servo_idle_pw=args.servo_idle_pw,
            servo_trigger_threshold=args.servo_trigger_threshold,
            servo_persist_frames=args.servo_persist_frames,
            servo_hold_time=args.servo_hold_time
        )
        
        print("Press Ctrl+C to stop (or 'q' in any window)")
        sender.run()
    except KeyboardInterrupt:
        print("\nStopping VO sender...")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
