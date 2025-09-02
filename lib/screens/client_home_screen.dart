import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/drone_service.dart';
import '../services/socket_service.dart';
import '../models/drone_status.dart';
import '../widgets/control_buttons_widget.dart';
import '../widgets/drone_status_widget.dart';
import 'mission_status_screen.dart';
import 'login_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  bool _pulledSettings = false;
  Map<String, dynamic>? _clientSettings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _pullClientSettings();
      final socketService = context.read<SocketService>();
      if (!socketService.isConnected) {
        await socketService.connect();
      }
    });
  }

  Future<void> _pullClientSettings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        setState(() { _pulledSettings = true; });
        return;
      }
      final emailKey = user.email!.toLowerCase();
      final doc = await FirebaseFirestore.instance.collection('clients').doc(emailKey).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          setState(() { _clientSettings = data; _pulledSettings = true; });
          final host = data['piIp'] as String?;
          final port = (data['port'] as num?)?.toInt();
          if (host != null && port != null) {
            final socketService = context.read<SocketService>();
            socketService.updateConnectionDetails(host, port);
          }
        } else {
          setState(() { _pulledSettings = true; });
        }
      } else {
        setState(() { _pulledSettings = true; });
      }
    } catch (_) {
      setState(() { _pulledSettings = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final showLogin = user == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardian'),
        centerTitle: true,
        actions: [
          if (showLogin)
            IconButton(
              tooltip: 'Login',
              icon: const Icon(Icons.login),
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            )
          else
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: _confirmLogout,
            ),
        ],
      ),
      body: SafeArea(
        child: Consumer2<SocketService, DroneService>(
          builder: (context, socketService, droneService, _) {
            final status = droneService.status;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_pulledSettings && _clientSettings == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange[700]),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('Not set up yet. Ask your installer (admin) to push your settings.'),
                          ),
                        ],
                      ),
                    ),

                  DroneStatusWidget(status: status),
                  const SizedBox(height: 16),
                  _DistanceCard(status: status),
                  const SizedBox(height: 16),
                  ControlButtonsWidget(
                    socketService: socketService,
                    droneService: droneService,
                    onSendCoordinates: () {},
                    onViewMissionStatus: () => _navigateToMissionStatus(context),
                    showSendCoordinates: false,
                    showArmButton: true,
                    isClientMode: true,
                  ),
                ],
              ),
            );
          },
        ),
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
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _navigateToMissionStatus(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const MissionStatusScreen(),
      ),
    );
  }
}

class _DistanceCard extends StatelessWidget {
  final DroneStatus status;
  const _DistanceCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final distance = _computeDistanceToFire(status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.straighten, color: Colors.purple[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Distance to Fire', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    distance == null ? 'Unknown' : '${distance.toStringAsFixed(1)} m',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.purple[700],
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double? _computeDistanceToFire(DroneStatus s) {
    final x = s.pose[0];
    final y = s.pose[1];
    final dx = x;
    final dy = y;
    final dist = (dx * dx + dy * dy).abs().toDouble();
    return dist.isFinite ? dist.sqrtSafe() : null;
  }
}

extension _Math on double {
  double sqrtSafe() {
    if (this < 0) return 0;
    return MathHelper.sqrt(this);
  }
}

class MathHelper {
  static double sqrt(double v) {
    return v == 0 ? 0 : v > 0 ? _sqrtNewton(v) : 0;
  }
  static double _sqrtNewton(double x) {
    double r = x;
    for (int i = 0; i < 8; i++) {
      r = 0.5 * (r + x / r);
    }
    return r;
  }
}
