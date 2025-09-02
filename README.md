# 🔥 Guardian Drone Controller

A Flutter mobile application for controlling a firefighting drone with real-time communication via TCP/Wi-Fi to a Raspberry Pi 5 controller.

## 📱 Features

- **Cross-platform**: Works on both Android and iOS
- **Real-time Communication**: TCP socket connection to Raspberry Pi
- **Drone Control**: Arm/disarm, mission planning, and emergency abort
- **Live Telemetry**: Real-time status updates and battery monitoring
- **Mission Management**: Coordinate input and mission status tracking
- **Error Handling**: Comprehensive error reporting for arming failures

## 🏗️ Architecture

```
Flutter Mobile App (Android/iOS)
        ↕ TCP Socket (Wi-Fi)
Raspberry Pi 5 Backend (Python)
        ↕ Serial/MAVLink
Pixhawk Flight Controller
        ↕ Control Signals
Firefighting Drone Hardware
```

## 🚀 Quick Start

### Flutter Mobile App Setup

1. **Prerequisites**
   - Flutter SDK (3.0.0 or higher)
   - Android Studio or VS Code
   - Physical Android device or iOS device

2. **Installation**
   ```bash
   # Clone the repository
   cd guardian_app
   
   # Get Flutter dependencies
   flutter pub get
   
   # For Android - Connect your device and enable developer options
   flutter run
   
   # For iOS (Mac only)
   cd ios && pod install && cd ..
   flutter run
   ```

3. **Configure Connection**
   - Open the app on your device
   - In the connection widget, enter your Raspberry Pi's IP address
   - Default port is 8765
   - Tap "Connect"

### Raspberry Pi Backend Setup

1. **Prerequisites**
   ```bash
   # On Raspberry Pi 5
   sudo apt update
   sudo apt install python3 python3-pip
   ```

2. **Install Dependencies**
   ```bash
   cd pi_backend
   pip3 install -r requirements.txt
   ```

3. **Run the Backend**
   ```bash
   python3 drone_controller.py
   ```

4. **Network Configuration**
   - Ensure Raspberry Pi is connected to the same Wi-Fi network as your mobile device
   - Note the Pi's IP address: `hostname -I`
   - Default server port: 8765

## 📋 App Usage Guide

### 1. Connection Setup
- Launch the app on your mobile device
- Enter Raspberry Pi IP address (e.g., 192.168.0.103)
- Enter port number (default: 8765)
- Tap "Connect" - you should see "Connected" status

### 2. Drone Arming
- Ensure connection is established
- Tap "Send Fire Coordinates" to open coordinate input screen
- In the "Arm Drone" section, tap "Arm Drone"
- Wait for confirmation or error messages
- Drone status should show "Armed & Ready"

### 3. Mission Execution
- Enter X and Y coordinates for fire location
- Ensure drone is armed (green "ARMED" indicator)
- Tap "Start Mission"
- Monitor progress in Mission Status screen

### 4. Mission Monitoring
- Tap "Mission Status" to view live telemetry
- Monitor drone position, altitude, and battery
- View real-time logs from the Raspberry Pi
- Use "Abort Mission" for emergency stop

## 🔧 Technical Details

### Communication Protocol

The app communicates with the Raspberry Pi using JSON messages over TCP:

**Commands sent to Pi:**
```json
{
  "command": "arm"
}

{
  "command": "start",
  "x": 12.5,
  "y": 4.3
}

{
  "command": "abort"
}
```

**Status updates from Pi:**
```json
{
  "status": "enroute",
  "pose": [12.5, 4.3, 10.0],
  "battery": 83.4,
  "message": "Flying to target",
  "armed": true,
  "errors": []
}
```

### Drone States
- **Idle**: Ready for arming
- **Arming**: Performing pre-flight checks
- **Armed**: Ready for mission
- **In Mission**: Mission active
- **En Route**: Flying to target
- **Arrived**: Reached fire location
- **Suppressing**: Fighting fire
- **Returning**: Coming back to home
- **Complete**: Mission finished
- **Error**: System error occurred
- **Aborting**: Emergency abort in progress

## 🛠️ Development

### Project Structure
```
guardian_app/
├── lib/
│   ├── models/          # Data models
│   ├── services/        # Business logic & TCP communication
│   ├── screens/         # UI screens
│   ├── widgets/         # Reusable UI components
│   └── main.dart        # App entry point
├── android/             # Android configuration
├── ios/                 # iOS configuration
├── pi_backend/          # Raspberry Pi Python backend
└── README.md
```

### Key Dependencies
- **provider**: State management
- **flutter_bloc**: Business logic component pattern
- **equatable**: Value equality

### Backend Dependencies
- **socket**: TCP communication
- **json**: Message serialization
- **threading**: Concurrent mission execution
- **logging**: Comprehensive logging

## 🔒 Safety Features

- **Pre-flight Checks**: Comprehensive arming validation
- **Emergency Abort**: Immediate mission termination
- **Battery Monitoring**: Low battery warnings
- **Connection Monitoring**: Automatic reconnection attempts
- **Error Reporting**: Detailed error messages and logging

## 🐛 Troubleshooting

### Connection Issues
1. **Cannot connect to Pi**
   - Verify both devices are on same Wi-Fi network
   - Check Pi IP address: `hostname -I`
   - Ensure Pi backend is running
   - Check firewall settings

2. **Commands not working**
   - Verify connection status in app
   - Check Pi backend logs
   - Restart the backend service

### Arming Issues
1. **Arming fails**
   - Check error messages in app
   - Verify drone status and battery level
   - Ensure hardware connections
   - Review Pi backend logs

### Mission Issues
1. **Mission won't start**
   - Ensure drone is armed first
   - Verify coordinates are valid numbers
   - Check connection stability

## 📱 Testing on Physical Device

### Android Testing
1. Enable Developer Options on your Android device
2. Enable USB Debugging
3. Connect device via USB
4. Run: `flutter run`
5. App will install and launch on your device

### Network Testing
1. Connect both phone and Pi to same Wi-Fi network
2. Start Pi backend: `python3 drone_controller.py`
3. Note Pi IP address from backend logs
4. Enter IP in app connection screen
5. Test connection and basic commands

## 🔄 Future Enhancements

- [ ] GPS integration for automatic coordinate detection
- [ ] Camera feed integration
- [ ] Multiple drone support
- [ ] Mission planning with waypoints
- [ ] Offline mode with cached missions
- [ ] Advanced telemetry visualization
- [ ] User authentication and logging

## 📄 License

This project is developed for firefighting drone operations. Please ensure compliance with local drone regulations and safety protocols.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on physical devices
5. Submit a pull request

## 📞 Support

For technical support or questions:
- Check the troubleshooting section
- Review Pi backend logs
- Test basic TCP connectivity
- Verify Flutter dependencies

---

**⚠️ Safety Notice**: Always follow local drone regulations and safety protocols when operating firefighting drones. This software is provided as-is for educational and development purposes. 