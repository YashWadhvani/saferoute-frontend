import 'package:google_place/google_place.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Lightweight interface for places lookups to allow test injection.
abstract class IPlacesService {
  Future<List<AutocompletePrediction>> autocomplete(String input);
  Future<DetailsResult?> getPlaceDetails(String placeId);
}

class PlacesService implements IPlacesService {
  final GooglePlace _googlePlace;

  PlacesService._(this._googlePlace);

  factory PlacesService.fromEnv() {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    return PlacesService._(GooglePlace(apiKey));
  }

  /// Autocomplete predictions for input text.
  @override
  Future<List<AutocompletePrediction>> autocomplete(String input) async {
    if (input.trim().isEmpty) return [];
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        debugPrint('PlacesService.autocomplete: no GOOGLE_MAPS_API_KEY provided');
        return [];
      }
      final result = await _googlePlace.autocomplete.get(input, types: 'geocode');
      if (result == null) {
        debugPrint('PlacesService.autocomplete: received null result');
        return [];
      }
      final preds = result.predictions ?? [];
      debugPrint('PlacesService.autocomplete: input="$input" -> ${preds.length} predictions');
      return preds;
    } catch (e, st) {
      debugPrint('PlacesService.autocomplete error: $e\n$st');
      return [];
    }
  }

  // no extra location-biased method; callers should use autocomplete() and local heuristics

  /// Get place details (especially lat/lng) from a placeId
  @override
  Future<DetailsResult?> getPlaceDetails(String placeId) async {
    final result = await _googlePlace.details.get(placeId);
    return result?.result;
  }
}
