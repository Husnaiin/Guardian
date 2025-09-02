import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/drone_service.dart';
import '../services/socket_service.dart';
import '../models/drone_status.dart';

class MissionStatusScreen extends StatefulWidget {
  const MissionStatusScreen({super.key});

  @override
  State<MissionStatusScreen> createState() => _MissionStatusScreenState();
}

class _MissionStatusScreenState extends State<MissionStatusScreen> {
  final ScrollController _logScrollController = ScrollController();
  bool _isAborting = false;

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mission Status'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final droneService = Provider.of<DroneService>(context, listen: false);
              droneService.requestStatus();
            },
            tooltip: 'Refresh Status',
          ),
        ],
      ),
      body: Consumer2<DroneService, SocketService>(
        builder: (context, droneService, socketService, child) {
          // Auto-scroll to bottom when new logs arrive
          if (socketService.logs.isNotEmpty) {
            _scrollToBottom();
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drone Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Status',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              _getStatusIcon(droneService.status.state),
                              color: _getStatusColor(droneService.status.state),
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    droneService.status.stateDisplayName,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: _getStatusColor(droneService.status.state),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (droneService.status.message.isNotEmpty)
                                    Text(
                                      droneService.status.message,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoTile(
                                'Position',
                                '(${droneService.status.pose[0].toStringAsFixed(1)}, ${droneService.status.pose[1].toStringAsFixed(1)})',
                                Icons.location_on,
                              ),
                            ),
                            Expanded(
                              child: _buildInfoTile(
                                'Altitude',
                                '${droneService.status.pose[2].toStringAsFixed(1)}m',
                                Icons.height,
                              ),
                            ),
                            Expanded(
                              child: _buildInfoTile(
                                'Battery',
                                '${droneService.status.battery.toStringAsFixed(1)}%',
                                Icons.battery_std,
                                valueColor: droneService.status.battery < 20 ? Colors.red : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Control Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: droneService.status.canAbort && !_isAborting
                            ? () => _abortMission(droneService)
                            : null,
                        icon: _isAborting 
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.cancel),
                        label: Text(_isAborting ? 'Aborting...' : 'Abort Mission'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => socketService.clearLogs(),
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear Logs'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Live Logs Section
                Expanded(
                  child: Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(Icons.article, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              Text(
                                'Live Telemetry Logs',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: socketService.isConnected ? Colors.green : Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      socketService.isConnected ? Icons.wifi : Icons.wifi_off,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      socketService.isConnected ? 'Connected' : 'Disconnected',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: socketService.logs.isEmpty
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.article_outlined,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'No logs available',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: _logScrollController,
                                  padding: const EdgeInsets.all(8.0),
                                  itemCount: socketService.logs.length,
                                  itemBuilder: (context, index) {
                                    final log = socketService.logs[index];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.fiber_manual_record,
                                            size: 8,
                                            color: Colors.blue[700],
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              log,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(DroneState state) {
    switch (state) {
      case DroneState.idle:
        return Icons.pause_circle_outline;
      case DroneState.arming:
        return Icons.refresh;
      case DroneState.armed:
        return Icons.security;
      case DroneState.inMission:
      case DroneState.enroute:
        return Icons.flight;
      case DroneState.arrived:
        return Icons.place;
      case DroneState.suppressing:
        return Icons.water_drop;
      case DroneState.returning:
        return Icons.home;
      case DroneState.complete:
        return Icons.check_circle;
      case DroneState.error:
        return Icons.error;
      case DroneState.aborting:
        return Icons.cancel;
    }
  }

  Color _getStatusColor(DroneState state) {
    switch (state) {
      case DroneState.idle:
        return Colors.grey;
      case DroneState.arming:
        return Colors.orange;
      case DroneState.armed:
        return Colors.green;
      case DroneState.inMission:
      case DroneState.enroute:
        return Colors.blue;
      case DroneState.arrived:
        return Colors.purple;
      case DroneState.suppressing:
        return Colors.red;
      case DroneState.returning:
        return Colors.indigo;
      case DroneState.complete:
        return Colors.green;
      case DroneState.error:
        return Colors.red;
      case DroneState.aborting:
        return Colors.orange;
    }
  }

  void _abortMission(DroneService droneService) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abort Mission'),
        content: const Text('Are you sure you want to abort the current mission? The drone will return to home immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Abort Mission'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isAborting = true;
    });

    final success = await droneService.abortMission();
    
    setState(() {
      _isAborting = false;
    });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mission abort command sent'),
          backgroundColor: Colors.orange,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to abort mission'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
} 