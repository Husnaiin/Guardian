import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../services/drone_service.dart';
import '../widgets/connection_widget.dart';
import '../widgets/drone_status_widget.dart';
import '../widgets/control_buttons_widget.dart';
import '../widgets/map_control_widget.dart';
import '../widgets/admin_push_settings_card.dart';
import '../widgets/video_record_widget.dart';
import '../widgets/loiter_land_widget.dart';
import '../widgets/check_ekf_widget.dart';
import '../widgets/fire_alert_dialog.dart';
import '../services/notification_service.dart';
import '../models/coordinates.dart';
import '../models/command.dart';
import '../widgets/sensor_mapping_card.dart';
import '../services/sensor_map_service.dart';
import 'dart:async';
import 'coordinate_input_screen.dart';
import 'mission_status_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _fireAlertSubscription;
  bool _isShowingDialog = false;
  VoidCallback? _socketListener;
  bool _pushedThisConnection = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
      _setupFireAlertListener();
      _identifyAsAdmin();
      _loadAndSyncSensorMap();
      _setupSocketConnectListener();
      _setupNotificationTapHandler();
    });
  }

  @override
  void dispose() {
    _fireAlertSubscription?.cancel();
    final socketService = Provider.of<SocketService>(context, listen: false);
    if (_socketListener != null) {
      socketService.removeListener(_socketListener!);
    }
    NotificationService().onNotificationTapped = null;
    NotificationService().onActionSelected = null;
    super.dispose();
  }

  void _setupFireAlertListener() {
    final droneService = Provider.of<DroneService>(context, listen: false);
    _fireAlertSubscription = droneService.fireAlertStream.listen((fireAlert) {
      if (mounted) {
        _handleFireAlert(fireAlert);
      }
    });
  }

  void _setupNotificationTapHandler() {
    // Handle notification body tap - show dialog
    NotificationService().onNotificationTapped = (payload) {
      if (payload != null && mounted) {
        final coords = payload.split(',');
        if (coords.length == 2) {
          final x = double.tryParse(coords[0]);
          final y = double.tryParse(coords[1]);
          if (x != null && y != null) {
            _showFireAlertDialog({'x': x, 'y': y});
          }
        }
      }
    };
    
    // Handle notification action buttons
    NotificationService().onActionSelected = (action, payload) {
      if (payload != null && mounted) {
        final coords = payload.split(',');
        if (coords.length == 2) {
          final x = double.tryParse(coords[0]);
          final y = double.tryParse(coords[1]);
          if (x != null && y != null) {
            if (action == 'accept') {
              _handleAccept(x, y);
            } else if (action == 'reject') {
              _handleReject();
            }
          }
        }
      }
    };
  }
  
  void _handleAccept(double x, double y) async {
    final socketService = Provider.of<SocketService>(context, listen: false);
    final coordinates = Coordinates(x: x, y: y);
    final success = await socketService.sendCommand(Command.start(coordinates));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Mission started to suppress fire at ($x, $y)'
                : 'Failed to start mission',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }
  
  void _handleReject() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fire alert rejected'),
          backgroundColor: Colors.grey,
        ),
      );
    }
  }

  void _handleFireAlert(Map<String, dynamic> fireAlert) {
    final x = (fireAlert['x'] as num).toDouble();
    final y = (fireAlert['y'] as num).toDouble();

    // Show system notification
    NotificationService().showFireAlert(x: x, y: y);

    // Also show dialog if app is in foreground
    if (!_isShowingDialog && mounted) {
      _showFireAlertDialog(fireAlert);
    }
  }

  void _showFireAlertDialog(Map<String, dynamic> fireAlert) {
    final x = (fireAlert['x'] as num).toDouble();
    final y = (fireAlert['y'] as num).toDouble();
    final socketService = Provider.of<SocketService>(context, listen: false);

    _isShowingDialog = true;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => FireAlertDialog(
        x: x,
        y: y,
        socketService: socketService,
        onDismiss: () {
          _isShowingDialog = false;
        },
      ),
    );
  }

  void _autoConnect() async {
    final socketService = Provider.of<SocketService>(context, listen: false);
    await socketService.connect();
  }

  void _identifyAsAdmin() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    socketService.setClientType('admin');
  }

  void _setupSocketConnectListener() {
    final socketService = Provider.of<SocketService>(context, listen: false);
    _socketListener = () async {
      final connected = socketService.isConnected;
      if (connected && !_pushedThisConnection) {
        _pushedThisConnection = true;
        final sensorService = Provider.of<SensorMapService>(context, listen: false);
        await sensorService.pushToServer(
          (map) => socketService.sendCommand(Command.updateSensorMap(map)),
        );
      } else if (!connected) {
        _pushedThisConnection = false;
      }
    };
    socketService.addListener(_socketListener!);
  }

  Future<void> _loadAndSyncSensorMap() async {
    final sensorService = Provider.of<SensorMapService>(context, listen: false);
    await sensorService.load();
    await sensorService.fetchRemote();
    final socketService = Provider.of<SocketService>(context, listen: false);
    if (socketService.isConnected) {
      await sensorService.pushToServer(
        (map) => socketService.sendCommand(Command.updateSensorMap(map)),
      );
    }
    await sensorService.pushRemote();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh Status',
          onPressed: () {
            final droneService = Provider.of<DroneService>(context, listen: false);
            droneService.requestStatus();
          },
        ),
        title: const Text('Guardian Admin'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: Consumer2<SocketService, DroneService>(
        builder: (context, socketService, droneService, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConnectionWidget(socketService: socketService),
                const SizedBox(height: 20),
                DroneStatusWidget(status: droneService.status),
                const SizedBox(height: 20),
                if (droneService.status.errors.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      border: Border.all(color: Colors.red[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error, color: Colors.red[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Errors:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...droneService.status.errors.map(
                          (error) => Text(
                            '• $error',
                            style: TextStyle(color: Colors.red[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                ControlButtonsWidget(
                  socketService: socketService,
                  droneService: droneService,
                  onSendCoordinates: () => _navigateToCoordinateInput(context),
                  onViewMissionStatus: () => _navigateToMissionStatus(context),
                  showSendCoordinates: true,
                  showArmButton: true,
                  isClientMode: false,
                ),
                const SizedBox(height: 20),
                // Loiter & Land controls (below mission control)
                LoiterLandWidget(socketService: socketService),
                const SizedBox(height: 20),
                // Check EKF button (below loiter/land card)
                CheckEKFWidget(socketService: socketService),
                const SizedBox(height: 20),
                // Video Recording controls (below mission control)
                VideoRecordWidget(socketService: socketService),
                const SizedBox(height: 20),
                MapControlWidget(
                  socketService: socketService,
                  droneService: droneService,
                ),
                const SizedBox(height: 20),
                SensorMappingCard(socketService: socketService),
                const SizedBox(height: 20),
                AdminPushSettingsCard(socketService: socketService),
                const SizedBox(height: 20),
                if (droneService.status.message.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      border: Border.all(color: Colors.blue[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            droneService.status.message,
                            style: TextStyle(color: Colors.blue[700]),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _navigateToCoordinateInput(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CoordinateInputScreen(),
      ),
    );
  }

  void _navigateToMissionStatus(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const MissionStatusScreen(),
      ),
    );
  }

  void _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Do you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }
} 