import 'package:flutter/material.dart';

class MapDetailScreen extends StatelessWidget {
  const MapDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map Detail')),
      body: const Center(child: Text('Map Detail Screen')),
    );
  }
}
