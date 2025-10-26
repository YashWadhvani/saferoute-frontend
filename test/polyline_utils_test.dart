import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute_app/utils/polyline_utils.dart';
void main() {
  test('decodePolyline returns expected points for known encoded string', () {
    // polyline for two points: (38.5,-120.2) -> (40.7,-120.95) -> (43.252,-126.453)
    final encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    final pts = decodePolyline(encoded);
    expect(pts.length, greaterThan(0));
    expect(pts.first.latitude, closeTo(38.5, 0.001));
    expect(pts.first.longitude, closeTo(-120.2, 0.001));
  });
}
