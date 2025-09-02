import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/drone_service.dart';
import '../services/socket_service.dart';
import '../models/coordinates.dart';

class CoordinateInputScreen extends StatefulWidget {
  const CoordinateInputScreen({super.key});

  @override
  State<CoordinateInputScreen> createState() => _CoordinateInputScreenState();
}

class _CoordinateInputScreenState extends State<CoordinateInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _xController = TextEditingController();
  final _yController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fire Coordinates'),
        centerTitle: true,
      ),
      body: Consumer2<DroneService, SocketService>(
        builder: (context, droneService, socketService, child) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!socketService.isConnected)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          border: Border.all(color: Colors.orange[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Not connected to Raspberry Pi. You can still enter coordinates.',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 20),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Drone Status',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  droneService.status.isArmed ? Icons.security : Icons.security_outlined,
                                  color: droneService.status.isArmed ? Colors.green : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(droneService.status.stateDisplayName),
                                const Spacer(),
                                Text(
                                  'Battery: ${droneService.status.battery.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: droneService.status.battery < 20 ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Arm Drone',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'The drone must be armed before starting a mission.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: droneService.status.canArm && !_isLoading
                                        ? () => _armDrone(droneService)
                                        : null,
                                    icon: const Icon(Icons.security),
                                    label: const Text('Arm Drone'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: droneService.status.isArmed && !_isLoading
                                        ? () => _disarmDrone(droneService)
                                        : null,
                                    icon: const Icon(Icons.security_outlined),
                                    label: const Text('Disarm'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey[600],
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fire Location Coordinates',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _xController,
                                    decoration: const InputDecoration(
                                      labelText: 'X Coordinate',
                                      hintText: 'Enter X position',
                                      prefixIcon: Icon(Icons.straighten),
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter X coordinate';
                                      }
                                      if (double.tryParse(value) == null) {
                                        return 'Please enter a valid number';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    controller: _yController,
                                    decoration: const InputDecoration(
                                      labelText: 'Y Coordinate',
                                      hintText: 'Enter Y position',
                                      prefixIcon: Icon(Icons.straighten),
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter Y coordinate';
                                      }
                                      if (double.tryParse(value) == null) {
                                        return 'Please enter a valid number';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: droneService.status.canStartMission && !_isLoading
                            ? () => _startMission(droneService)
                            : null,
                        icon: _isLoading 
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.flight_takeoff),
                        label: Text(_isLoading ? 'Starting Mission...' : 'Start Mission'),
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

                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Enter the X and Y coordinates of the fire location. Make sure the drone is armed before starting the mission.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _armDrone(DroneService droneService) async {
    setState(() { _isLoading = true; });
    final success = await droneService.armDrone();
    setState(() { _isLoading = false; });
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Arming command sent'), backgroundColor: Colors.green),
      );
    }
  }

  void _disarmDrone(DroneService droneService) async {
    setState(() { _isLoading = true; });
    final success = await droneService.disarmDrone();
    setState(() { _isLoading = false; });
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disarm command sent'), backgroundColor: Colors.grey),
      );
    }
  }

  void _startMission(DroneService droneService) async {
    if (!_formKey.currentState!.validate()) return;
    final x = double.parse(_xController.text);
    final y = double.parse(_yController.text);
    final coordinates = Coordinates(x: x, y: y);

    setState(() { _isLoading = true; });
    final success = await droneService.startMission(coordinates);
    setState(() { _isLoading = false; });

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mission started to coordinates ($x, $y)'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start mission'), backgroundColor: Colors.red),
      );
    }
  }
} 