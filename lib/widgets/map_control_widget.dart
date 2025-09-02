import 'package:flutter/material.dart';
import '../services/drone_service.dart';
import '../services/socket_service.dart';
import '../models/command.dart';

class MapControlWidget extends StatefulWidget {
  final SocketService socketService;
  final DroneService droneService;

  const MapControlWidget({
    super.key,
    required this.socketService,
    required this.droneService,
  });

  @override
  State<MapControlWidget> createState() => _MapControlWidgetState();
}

class _MapControlWidgetState extends State<MapControlWidget> {
  bool _isBuilding = false;
  bool _isLoading = false;
  bool _isSaving = false;
  String _mapStatus = 'No map loaded';

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
                Icon(Icons.map, color: Colors.purple[700]),
                const SizedBox(width: 8),
                Text(
                  'SLAM Map Control',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _mapStatus,
                    style: TextStyle(
                      color: Colors.purple[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Map Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !_isBuilding && !_isLoading
                        ? () => _buildMap(context)
                        : null,
                    icon: _isBuilding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_location),
                    label: Text(_isBuilding ? 'Building...' : 'Build Map'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !_isBuilding && !_isLoading
                        ? () => _loadMap(context)
                        : null,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(_isLoading ? 'Loading...' : 'Load Map'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            
            // Save Map Button (shown only when building is complete)
            if (_isBuilding || _mapStatus.contains('built'))
              Column(
                children: [
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: !_isSaving && _mapStatus.contains('built')
                          ? () => _saveMap(context)
                          : null,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isSaving ? 'Saving Map...' : 'Save Map'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            
            const SizedBox(height: 12),
            
            // Help Text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.purple[700]),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Build Map: Record new SLAM map for drone localization\nLoad Map: Use previously saved map from Raspberry Pi',
                      style: TextStyle(fontSize: 12),
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

  void _buildMap(BuildContext context) async {
    setState(() {
      _isBuilding = true;
      _mapStatus = 'Building map...';
    });

    try {
      // Send build map command to Pi
      final success = await widget.socketService.sendCommand(
        Command.buildMap(),
      );

      if (success) {
        // Simulate building process (in real implementation, listen for Pi responses)
        await Future.delayed(const Duration(seconds: 3));
        
        setState(() {
          _mapStatus = 'Map built successfully';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Map building started. Check mission status for progress.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        throw Exception('Failed to send build map command');
      }
    } catch (e) {
      setState(() {
        _mapStatus = 'Build failed';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to build map: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isBuilding = false;
      });
    }
  }

  void _loadMap(BuildContext context) async {
    setState(() {
      _isLoading = true;
      _mapStatus = 'Loading map...';
    });

    try {
      // Send load map command to Pi
      final success = await widget.socketService.sendCommand(
        Command.loadMap(),
      );

      if (success) {
        await Future.delayed(const Duration(seconds: 2));
        
        setState(() {
          _mapStatus = 'Map loaded successfully';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Map loaded from Raspberry Pi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Failed to send load map command');
      }
    } catch (e) {
      setState(() {
        _mapStatus = 'Load failed';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load map: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _saveMap(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Map'),
        content: const Text('Save the current SLAM map to Raspberry Pi? This will overwrite any existing map.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Save Map'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSaving = true;
      _mapStatus = 'Saving map...';
    });

    try {
      // Send save map command to Pi
      final success = await widget.socketService.sendCommand(
        Command.saveMap(),
      );

      if (success) {
        await Future.delayed(const Duration(seconds: 2));
        
        setState(() {
          _mapStatus = 'Map saved successfully';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Map saved to Raspberry Pi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Failed to send save map command');
      }
    } catch (e) {
      setState(() {
        _mapStatus = 'Save failed';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save map: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }
} 