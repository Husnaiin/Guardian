import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../services/drone_service.dart';
import '../widgets/connection_widget.dart';
import '../widgets/drone_status_widget.dart';
import '../widgets/control_buttons_widget.dart';
import '../widgets/map_control_widget.dart';
import '../widgets/admin_push_settings_card.dart';
import 'coordinate_input_screen.dart';
import 'mission_status_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final socketService = Provider.of<SocketService>(context, listen: false);
      final droneService = Provider.of<DroneService>(context, listen: false);
      droneService.initialize(socketService);
      _autoConnect();
    });
  }

  void _autoConnect() async {
    final socketService = Provider.of<SocketService>(context, listen: false);
    await socketService.connect();
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
                MapControlWidget(
                  socketService: socketService,
                  droneService: droneService,
                ),
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