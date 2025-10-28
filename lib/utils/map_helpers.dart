import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

List<LatLng> decodePolyline(String encoded) {
  final List<LatLng> points = [];
  int index = 0;
  int len = encoded.length;
  int lat = 0;
  int lng = 0;
  while (index < len) {
    int b;
    int shift = 0;
    int result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
    lat += dlat;
    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
    lng += dlng;
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

Color? parseColorString(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final s = input.trim();
  try {
    if (s.startsWith('#')) {
      final hex = s.substring(1);
      if (hex.length == 6) {
        final v = int.parse('FF$hex', radix: 16);
        return Color(v);
      } else if (hex.length == 8) {
        final v = int.parse(hex, radix: 16);
        return Color(v);
      }
    }
    if (s.startsWith('0x')) {
      final v = int.parse(s);
      return Color(v);
    }
    final c = s.toLowerCase();
    if (c.contains('green')) return Colors.green;
    if (c.contains('yellow')) return Colors.yellow;
    if (c.contains('orange')) return Colors.orange;
    if (c.contains('red')) return Colors.red;
    if (c.contains('blue')) return Colors.blue;
    return Colors.blueGrey;
  } catch (_) {
    return null;
  }
}

double bearing(LatLng a, LatLng b) {
  final lat1 = _toRad(a.latitude);
  final lat2 = _toRad(b.latitude);
  final dLon = _toRad(b.longitude - a.longitude);
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  final brng = math.atan2(y, x);
  return (_toDeg(brng) + 360) % 360;
}

double _toRad(double d) => d * math.pi / 180.0;
double _toDeg(double r) => r * 180.0 / math.pi;

double remainingDistanceFromIndexOnRoute(List<LatLng> pts, int idx) {
  if (idx >= pts.length - 1) return 0.0;
  double sum = 0.0;
  for (int i = idx; i < pts.length - 1; i++) {
    sum += Geolocator.distanceBetween(pts[i].latitude, pts[i].longitude, pts[i + 1].latitude, pts[i + 1].longitude);
  }
  return sum;
}

int findNearestIndexOnRoute(List<LatLng> pts, LatLng loc) {
  if (pts.isEmpty) return 0;
  double best = double.infinity;
  int idx = 0;
  for (int i = 0; i < pts.length; i++) {
    final d = Geolocator.distanceBetween(loc.latitude, loc.longitude, pts[i].latitude, pts[i].longitude);
    if (d < best) {
      best = d;
      idx = i;
    }
  }
  return idx;
}

String formatDistance(double meters) {
  if (meters >= 1000) {
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }
  return '${meters.round()} m';
}

String formatDistanceLong(double meters) {
  if (meters >= 1000) {
    final km = meters / 1000.0;
    final kmStr = km.toStringAsFixed(1);
    return '$kmStr kilometers';
  }
  final m = meters.round();
  return m == 1 ? '$m meter' : '$m meters';
}
