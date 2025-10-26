import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_place/google_place.dart';
// no direct map types needed in this test

import 'package:saferoute_app/widgets/search_controls.dart';
import 'package:saferoute_app/services/places_service.dart';

class FakePlacesService implements IPlacesService {
  @override
  Future<List<AutocompletePrediction>> autocomplete(String input) async {
    await Future.delayed(Duration(milliseconds: 10));
    if (input.contains('nowhere')) return [];
    return [AutocompletePrediction(description: 'Test Place', placeId: 'xyz')];
  }

  @override
  Future<DetailsResult?> getPlaceDetails(String placeId) async {
    return DetailsResult(geometry: Geometry(location: Location(lat: 12.34, lng: 56.78)));
  }
}

void main() {
  testWidgets('SearchControls shows synthetic fallback when no predictions', (WidgetTester tester) async {
    final sourceController = TextEditingController();
    final destController = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SearchControls(
          sourceController: sourceController,
          destController: destController,
          navigating: false,
          showCompare: false,
          sourceLat: null,
          sourceLng: null,
          destLat: null,
          destLng: null,
          onSourceCoordsSet: (double lat, double lng) {},
          onSourceCoordsCleared: () {},
          onDestCoordsSet: (double lat, double lng) {},
          onComparePressed: () {},
          onMoveCamera: (_) {},
          placesService: FakePlacesService(),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField).at(1), 'nowhere');
  await tester.pump(const Duration(milliseconds: 450));
  // the typed text will appear both in the TextField and as a suggestion ListTile.
  // assert that the suggestion ListTile exists specifically.
  expect(find.widgetWithText(ListTile, 'nowhere'), findsOneWidget);
  });

  testWidgets('SearchControls shows remote prediction', (WidgetTester tester) async {
    final sourceController = TextEditingController();
    final destController = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SearchControls(
          sourceController: sourceController,
          destController: destController,
          navigating: false,
          showCompare: false,
          sourceLat: null,
          sourceLng: null,
          destLat: null,
          destLng: null,
          onSourceCoordsSet: (double lat, double lng) {},
          onSourceCoordsCleared: () {},
          onDestCoordsSet: (double lat, double lng) {},
          onComparePressed: () {},
          onMoveCamera: (dynamic p) {},
          placesService: FakePlacesService(),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField).at(1), 'somewhere');
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Test Place'), findsOneWidget);
  });
}
