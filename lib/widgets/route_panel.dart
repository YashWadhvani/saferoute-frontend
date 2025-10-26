// widgets/route_panel.dart
// UI widget that displays the list of candidate routes and actions (select, start navigation).
import 'package:flutter/material.dart';
import '../models/route_model.dart';
import '../utils/color_utils.dart';

typedef OnSelect = void Function(int index);
typedef OnStartNav = void Function(int index);

class RoutePanel extends StatelessWidget {
  final List<RouteModel> routes;
  final int? selectedIndex;
  final bool navigating;
  final OnSelect onSelect;
  final OnStartNav onStartNav;
  final VoidCallback onClose;

  const RoutePanel({super.key, required this.routes, required this.selectedIndex, required this.navigating, required this.onSelect, required this.onStartNav, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      color: Colors.white,
      height: navigating ? 120 : 260,
      child: navigating
          ? Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(child: Text('Routes available: ${routes.length}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  IconButton(icon: const Icon(Icons.expand_less), onPressed: onClose)
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Routes', style: TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(icon: const Icon(Icons.close), onPressed: onClose)
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: routes.length,
                    itemBuilder: (context, index) {
                      final r = routes[index];
                      final selected = selectedIndex == index;
                      return ListTile(
                        selected: selected,
                        onTap: () => onSelect(index),
                        leading: r.color != null
                            ? Container(width: 12, height: 12, decoration: BoxDecoration(color: parseColorString(r.color) ?? Colors.blueGrey, shape: BoxShape.circle))
                            : null,
                        title: Text('Route ${index + 1}${selected ? ' (selected)' : ''}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Safety: ${r.safetyScore.toStringAsFixed(2)}'),
                            if (r.distanceText.isNotEmpty) Text('Distance: ${r.distanceText}'),
                            if (r.durationText.isNotEmpty) Text('Duration: ${r.durationText}'),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.map), onPressed: () => onSelect(index)),
                            IconButton(icon: Icon(navigating && selected ? Icons.stop : Icons.navigation), onPressed: () => onStartNav(index)),
                          ],
                        ),
                      );
                    },
                  ),
                )
              ],
            ),
    );
  }
}
