import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import '../services/route_service.dart';
import 'navigation_screen.dart';

/// Expected backend response schema (assumed):
/// {
///   routes: [
///     {
///       id: string,
///       polyline: string (encoded) OR points: [{lat: double, lng: double}],
///       safetyScore: number
///     },
///     ...
///   ]
/// }

class RouteSuggestionScreen extends StatefulWidget {
  final String sourceName;
  final String destName;
  final double? sourceLat;
  final double? sourceLng;
  final double? destLat;
  final double? destLng;

  const RouteSuggestionScreen({
    super.key,
    required this.sourceName,
    required this.destName,
    this.sourceLat,
    this.sourceLng,
    this.destLat,
    this.destLng,
  });

  @override
  State<RouteSuggestionScreen> createState() => _RouteSuggestionScreenState();
}

class _RouteSuggestionScreenState extends State<RouteSuggestionScreen> {
  bool _loading = true;
  String? _error;
  List<RouteModel> _routes = [];
  // previously used to show the outgoing JSON payload for debugging; removed from UI
  GoogleMapController? _controller;
  bool _mapReady = false;
  int? _selectedRouteIndex;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
    _fetchUserLocation();
  }

  Future<void> _fetchUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
  final locationSettings = const LocationSettings(accuracy: LocationAccuracy.high);
  final pos = await Geolocator.getCurrentPosition(locationSettings: locationSettings);
        _userLat = pos.latitude;
        _userLng = pos.longitude;
        if (_mapReady && _controller != null) {
          try {
            await _controller!.animateCamera(CameraUpdate.newLatLng(LatLng(_userLat!, _userLng!)));
          } catch (_) {}
        }
      }
    } catch (_) {
      // ignore location errors; centering is optional
    }
  }

  Future<void> _fetchRoutes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Build origin/destination objects with multiple common key variants
      // so the backend can accept whichever schema it expects.
      final originObj = <String, dynamic>{
        'name': (widget.sourceName.isNotEmpty ? widget.sourceName : 'origin'),
        if (widget.sourceLat != null) 'lat': widget.sourceLat,
        if (widget.sourceLng != null) 'lng': widget.sourceLng,
        if (widget.sourceLat != null) 'latitude': widget.sourceLat,
        if (widget.sourceLng != null) 'longitude': widget.sourceLng,
        if (widget.sourceLat != null) 'location': {
          'lat': widget.sourceLat,
          'lng': widget.sourceLng,
        },
      };

      final destinationObj = <String, dynamic>{
        'name': (widget.destName.isNotEmpty ? widget.destName : 'destination'),
        if (widget.destLat != null) 'lat': widget.destLat,
        if (widget.destLng != null) 'lng': widget.destLng,
        if (widget.destLat != null) 'latitude': widget.destLat,
        if (widget.destLng != null) 'longitude': widget.destLng,
        if (widget.destLat != null) 'location': {
          'lat': widget.destLat,
          'lng': widget.destLng,
        },
      };

      // Ensure we have coordinates for both origin and destination. Many backends
      // require lat/lng rather than free-form names. If missing, show an error
      // and avoid making the request so the user can pick a suggestion with coords.
      final hasOriginCoords = originObj.containsKey('lat') && originObj.containsKey('lng');
      final hasDestCoords = destinationObj.containsKey('lat') && destinationObj.containsKey('lng');
      if (!hasOriginCoords || !hasDestCoords) {
        final missing = <String>[];
  if (!hasOriginCoords) { missing.add('origin'); }
  if (!hasDestCoords) { missing.add('destination'); }
        if (mounted) {
          setState(() {
          _error = 'Please select ${missing.join(' and ')} from the suggestions so coordinates are provided.';
          _loading = false;
        });
        }
        return;
      }

      // We used to normalize into flat objects, but now we send simple strings
      // 'lat,lng' or place names and let the backend.parseLoc handle resolution.

      // Many backends accept locations as simple "lat,lng" strings or free-form
      // text. Sending the coordinates as strings keeps the server-side parseLoc
      // flexible and avoids schema mismatches with nested objects.
  String to6(double v) => v.toStringAsFixed(6);

      String makeLatLngString(Map<String, dynamic> p) {
        if (p.containsKey('lat') && p.containsKey('lng')) {
          return '${to6((p['lat'] as num).toDouble())},${to6((p['lng'] as num).toDouble())}';
        }
        if (p.containsKey('latitude') && p.containsKey('longitude')) {
          return '${to6((p['latitude'] as num).toDouble())},${to6((p['longitude'] as num).toDouble())}';
        }
        if (p.containsKey('location') && p['location'] is Map) {
          final loc = p['location'] as Map;
          if (loc.containsKey('lat') && loc.containsKey('lng')) {
            return '${to6((loc['lat'] as num).toDouble())},${to6((loc['lng'] as num).toDouble())}';
          }
        }
        // fallback to name (place string) so backend can attempt to resolve
        return p['name']?.toString() ?? '';
      }

      final originValue = makeLatLngString(originObj);
      final destinationValue = makeLatLngString(destinationObj);

      final data = {
        // send as simple strings so backend.parseLoc can handle them reliably
        'origin': originValue,
        'destination': destinationValue,
      };
      // we no longer display the raw payload in the UI; proceed to call service

      final body = await RouteService.compareRoutes(data);
      if (body == null) throw Exception('Empty response');

      final routesRaw = body['routes'] as List?;
      if (routesRaw == null) throw Exception('Invalid response: missing routes');

      final parsed = <RouteModel>[];
      // helper to parse numeric values flexibly
      double parseDouble(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
        return 0.0;
      }

      for (final r in routesRaw) {
        final id = r['id']?.toString() ?? UniqueKey().toString();

        // support both camelCase and snake_case keys: safetyScore or safety_score
        final safetyVal = r['safetyScore'] ?? r['safety_score'] ?? r['safety'];
        final double score = parseDouble(safetyVal);

        // extract color (optional) and tags
        final String? colorStr = r['color'] is String ? (r['color'] as String) : null;
        List<String> tags = [];
        if (r['tags'] is List) {
          tags = (r['tags'] as List).map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        }

        // distance/duration text if provided
        String distanceText = '';
        if (r['distance'] is Map && r['distance']['text'] != null) {
          distanceText = r['distance']['text'].toString();
        }
        String durationText = '';
        if (r['duration'] is Map && r['duration']['text'] != null) {
          durationText = r['duration']['text'].toString();
        }

        List<LatLng> points = [];
        if (r['polyline'] is String) {
          points = decodePolyline(r['polyline'] as String);
        } else if (r['points'] is List) {
          points = (r['points'] as List)
              .map<LatLng>((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
              .toList();
        }

        parsed.add(RouteModel(
          id: id,
          points: points,
          safetyScore: score,
          color: colorStr,
          tags: tags,
          distanceText: distanceText,
          durationText: durationText,
        ));
      }

      if (mounted) {
        setState(() {
          _routes = parsed;
          // Auto-select the safest route by default (highest safetyScore)
          if (_routes.isNotEmpty) {
            int bestIdx = 0;
            double bestScore = _routes[0].safetyScore;
            for (int i = 1; i < _routes.length; i++) {
              if (_routes[i].safetyScore > bestScore) {
                bestScore = _routes[i].safetyScore;
                bestIdx = i;
              }
            }
            _selectedRouteIndex = bestIdx;
          } else {
            _selectedRouteIndex = null;
          }

          // Build polylines for the map and markers
          _buildPolylines();
          _updateMarkers();
        });

        // Fit map to the selected route if possible
        if (_selectedRouteIndex != null) {
          _fitMapToRoute(_selectedRouteIndex!);
        }
      }
    } catch (e) {
      debugPrint('Error fetching routes: $e');
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    _mapReady = true;
    // If routes already present, fit the map
    if (_routes.isNotEmpty) {
      _fitMapToRoute(_selectedRouteIndex ?? 0);
    }
    // If we have the user's location, center the map there
    if (_userLat != null && _userLng != null) {
      try {
        _controller!.animateCamera(CameraUpdate.newLatLng(LatLng(_userLat!, _userLng!)));
      } catch (_) {}
    }
  }

  void _buildPolylines() {
    final polylines = <Polyline>{};
    for (var i = 0; i < _routes.length; i++) {
      final r = _routes[i];
      final id = PolylineId('route_$i');
      final isSelected = _selectedRouteIndex != null && _selectedRouteIndex == i;
      // If server provided a color string, try to parse it and use it.
      Color? parsed = _parseColorString(r.color);

      // Fallback: determine color from safetyScore. Support both 0-1 and 0-5 scales.
      double score = r.safetyScore;
      if (score <= 1.0) {
        // normalize to 0-5 scale
        score = score * 5.0;
      }

      Color baseColor;
      if (parsed != null) {
        baseColor = parsed;
      } else if (score >= 4.0) {
        baseColor = Colors.green;
      } else if (score >= 2.5) {
        baseColor = Colors.orange;
      } else {
        baseColor = Colors.red;
      }

        // apply alpha based on selection; non-selected are more transparent now
  final int rCh = ((baseColor.r * 255.0).round() & 0xFF);
  final int gCh = ((baseColor.g * 255.0).round() & 0xFF);
  final int bCh = ((baseColor.b * 255.0).round() & 0xFF);
      final polyColor = isSelected
        ? Color.fromARGB((0.95 * 255).round(), rCh, gCh, bCh)
        : Color.fromARGB((0.45 * 255).round(), rCh, gCh, bCh);

      polylines.add(Polyline(
        polylineId: id,
        points: r.points,
        color: polyColor,
        width: isSelected ? 8 : 5,
        consumeTapEvents: true,
        onTap: () => _onSelectRoute(i),
        zIndex: isSelected ? 2 : 1,
      ));
    }
    setState(() => _polylines = polylines);
  }

  void _onSelectRoute(int index) {
    setState(() {
      _selectedRouteIndex = index;
      _buildPolylines();
    });
    _fitMapToRoute(index);
  }

  void _fitMapToRoute(int index) async {
    if (!_mapReady || _controller == null) return;
    if (_routes.isEmpty) return;
    final idx = index.clamp(0, _routes.length - 1);
    final pts = _routes[idx].points;
    if (pts.isEmpty) return;
    double south = pts.first.latitude;
    double north = pts.first.latitude;
    double west = pts.first.longitude;
    double east = pts.first.longitude;
    for (final p in pts) {
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }
    final bounds = LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east));
    try {
      await _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
    } catch (e) {
      // animateCamera may throw if map not laid out yet; ignore
    }
  }

  // decode encoded polyline algorithm (Google polyline)
  List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  Color _colorFromName(String name) {
    final c = name.toLowerCase();
    if (c.contains('yellow')) return Colors.yellow;
    if (c.contains('green')) return Colors.green;
    if (c.contains('red')) return Colors.red;
    if (c.contains('orange')) return Colors.orange;
    if (c.contains('blue')) return Colors.blue;
    return Colors.blueGrey;
  }

  /// Parse backend-provided color string into a [Color]. Supports:
  /// - hex `#RRGGBB` or `#AARRGGBB`
  /// - `0xAARRGGBB` style
  /// - simple color names like 'green', 'red'
  Color? _parseColorString(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    final s = input.trim();
    try {
      if (s.startsWith('#')) {
        final hex = s.substring(1);
        if (hex.length == 6) {
          // RRGGBB -> add FF alpha
          final v = int.parse('FF$hex', radix: 16);
          return Color(v);
        } else if (hex.length == 8) {
          final v = int.parse(hex, radix: 16);
          return Color(v);
        }
      }
      if (s.startsWith('0x')) {
        final v = int.parse(s);
        return Color(v);
      }
      // fallback: named colors
      return _colorFromName(s);
    } catch (e) {
      return null;
    }
  }

  void _updateMarkers() {
    final markers = <Marker>{};
    if (widget.sourceLat != null && widget.sourceLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('origin'),
        position: LatLng(widget.sourceLat!, widget.sourceLng!),
        infoWindow: InfoWindow(title: 'Origin', snippet: widget.sourceName),
      ));
    }
    if (widget.destLat != null && widget.destLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(widget.destLat!, widget.destLng!),
        infoWindow: InfoWindow(title: 'Destination', snippet: widget.destName),
      ));
    }
    if (_userLat != null && _userLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('you'),
        position: LatLng(_userLat!, _userLng!),
        infoWindow: const InfoWindow(title: 'You'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }
    setState(() => _markers = markers);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compare Routes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Column(
                  children: [
                    // Compact origin/destination row (names only)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text('Origin: ${widget.sourceName}', style: const TextStyle(fontWeight: FontWeight.w600))),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Destination: ${widget.destName}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          // Google Map showing all routes
                          GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: (widget.sourceLat != null && widget.sourceLng != null)
                                  ? LatLng(widget.sourceLat!, widget.sourceLng!)
                                  : const LatLng(23.0225, 72.5714),
                              zoom: 12,
                            ),
                            polylines: _polylines,
                            markers: _markers,
                            myLocationEnabled: false,
                            zoomControlsEnabled: true,
                            onMapCreated: _onMapCreated,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 240,
                      child: ListView.builder(
                        itemCount: _routes.length,
                        itemBuilder: (context, index) {
                          final r = _routes[index];
                          final selected = _selectedRouteIndex == index;
                          return ListTile(
                            selected: selected,
                            selectedTileColor: Color.fromRGBO(33, 150, 243, 0.08),
                            leading: r.color != null
                                ? Container(width: 12, height: 12, decoration: BoxDecoration(color: _colorFromName(r.color!), shape: BoxShape.circle))
                                : null,
                            title: Text('Route ${index + 1}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Safety: ${r.safetyScore.toStringAsFixed(2)}'),
                                if (r.distanceText.isNotEmpty) Text('Distance: ${r.distanceText}'),
                                if (r.durationText.isNotEmpty) Text('Duration: ${r.durationText}'),
                                if (r.tags.isNotEmpty) Text('Tags: ${r.tags.join(', ')}', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            onTap: () => _onSelectRoute(index),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.map),
                                  onPressed: () {
                                    // Return selected route points and safety score
                                    Navigator.pop(context, {'points': r.points, 'safety': r.safetyScore});
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.navigation),
                                  tooltip: 'Start Navigation',
                                  onPressed: () {
                                    // Push the in-app navigation screen
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => NavigationScreen(
                                          points: r.points,
                                          sourceName: widget.sourceName,
                                          destName: widget.destName,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class RouteModel {
  final String id;
  final List<LatLng> points;
  final double safetyScore;
  final String? color;
  final List<String> tags;
  final String distanceText;
  final String durationText;

  RouteModel({
    required this.id,
    required this.points,
    required this.safetyScore,
    this.color,
    this.tags = const [],
    this.distanceText = '',
    this.durationText = '',
  });
}

