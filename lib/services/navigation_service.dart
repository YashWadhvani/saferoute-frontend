// services/navigation_service.dart
// Provides real-time navigation updates (nearest point, distances, instructions) and TTS integration.
import 'dart:async';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';
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

  // whether the TTS instance supports the requested language for speech
  bool _ttsLanguageSupported = true;

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
      // Helpers: format distance for speech with unit conversion and pluralization
      String englishDistance(double meters) {
        if (meters >= 1000) {
          final km = meters / 1000.0;
          final kmStr = km.toStringAsFixed(1);
          final kmVal = double.parse(kmStr);
          return kmVal == 1.0 ? '$kmStr kilometer' : '$kmStr kilometers';
        }
        final m = meters.round();
        return m == 1 ? '$m meter' : '$m meters';
      }

      String hindiDistance(double meters) {
        if (meters >= 1000) {
          final km = meters / 1000.0;
          final kmStr = km.toStringAsFixed(1);
          return '$kmStr किलोमीटर में';
        }
        final m = meters.round();
        return '$m मीटर में';
      }

      // Build the spoken string according to requested language (English default)
      String buildSpoken(String instrText, double distanceMeters, String? lang, bool isFinal) {
        final lower = instrText.toLowerCase();
  final isContinue = lower.contains('continue');

        if (lang != null && lang.toLowerCase().startsWith('hi')) {
          // Hindi translations (simple rule-based mapping)
          final base = () {
            if (lower.contains('turn left')) return 'बाएं मुड़ें';
            if (lower.contains('turn right')) return 'दाएं मुड़ें';
            if (lower.contains('continue straight')) return 'सीधे जाएँ';
            return 'आगे बढ़ते रहें';
          }();
          if (isFinal) return 'अब $base'; // e.g. "अब बाएं मुड़ें"
          // For continue -> use "for" semantics in English; in Hindi keep "... में" which we attach in _hindiDistance
          return '$base ${hindiDistance(distanceMeters)}';
        }

        // English phrasing: use "for" when continuing straight, "in" for turns
        if (isFinal) return 'Now $instrText';
        final distStr = englishDistance(distanceMeters);
        if (isContinue) {
          return '$instrText for $distStr';
        }
        // default (turns): use 'in'
        return '$instrText in $distStr';
      }

      final maybeSpoken = buildSpoken(instr, distanceToNext, language, bucket == 10);
      final update = NavigationUpdate(loc, instr, distanceToNext, remaining, nearest, maybeSpoken);
      _controller.add(update);

      // TTS throttling: only speak when instruction changes OR when we pass
      // into a closer distance bucket (200m,100m,50m,20m,10m)
      try {
            // Apply TTS settings if provided (do this once at start)
            try {
                if (language != null) {
                  // Check available languages on the device and use a close match if needed
                  // Note: flutter_tts exposes available languages as a Future-getter in some versions
                  final langsRaw = tts == null ? null : await tts!.getLanguages;
                  // Debug: log raw languages returned by TTS engine
                  try {
                    debugPrint('NavigationService: available TTS languages raw: $langsRaw');
                  } catch (_) {}
                  final langs = (langsRaw ?? <dynamic>[]).map((e) => e.toString()).toList();
                  String? chosen;
                  if (langs.isNotEmpty) {
                    if (langs.contains(language)) {
                      chosen = language;
                    }
                    if (chosen == null) {
                      chosen = langs.firstWhere(
                        (l) => l.toLowerCase().startsWith(language.split('-').first.toLowerCase()),
                        orElse: () => '',
                      );
                      if (chosen != null && chosen.isEmpty) chosen = null;
                    }
                  }
                  // Debug: show chosen language or that none was matched
                  try {
                    debugPrint('NavigationService: requested language=$language, chosen=$chosen, langs=$langs');
                  } catch (_) {}
                  if (chosen != null) {
                    await tts?.setLanguage(chosen);
                    _ttsLanguageSupported = true;
                  } else {
                    // language not available on device; skip TTS and fallback silently
                    _ttsLanguageSupported = false;
                  }
                }
              if (rate != null) {
                try { await tts?.setSpeechRate(rate); } catch (_) {}
              }
            } catch (_) {
              // If TTS initialization fails, avoid speaking but continue emitting updates
              _ttsLanguageSupported = false;
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
        if (shouldSpeak && !suppressed && _ttsLanguageSupported) {
          _lastInstruction = instr;
          _lastDistanceBucket = bucket == -1 ? _lastDistanceBucket : bucket;
          await tts?.stop();
          final isFinal = bucket == 10;
          // build spoken text according to language
          final spokenToSpeak = buildSpoken(instr, distanceToNext, language, isFinal);
          await tts?.speak(spokenToSpeak);
        }
      } catch (_) {}
    });
  }

  void stop() {
    _posSub?.cancel();
    _posSub = null;
  }

  /// Apply TTS settings (language and rate) to the held FlutterTts instance
  /// at runtime. This can be called while navigation is active to change voice.
  Future<void> applyTtsSettings({String? language, double? rate}) async {
    if (tts == null) return;
    try {
      if (language != null) {
        final langsRaw = await tts!.getLanguages;
        try {
          debugPrint('NavigationService.applyTtsSettings: available languages raw: $langsRaw');
        } catch (_) {}
        final langs = (langsRaw ?? <dynamic>[]).map((e) => e.toString()).toList();
        String? chosen;
        if (langs.isNotEmpty) {
          if (langs.contains(language)) {
            chosen = language;
          }
          if (chosen == null) {
            chosen = langs.firstWhere(
              (l) => l.toLowerCase().startsWith(language.split('-').first.toLowerCase()),
              orElse: () => '',
            );
            if (chosen != null && chosen.isEmpty) chosen = null;
          }
        }
        try {
          debugPrint('NavigationService.applyTtsSettings: requested=$language, chosen=$chosen, langs=$langs');
        } catch (_) {}
        if (chosen != null) {
          await tts?.setLanguage(chosen);
          _ttsLanguageSupported = true;
        } else {
          _ttsLanguageSupported = false;
        }
      }
      if (rate != null) {
        try {
          await tts?.setSpeechRate(rate);
        } catch (_) {}
      }
    } catch (_) {
      _ttsLanguageSupported = false;
    }
  }

  void dispose() {
    _posSub?.cancel();
    _controller.close();
  }

  // helpers are provided by lib/utils/map_helpers.dart
}
