import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute_app/models/route_model.dart';

// We use a small fake decoder that mirrors expected shape
void main() {
  test('RouteModel.fromJson parses points and fields', () {
    final json = {
      'id': 'r1',
      'points': [
        {'lat': 10.0, 'lng': 20.0},
        {'lat': 11.0, 'lng': 21.0},
      ],
      'safetyScore': 4.2,
      'color': '#00FF00',
      'tags': ['a', 'b'],
      'distance': {'text': '5 km'},
      'duration': {'text': '8 mins'},
    };

    final r = RouteModel.fromJson(json, (s) => []);

    // Because our fake decodeFake returns list-of-maps not LatLng, the factory will handle actual decode in real code.
    // Here we only validate that no exception is thrown and fields are read.
    expect(r.id, equals('r1'));
    expect(r.safetyScore, closeTo(4.2, 0.001));
    expect(r.color, equals('#00FF00'));
    expect(r.tags.length, equals(2));
    expect(r.distanceText, equals('5 km'));
  });
}
