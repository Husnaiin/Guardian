import 'package:equatable/equatable.dart';

enum DroneState {
  idle,
  arming,
  armed,
  inMission,
  enroute,
  arrived,
  suppressing,
  returning,
  complete,
  error,
  aborting
}

class DroneStatus extends Equatable {
  final DroneState state;
  final List<double> pose; // [x, y, z]
  final double battery;
  final String message;
  final bool isArmed;
  final List<String> errors;

  const DroneStatus({
    this.state = DroneState.idle,
    this.pose = const [0.0, 0.0, 0.0],
    this.battery = 100.0,
    this.message = '',
    this.isArmed = false,
    this.errors = const [],
  });

  DroneStatus copyWith({
    DroneState? state,
    List<double>? pose,
    double? battery,
    String? message,
    bool? isArmed,
    List<String>? errors,
  }) {
    return DroneStatus(
      state: state ?? this.state,
      pose: pose ?? this.pose,
      battery: battery ?? this.battery,
      message: message ?? this.message,
      isArmed: isArmed ?? this.isArmed,
      errors: errors ?? this.errors,
    );
  }

  String get stateDisplayName {
    switch (state) {
      case DroneState.idle:
        return 'Idle';
      case DroneState.arming:
        return 'Arming...';
      case DroneState.armed:
        return 'Armed & Ready';
      case DroneState.inMission:
        return 'In Mission';
      case DroneState.enroute:
        return 'En Route';
      case DroneState.arrived:
        return 'Target Reached';
      case DroneState.suppressing:
        return 'Suppressing Fire';
      case DroneState.returning:
        return 'Returning Home';
      case DroneState.complete:
        return 'Mission Complete';
      case DroneState.error:
        return 'Error';
      case DroneState.aborting:
        return 'Aborting Mission';
    }
  }

  bool get canStartMission {
    // Allow starting mission regardless of armed state; server will validate.
    return true;
  }

  bool get canArm {
    return state == DroneState.idle && !isArmed;
  }

  bool get canAbort {
    return state == DroneState.inMission || 
           state == DroneState.enroute || 
           state == DroneState.arrived || 
           state == DroneState.suppressing;
  }

  @override
  List<Object?> get props => [state, pose, battery, message, isArmed, errors];
} 