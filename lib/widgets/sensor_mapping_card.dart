import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import '../services/sensor_map_service.dart';
import '../models/command.dart';
import 'package:provider/provider.dart';

class SensorMappingCard extends StatefulWidget {
  final SocketService socketService;
  const SensorMappingCard({super.key, required this.socketService});

  @override
  State<SensorMappingCard> createState() => _SensorMappingCardState();
}

class _SensorMappingCardState extends State<SensorMappingCard> {
  final _formKey = GlobalKey<FormState>();
  final _loc1x = TextEditingController();
  final _loc1y = TextEditingController();
  final _loc2x = TextEditingController();
  final _loc2y = TextEditingController();
  final _loc3x = TextEditingController();
  final _loc3y = TextEditingController();
  final _loc4x = TextEditingController();
  final _loc4y = TextEditingController();
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final map = Provider.of<SensorMapService>(context).map;
    _setControllers(map);
  }

  @override
  void dispose() {
    _loc1x.dispose();
    _loc1y.dispose();
    _loc2x.dispose();
    _loc2y.dispose();
    _loc3x.dispose();
    _loc3y.dispose();
    _loc4x.dispose();
    _loc4y.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sensors, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Text(
                    'Sensor Locations',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _row('Sensor 1', _loc1x, _loc1y),
              _row('Sensor 2', _loc2x, _loc2y),
              _row('Sensor 3', _loc3x, _loc3y),
              _row('Sensor 4', _loc4x, _loc4y),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Save Sensor Map'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, TextEditingController cx, TextEditingController cy) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(child: _numField(cx, 'X')),
          const SizedBox(width: 8),
          Expanded(child: _numField(cy, 'Y')),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController c, String hint) {
    return TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      validator: (v) => double.tryParse((v ?? '').trim()) == null ? 'Num' : null,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final map = _currentMap();
    final sensorService = Provider.of<SensorMapService>(context, listen: false);
    await sensorService.updateAndPersist(map);
    final ok = await widget.socketService.sendCommand(Command.updateSensorMap(map));
    await sensorService.pushRemote();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Sensor map updated' : 'Failed to update sensor map'),
          backgroundColor: ok ? Colors.green[700] : Colors.red,
        ),
      );
      setState(() => _saving = false);
    }
  }

  void _setControllers(Map<String, Map<String, double>> map) {
    _loc1x.text = map['fire:location1']?['x']?.toString() ?? '';
    _loc1y.text = map['fire:location1']?['y']?.toString() ?? '';
    _loc2x.text = map['fire:location2']?['x']?.toString() ?? '';
    _loc2y.text = map['fire:location2']?['y']?.toString() ?? '';
    _loc3x.text = map['fire:location3']?['x']?.toString() ?? '';
    _loc3y.text = map['fire:location3']?['y']?.toString() ?? '';
    _loc4x.text = map['fire:location4']?['x']?.toString() ?? '';
    _loc4y.text = map['fire:location4']?['y']?.toString() ?? '';
  }

  Map<String, Map<String, double>> _currentMap() {
    return {
      'fire:location1': {'x': double.parse(_loc1x.text), 'y': double.parse(_loc1y.text)},
      'fire:location2': {'x': double.parse(_loc2x.text), 'y': double.parse(_loc2y.text)},
      'fire:location3': {'x': double.parse(_loc3x.text), 'y': double.parse(_loc3y.text)},
      'fire:location4': {'x': double.parse(_loc4x.text), 'y': double.parse(_loc4y.text)},
    };
  }
}

