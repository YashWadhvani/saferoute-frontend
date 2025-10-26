// services/navigation_service.dart
// Provides real-time navigation updates (nearest point, distances, instructions) and TTS integration.
import 'dart:async';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/map_helpers.dart';

class NavigationUpdate {
  final LatLng userLocation;
  final String instruction;
  final double distanceToNext;
  final double remainingDistance;
  final int nearestIndex;
  final String spoken; // exact text spoken (or would be spoken) by TTS

  NavigationUpdate(this.userLocation, this.instruction, this.distanceToNext, this.remainingDistance, this.nearestIndex, this.spoken);
}

typedef DecodePolylineFn = List<LatLng> Function(String);

class NavigationService {
  final StreamController<NavigationUpdate> _controller = StreamController.broadcast();
  Stream<NavigationUpdate> get updates => _controller.stream;
  StreamSubscription<Position>? _posSub;
  final FlutterTts? tts;
  String? _lastInstruction;
  int? _lastDistanceBucket;
  DateTime? _suppressUntil;

  NavigationService({this.tts});

  void start(List<LatLng> routePoints, {String? language, double? rate, bool muteOnRestore = false}) async {
    _posSub?.cancel();

    if (muteOnRestore) {
      _suppressUntil = DateTime.now().add(const Duration(seconds: 4));
    } else {
      _suppressUntil = null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }

  _posSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2))
    .listen((pos) async {
      final loc = LatLng(pos.latitude, pos.longitude);
  final nearest = findNearestIndexOnRoute(routePoints, loc);
      final nextIdx = math.min(nearest + 1, routePoints.length - 1);
      final instr = (() {
        if (routePoints.length < 3) return 'Continue';
        final prev = (nextIdx - 1).clamp(0, routePoints.length - 1);
        final next = (nextIdx + 1).clamp(0, routePoints.length - 1);
        final a = routePoints[prev];
        final b = routePoints[nextIdx];
        final c = routePoints[next];
        final bearing1 = bearing(a, b);
        final bearing2 = bearing(b, c);
        double diff = (bearing2 - bearing1).abs();
        if (diff > 180) diff = 360 - diff;
        if (diff < 15) return 'Continue straight';
        if (bearing2 > bearing1) return 'Turn right';
        return 'Turn left';
      })();
      final distanceToNext = Geolocator.distanceBetween(loc.latitude, loc.longitude, routePoints[nextIdx].latitude, routePoints[nextIdx].longitude);
      final remaining = remainingDistanceFromIndexOnRoute(routePoints, nextIdx);

      // Decide spoken text for this update (same logic as below for TTS)
      final buckets = [500, 200, 10];
      int bucket = -1;
      for (int i = 0; i < buckets.length; i++) {
        if (distanceToNext <= buckets[i]) {
          bucket = buckets[i];
        }
      }
      final maybeSpoken = bucket == 10 ? instr : '$instr for ${distanceToNext.round()} meters';
      final update = NavigationUpdate(loc, instr, distanceToNext, remaining, nearest, maybeSpoken);
      _controller.add(update);

      // TTS throttling: only speak when instruction changes OR when we pass
      // into a closer distance bucket (200m,100m,50m,20m,10m)
      try {
        // Apply TTS settings if provided
        if (language != null) {
          try { await tts?.setLanguage(language); } catch (_) {}
        }
        if (rate != null) {
          try { await tts?.setSpeechRate(rate); } catch (_) {}
        }
        // speak at fixed distance thresholds: 500m, 200m, and final 10m (brief)
        final buckets = [500, 200, 10];
        int bucket = -1;
        for (int i = 0; i < buckets.length; i++) {
          if (distanceToNext <= buckets[i]) {
            bucket = buckets[i];
          }
        }
        final shouldSpeak = (_lastInstruction != instr) || (_lastDistanceBucket == null && bucket != -1) || (bucket != -1 && _lastDistanceBucket != bucket && (_lastDistanceBucket == null || bucket < _lastDistanceBucket!));
        // Do not speak if we're within a suppression window (used for auto-restore)
        final suppressed = _suppressUntil != null && DateTime.now().isBefore(_suppressUntil!);
        if (shouldSpeak && !suppressed) {
          _lastInstruction = instr;
          _lastDistanceBucket = bucket == -1 ? _lastDistanceBucket : bucket;
          await tts?.stop();
          if (bucket == 10) {
            // final proximity: speak brief instruction without meter count
            await tts?.speak(instr);
          } else {
            await tts?.speak('$instr for ${distanceToNext.round()} meters');
          }
        }
      } catch (_) {}
    });
  }

  void stop() {
    _posSub?.cancel();
    _posSub = null;
  }

  void dispose() {
    _posSub?.cancel();
    _controller.close();
  }

  // helpers are provided by lib/utils/map_helpers.dart
}
