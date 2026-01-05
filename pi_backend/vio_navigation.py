#!/usr/bin/env python3
"""
VIO-based Navigation System
Integrates visual odometry with obstacle detection for autonomous drone navigation
"""

import pyrealsense2 as rs
import numpy as np
import cv2
import time
import threading
import logging
from collections import deque

logger = logging.getLogger(__name__)

class IMUValidator:
    """Use IMU to VALIDATE visual odometry, not drive it"""
    
    def __init__(self, use_imu=False):
        self.use_imu = use_imu
        
        # IMU state tracking (for validation only)
        self.imu_velocity = np.zeros(3)
        self.prev_time = None
        
        # IMU bias calibration
        self.accel_bias = np.zeros(3)
        self.gyro_bias = np.zeros(3)
        self.bias_initialized = False
        self.bias_samples = []
        
        # Validation parameters
        self.max_acceleration = 3.0   # m/s² - physically possible for camera movement
        self.max_velocity = 2.0       # m/s - max reasonable camera velocity
        self.max_position_jump = 0.5  # m - max jump in one frame
        
        # Statistics
        self.rejected_count = 0
        self.accepted_count = 0
        self.last_rejection_reason = ""
        
    def initialize_bias(self, accel, gyro):
        """Initialize IMU bias from stationary measurements"""
        
        self.bias_samples.append({
            'accel': accel.copy(),
            'gyro': gyro.copy()
        })
        
        # Need 50 samples
        if len(self.bias_samples) >= 50:
            accels = np.array([s['accel'] for s in self.bias_samples])
            gyros = np.array([s['gyro'] for s in self.bias_samples])
            
            self.accel_bias = np.mean(accels, axis=0)
            self.gyro_bias = np.mean(gyros, axis=0)
            self.accel_bias[2] = self.accel_bias[2] - (-9.81)  # Remove gravity
            
            self.bias_initialized = True
            logger.info("✓ IMU calibrated (validation mode)")
            logger.info(f"  Max accel: {self.max_acceleration} m/s²")
            logger.info(f"  Max velocity: {self.max_velocity} m/s")
            logger.info(f"  Max jump: {self.max_position_jump} m")
    
    def update_imu_velocity(self, accel, gyro, dt):
        """Track IMU velocity for validation (not used for position!)"""
        
        if dt <= 0 or dt > 0.5:
            return
        
        if not self.bias_initialized:
            self.initialize_bias(accel, gyro)
            return
        
        # Update IMU velocity estimate
        accel_corrected = accel - self.accel_bias
        accel_corrected[2] += 9.81  # Remove gravity
        
        self.imu_velocity += accel_corrected * dt
        self.imu_velocity *= 0.98  # Damping
    
    def validate_motion(self, vision_position, vision_velocity, prev_position, dt):
        """
        Validate if visual motion is physically possible using IMU
        Returns: (is_valid, reason)
        """
        
        if not self.use_imu or not self.bias_initialized:
            self.accepted_count += 1
            return True, "No IMU"
        
        if dt <= 0:
            return True, "Invalid dt"
        
        # Calculate visual motion
        position_delta = vision_position - prev_position
        position_delta_magnitude = np.linalg.norm(position_delta)
        
        # Check 1: Position jump too large (glitch detection)
        if position_delta_magnitude > self.max_position_jump:
            self.rejected_count += 1
            self.last_rejection_reason = f"Jump too large: {position_delta_magnitude:.2f}m"
            return False, self.last_rejection_reason
        
        # Check 2: Velocity too high
        if vision_velocity is not None:
            velocity_magnitude = np.linalg.norm(vision_velocity)
            if velocity_magnitude > self.max_velocity:
                self.rejected_count += 1
                self.last_rejection_reason = f"Velocity too high: {velocity_magnitude:.2f}m/s"
                return False, self.last_rejection_reason
        
        # Check 3: Implied acceleration (from position change)
        implied_velocity = position_delta / dt
        implied_velocity_magnitude = np.linalg.norm(implied_velocity)
        
        if implied_velocity_magnitude > self.max_velocity:
            self.rejected_count += 1
            self.last_rejection_reason = f"Implied velocity: {implied_velocity_magnitude:.2f}m/s"
            return False, self.last_rejection_reason
        
        # Check 4: Compare with IMU velocity (if available)
        if np.linalg.norm(self.imu_velocity) > 0.1:  # IMU has velocity estimate
            velocity_diff = np.linalg.norm(implied_velocity - self.imu_velocity)
            # If vision and IMU disagree by more than 1 m/s, reject
            if velocity_diff > 1.0:
                self.rejected_count += 1
                self.last_rejection_reason = f"IMU mismatch: {velocity_diff:.2f}m/s"
                return False, self.last_rejection_reason
        
        # All checks passed
        self.accepted_count += 1
        return True, "OK"

class VIONavigator:
    """Visual-Inertial Odometry Navigator with obstacle detection"""
    
    def __init__(self, feature_mode='sift', use_imu_validation=False):
        """
        Initialize VIO navigator
        
        Args:
            feature_mode: 'sift' (uses SIFT + optical flow), 'orb' (uses ORB + optical flow), 
                         or 'optical_flow' (optical flow only) (default: sift)
            use_imu_validation: Use IMU to validate visual odometry (default: False)
        """
        self.feature_mode = feature_mode.lower()
        
        # Position tracking
        self.position = np.zeros(3)  # [x, y, z] in meters
        self.velocity = np.zeros(3)
        self.prev_position = np.zeros(3)  # For IMU validation
        self.rotation = np.eye(3)
        
        # Camera state
        self.prev_gray = None
        self.prev_depth = None
        self.prev_points = None  # For optical flow
        self.prev_descriptors = None  # For SIFT/ORB
        self.prev_sift_points = None  # SIFT keypoints
        self.prev_time = None
        
        # Camera intrinsics
        self.fx = self.fy = self.cx = self.cy = None
        self.depth_scale = 0.001
        
        # Feature detection - Always initialize both SIFT and optical flow
        if self.feature_mode == 'sift':
            self.detector = cv2.SIFT_create(nfeatures=1000)
            self.matcher = cv2.BFMatcher(cv2.NORM_L2, crossCheck=False)
            self.use_sift = True
            self.use_optical_flow = True
        elif self.feature_mode == 'orb':
            self.detector = cv2.ORB_create(nfeatures=500)
            self.matcher = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=False)
            self.use_sift = False
            self.use_optical_flow = True
        else:  # optical_flow only
            self.detector = None
            self.matcher = None
            self.use_sift = False
            self.use_optical_flow = True
        
        # Optical flow parameters (EXACT from visual_odometry_robust.py)
        self.feature_params = dict(
            maxCorners=500,  # Increased from 300 for more features
            qualityLevel=0.01,
            minDistance=8,   # Reduced from 10 to allow more features
            blockSize=7
        )
        self.lk_params = dict(
            winSize=(21, 21),
            maxLevel=3,
            criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 30, 0.01)
        )
        
        # Tracking quality (EXACT from visual_odometry_robust.py)
        self.tracking_quality = 0.0
        self.inlier_ratio = 0.0
        self.min_features = 50  # Increased from 30
        self.min_inliers = 20   # Increased from 15
        self.max_depth = 5.0  # meters
        self.min_depth = 0.1  # meters
        
        # Obstacle detection
        self.obstacle_detected = False
        self.obstacle_distance = float('inf')
        self.min_obstacle_distance = 0.5  # meters
        
        # Path width detection
        self.path_width = float('inf')
        self.min_path_width = 0.61  # meters (2 feet)
        self.path_clear = True
        
        # IMU validation (validates visual estimates, doesn't calculate position)
        self.imu_validator = IMUValidator(use_imu=use_imu_validation)
        self.validation_status = "OK"
        
        # Thread safety
        self.lock = threading.Lock()
    
    def set_camera_intrinsics(self, intrinsics, depth_scale):
        """Set camera intrinsics"""
        self.fx = intrinsics.fx
        self.fy = intrinsics.fy
        self.cx = intrinsics.ppx
        self.cy = intrinsics.ppy
        self.depth_scale = depth_scale
    
    def get_3d_points_filtered(self, points_2d, depth_frame):
        """Convert 2D points to 3D with robust depth filtering (EXACT from visual_odometry_robust.py)"""
        points_3d = []
        valid_indices = []
        
        for i, (x, y) in enumerate(points_2d):
            x_int, y_int = int(round(x)), int(round(y))
            
            # Check bounds with margin
            if x_int < 5 or x_int >= depth_frame.shape[1] - 5:
                continue
            if y_int < 5 or y_int >= depth_frame.shape[0] - 5:
                continue
            
            # Get median depth in 3x3 window for stability
            window = depth_frame[y_int-1:y_int+2, x_int-1:x_int+2]
            valid_depths = window[window > 0]
            
            if len(valid_depths) < 3:
                continue
            
            depth = np.median(valid_depths) * self.depth_scale
            
            # Filter by depth range
            if depth < self.min_depth or depth > self.max_depth:
                continue
            
            # Back-project to 3D
            z = depth
            x_3d = (x - self.cx) * z / self.fx
            y_3d = (y - self.cy) * z / self.fy
            
            points_3d.append([x_3d, y_3d, z])
            valid_indices.append(i)
        
        return np.array(points_3d) if points_3d else np.array([]), valid_indices
    
    def process_frame(self, color_image, depth_frame, record_viz=False, imu_data=None):
        """
        Process camera frame for VIO and obstacle detection
        
        Args:
            color_image: BGR color image
            depth_frame: Depth image (numpy array)
            record_viz: If True, returns visualization image
            imu_data: Tuple of (accel, gyro) for IMU validation (optional)
        
        Returns:
            (position, velocity, obstacle_detected, path_clear, tracking_quality, viz_image, matched_points)
        """
        with self.lock:
            gray = cv2.cvtColor(color_image, cv2.COLOR_BGR2GRAY)
            current_time = time.time()
            
            viz_image = None
            matched_points = 0
            
            # Initialize on first frame
            if self.prev_gray is None:
                self.prev_gray = gray
                self.prev_depth = depth_frame
                self.prev_time = current_time
                self.prev_position = self.position.copy()
                
                # Initialize SIFT/ORB features
                if self.use_sift or (self.detector is not None and self.feature_mode != 'optical_flow'):
                    self._detect_features(gray)
                
                # Initialize optical flow features
                if self.use_optical_flow:
                    corners = cv2.goodFeaturesToTrack(gray, mask=None, **self.feature_params)
                    if corners is not None:
                        self.prev_points = corners.reshape(-1, 2)
                
                return self.position.copy(), self.velocity.copy(), False, True, 0.0, None, 0
            
            # Calculate dt
            dt = current_time - self.prev_time if self.prev_time else 0.066
            
            # Update IMU velocity estimate (for validation only)
            if imu_data is not None:
                accel, gyro = imu_data
                self.imu_validator.update_imu_velocity(accel, gyro, dt)
            
            # Track features using both SIFT and optical flow (if enabled)
            good_prev_list = []
            good_curr_list = []
            
            # Track with SIFT/ORB if enabled
            if self.use_sift or (self.detector is not None and self.feature_mode != 'optical_flow'):
                sift_prev, sift_curr = self._track_features(gray)
                if sift_prev is not None and sift_curr is not None:
                    good_prev_list.append(sift_prev)
                    good_curr_list.append(sift_curr)
            
            # Track with optical flow if enabled
            if self.use_optical_flow:
                of_prev, of_curr = self._track_optical_flow(gray)
                if of_prev is not None and of_curr is not None:
                    good_prev_list.append(of_prev)
                    good_curr_list.append(of_curr)
            
            # Combine all tracked features
            if len(good_prev_list) > 0:
                good_prev = np.vstack(good_prev_list)
                good_curr = np.vstack(good_curr_list)
            else:
                good_prev = None
                good_curr = None
            
            # Store previous position before update
            temp_prev_position = self.position.copy()
            
            # Process motion with tracked features
            motion_estimated = False
            if good_prev is not None and good_curr is not None:
                matched_points = len(good_prev)
                motion_estimated = self._estimate_motion_from_points(good_prev, good_curr, depth_frame, dt)
            
            # IMU VALIDATION: Check if visual motion is physically possible
            if motion_estimated and self.tracking_quality > 0:
                validation_ok, reason = self.imu_validator.validate_motion(
                    self.position, self.velocity, temp_prev_position, dt
                )
                
                if not validation_ok:
                    # REJECT visual estimate - revert to previous position
                    self.position = temp_prev_position.copy()
                    self.validation_status = f"REJECTED: {reason}"
                    logger.warning(f"Frame rejected: {reason}")
                else:
                    # Accept visual estimate
                    self.prev_position = self.position.copy()
                    self.validation_status = "OK"
            
            # Detect obstacles (path width check disabled for performance)
            self._detect_obstacles(depth_frame)
            
            # Create visualization if recording
            if record_viz and good_prev is not None and good_curr is not None:
                viz_image = self._create_visualization(color_image, good_prev, good_curr)
            
            # Re-detect features if needed
            # Re-detect SIFT/ORB features
            if self.use_sift or (self.detector is not None and self.feature_mode != 'optical_flow'):
                self._detect_features(gray)
            
            # Re-detect optical flow features
            if self.use_optical_flow:
                if self.prev_points is None or len(self.prev_points) < self.min_features:
                    corners = cv2.goodFeaturesToTrack(gray, mask=None, **self.feature_params)
                    if corners is not None:
                        self.prev_points = corners.reshape(-1, 2)
            
            # Update state
            self.prev_gray = gray
            self.prev_depth = depth_frame
            self.prev_time = current_time
            
            # Path width always True (disabled)
            return (self.position.copy(), self.velocity.copy(), 
                   self.obstacle_detected, True, self.tracking_quality, viz_image, matched_points)
    
    def _detect_features(self, gray):
        """Detect SIFT/ORB features in current frame"""
        if self.detector is not None:
            kp, desc = self.detector.detectAndCompute(gray, None)
            if kp and desc is not None:
                self.prev_sift_points = np.array([p.pt for p in kp], dtype=np.float32)
                self.prev_descriptors = desc
    
    def _estimate_motion_from_points(self, good_prev, good_curr, depth_frame, dt):
        """Estimate motion from tracked feature points (EXACT from visual_odometry_robust.py)"""
        if len(good_prev) < 5:
            return False
        
        # Get 3D points using robust filtering (EXACT from visual_odometry_robust.py)
        prev_3d, prev_valid = self.get_3d_points_filtered(good_prev, self.prev_depth)
        curr_3d, curr_valid = self.get_3d_points_filtered(good_curr, depth_frame)
        
        # Match indices (EXACT from visual_odometry_robust.py)
        matched_prev = []
        matched_curr = []
        
        valid_set = set(prev_valid) & set(curr_valid)
        for idx in valid_set:
            if idx < len(prev_3d) and idx < len(curr_3d):
                prev_idx = prev_valid.index(idx)
                curr_idx = curr_valid.index(idx)
                if prev_idx < len(prev_3d) and curr_idx < len(curr_3d):
                    matched_prev.append(prev_3d[prev_idx])
                    matched_curr.append(curr_3d[curr_idx])
        
        # Estimate motion with RANSAC
        if len(matched_prev) >= self.min_inliers:
            matched_prev = np.array(matched_prev)
            matched_curr = np.array(matched_curr)
            
            R, t, inlier_ratio = self._estimate_motion_ransac(matched_prev, matched_curr)
            
            self.inlier_ratio = inlier_ratio
            self.tracking_quality = len(matched_prev)  # EXACT from visual_odometry_robust.py
            
            if R is not None and t is not None and inlier_ratio > 0.3:
                # Good tracking - update position (including altitude)
                delta_position = -self.rotation @ t
                
                # Sanity check - reject huge jumps (EXACT from visual_odometry_robust.py)
                delta_magnitude = np.linalg.norm(delta_position)
                if delta_magnitude < 0.5:  # Max 50cm per frame (EXACT from visual_odometry_robust.py)
                    self.position += delta_position
                    self.rotation = self.rotation @ R
                    
                    if dt > 0:
                        self.velocity = delta_position / dt
                    
                    return True
        
        return False
    
    def _create_visualization(self, color_image, good_prev, good_curr):
        """Create visualization image with tracked features"""
        viz = color_image.copy()
        
        # Draw tracked features
        for i in range(len(good_prev)):
            prev_pt = tuple(good_prev[i].astype(int))
            curr_pt = tuple(good_curr[i].astype(int))
            
            # Draw line showing motion
            cv2.line(viz, prev_pt, curr_pt, (0, 255, 0), 1)
            # Draw current point
            cv2.circle(viz, curr_pt, 3, (0, 255, 255), -1)
        
        # Draw odometry info
        pos = self.position
        vel = self.velocity
        
        # Text overlay (black, bold, smaller font)
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = 0.35  # Half of 0.7
        thickness = 1 
        color = (0, 0, 0)  # Black
        y_offset = 15
        line_height = 15
        
        # Position X
        x_dir = "RIGHT" if pos[0] > 0 else "LEFT "
        cv2.putText(viz, f"X: {pos[0]:+.2f}m {x_dir}", 
                   (10, y_offset), font, font_scale, color, thickness)
        y_offset += line_height
        
        # Position Y (Altitude) - fix labeling: Y+ is down in camera coords, so flip
        y_dir = "DOWN" if pos[1] > 0 else "UP  "
        cv2.putText(viz, f"Y: {pos[1]:+.2f}m {y_dir}", 
                   (10, y_offset), font, font_scale, color, thickness)
        y_offset += line_height
        
        # Position Z
        z_dir = "FWD " if pos[2] > 0 else "BACK"
        cv2.putText(viz, f"Z: {pos[2]:+.2f}m {z_dir}", 
                   (10, y_offset), font, font_scale, color, thickness)
        y_offset += line_height
        
        # Altitude (separate line)
        cv2.putText(viz, f"Altitude: {pos[1]:+.2f}m", 
                   (10, y_offset), font, font_scale, color, thickness)
        y_offset += line_height
        
        # Velocity
        cv2.putText(viz, f"Velocity: {np.linalg.norm(vel):.2f} m/s", 
                   (10, y_offset), font, font_scale, color, thickness)
        y_offset += line_height
        
        # Features
        cv2.putText(viz, f"Features: {len(good_prev)}", 
                   (10, y_offset), font, font_scale, color, thickness)
        y_offset += line_height
        
        # Quality
        cv2.putText(viz, f"Quality: {self.tracking_quality:.2f}", 
                   (10, y_offset), font, font_scale, color, thickness)
        
        return viz
    
    def _track_optical_flow(self, gray):
        """Track features using optical flow"""
        if self.prev_points is None or len(self.prev_points) < self.min_features:
            return None, None
        
        curr_points, status, _ = cv2.calcOpticalFlowPyrLK(
            self.prev_gray, gray,
            self.prev_points.reshape(-1, 1, 2),
            None, **self.lk_params
        )
        
        if curr_points is not None:
            good_prev = self.prev_points[status.flatten() == 1]
            good_curr = curr_points.reshape(-1, 2)[status.flatten() == 1]
            self.prev_points = good_curr
            return good_prev, good_curr
        
        return None, None
    
    def _track_features(self, gray):
        """Track features using SIFT/ORB matching"""
        if self.prev_descriptors is None or self.prev_sift_points is None:
            return None, None
        
        kp_curr, desc_curr = self.detector.detectAndCompute(gray, None)
        
        if desc_curr is None or len(desc_curr) < self.min_features:
            return None, None
        
        matches = self.matcher.knnMatch(self.prev_descriptors, desc_curr, k=2)
        
        good_matches = []
        for m_n in matches:
            if len(m_n) == 2:
                m, n = m_n
                if m.distance < 0.75 * n.distance:
                    good_matches.append(m)
        
        if len(good_matches) < self.min_features:
            return None, None
        
        prev_pts = np.array([self.prev_sift_points[m.queryIdx] for m in good_matches], dtype=np.float32)
        curr_pts = np.array([kp_curr[m.trainIdx].pt for m in good_matches], dtype=np.float32)
        
        return prev_pts, curr_pts
    
    def _estimate_motion_ransac(self, prev_3d, curr_3d, iterations=100):
        """Estimate motion with RANSAC for outlier rejection (EXACT from visual_odometry_robust.py)"""
        n = len(prev_3d)
        if n < self.min_inliers:
            return None, None, 0
        
        best_inliers = 0
        best_R = None
        best_t = None
        threshold = 0.05  # 5cm threshold for inliers
        
        for _ in range(iterations):
            # Randomly sample 3 points
            if n < 3:
                break
            
            indices = np.random.choice(n, min(3, n), replace=False)
            sample_prev = prev_3d[indices]
            sample_curr = curr_3d[indices]
            
            # Compute transformation from sample
            try:
                # Centroids
                centroid_prev = np.mean(sample_prev, axis=0)
                centroid_curr = np.mean(sample_curr, axis=0)
                
                # Center points
                prev_centered = sample_prev - centroid_prev
                curr_centered = sample_curr - centroid_curr
                
                # SVD
                H = prev_centered.T @ curr_centered
                U, S, Vt = np.linalg.svd(H)
                R = Vt.T @ U.T
                
                # Ensure proper rotation
                if np.linalg.det(R) < 0:
                    Vt[-1, :] *= -1
                    R = Vt.T @ U.T
                
                # Translation
                t = centroid_curr - R @ centroid_prev
                
                # Count inliers
                transformed = (R @ prev_3d.T).T + t
                errors = np.linalg.norm(curr_3d - transformed, axis=1)
                inliers = np.sum(errors < threshold)
                
                if inliers > best_inliers:
                    best_inliers = inliers
                    best_R = R
                    best_t = t
                    
            except:
                continue
        
        # Refine with all inliers if we have enough (EXACT from visual_odometry_robust.py)
        if best_inliers >= self.min_inliers:
            transformed = (best_R @ prev_3d.T).T + best_t
            errors = np.linalg.norm(curr_3d - transformed, axis=1)
            inlier_mask = errors < threshold
            
            # Re-estimate with inliers only
            try:
                inlier_prev = prev_3d[inlier_mask]
                inlier_curr = curr_3d[inlier_mask]
                
                centroid_prev = np.mean(inlier_prev, axis=0)
                centroid_curr = np.mean(inlier_curr, axis=0)
                
                prev_centered = inlier_prev - centroid_prev
                curr_centered = inlier_curr - centroid_curr
                
                H = prev_centered.T @ curr_centered
                U, S, Vt = np.linalg.svd(H)
                best_R = Vt.T @ U.T
                
                if np.linalg.det(best_R) < 0:
                    Vt[-1, :] *= -1
                    best_R = Vt.T @ U.T
                
                best_t = centroid_curr - best_R @ centroid_prev
                
            except:
                pass
        
        inlier_ratio = best_inliers / n if n > 0 else 0
        return best_R, best_t, inlier_ratio
    
    def _detect_obstacles(self, depth_frame):
        """Detect obstacles in front of drone"""
        h, w = depth_frame.shape
        
        # Check center region (middle 40% of frame)
        center_y1, center_y2 = int(h * 0.3), int(h * 0.7)
        center_x1, center_x2 = int(w * 0.3), int(w * 0.7)
        
        center_region = depth_frame[center_y1:center_y2, center_x1:center_x2]
        valid_depths = center_region[center_region > 0] * self.depth_scale
        
        if len(valid_depths) > 0:
            self.obstacle_distance = np.median(valid_depths)
            self.obstacle_detected = self.obstacle_distance < self.min_obstacle_distance
        else:
            self.obstacle_distance = float('inf')
            self.obstacle_detected = False
    
    def _check_path_width(self, depth_frame):
        """Check if path is wide enough for drone (2 feet radius)"""
        h, w = depth_frame.shape
        
        # Check horizontal line at center height
        center_row = depth_frame[h // 2, :]
        valid_depths = center_row * self.depth_scale
        
        # Find closest obstacle on left and right
        left_half = valid_depths[:w//2]
        right_half = valid_depths[w//2:]
        
        left_dist = np.min(left_half[left_half > 0]) if np.any(left_half > 0) else float('inf')
        right_dist = np.min(right_half[right_half > 0]) if np.any(right_half > 0) else float('inf')
        
        self.path_width = left_dist + right_dist
        self.path_clear = self.path_width >= self.min_path_width
    
    def reset(self):
        """Reset VIO state"""
        with self.lock:
            self.position = np.zeros(3)
            self.velocity = np.zeros(3)
            self.rotation = np.eye(3)
            self.prev_gray = None
            self.prev_depth = None
            self.prev_points = None
            self.prev_descriptors = None
            self.prev_sift_points = None
            self.prev_time = None
            logger.info("VIO state reset")
    
    def get_position(self):
        """Get current position (thread-safe)"""
        with self.lock:
            return self.position.copy()
    
    def get_velocity(self):
        """Get current velocity (thread-safe)"""
        with self.lock:
            return self.velocity.copy()
    
    def get_validation_stats(self):
        """Get IMU validation statistics"""
        total = self.imu_validator.accepted_count + self.imu_validator.rejected_count
        if total > 0:
            accept_rate = self.imu_validator.accepted_count / total
        else:
            accept_rate = 0.0
        
        return {
            'accepted': self.imu_validator.accepted_count,
            'rejected': self.imu_validator.rejected_count,
            'accept_rate': accept_rate,
            'status': self.validation_status,
            'calibrated': self.imu_validator.bias_initialized
        }

