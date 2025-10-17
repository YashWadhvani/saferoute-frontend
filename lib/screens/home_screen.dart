import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:google_place/google_place.dart';
import 'dart:math' as math;
import 'package:flutter_tts/flutter_tts.dart';
import '../services/route_service.dart';
import '../services/places_service.dart';
import 'route_suggestion_screen.dart';

// Which field is currently requesting suggestions (source or destination)
enum ActiveField { none, source, dest }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? _controller;
  static const LatLng _center = LatLng(23.0225, 72.5714); // Ahmedabad
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  final PlacesService _placesService = PlacesService.fromEnv();
  bool _showCompare = false;
  bool _gettingLocation = false;
  // which field is currently requesting suggestions
  ActiveField _activeField = ActiveField.none;
  List suggestions = [];
  Timer? _debounceTimer;
  bool _loadingSuggestions = false;
  double? _sourceLat;
  double? _sourceLng;
  double? _destLat;
  double? _destLng;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // Compare Routes / Navigation state
  List<RouteModel> _routes = [];
  int? _selectedRouteIndex;
  bool _routePanelVisible = false;
  bool _navigating = false;
  StreamSubscription<Position>? _posSub;
  String _navInstruction = 'Press Start to begin navigation';
  FlutterTts? _tts;

  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _fetchUserLocation();
    _tts = FlutterTts();
    _tts?.setLanguage('en-US');
    _tts?.setSpeechRate(0.45);
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
        if (mounted) {
          _userLat = pos.latitude;
          _userLng = pos.longitude;
          _updateMarkers();
          if (_controller != null) {
            try {
              await _controller!.animateCamera(CameraUpdate.newLatLng(LatLng(_userLat!, _userLng!)));
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // ignore
    }
  }

  // --- Route & Navigation helpers (copied/adapted from RouteSuggestionScreen/NavigationScreen)

  List<LatLng> _decodePolyline(String encoded) {
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

  Color? _parseColorString(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    final s = input.trim();
    try {
      if (s.startsWith('#')) {
        final hex = s.substring(1);
        if (hex.length == 6) {
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
      final c = s.toLowerCase();
      if (c.contains('green')) return Colors.green;
      if (c.contains('yellow')) return Colors.yellow;
      if (c.contains('orange')) return Colors.orange;
      if (c.contains('red')) return Colors.red;
      if (c.contains('blue')) return Colors.blue;
      return Colors.blueGrey;
    } catch (_) {
      return null;
    }
  }

  void _buildPolylinesFromRoutes() {
    final polylines = <Polyline>{};
    for (var i = 0; i < _routes.length; i++) {
      final r = _routes[i];
      final id = PolylineId('route_$i');
      final isSelected = _selectedRouteIndex != null && _selectedRouteIndex == i;

      // parse color from backend if present
      Color? parsed = _parseColorString(r.color);

      double score = r.safetyScore;
      if (score <= 1.0) score = score * 5.0;

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

  final int rCh = ((baseColor.r * 255.0).round() & 0xFF);
  final int gCh = ((baseColor.g * 255.0).round() & 0xFF);
  final int bCh = ((baseColor.b * 255.0).round() & 0xFF);
    final polyColor = isSelected
      ? Color.fromARGB((0.95 * 255).round(), rCh, gCh, bCh)
      : Color.fromARGB((0.45 * 255).round(), rCh, gCh, bCh);

      polylines.add(Polyline(polylineId: id, points: r.points, color: polyColor, width: isSelected ? 8 : 5, consumeTapEvents: true, onTap: () => _onSelectRoute(i), zIndex: isSelected ? 2 : 1));
    }
    setState(() => _polylines
      ..clear()
      ..addAll(polylines));
  }

  void _onSelectRoute(int index) {
    setState(() {
      _selectedRouteIndex = index;
    });
    _buildPolylinesFromRoutes();
    _fitMapToRoute(index);
  }

  void _fitMapToRoute(int index) async {
    if (_controller == null) return;
    if (_routes.isEmpty) return;
    final pts = _routes[index].points;
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
    } catch (_) {}
  }

  Future<void> _fetchRoutesInPlace() async {
    setState(() {
      _routes = [];
      _selectedRouteIndex = null;
      _routePanelVisible = false;
    });

    final source = _sourceController.text.trim();
    final dest = _destController.text.trim();

    // Ensure we have coords for dest and source if possible (geocode as fallback)
    if ((_destLat == null || _destLng == null) && dest.isNotEmpty) {
      try {
        final locations = await geocoding.locationFromAddress(dest);
        if (locations.isNotEmpty) {
          final loc = locations.first;
          _destLat = loc.latitude;
          _destLng = loc.longitude;
        }
      } catch (_) {}
    }
    if ((_sourceLat == null || _sourceLng == null) && source.isNotEmpty) {
      try {
        final locations = await geocoding.locationFromAddress(source);
        if (locations.isNotEmpty) {
          final loc = locations.first;
          _sourceLat = loc.latitude;
          _sourceLng = loc.longitude;
        }
      } catch (_) {}
    }

    if (_destLat == null || _destLng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a destination with coordinates')));
      return;
    }

    String to6(double v) => v.toStringAsFixed(6);
    String makeLatLngString(double? lat, double? lng, String fallback) {
      if (lat != null && lng != null) return '${to6(lat)},${to6(lng)}';
      return fallback;
    }

    final originValue = makeLatLngString(_sourceLat, _sourceLng, source.isNotEmpty ? source : 'origin');
    final destinationValue = makeLatLngString(_destLat, _destLng, dest);

    final data = {'origin': originValue, 'destination': destinationValue};

    try {
      final body = await RouteService.compareRoutes(data);
      if (body == null) throw Exception('Empty response');
      final routesRaw = body['routes'] as List?;
      if (routesRaw == null) throw Exception('Invalid response: missing routes');

      final parsed = <RouteModel>[];
      double parseDouble(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
        return 0.0;
      }

      for (final r in routesRaw) {
        final id = r['id']?.toString() ?? UniqueKey().toString();
        final safetyVal = r['safetyScore'] ?? r['safety_score'] ?? r['safety'];
        final double score = parseDouble(safetyVal);
        final String? colorStr = r['color'] is String ? (r['color'] as String) : null;
        List<String> tags = [];
        if (r['tags'] is List) {
          tags = (r['tags'] as List).map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
        }

        String distanceText = '';
        if (r['distance'] is Map && r['distance']['text'] != null) distanceText = r['distance']['text'].toString();
        String durationText = '';
        if (r['duration'] is Map && r['duration']['text'] != null) durationText = r['duration']['text'].toString();

        List<LatLng> points = [];
        if (r['polyline'] is String) {
          points = _decodePolyline(r['polyline'] as String);
        } else if (r['points'] is List) {
          points = (r['points'] as List).map<LatLng>((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
        }

        parsed.add(RouteModel(id: id, points: points, safetyScore: score, color: colorStr, tags: tags, distanceText: distanceText, durationText: durationText));
      }

      if (!mounted) return;
      setState(() {
        _routes = parsed;
        // auto-select safest route
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
        _routePanelVisible = true;
        _buildPolylinesFromRoutes();
        _updateMarkers();
      });

      if (_selectedRouteIndex != null) _fitMapToRoute(_selectedRouteIndex!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching routes: $e')));
    }
  }

  void _startInPlaceNavigation(int routeIndex) async {
    if (routeIndex < 0 || routeIndex >= _routes.length) return;
    _selectedRouteIndex = routeIndex;
    _buildPolylinesFromRoutes();
    _fitMapToRoute(routeIndex);

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission required for navigation')));
      return;
    }

    setState(() {
      _navigating = true;
      _navInstruction = 'Navigation started';
    });

    // minimize the route panel when navigation starts
    setState(() {
      _routePanelVisible = false;
    });

    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2))
        .listen((pos) {
      final loc = LatLng(pos.latitude, pos.longitude);
      // update user location and instruction
      setState(() {
        _userLat = loc.latitude;
        _userLng = loc.longitude;
      });
      if (_controller != null) {
        try {
          _controller!.animateCamera(CameraUpdate.newLatLng(loc));
        } catch (_) {}
      }

      // compute nearest point and rudimentary instruction
      final nearest = _findNearestIndexOnRoute(_routes[routeIndex].points, loc);
      final nextIdx = math.min(nearest + 1, _routes[routeIndex].points.length - 1);
      final instr = _deriveInstructionForRoute(_routes[routeIndex].points, nextIdx);
      final distanceToNext = Geolocator.distanceBetween(loc.latitude, loc.longitude, _routes[routeIndex].points[nextIdx].latitude, _routes[routeIndex].points[nextIdx].longitude);
      final remaining = _remainingDistanceFromIndexOnRoute(_routes[routeIndex].points, nextIdx);
      final formattedNext = _formatDistance(distanceToNext);
      final formattedTotal = _formatDistance(remaining);
      final newNav = '$instr in $formattedNext • Remaining: $formattedTotal';
      setState(() {
        _navInstruction = newNav;
      });
      // speak instruction
      try {
        _tts?.stop();
        _tts?.speak('$instr in ${distanceToNext.round()} meters');
      } catch (_) {}
    });
  }

  void _stopInPlaceNavigation() {
    _posSub?.cancel();
    _posSub = null;
    setState(() {
      _navigating = false;
      _navInstruction = 'Navigation stopped';
    });
  }

  int _findNearestIndexOnRoute(List<LatLng> pts, LatLng loc) {
    if (pts.isEmpty) return 0;
    double best = double.infinity;
    int idx = 0;
    for (int i = 0; i < pts.length; i++) {
      final d = Geolocator.distanceBetween(loc.latitude, loc.longitude, pts[i].latitude, pts[i].longitude);
      if (d < best) {
        best = d;
        idx = i;
      }
    }
    return idx;
  }

  String _deriveInstructionForRoute(List<LatLng> pts, int idx) {
    if (pts.length < 3) return 'Continue';
    final prev = (idx - 1).clamp(0, pts.length - 1);
    final next = (idx + 1).clamp(0, pts.length - 1);
    final a = pts[prev];
    final b = pts[idx];
    final c = pts[next];
    final bearing1 = _bearing(a, b);
    final bearing2 = _bearing(b, c);
    double diff = (bearing2 - bearing1).abs();
    if (diff > 180) diff = 360 - diff;
    if (diff < 15) return 'Continue straight';
    if (bearing2 > bearing1) return 'Turn right';
    return 'Turn left';
  }

  double _bearing(LatLng a, LatLng b) {
    final lat1 = _toRad(a.latitude);
    final lat2 = _toRad(b.latitude);
    final dLon = _toRad(b.longitude - a.longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x);
    return (_toDeg(brng) + 360) % 360;
  }

  double _toRad(double d) => d * math.pi / 180.0;
  double _toDeg(double r) => r * 180.0 / math.pi;

  double _remainingDistanceFromIndexOnRoute(List<LatLng> pts, int idx) {
    if (idx >= pts.length - 1) return 0.0;
    double sum = 0.0;
    for (int i = idx; i < pts.length - 1; i++) {
      sum += Geolocator.distanceBetween(pts[i].latitude, pts[i].longitude, pts[i + 1].latitude, pts[i + 1].longitude);
    }
    return sum;
  }

  // Format meters into friendly string (m or km)
  String _formatDistance(double meters) {
    if (meters >= 1000) {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  // Compact, non-editable top bar shown while navigating
  Widget _buildCompactRouteBar() {
    final src = _sourceController.text.trim().isNotEmpty ? _sourceController.text.trim() : 'Origin';
    final dst = _destController.text.trim().isNotEmpty ? _destController.text.trim() : 'Destination';
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
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              // stop navigation and restore controls
              if (_navigating) _stopInPlaceNavigation();
            },
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SafeRoute Map")),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Text('SafeRoute', style: TextStyle(color: Colors.white, fontSize: 20)),
            ),
            ListTile(title: const Text('Home'), onTap: () => Navigator.pushReplacementNamed(context, '/')),
            ListTile(title: const Text('Profile'), onTap: () => Navigator.pushNamed(context, '/profile')),
            ListTile(title: const Text('Settings'), onTap: () => Navigator.pushNamed(context, '/settings')),
            ListTile(title: const Text('Onboarding'), onTap: () => Navigator.pushNamed(context, '/onboarding')),
            ListTile(title: const Text('Map Detail'), onTap: () => Navigator.pushNamed(context, '/map_detail')),
            ListTile(title: const Text('Contacts'), onTap: () => Navigator.pushNamed(context, '/contacts')),
            ListTile(title: const Text('Logout'), onTap: () => Navigator.pushReplacementNamed(context, '/login')),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                if (_navigating)
                  _buildCompactRouteBar()
                else
                  TextField(
                  controller: _sourceController,
                  decoration: InputDecoration(
                    labelText: 'Source',
                    hintText: 'Type origin or use current location',
                    prefixIcon: const Icon(Icons.my_location),
                    // suffix button: fetch current location or clear
                    suffixIcon: _gettingLocation
                        ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                      tooltip: 'Use current location / Clear',
                      icon: _sourceLat != null && _sourceLng != null ? const Icon(Icons.clear) : const Icon(Icons.gps_fixed),
                      onPressed: () async {
                        if (_sourceLat != null && _sourceLng != null) {
                          // clear stored coords and text so user can type
                          setState(() {
                            _sourceLat = null;
                            _sourceLng = null;
                            _sourceController.clear();
                          });
                          return;
                        }

                        setState(() => _gettingLocation = true);
                        try {
                          LocationPermission permission = await Geolocator.checkPermission();
                          if (permission == LocationPermission.denied) {
                            permission = await Geolocator.requestPermission();
                          }
                          if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
                            if (mounted) _sourceController.text = 'Location permission denied';
                          } else {
                            final locationSettings = const LocationSettings(accuracy: LocationAccuracy.high);
                            final pos = await Geolocator.getCurrentPosition(locationSettings: locationSettings);
                            if (mounted) {
                              try {
                                final placemarks = await geocoding.placemarkFromCoordinates(pos.latitude, pos.longitude);
                                if (placemarks.isNotEmpty) {
                                  final pm = placemarks.first;
                                  _sourceController.text = '${pm.name ?? ''} ${pm.street ?? ''}, ${pm.locality ?? ''}'.trim();
                                } else {
                                  _sourceController.text = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
                                }
                              } catch (_) {
                                _sourceController.text = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
                              }
                              _sourceLat = pos.latitude;
                              _sourceLng = pos.longitude;
                              _updateMarkers();
                            }
                          }
                        } catch (e) {
                          if (mounted) _sourceController.text = 'Unable to get location';
                        } finally {
                          if (mounted) setState(() => _gettingLocation = false);
                        }
                      },
                    ),
                  ),
                  onChanged: (v) {
                    // If user edits the source text manually, clear stored coordinates so
                    // we treat it as a typed address that may need geocoding.
                    if (_sourceLat != null || _sourceLng != null) {
                      setState(() {
                        _sourceLat = null;
                        _sourceLng = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                if (!_navigating)
                  TextField(
                  controller: _destController,
                  decoration: const InputDecoration(
                    labelText: 'Destination',
                    hintText: 'Start typing destination...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) async {
                    final hasText = value.trim().isNotEmpty;
                    if (hasText && !_showCompare) {
                      setState(() => _showCompare = true);
                    } else if (!hasText && _showCompare) {
                      setState(() => _showCompare = false);
                    }

                    // Autocomplete suggestions with debounce
                    _debounceTimer?.cancel();
                    if (hasText) {
                      setState(() {
                        _loadingSuggestions = true;
                      });
                      _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
                        try {
                          final preds = await _placesService.autocomplete(value);
                          if (mounted) {
                            if (preds.isEmpty) {
                              // fallback: show the typed text as a synthetic suggestion so user can tap to geocode
                              setState(() => suggestions = [
                                    {
                                      'description': value,
                                      'synthetic': true,
                                    }
                                  ]);
                            } else {
                              setState(() => suggestions = preds);
                            }
                          }
                        } catch (_) {
                          if (mounted) {
                            // on error, provide the typed value as fallback
                            setState(() => suggestions = [
                                  {
                                    'description': value,
                                    'synthetic': true,
                                  }
                                ]);
                          }
                        } finally {
                          if (mounted) { setState(() => _loadingSuggestions = false); }
                        }
                      });
                    } else {
                      if (mounted) { setState(() {
                        suggestions = [];
                        _loadingSuggestions = false;
                      }); }
                    }

                    // No automatic filling of source when typing destination anymore.
                    // Users can type an origin or tap the location icon on the source field.
                  },
                ),
                // suggestions list
                // suggestions area
                if (_loadingSuggestions)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
                if (!_loadingSuggestions && suggestions.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: suggestions.length,
                      itemBuilder: (context, index) {
                        final item = suggestions[index];
                        String desc = '';
                        final bool synthetic = (item is Map && item['synthetic'] == true);
                        if (synthetic) {
                          desc = (item['description'] ?? '').toString();
                        } else if (item is AutocompletePrediction) {
                          desc = item.description ?? item.structuredFormatting?.mainText ?? '';
                        } else {
                          desc = item.toString();
                        }

                        return ListTile(
                          title: Text(desc),
                          onTap: () async {
                            final active = _activeField;
                            setState(() => suggestions = []);
                            if (active == ActiveField.source) {
                              _sourceController.text = desc;
                              if (synthetic) {
                                try {
                                  final locations = await geocoding.locationFromAddress(desc);
                                  if (locations.isNotEmpty) {
                                    final loc = locations.first;
                                    _sourceLat = loc.latitude;
                                    _sourceLng = loc.longitude;
                                    if (_controller != null) _controller!.animateCamera(CameraUpdate.newLatLng(LatLng(_sourceLat!, _sourceLng!)));
                                    _updateMarkers();
                                  }
                                } catch (_) {}
                              } else if (item is AutocompletePrediction && item.placeId != null) {
                                final details = await _placesService.getPlaceDetails(item.placeId!);
                                final lat = details?.geometry?.location?.lat;
                                final lng = details?.geometry?.location?.lng;
                                if (lat != null && lng != null) {
                                  _sourceLat = lat;
                                  _sourceLng = lng;
                                  if (_controller != null) _controller!.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
                                  _updateMarkers();
                                }
                              }
                            } else {
                              // default: destination
                              _destController.text = desc;
                              if (synthetic) {
                                try {
                                  final locations = await geocoding.locationFromAddress(desc);
                                  if (locations.isNotEmpty) {
                                    final loc = locations.first;
                                    _destLat = loc.latitude;
                                    _destLng = loc.longitude;
                                    if (_controller != null) _controller!.animateCamera(CameraUpdate.newLatLng(LatLng(_destLat!, _destLng!)));
                                    _updateMarkers();
                                  }
                                } catch (_) {}
                              } else if (item is AutocompletePrediction && item.placeId != null) {
                                final details = await _placesService.getPlaceDetails(item.placeId!);
                                final lat = details?.geometry?.location?.lat;
                                final lng = details?.geometry?.location?.lng;
                                if (lat != null && lng != null) {
                                  _destLat = lat;
                                  _destLng = lng;
                                  if (_controller != null) _controller!.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
                                  _updateMarkers();
                                }
                              }
                            }
                            _activeField = ActiveField.none;
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                if (_showCompare)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _fetchRoutesInPlace,
                      icon: const Icon(Icons.compare_arrows),
                      label: const Text('Compare Routes'),
                    ),
                  ),
              ],
            ),
          ),
          // Inline navigation instruction bar
          if (_navigating)
            Positioned(
              left: 12,
              right: 12,
              bottom: _routePanelVisible ? 272 : 24,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: Card(
                  key: ValueKey(_navInstruction),
                  elevation: 6,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(child: Text(_navInstruction, style: const TextStyle(fontWeight: FontWeight.w600))),
                        ElevatedButton(onPressed: _stopInPlaceNavigation, child: const Text('Stop'))
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Expanded map below the controls
          Expanded(
            child: GoogleMap(
              onMapCreated: (controller) => _controller = controller,
              initialCameraPosition: const CameraPosition(target: _center, zoom: 14),
              myLocationEnabled: true,
              polylines: _polylines,
              markers: _markers,
            ),
          ),
          // Route options panel (in-place) - appears over map when routes are present
          if (_routePanelVisible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                color: Colors.white,
                height: _navigating ? 120 : 260,
                child: _navigating
                    ? Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Expanded(child: Text('Routes available: ${_routes.length}', style: const TextStyle(fontWeight: FontWeight.w700))),
                            IconButton(
                              icon: const Icon(Icons.expand_less),
                              onPressed: () => setState(() => _routePanelVisible = false),
                            )
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
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    setState(() {
                                      _routePanelVisible = false;
                                    });
                                  },
                                )
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _routes.length,
                              itemBuilder: (context, index) {
                                final r = _routes[index];
                                final selected = _selectedRouteIndex == index;
                                return ListTile(
                                  selected: selected,
                                  leading: r.color != null
                                      ? Container(width: 12, height: 12, decoration: BoxDecoration(color: _parseColorString(r.color) ?? Colors.blueGrey, shape: BoxShape.circle))
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
                                      IconButton(
                                        icon: const Icon(Icons.map),
                                        onPressed: () {
                                          _onSelectRoute(index);
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(_navigating && _selectedRouteIndex == index ? Icons.stop : Icons.navigation),
                                        onPressed: () {
                                          if (_navigating && _selectedRouteIndex == index) {
                                            _stopInPlaceNavigation();
                                          } else {
                                            _startInPlaceNavigation(index);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          )
                        ],
                      ),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_navigating) {
            // toggle the route options panel (minimized) when navigating
            setState(() => _routePanelVisible = !_routePanelVisible);
          } else {
            // when not navigating, act as quick Compare Routes
            _fetchRoutesInPlace();
          }
        },
        label: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6.0),
          child: Text('Route Options'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _sourceController.dispose();
    _destController.dispose();
    super.dispose();
  }

  void _updateMarkers() {
    final markers = <Marker>{};
    if (_sourceLat != null && _sourceLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('origin'),
        position: LatLng(_sourceLat!, _sourceLng!),
        infoWindow: InfoWindow(title: 'Origin', snippet: _sourceController.text),
      ));
    }
    if (_destLat != null && _destLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(_destLat!, _destLng!),
        infoWindow: InfoWindow(title: 'Destination', snippet: _destController.text),
      ));
    }
    setState(() => _markers
      ..clear()
      ..addAll(markers));
  }
}
