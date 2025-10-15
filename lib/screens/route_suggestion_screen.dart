import 'package:flutter/material.dart';

class RouteSuggestionScreen extends StatelessWidget {
  const RouteSuggestionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Suggested Routes")),
      body: const Center(child: Text("Route suggestions coming soon...")),
    );
  }
}
