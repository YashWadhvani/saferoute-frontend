import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:saferoute_app/widgets/search_controls.dart';
import 'package:saferoute_app/services/places_service.dart';
import 'package:google_place/google_place.dart';

class FakePlacesService implements IPlacesService {
  @override
  Future<List<AutocompletePrediction>> autocomplete(String input) async => <AutocompletePrediction>[];

  @override
  Future<DetailsResult?> getPlaceDetails(String placeId) async => null;
}

void main() {
  testWidgets('SearchControls shows fields and triggers compare callback', (WidgetTester tester) async {
    final srcCtrl = TextEditingController();
    final dstCtrl = TextEditingController();

    bool compareTapped = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SearchControls(
          sourceController: srcCtrl,
          destController: dstCtrl,
          navigating: false,
          showCompare: true,
          sourceLat: null,
          sourceLng: null,
          destLat: null,
          destLng: null,
          onSourceCoordsSet: (a, b) {},
          onSourceCoordsCleared: () {},
          onDestCoordsSet: (a, b) {},
          onComparePressed: () => compareTapped = true,
          onMoveCamera: (pos) {},
          placesService: FakePlacesService(),
        ),
      ),
    ));

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Compare Routes'), findsOneWidget);

    await tester.tap(find.text('Compare Routes'));
    await tester.pumpAndSettle();

    expect(compareTapped, isTrue);
  });
}
