import 'package:flutter/material.dart';
import '../services/drone_service.dart';
import '../services/socket_service.dart';

class ControlButtonsWidget extends StatelessWidget {
  final SocketService socketService;
  final DroneService droneService;
  final VoidCallback onSendCoordinates;
  final VoidCallback onViewMissionStatus;
  final bool showSendCoordinates; // client=false
  final bool showArmButton; // client=true but labeled Fly
  final bool isClientMode;

  const ControlButtonsWidget({
    super.key,
    required this.socketService,
    required this.droneService,
    required this.onSendCoordinates,
    required this.onViewMissionStatus,
    this.showSendCoordinates = true,
    this.showArmButton = true,
    this.isClientMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mission Control',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (showSendCoordinates)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: onSendCoordinates,
                  icon: const Icon(Icons.send_and_archive),
                  label: const Text('Send Fire Coordinates'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            if (showSendCoordinates) const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onViewMissionStatus,
                    icon: const Icon(Icons.monitor),
                    label: const Text('Mission Status'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _requestStatus(context),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (showArmButton)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: droneService.status.canArm
                          ? () => _quickArm(context)
                          : null,
                      icon: const Icon(Icons.flight_takeoff),
                      label: Text(isClientMode ? 'Fly' : 'Arm'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green[700],
                        side: BorderSide(color: Colors.green[700]!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: droneService.status.canAbort
                          ? () => _quickAbort(context)
                          : null,
                      icon: const Icon(Icons.cancel),
                      label: const Text('Emergency Stop'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[700],
                        side: BorderSide(color: Colors.red[700]!),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            // Status indicators at bottom
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatusIndicator(
                  'Connection',
                  socketService.isConnected,
                  socketService.isConnected ? Colors.green : Colors.red,
                ),
                _buildStatusIndicator(
                  'Armed',
                  droneService.status.isArmed,
                  droneService.status.isArmed ? Colors.green : Colors.grey,
                ),
                _buildStatusIndicator(
                  'Mission Active',
                  droneService.status.canAbort,
                  droneService.status.canAbort ? Colors.blue : Colors.grey,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool isActive, Color color) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _requestStatus(BuildContext context) async {
    final success = await droneService.requestStatus();
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status refresh requested'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _quickArm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isClientMode ? 'Fly' : 'Arm Drone'),
        content: Text(isClientMode
            ? 'Start the drone now? Ensure the area is clear.'
            : 'Are you sure you want to arm the drone? Make sure the area is clear.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(isClientMode ? 'Fly' : 'Arm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await droneService.armDrone();
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isClientMode ? 'Fly command sent' : 'Arm command sent'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _quickAbort(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency Stop'),
        content: const Text('This will immediately abort the current mission and return the drone to home. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Emergency Stop'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await droneService.abortMission();
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Emergency abort command sent'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
} 