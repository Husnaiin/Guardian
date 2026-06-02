# Guardian - Firefighting Drone Management System

## Business Overview

Guardian is a comprehensive drone management solution designed to enhance the speed and safety of firefighting operations. By enabling automated drone deployments directly to reported fire locations, Guardian minimizes response times and mitigates risks to human personnel. The system allows emergency responders, system administrators, and authorized clients to coordinate effortlessly, offering real-time situational awareness and precision-targeted fire suppression drops.

## System-Level Overview

The Guardian system is composed of two primary subsystems that communicate in real-time to facilitate drone operations:

### 1. Command & Control Center (Mobile Application)

A cross-platform mobile application providing an intuitive interface for operators. 
- **Mission Control**: Dispatch drones to precise coordinates via interactive maps.
- **Telemetry & Monitoring**: Live streaming of drone altitude, battery levels, connection status, and flight states (e.g., *En Route*, *Suppressing*, *Returning*).
- **Role Management**: Differentiates between administrators who have full control over the flight and external clients who can report fires or view statuses.

### 2. Drone Onboard Backend (Raspberry Pi)

A lightweight, Python-driven server running onboard the drone's companion computer (Raspberry Pi). 
- **Hardware Interface**: Computes navigation and positioning utilizing Visual Inertial Odometry (VIO) for robust GPS-denied navigation, interfacing with Pixhawk flight controllers via MAVLink.
- **Computer Vision Pipeline**: Executes object detection models (e.g., ONNX-based AI) on live camera feeds to visually confirm fire presence before deploying suppressants.
- **Payload Control**: Integrates directly with GPIO servos to trigger the physical release of fire suppression payloads.

### 3. Communication Architecture

The Mobile Application and Drone Backend are linked via a robust TCP Socket connection, ensuring low-latency telemetry updates and reliable command execution (arming, loitering, aborting, or landing) even in challenging network environments typical of emergency scenarios.

## Key Capabilities

- **GPS-Denied Flight**: Fully functional in complex, indoor, or occluded environments utilizing Visual Inertial Odometry (VIO), eliminating reliance on satellite positioning.
- **Automated Dispatch**: Click a map location to instantly route the drone.
- **Intelligent Suppressant Drop**: Vision-based fire confirmation ensures accurate payload delivery.
- **Failsafe Operations**: Built-in emergency commands (abort, return to launch, land immediately) provide human-in-the-loop safety.
