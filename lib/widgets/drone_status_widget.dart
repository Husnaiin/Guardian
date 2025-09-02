import 'package:flutter/material.dart';
import '../models/drone_status.dart';

class DroneStatusWidget extends StatelessWidget {
  final DroneStatus status;

  const DroneStatusWidget({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStatusIcon(),
                  color: _getStatusColor(),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Drone Status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      status.stateDisplayName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _getStatusColor(),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: status.isArmed ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        status.isArmed ? Icons.security : Icons.security_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        status.isArmed ? 'ARMED' : 'DISARMED',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoContainer(
                    'Position',
                    '(${status.pose[0].toStringAsFixed(1)}, ${status.pose[1].toStringAsFixed(1)})',
                    Icons.location_on,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoContainer(
                    'Altitude',
                    '${status.pose[2].toStringAsFixed(1)}m',
                    Icons.height,
                    Colors.purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoContainer(
                    'Battery',
                    '${status.battery.toStringAsFixed(1)}%',
                    Icons.battery_std,
                    _getBatteryColor(status.battery),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoContainer(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (status.state) {
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

  Color _getStatusColor() {
    switch (status.state) {
      case DroneState.idle:
        return Colors.grey[600]!;
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

  Color _getBatteryColor(double battery) {
    if (battery > 60) return Colors.green;
    if (battery > 30) return Colors.orange;
    return Colors.red;
  }
} 