import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SensorMapService extends ChangeNotifier {
  static const _prefsKey = 'sensor_map';
  static const _defaultMap = {
    'fire:location1': {'x': 10.0, 'y': 20.0},
    'fire:location2': {'x': 30.0, 'y': 40.0},
    'fire:location3': {'x': 50.0, 'y': 60.0},
    'fire:location4': {'x': 70.0, 'y': 80.0},
  };

  Map<String, Map<String, double>> _map =
      _defaultMap.map((k, v) => MapEntry(k, {'x': v['x']!, 'y': v['y']!}));
  bool _pendingRemote = false;

  Map<String, Map<String, double>> get map => _map;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        final decoded = jsonDecode(saved) as Map<String, dynamic>;
        _map = _toDoubleMap(decoded);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> fetchRemote() async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('config').doc('sensor_map').get();
      if (doc.exists) {
        final data = doc.data()!;
        _map = _toDoubleMap(Map<String, dynamic>.from(data));
        await _saveLocal();
        notifyListeners();
      }
    } catch (_) {
      // ignore; stay with local map
    }
  }

  Future<void> updateAndPersist(Map<String, Map<String, double>> newMap) async {
    _map = Map.fromEntries(newMap.entries.map(
        (e) => MapEntry(e.key.toLowerCase(), {'x': e.value['x']!, 'y': e.value['y']!})));
    await _saveLocal();
    _pendingRemote = true;
    notifyListeners();
  }

  Future<void> pushRemote() async {
    if (!_pendingRemote) return;
    try {
      await FirebaseFirestore.instance
          .collection('config')
          .doc('sensor_map')
          .set(_map);
      _pendingRemote = false;
    } catch (_) {
      _pendingRemote = true;
    }
  }

  Future<void> pushToServer(
      Future<bool> Function(Map<String, Map<String, double>>) sender) async {
    await sender(_map);
  }

  Map<String, Map<String, double>> _toDoubleMap(Map<String, dynamic> raw) {
    final out = <String, Map<String, double>>{};
    raw.forEach((k, v) {
      if (v is Map<String, dynamic> && v.containsKey('x') && v.containsKey('y')) {
        final dx = (v['x'] as num).toDouble();
        final dy = (v['y'] as num).toDouble();
        out[k.toLowerCase()] = {'x': dx, 'y': dy};
      }
    });
    return out.isNotEmpty ? out : _defaultMap.map((k, v) => MapEntry(k, {'x': v['x']!, 'y': v['y']!}));
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_map));
    } catch (_) {}
  }
}

