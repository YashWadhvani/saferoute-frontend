import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:saferoute_app/widgets/route_panel.dart';
import 'package:saferoute_app/models/route_model.dart';

void main() {
  testWidgets('RoutePanel shows routes and callbacks are invoked', (WidgetTester tester) async {
    final routes = [
      RouteModel(id: 'r1', points: [LatLng(0, 0)], safetyScore: 4.2, color: '#00FF00', distanceText: '1.0 km', durationText: '5 mins'),
      RouteModel(id: 'r2', points: [LatLng(1, 1)], safetyScore: 2.1, color: '#FF0000', distanceText: '2.5 km', durationText: '12 mins'),
    ];

    int selected = -1;
    int started = -1;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoutePanel(
          routes: routes,
          selectedIndex: null,
          navigating: false,
          onSelect: (i) => selected = i,
          onStartNav: (i) => started = i,
          onClose: () {},
        ),
      ),
    ));

    // List items should display
    expect(find.text('Route 1'), findsOneWidget);
    expect(find.text('Route 2'), findsOneWidget);

    // Tap first list tile (onSelect)
    await tester.tap(find.text('Route 1'));
    await tester.pumpAndSettle();
    expect(selected, 0);

    // Tap the navigation button for the second route (onStartNav)
    final navButtons = find.byIcon(Icons.navigation);
    expect(navButtons, findsWidgets);
    await tester.tap(navButtons.last);
    await tester.pumpAndSettle();
    expect(started, 1);
  });
}
