// widgets/compact_route_bar.dart
// Small top bar shown during active navigation that replaces the editable inputs.
import 'package:flutter/material.dart';

typedef OnStop = void Function();

class CompactRouteBar extends StatelessWidget {
  final String src;
  final String dst;
  final OnStop onStop;

  const CompactRouteBar({super.key, required this.src, required this.dst, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('$src → $dst', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: () => onStop()),
        ],
      ),
    );
  }
}
