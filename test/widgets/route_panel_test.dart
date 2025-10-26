import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:saferoute_app/widgets/route_panel.dart';
import 'package:saferoute_app/models/route_model.dart';

void main() {
  testWidgets('RoutePanel shows routes and allows selection', (WidgetTester tester) async {
    final routes = [
      RouteModel(id: 'r1', points: [], color: '#ff0000', safetyScore: 3.5, distanceText: '1 km', durationText: '5 min'),
      RouteModel(id: 'r2', points: [], color: '#00ff00', safetyScore: 4.2, distanceText: '1.2 km', durationText: '6 min'),
    ];

    int? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoutePanel(
          routes: routes,
          selectedIndex: null,
          navigating: false,
          onSelect: (i) => selected = i,
          onStartNav: (i) {},
          onClose: () {},
        ),
      ),
    ));

    expect(find.text('Routes'), findsOneWidget);
    await tester.tap(find.text('Route 1'));
    await tester.pumpAndSettle();
    expect(selected, 0);
  });
}
