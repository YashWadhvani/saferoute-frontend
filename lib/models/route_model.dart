// models/route_model.dart
// Data model representing a single candidate route returned by the backend.
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// RouteModel holds the parsed route info (points, safety score, color, tags).
class RouteModel {
  final String id;
  final List<LatLng> points;
  final double safetyScore;
  final String? color;
  final List<String> tags;
  final String distanceText;
  final String durationText;

  RouteModel({
    required this.id,
    required this.points,
    required this.safetyScore,
    this.color,
    this.tags = const [],
    this.distanceText = '',
    this.durationText = '',
  });

  factory RouteModel.fromJson(Map<String, dynamic> json, List<LatLng> Function(String) decodePolyline) {
    double parseDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

  final id = json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString();
    final safetyVal = json['safetyScore'] ?? json['safety_score'] ?? json['safety'];
    final score = parseDouble(safetyVal);
    final String? colorStr = json['color'] is String ? (json['color'] as String) : null;

    List<String> tags = [];
    if (json['tags'] is List) {
      tags = (json['tags'] as List).map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }

    String distanceText = '';
    if (json['distance'] is Map && json['distance']['text'] != null) distanceText = json['distance']['text'].toString();
    String durationText = '';
    if (json['duration'] is Map && json['duration']['text'] != null) durationText = json['duration']['text'].toString();

    List<LatLng> points = [];
    if (json['polyline'] is String) {
      points = decodePolyline(json['polyline'] as String);
    } else if (json['points'] is List) {
      try {
        points = (json['points'] as List).map<LatLng>((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
      } catch (_) {
        points = [];
      }
    }

    return RouteModel(id: id, points: points, safetyScore: score, color: colorStr, tags: tags, distanceText: distanceText, durationText: durationText);
  }
}
