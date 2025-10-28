import 'dart:async';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/map_helpers.dart';
import '../models/route_model.dart';
import '../state/tts_settings.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:google_place/google_place.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../services/places_service.dart';
import '../services/route_service.dart';
import '../services/navigation_service.dart';
import '../services/sos_service.dart';
import 'rating_screen.dart';
import 'debug_inspector_screen.dart';

enum ActiveField { none, source, dest }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final PlacesService _placesService = PlacesService.fromEnv();

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts();
    _tts?.setLanguage('en-US');
    // create navigation service (will use same TTS instance)
    _navigationService = NavigationService(tts: _tts);
    _loadCarIcon();
    WidgetsBinding.instance.addObserver(this);
    // try to restore navigation state if app was backgrounded
    _restoreNavigationIfAny();
    _fetchUserLocation();
  }

  BitmapDescriptor? _carIcon;
  LatLng? _prevNavLocation;

  Future<void> _loadCarIcon() async {
    try {
      // Prefer the high-level API which handles scaling for assets.
      final double dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? View.of(context).devicePixelRatio;
      final config = ImageConfiguration(devicePixelRatio: dpr, size: const Size(24, 24));
      // `fromAssetImage` is deprecated; use the new `BitmapDescriptor.asset`
      // shape which accepts an ImageConfiguration first and returns a Future.
      try {
        final assetIcon = await BitmapDescriptor.asset(config, 'assets/images/car.png');
        if (!mounted) return;
        setState(() => _carIcon = assetIcon);
        return;
      } catch (_) {
        // fall through to bytes fallback
      }
    } catch (_) {
      // fall back to manual bytes-based creation (older approach) if asset image fails
    }

    // Fallback: load bytes and create BitmapDescriptor from raw image data
    try {
      final assetBundle = DefaultAssetBundle.of(context);
      const double desiredLogicalWidth = 24; // logical pixels for marker size
      final double dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? View.of(context).devicePixelRatio;
      final data = await assetBundle.load('assets/images/car.png');
      final bytes = data.buffer.asUint8List();
      final int targetWidth = (desiredLogicalWidth * dpr).round();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      final ui.Image resized = frame.image;
      final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final resizedBytes = byteData.buffer.asUint8List();
      final icon = BitmapDescriptor.bytes(resizedBytes);
      if (!mounted) return;
      setState(() => _carIcon = icon);
    } catch (_) {
      // ignore completely - map will use default marker
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navUpdateSub?.cancel();
    _navigationService?.dispose();
    _tts?.stop();
    super.dispose();
  }

  double? _userLat;
  double? _userLng;
  void _fetchUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
      });
      // Center map on user location if map is ready
      if (_controller != null && _userLat != null && _userLng != null) {
        _controller!.animateCamera(
          CameraUpdate.newLatLng(LatLng(_userLat!, _userLng!)),
        );
      }
    } catch (_) {}
  }

  void _updateMarkers() {
    final markers = <Marker>{};
    // do not add origin marker - Google Maps will show current location
    if (_destLat != null && _destLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(_destLat!, _destLng!),
          infoWindow: InfoWindow(
            title: 'Destination',
            snippet: _destController.text,
          ),
        ),
      );
    }
    // add moving car marker if navigating and we have an update
    if (_navigating && _lastNavUpdate != null) {
      final pos = _lastNavUpdate!.userLocation;
      double rotation = 0.0;
      if (_prevNavLocation != null) {
        rotation = bearing(_prevNavLocation!, pos);
      }
      markers.add(Marker(
        markerId: const MarkerId('car'),
        position: pos,
        icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        rotation: rotation,
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(title: 'You', snippet: _lastNavUpdate!.instruction),
      ));
    }
    setState(() {
      _markers = markers;
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
  }

  void _onSelectRoute(int index) {
    setState(() {
      _selectedRouteIndex = index;
      _routePanelVisible = true;
    });
    // Rebuild polylines so the selected route is visually updated
    _buildPolylinesFromRoutes();
    // Optionally fit map to the selected route
    if (_controller != null && _routes.length > index && _routes[index].points.isNotEmpty) {
      final bounds = _boundsFromPoints(_routes[index].points);
      _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
    }
  }

  Future<void> _fetchRoutesInPlace() async {
    final source = _sourceController.text.trim();
    final dest = _destController.text.trim();
    setState(() => _routePanelVisible = true);
    // Geocode if needed
    double? srcLat = _sourceLat,
        srcLng = _sourceLng,
        dstLat = _destLat,
        dstLng = _destLng;
    if ((srcLat == null || srcLng == null) && source.isNotEmpty) {
      try {
        final locations = await geocoding.locationFromAddress(source);
        if (locations.isNotEmpty) {
          srcLat = locations.first.latitude;
          srcLng = locations.first.longitude;
        }
      } catch (_) {}
    }
    if ((dstLat == null || dstLng == null) && dest.isNotEmpty) {
      try {
        final locations = await geocoding.locationFromAddress(dest);
        if (locations.isNotEmpty) {
          dstLat = locations.first.latitude;
          dstLng = locations.first.longitude;
        }
      } catch (_) {}
    }
    if (dstLat == null || dstLng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid destination.')),
      );
      return;
    }
    // Build payload for backend
    final data = {
      'origin': srcLat != null && srcLng != null
          ? '${srcLat.toStringAsFixed(6)},${srcLng.toStringAsFixed(6)}'
          : source,
      'destination':
          '${dstLat.toStringAsFixed(6)},${dstLng.toStringAsFixed(6)}',
    };
    setState(() => _loadingSuggestions = true);
    try {
      final body = await RouteService.compareRoutes(data);
      final routesRaw = body['routes'] as List?;
      if (routesRaw == null) throw Exception('No routes found');
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
        final String? colorStr = r['color'] is String
            ? (r['color'] as String)
            : null;
        List<String> tags = [];
        if (r['tags'] is List) {
          tags = (r['tags'] as List)
              .map((e) => e?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
        }
        String distanceText = '';
        if (r['distance'] is Map && r['distance']['text'] != null)
          {distanceText = r['distance']['text'].toString();}
        String durationText = '';
        if (r['duration'] is Map && r['duration']['text'] != null)
          {durationText = r['duration']['text'].toString();}
        List<LatLng> points = [];
        if (r['polyline'] is String) {
          points = decodePolyline(r['polyline'] as String);
        } else if (r['points'] is List) {
          points = (r['points'] as List)
              .map<LatLng>(
                (p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ),
              )
              .toList();
        }
        parsed.add(
          RouteModel(
            id: id,
            points: points,
            safetyScore: score,
            color: colorStr,
            tags: tags,
            distanceText: distanceText,
            durationText: durationText,
          ),
        );
      }
      setState(() {
        _routes = parsed;
        _selectedRouteIndex = parsed.isNotEmpty ? 0 : null;
        _loadingSuggestions = false;
        // Optionally, fit map to first route
        if (_controller != null &&
            parsed.isNotEmpty &&
            parsed[0].points.isNotEmpty) {
          final bounds = _boundsFromPoints(parsed[0].points);
          _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
        }
        _buildPolylinesFromRoutes();
      });
    } catch (e) {
      setState(() => _loadingSuggestions = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching routes: $e')));
    }
  }

  void _buildPolylinesFromRoutes() {
    final polylines = <Polyline>{};
    for (var i = 0; i < _routes.length; i++) {
      final r = _routes[i];
      final id = PolylineId('route_$i');
      final isSelected =
          _selectedRouteIndex != null && _selectedRouteIndex == i;
      Color? parsed = parseColorString(r.color);
      Color baseColor;
      if (parsed != null) {
        baseColor = parsed;
      } else if (r.safetyScore >= 4.0) {
        baseColor = Colors.green;
      } else if (r.safetyScore >= 2.5) {
        baseColor = Colors.orange;
      } else {
        baseColor = Colors.red;
      }
      // Use Color.withOpacity for clarity and correctness
  final polyColor = baseColor.withAlpha(((isSelected ? 0.95 : 0.45) * 255).round());
      // If selected and navigating, draw only the remaining part from nearestIndex
      if (isSelected && _navigating && _lastNavUpdate != null && _lastNavUpdate!.nearestIndex >= 0) {
        final startIdx = _lastNavUpdate!.nearestIndex;
        final remainingPoints = (startIdx < r.points.length) ? r.points.sublist(startIdx) : r.points;
        // shadow
        polylines.add(
          Polyline(
            polylineId: PolylineId('route_${i}_shadow'),
            points: remainingPoints,
            color: Colors.black.withAlpha((0.18 * 255).round()),
            width: 14,
            consumeTapEvents: false,
            zIndex: 2,
          ),
        );
        polylines.add(
          Polyline(
            polylineId: id,
            points: remainingPoints,
            color: polyColor,
            width: 10,
            consumeTapEvents: true,
            onTap: () => _onSelectRoute(i),
            zIndex: 3,
          ),
        );
        // also draw faded past route for context (optional)
        if (startIdx > 1) {
          final past = r.points.sublist(0, startIdx);
          polylines.add(Polyline(
            polylineId: PolylineId('route_${i}_past'),
            points: past,
            color: baseColor.withAlpha((0.18 * 255).round()),
            width: 4,
            zIndex: 0,
          ));
        }
      } else {
        // normal rendering
        polylines.add(
          Polyline(
            polylineId: id,
            points: r.points,
            color: polyColor,
            width: isSelected ? 10 : 5,
            consumeTapEvents: true,
            onTap: () => _onSelectRoute(i),
            zIndex: isSelected ? 3 : 1,
          ),
        );
      }
    }
    setState(() => _polylines = polylines);
  }

  LatLngBounds _boundsFromPoints(List<LatLng> pts) {
    double south = pts.first.latitude,
        north = pts.first.latitude,
        west = pts.first.longitude,
        east = pts.first.longitude;
    for (final p in pts) {
      south = south < p.latitude ? south : p.latitude;
      north = north > p.latitude ? north : p.latitude;
      west = west < p.longitude ? west : p.longitude;
      east = east > p.longitude ? east : p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  void _startInPlaceNavigation(int routeIndex) {
    if (_routes.isEmpty || routeIndex < 0 || routeIndex >= _routes.length) return;
    final route = _routes[routeIndex];
    final points = route.points;
    if (points.isEmpty) return;

    final settings = Provider.of<TtsSettings>(context, listen: false);
    _navigationService ??= NavigationService(tts: _tts);
    // start emitting navigation updates
    _navigationService!.start(points, language: settings.language, rate: settings.rate);
    _navUpdateSub?.cancel();
    int lastCameraMs = 0;
    _navUpdateSub = _navigationService!.updates.listen((update) async {
      if (!mounted) return;
      // track previous position for rotation
      _prevNavLocation = _lastNavUpdate?.userLocation;
      setState(() {
        _navInstruction = update.instruction;
        _lastNavUpdate = update;
      });
      // update visuals
      _updateMarkers();
      _buildPolylinesFromRoutes();
      // Throttled camera follow (every 1200ms)
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastCameraMs > 1200) {
        lastCameraMs = now;
        try {
          if (_controller != null) {
            await _controller!.animateCamera(CameraUpdate.newLatLng(update.userLocation));
          }
        } catch (_) {}
      }
    });
    // persist navigation state so we can resume if app is backgrounded
    _persistNavigationState(routeIndex, points);
    setState(() {
      _navigating = true;
      _selectedRouteIndex = routeIndex;
    });
  }

  void _stopInPlaceNavigation() {
    _navigationService?.stop();
    _navUpdateSub?.cancel();
    _navUpdateSub = null;
    // clear persisted navigation state
    _clearPersistedNavigation();
    setState(() {
      _navigating = false;
      _navInstruction = 'Press Start to begin navigation';
    });
    // Automatically prompt rating (navigate to rating screen)
    if (_selectedRouteIndex != null && _selectedRouteIndex! >= 0 && _selectedRouteIndex! < _routes.length) {
      final routeId = _routes[_selectedRouteIndex!].id;
      Future.microtask(() {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => RatingScreen(routeId: routeId)));
      });
    }
  }

  // Persist minimal navigation state: selected route index and polyline points
  Future<void> _persistNavigationState(int selectedIndex, List<LatLng> points) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pts = points.map((p) => '${p.latitude},${p.longitude}').toList();
      await prefs.setString('nav_selected_index', selectedIndex.toString());
      await prefs.setStringList('nav_points', pts);
    } catch (_) {}
  }

  Future<void> _clearPersistedNavigation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('nav_selected_index');
      await prefs.remove('nav_points');
    } catch (_) {}
  }

  Future<void> _restoreNavigationIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idxStr = prefs.getString('nav_selected_index');
      final pts = prefs.getStringList('nav_points');
      if (idxStr != null && pts != null && pts.isNotEmpty) {
        final idx = int.tryParse(idxStr) ?? 0;
        final routePoints = pts.map((s) {
          final parts = s.split(',');
          return LatLng(double.parse(parts[0]), double.parse(parts[1]));
        }).toList();
  // start navigation quietly (mute TTS for a short window)
    if (!mounted) return;
    final settings = Provider.of<TtsSettings>(context, listen: false);
    _navigationService ??= NavigationService(tts: _tts);
    _navigationService!.start(routePoints, language: settings.language, rate: settings.rate, muteOnRestore: true);
        _navUpdateSub?.cancel();
        int lastCameraMs = 0;
        _navUpdateSub = _navigationService!.updates.listen((update) async {
          if (!mounted) return;
          _prevNavLocation = _lastNavUpdate?.userLocation;
          setState(() {
            _navInstruction = update.instruction;
            _lastNavUpdate = update;
            _navigating = true;
            _selectedRouteIndex = idx;
          });
          _updateMarkers();
          _buildPolylinesFromRoutes();
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastCameraMs > 1200) {
            lastCameraMs = now;
            try {
              if (_controller != null) {
                await _controller!.animateCamera(CameraUpdate.newLatLng(update.userLocation));
              }
            } catch (_) {}
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Navigation resumed')),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _sendSos() async {
    try {
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final service = SosService();
      final ok = await service.sendSos(lat: pos.latitude, lng: pos.longitude, message: 'SOS from SafeRoute');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'SOS sent' : 'Failed to send SOS')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to get location or send SOS')));
    }
  }


  GoogleMapController? _controller;
  static const LatLng _center = LatLng(23.0225, 72.5714); // Ahmedabad
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  MapType _mapType = MapType.hybrid;
  bool _trafficEnabled = true;
  bool _navigating = false;
  double? _sourceLat;
  double? _sourceLng;
  double? _destLat;
  double? _destLng;
  FlutterTts? _tts;
  bool _gettingLocation = false;
  List suggestions = [];
  Timer? _debounceTimer;
  bool _loadingSuggestions = false;
  bool _showCompare = false;
  NavigationService? _navigationService;
  StreamSubscription<NavigationUpdate>? _navUpdateSub;
  String _navInstruction = 'Press Start to begin navigation';
  NavigationUpdate? _lastNavUpdate;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<RouteModel> _routes = [];
  int? _selectedRouteIndex;
  bool _routePanelVisible = false;
  ActiveField _activeField = ActiveField.none;

  Widget _buildCompactRouteBar() {
    final src = _sourceController.text.trim().isNotEmpty
        ? _sourceController.text.trim()
        : 'Origin';
    final dst = _destController.text.trim().isNotEmpty
        ? _destController.text.trim()
        : 'Destination';
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                '$src → $dst',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              if (_navigating) _stopInPlaceNavigation();
            },
          ),
        ],
      ),
    );
  }

  Widget _maneuverIconFor(String instr) {
    final t = instr.toLowerCase();
    if (t.contains('left')) return const Icon(Icons.turn_left, color: Colors.black87);
    if (t.contains('right')) return const Icon(Icons.turn_right, color: Colors.black87);
    return const Icon(Icons.arrow_upward, color: Colors.black87);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SafeRoute Map"),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'traffic') {
                setState(() => _trafficEnabled = !_trafficEnabled);
              } else {
                setState(() {
                  switch (v) {
                    case 'normal':
                      _mapType = MapType.normal;
                      break;
                    case 'hybrid':
                      _mapType = MapType.hybrid;
                      break;
                    case 'satellite':
                      _mapType = MapType.satellite;
                      break;
                    case 'terrain':
                      _mapType = MapType.terrain;
                      break;
                    default:
                      _mapType = MapType.satellite;
                  }
                });
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'normal',
                child: Row(
                  children: [
                    if (_mapType == MapType.normal)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    const Text('Normal'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'hybrid',
                child: Row(
                  children: [
                    if (_mapType == MapType.hybrid)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    const Text('Hybrid'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'satellite',
                child: Row(
                  children: [
                    if (_mapType == MapType.satellite)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    const Text('Satellite'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'terrain',
                child: Row(
                  children: [
                    if (_mapType == MapType.terrain)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    const Text('Terrain'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'traffic',
                child: Text(
                  _trafficEnabled ? 'Disable Traffic' : 'Enable Traffic',
                ),
              ),
            ],
            icon: const Icon(Icons.map),
          ),
          IconButton(
            icon: const Icon(Icons.record_voice_over),
            onPressed: () async {
              // show small popup dialog for TTS settings
              final settings = Provider.of<TtsSettings>(context, listen: false);
              String selectedLang = settings.language;
              // Ensure selectedLang is a valid dropdown value
              const supportedLangs = ['en-US', 'hi-IN'];
              if (!supportedLangs.contains(selectedLang)) {
                selectedLang = 'en-US';
              }
              double selectedRate = settings.rate;
              if (!mounted) return;
              await showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('TTS Settings'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedLang,
                        items: const [
                          DropdownMenuItem(
                            value: 'en-US',
                            child: Text('English'),
                          ),
                          DropdownMenuItem(
                            value: 'hi-IN',
                            child: Text('Hindi'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) selectedLang = v;
                        },
                        decoration: const InputDecoration(
                          labelText: 'Language',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Rate'),
                          Expanded(
                            child: StatefulBuilder(
                              builder: (c, setStateSB) {
                                return Slider(
                                  value: selectedRate,
                                  min: 0.2,
                                  max: 1.0,
                                  divisions: 8,
                                  label: selectedRate.toStringAsFixed(2),
                                  onChanged: (v) =>
                                      setStateSB(() => selectedRate = v),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        // close dialog first (avoid using dialog context after async await)
                        Navigator.of(ctx).pop();
                        // apply settings to provider and live TTS
                        await settings.setLanguage(selectedLang);
                        await settings.setRate(selectedRate);
                        try {
                          await _tts?.setLanguage(selectedLang);
                          await _tts?.setSpeechRate(selectedRate);
                          // Also apply settings to navigation service if active so changes take effect immediately
                          _navigationService?.applyTtsSettings(language: selectedLang, rate: selectedRate);
                        } catch (_) {}
                      },
                      child: const Text('Submit'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'TTS Settings',
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Text(
                'SafeRoute',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
            ListTile(
              title: const Text('Home'),
              onTap: () => Navigator.pushReplacementNamed(context, '/'),
            ),
            ListTile(
              title: const Text('Profile'),
              onTap: () => Navigator.pushNamed(context, '/profile'),
            ),
            ListTile(
              title: const Text('Settings'),
              onTap: () => Navigator.pushNamed(context, '/settings'),
            ),
            ListTile(
              title: const Text('Onboarding'),
              onTap: () => Navigator.pushNamed(context, '/onboarding'),
            ),
            ListTile(
              title: const Text('Map Detail'),
              onTap: () => Navigator.pushNamed(context, '/map_detail'),
            ),
            ListTile(
              title: const Text('Contacts'),
              onTap: () => Navigator.pushNamed(context, '/contacts'),
            ),
            ListTile(
              title: const Text('Logout'),
              onTap: () => Navigator.pushReplacementNamed(context, '/login'),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
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
                      suffixIcon: _gettingLocation
                          ? const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Use current location / Clear',
                              icon: _sourceLat != null && _sourceLng != null
                                  ? const Icon(Icons.clear)
                                  : const Icon(Icons.gps_fixed),
                              onPressed: () async {
                                if (_sourceLat != null && _sourceLng != null) {
                                  setState(() {
                                    _sourceLat = null;
                                    _sourceLng = null;
                                    _sourceController.clear();
                                  });
                                  return;
                                }

                                setState(() => _gettingLocation = true);
                                try {
                                  LocationPermission permission =
                                      await Geolocator.checkPermission();
                                  if (permission == LocationPermission.denied) {
                                    permission =
                                        await Geolocator.requestPermission();
                                  }
                                  if (permission ==
                                          LocationPermission.deniedForever ||
                                      permission == LocationPermission.denied) {
                                    if (mounted) {
                                      _sourceController.text =
                                          'Location permission denied';
                                    }
                                  } else {
                                    final locationSettings =
                                        const LocationSettings(
                                          accuracy: LocationAccuracy.high,
                                        );
                                    final pos =
                                        await Geolocator.getCurrentPosition(
                                          locationSettings: locationSettings,
                                        );
                                    if (!mounted) return;
                                    try {
                                      final placemarks = await geocoding
                                          .placemarkFromCoordinates(
                                            pos.latitude,
                                            pos.longitude,
                                          );
                                      if (placemarks.isNotEmpty) {
                                        final pm = placemarks.first;
                                        _sourceController.text =
                                            '${pm.name ?? ''} ${pm.street ?? ''}, ${pm.locality ?? ''}'
                                                .trim();
                                      } else {
                                        _sourceController.text =
                                            '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
                                      }
                                    } catch (_) {
                                      _sourceController.text =
                                          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
                                    }
                                    _sourceLat = pos.latitude;
                                    _sourceLng = pos.longitude;
                                    _updateMarkers();
                                  }
                                } catch (e) {
                                  if (mounted){
                                    _sourceController.text =
                                        'Unable to get location';}
                                } finally {
                                  if (mounted){
                                    setState(() => _gettingLocation = false);}
                                }
                              },
                            ),
                    ),
                    onChanged: (v) {
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

                      _debounceTimer?.cancel();
                      if (hasText) {
                        setState(() => _loadingSuggestions = true);
                        _debounceTimer = Timer(
                          const Duration(milliseconds: 400),
                          () async {
                            try {
                              final preds = await _placesService.autocomplete(
                                value,
                              );
                              if (!mounted) return;
                              if (preds.isEmpty) {
                                setState(
                                  () => suggestions = [
                                    {'description': value, 'synthetic': true},
                                  ],
                                );
                              } else {
                                setState(() => suggestions = preds);
                              }
                            } catch (_) {
                              if (!mounted) return;
                              setState(() {
                                suggestions = [
                                  {'description': value, 'synthetic': true},
                                ];
                              });
                            } finally {
                              if (mounted) {
                                setState(() => _loadingSuggestions = false);
                              }
                            }
                          },
                        );
                      } else {
                        if (mounted) {
                          setState(() {
                            suggestions = [];
                            _loadingSuggestions = false;
                          });
                        }
                      }
                    },
                  ),
                if (_loadingSuggestions)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
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
                        final bool synthetic =
                            (item is Map && item['synthetic'] == true);
                        if (synthetic) {
                          desc = (item['description'] ?? '').toString();
                        } else if (item is AutocompletePrediction) {
                          desc =
                              item.description ??
                              item.structuredFormatting?.mainText ??
                              '';
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
                                  final locations = await geocoding
                                      .locationFromAddress(desc);
                                  if (locations.isNotEmpty) {
                                    final loc = locations.first;
                                    _sourceLat = loc.latitude;
                                    _sourceLng = loc.longitude;
                                    if (_controller != null)
                                      {_controller!.animateCamera(
                                        CameraUpdate.newLatLng(
                                          LatLng(_sourceLat!, _sourceLng!),
                                        ),
                                      );}
                                    _updateMarkers();
                                  }
                                } catch (_) {}
                              } else if (item is AutocompletePrediction &&
                                  item.placeId != null) {
                                final details = await _placesService
                                    .getPlaceDetails(item.placeId!);
                                final lat = details?.geometry?.location?.lat;
                                final lng = details?.geometry?.location?.lng;
                                if (lat != null && lng != null) {
                                  _sourceLat = lat;
                                  _sourceLng = lng;
                                  if (_controller != null)
                                    {_controller!.animateCamera(
                                      CameraUpdate.newLatLng(LatLng(lat, lng)),
                                    );}
                                  _updateMarkers();
                                }
                              }
                            } else {
                              _destController.text = desc;
                              if (synthetic) {
                                try {
                                  final locations = await geocoding
                                      .locationFromAddress(desc);
                                  if (locations.isNotEmpty) {
                                    final loc = locations.first;
                                    _destLat = loc.latitude;
                                    _destLng = loc.longitude;
                                    if (_controller != null)
                                      {_controller!.animateCamera(
                                        CameraUpdate.newLatLng(
                                          LatLng(_destLat!, _destLng!),
                                        ),
                                      );}
                                    _updateMarkers();
                                  }
                                } catch (_) {}
                              } else if (item is AutocompletePrediction &&
                                  item.placeId != null) {
                                final details = await _placesService
                                    .getPlaceDetails(item.placeId!);
                                final lat = details?.geometry?.location?.lat;
                                final lng = details?.geometry?.location?.lng;
                                if (lat != null && lng != null) {
                                  _destLat = lat;
                                  _destLng = lng;
                                  if (_controller != null)
                                    {_controller!.animateCamera(
                                      CameraUpdate.newLatLng(LatLng(lat, lng)),
                                    );}
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: Card(
                  key: ValueKey(_lastNavUpdate?.spoken ?? _navInstruction),
                  elevation: 6,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        if (_lastNavUpdate != null) ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: _maneuverIconFor(_lastNavUpdate!.instruction),
                          ),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _lastNavUpdate?.spoken ?? _navInstruction,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (_lastNavUpdate != null)
                                Text(
                                  'Next in ${formatDistanceLong(_lastNavUpdate!.distanceToNext)} • ${formatDistanceLong(_lastNavUpdate!.remainingDistance)} left',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _stopInPlaceNavigation,
                          child: const Text('Stop'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Expanded map below the controls
          Expanded(
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: const CameraPosition(
                target: _center,
                zoom: 13,
              ),
              myLocationEnabled: true,
              polylines: _polylines,
              markers: _markers,
              mapType: _mapType,
              trafficEnabled: _trafficEnabled,
              onTap: (_) => setState(() => _routePanelVisible = false),
            ),
          ),

          ],
          ),
          // Route options panel (in-place) as overlay
          if (_routePanelVisible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _navigating ? 120 : 260,
                child: Material(
                  elevation: 12,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                    child: Container(
                      color: Colors.white,
                      child: _navigating
                    ? Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Routes available: ${_routes.length}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.expand_less),
                              onPressed: () =>
                                  setState(() => _routePanelVisible = false),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // Drag handle and header
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Column(
                              children: [
                                Container(
                                  width: 48,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Routes',
                                        style: TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          setState(() {
                                            _routePanelVisible = false;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _routes.length,
                              itemBuilder: (context, index) {
                                final r = _routes[index];
                                final selected = _selectedRouteIndex == index;
                                return Container(
                                  color: selected ? Colors.blue.shade50 : null,
                                  child: ListTile(
                                    selected: selected,
                                    leading: r.color != null
                                        ? Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: parseColorString(r.color) ??
                                                  Colors.blueGrey,
                                              shape: BoxShape.circle,
                                            ),
                                          )
                                        : null,
                                    title: Text(
                                      'Route ${index + 1}${selected ? ' (selected)' : ''}',
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Safety: ${r.safetyScore.toStringAsFixed(2)}',
                                        ),
                                        if (r.distanceText.isNotEmpty)
                                          Text('Distance: ${r.distanceText}'),
                                        if (r.durationText.isNotEmpty)
                                          Text('Duration: ${r.durationText}'),
                                      ],
                                    ),
                                    onTap: () => _onSelectRoute(index),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            _navigating &&
                                                    _selectedRouteIndex == index
                                                ? Icons.stop
                                                : Icons.navigation,
                                          ),
                                          onPressed: () {
                                            if (_navigating &&
                                                _selectedRouteIndex == index) {
                                              _stopInPlaceNavigation();
                                            } else {
                                              _startInPlaceNavigation(index);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
                  ),
                ),
            ),
      )],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      // Hide floating action buttons when route panel is visible OR when actively navigating.
      floatingActionButton: (_routePanelVisible || _navigating)
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FloatingActionButton(
                  backgroundColor: Colors.redAccent,
                  heroTag: 'sos',
                  mini: true,
                  onPressed: () async {
                    // confirm
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Send SOS'),
                        content: const Text('Send SOS to your trusted contacts with your current location?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Send')),
                        ],
                      ),
                    );
                    if (ok == true) await _sendSos();
                  },
                  child: const Icon(Icons.warning),
                ),
                const SizedBox(height: 8),
                // Debug inspector quick button (shows stored token and example payloads)
                FloatingActionButton(
                  heroTag: 'debug',
                  mini: true,
                  onPressed: () async {
                    if (!mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DebugInspectorScreen()));
                  },
                  child: const Icon(Icons.bug_report),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'routes',
                  onPressed: null,
                  label: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.0),
                    child: Text('Route Options'),
                  ),
                ),
              ],
            ),
    );
  }
}
