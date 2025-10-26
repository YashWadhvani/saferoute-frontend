import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute_app/utils/color_utils.dart';
import 'package:flutter/material.dart';

void main() {
  test('parseColorString handles hex and names', () {
    final c1 = parseColorString('#FF0000');
  expect(c1, isNotNull);
  expect((c1!.a * 255.0).round() & 0xFF, equals(0xFF));
  expect((c1.r * 255.0).round() & 0xFF, equals(0xFF));
  expect((c1.g * 255.0).round() & 0xFF, equals(0x00));
  expect((c1.b * 255.0).round() & 0xFF, equals(0x00));

    final c2 = parseColorString('green');
  expect(c2, isNotNull);
  expect((c2!.r * 255.0).round() & 0xFF, equals((Colors.green.r * 255.0).round() & 0xFF));
  expect((c2.g * 255.0).round() & 0xFF, equals((Colors.green.g * 255.0).round() & 0xFF));
  expect((c2.b * 255.0).round() & 0xFF, equals((Colors.green.b * 255.0).round() & 0xFF));

    final c3 = parseColorString('0xFF00FF00');
  expect(c3, isNotNull);
  expect((c3!.a * 255.0).round() & 0xFF, equals(0xFF));
  expect((c3.r * 255.0).round() & 0xFF, equals(0x00));
  expect((c3.g * 255.0).round() & 0xFF, equals(0xFF));
  expect((c3.b * 255.0).round() & 0xFF, equals(0x00));
  });
}
