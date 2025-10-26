// color_utils.dart
// Helper to parse backend-provided color strings into Flutter [Color] objects.
import 'package:flutter/material.dart';

/// Parse color strings like `#RRGGBB`, `#AARRGGBB`, `0xAARRGGBB` or named colors.
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
