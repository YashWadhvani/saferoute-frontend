// state/route_state.dart
// Centralized ChangeNotifier that fetches and holds route candidates from the backend.
import 'package:flutter/material.dart';
import '../models/route_model.dart';
import '../services/route_service.dart';
import '../utils/polyline_utils.dart';

class RouteState extends ChangeNotifier {
  List<RouteModel> routes = [];
  int? selectedIndex;
  bool loading = false;
  String? error;

  Future<void> fetchRoutes(Map<String, dynamic> data) async {
    loading = true;
    error = null;
    routes = [];
    selectedIndex = null;
    notifyListeners();

    try {
      final body = await RouteService.compareRoutes(data);
      if (body == null) throw Exception('Empty response');
      final routesRaw = body['routes'] as List?;
      if (routesRaw == null) throw Exception('Invalid response: missing routes');

      final parsed = routesRaw.map<RouteModel>((r) => RouteModel.fromJson(r as Map<String, dynamic>, decodePolyline)).toList();

      routes = parsed;
      if (routes.isNotEmpty) {
        int bestIdx = 0;
        double bestScore = routes[0].safetyScore;
        for (int i = 1; i < routes.length; i++) {
          if (routes[i].safetyScore > bestScore) {
            bestScore = routes[i].safetyScore;
            bestIdx = i;
          }
        }
        selectedIndex = bestIdx;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void selectRoute(int i) {
    if (i < 0 || i >= routes.length) return;
    selectedIndex = i;
    notifyListeners();
  }
}
