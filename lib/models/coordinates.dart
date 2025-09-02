import 'package:equatable/equatable.dart';

class Coordinates extends Equatable {
  final double x;
  final double y;

  const Coordinates({
    required this.x,
    required this.y,
  });

  Coordinates copyWith({
    double? x,
    double? y,
  }) {
    return Coordinates(
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
    };
  }

  factory Coordinates.fromJson(Map<String, dynamic> json) {
    return Coordinates(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }

  @override
  String toString() {
    return 'Coordinates(x: $x, y: $y)';
  }

  @override
  List<Object?> get props => [x, y];
} 