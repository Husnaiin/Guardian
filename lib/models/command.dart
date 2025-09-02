import 'package:equatable/equatable.dart';
import 'coordinates.dart';

class Command extends Equatable {
  final String command;
  final Coordinates? coordinates;
  final Map<String, dynamic>? additionalData;

  const Command({
    required this.command,
    this.coordinates,
    this.additionalData,
  });

  // Factory constructors for different command types
  factory Command.arm() {
    return const Command(command: 'arm');
  }

  factory Command.disarm() {
    return const Command(command: 'disarm');
  }

  factory Command.start(Coordinates coordinates) {
    return Command(
      command: 'start',
      coordinates: coordinates,
    );
  }

  factory Command.abort() {
    return const Command(command: 'abort');
  }

  factory Command.status() {
    return const Command(command: 'status');
  }

  factory Command.buildMap() {
    return const Command(command: 'build_map');
  }

  factory Command.loadMap() {
    return const Command(command: 'load_map');
  }

  factory Command.saveMap() {
    return const Command(command: 'save_map');
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'command': command,
    };

    if (coordinates != null) {
      json.addAll(coordinates!.toJson());
    }

    if (additionalData != null) {
      json.addAll(additionalData!);
    }

    return json;
  }

  factory Command.fromJson(Map<String, dynamic> json) {
    Coordinates? coordinates;
    if (json.containsKey('x') && json.containsKey('y')) {
      coordinates = Coordinates.fromJson(json);
    }

    return Command(
      command: json['command'] as String,
      coordinates: coordinates,
      additionalData: Map<String, dynamic>.from(json)
        ..remove('command')
        ..remove('x')
        ..remove('y'),
    );
  }

  @override
  String toString() {
    return 'Command(command: $command, coordinates: $coordinates, additionalData: $additionalData)';
  }

  @override
  List<Object?> get props => [command, coordinates, additionalData];
} 