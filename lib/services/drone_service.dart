import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/drone_status.dart';
import '../models/coordinates.dart';
import '../models/command.dart';
import 'socket_service.dart';

class DroneService extends ChangeNotifier {
  DroneStatus _status = const DroneStatus();
  SocketService? _socketService;
  StreamSubscription? _messageSubscription;

  // Getters
  DroneStatus get status => _status;

  void initialize(SocketService socketService) {
    _socketService = socketService;
    
    // Listen to incoming messages from the Pi
    _messageSubscription = _socketService!.messageStream.listen(_handleMessage);
  }

  void _handleMessage(Map<String, dynamic> message) {
    try {
      // Handle different types of messages from the Pi
      if (message.containsKey('status')) {
        _updateStatusFromMessage(message);
      } else if (message.containsKey('error')) {
        _handleError(message['error'].toString());
      } else if (message.containsKey('armed')) {
        _updateArmedStatus(message['armed'] as bool);
      } else if (message.containsKey('arm_errors')) {
        _handleArmErrors(List<String>.from(message['arm_errors']));
      }
    } catch (e) {
      _handleError('Error processing message: $e');
    }
  }

  void _updateStatusFromMessage(Map<String, dynamic> message) {
    DroneState newState = _status.state;
    
    // Parse status from message
    final statusString = message['status'] as String;
    switch (statusString.toLowerCase()) {
      case 'idle':
        newState = DroneState.idle;
        break;
      case 'armed':
        newState = DroneState.armed;
        break;
      case 'enroute':
        newState = DroneState.enroute;
        break;
      case 'arrived':
        newState = DroneState.arrived;
        break;
      case 'suppressing':
        newState = DroneState.suppressing;
        break;
      case 'returning':
        newState = DroneState.returning;
        break;
      case 'complete':
        newState = DroneState.complete;
        break;
      case 'error':
        newState = DroneState.error;
        break;
    }

    // Extract pose and battery if available
    List<double> pose = _status.pose;
    if (message.containsKey('pose')) {
      pose = List<double>.from(message['pose']);
    }

    double battery = _status.battery;
    if (message.containsKey('battery')) {
      battery = (message['battery'] as num).toDouble();
    }

    String statusMessage = message['message'] ?? '';

    _updateStatus(_status.copyWith(
      state: newState,
      pose: pose,
      battery: battery,
      message: statusMessage,
    ));
  }

  void _updateArmedStatus(bool isArmed) {
    final newState = isArmed ? DroneState.armed : DroneState.idle;
    _updateStatus(_status.copyWith(
      isArmed: isArmed,
      state: newState,
      message: isArmed ? 'Drone armed successfully' : 'Drone disarmed',
      errors: [],
    ));
  }

  void _handleArmErrors(List<String> errors) {
    _updateStatus(_status.copyWith(
      state: DroneState.error,
      isArmed: false,
      errors: errors,
      message: 'Arming failed: ${errors.join(', ')}',
    ));
  }

  void _handleError(String error) {
    _updateStatus(_status.copyWith(
      state: DroneState.error,
      message: error,
      errors: [error],
    ));
  }

  void _updateStatus(DroneStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  Future<bool> armDrone() async {
    if (_socketService == null || !_socketService!.isConnected) {
      _handleError('Not connected to Raspberry Pi');
      return false;
    }

    if (!_status.canArm) {
      _handleError('Cannot arm drone in current state');
      return false;
    }

    _updateStatus(_status.copyWith(
      state: DroneState.arming,
      message: 'Arming drone...',
      errors: [],
    ));

    return await _socketService!.sendCommand(Command.arm());
  }

  Future<bool> disarmDrone() async {
    if (_socketService == null || !_socketService!.isConnected) {
      _handleError('Not connected to Raspberry Pi');
      return false;
    }

    _updateStatus(_status.copyWith(
      isArmed: false,
      state: DroneState.idle,
      message: 'Disarming drone...',
      errors: [],
    ));

    return await _socketService!.sendCommand(Command.disarm());
  }

  Future<bool> startMission(Coordinates coordinates) async {
    if (_socketService == null || !_socketService!.isConnected) {
      _handleError('Not connected to Raspberry Pi');
      return false;
    }

    if (!_status.canStartMission) {
      _handleError('Cannot start mission: Drone must be armed first');
      return false;
    }

    _updateStatus(_status.copyWith(
      state: DroneState.inMission,
      message: 'Starting mission to (${coordinates.x}, ${coordinates.y})',
      errors: [],
    ));

    return await _socketService!.sendCommand(Command.start(coordinates));
  }

  Future<bool> abortMission() async {
    if (_socketService == null || !_socketService!.isConnected) {
      _handleError('Not connected to Raspberry Pi');
      return false;
    }

    if (!_status.canAbort) {
      _handleError('No active mission to abort');
      return false;
    }

    _updateStatus(_status.copyWith(
      state: DroneState.aborting,
      message: 'Aborting mission...',
    ));

    return await _socketService!.sendCommand(Command.abort());
  }

  Future<bool> requestStatus() async {
    if (_socketService == null || !_socketService!.isConnected) {
      return false;
    }

    return await _socketService!.sendCommand(Command.status());
  }

  void resetStatus() {
    _updateStatus(const DroneStatus());
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
} 