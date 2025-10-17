import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// A lightweight in-app navigation screen. It does not replace Google Maps
// turn-by-turn but provides a local navigation UI: shows the chosen route,
// tracks the user's location, centers the camera, and shows simple next-
// maneuver hints derived from polyline geometry.

class NavigationScreen extends StatefulWidget {
  final String sourceName;
  final String destName;
  final List<LatLng> points;

  const NavigationScreen({super.key, required this.points, required this.sourceName, required this.destName});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  GoogleMapController? _controller;
  StreamSubscription<Position?>? _posSub;
  LatLng? _userLoc;
  bool _navigating = false;
  int _nextIndex = 0; // index in points that we are heading to
  String _instruction = 'Press Start to begin navigation';

  @override
  void initState() {
    super.initState();
    // initially center map on first point or user's last known location
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _startNavigation() async {
    if (widget.points.isEmpty) return;
    // request permission and start listening to location updates
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission required for navigation')));
      }
      return;
    }

    setState(() {
      _navigating = true;
      _instruction = 'Navigation started';
    });

    // listen to position stream with reasonable settings
    _posSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2))
        .listen((pos) {
      final loc = LatLng(pos.latitude, pos.longitude);
      _onLocationUpdate(loc);
    });
  }

  void _stopNavigation() {
    setState(() {
      _navigating = false;
      _instruction = 'Navigation stopped';
    });
    _posSub?.cancel();
    _posSub = null;
  }

  void _onLocationUpdate(LatLng loc) async {
    _userLoc = loc;

    // center camera on the user
    if (_controller != null) {
      try {
        await _controller!.animateCamera(CameraUpdate.newLatLng(loc));
      } catch (_) {}
    }

    // compute nearest index on the route polyline
    final nearestIdx = _findNearestSegmentIndex(loc, widget.points);
    // next waypoint is min(nearestIdx+1, last)
    final nextIdx = math.min(nearestIdx + 1, widget.points.length - 1);
    _nextIndex = nextIdx;

    final distanceToNext = Geolocator.distanceBetween(loc.latitude, loc.longitude, widget.points[nextIdx].latitude, widget.points[nextIdx].longitude);

    // derive a simple instruction based on angle change at nextIdx
    final instr = _deriveInstructionAtIndex(nextIdx);

    setState(() {
      _instruction = '$instr — ${distanceToNext.toStringAsFixed(0)} m';
    });
  }

  // Find index of point on the polyline that is nearest to the given location.
  int _findNearestSegmentIndex(LatLng loc, List<LatLng> pts) {
    if (pts.isEmpty) return 0;
    double bestDist = double.infinity;
    int bestIdx = 0;
    for (int i = 0; i < pts.length; i++) {
      final d = Geolocator.distanceBetween(loc.latitude, loc.longitude, pts[i].latitude, pts[i].longitude);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  // Very naive instruction generator: check angle between incoming and outgoing segment
  String _deriveInstructionAtIndex(int idx) {
    if (widget.points.length < 3) return 'Continue';
    final prev = (idx - 1).clamp(0, widget.points.length - 1);
    final next = (idx + 1).clamp(0, widget.points.length - 1);
    final a = widget.points[prev];
    final b = widget.points[idx];
    final c = widget.points[next];

    final bearing1 = _bearing(a, b);
    final bearing2 = _bearing(b, c);
    double diff = (bearing2 - bearing1).abs();
    if (diff > 180) diff = 360 - diff;

    if (diff < 15) return 'Continue straight';
    if (bearing2 > bearing1) {
      return 'Turn right';
    } else {
      return 'Turn left';
    }
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

  double _remainingDistanceFromIndex(int idx) {
    if (idx >= widget.points.length - 1) return 0.0;
    double sum = 0.0;
    for (int i = idx; i < widget.points.length - 1; i++) {
      sum += Geolocator.distanceBetween(widget.points[i].latitude, widget.points[i].longitude, widget.points[i + 1].latitude, widget.points[i + 1].longitude);
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final routePolyline = Polyline(
      polylineId: const PolylineId('nav_route'),
      points: widget.points,
      color: Colors.blueAccent,
      width: 6,
    );

    final markers = <Marker>{
      if (widget.points.isNotEmpty)
        Marker(markerId: const MarkerId('origin'), position: widget.points.first, infoWindow: InfoWindow(title: widget.sourceName)),
      if (widget.points.isNotEmpty)
        Marker(markerId: const MarkerId('destination'), position: widget.points.last, infoWindow: InfoWindow(title: widget.destName)),
      if (_userLoc != null)
        Marker(markerId: const MarkerId('you'), position: _userLoc!, infoWindow: InfoWindow(title: 'You'), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Navigation')),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: widget.points.isNotEmpty ? widget.points.first : const LatLng(0, 0), zoom: 16),
              polylines: {routePolyline},
              markers: markers,
              myLocationEnabled: true,
              onMapCreated: (c) => _controller = c,
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_instruction, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('Remaining: ${_remainingDistanceFromIndex(_nextIndex).toStringAsFixed(0)} m', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                )),
                ElevatedButton(
                  onPressed: _navigating ? _stopNavigation : _startNavigation,
                  child: Text(_navigating ? 'Stop' : 'Start'),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
