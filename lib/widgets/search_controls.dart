// widgets/search_controls.dart
// Encapsulates the source/destination inputs, suggestions and Compare button
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_place/google_place.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

import '../services/places_service.dart';

enum ActiveField { none, source, dest }

class SearchControls extends StatefulWidget {
  final TextEditingController sourceController;
  final TextEditingController destController;
  final bool navigating;
  final bool showCompare;
  final double? sourceLat;
  final double? sourceLng;
  final double? destLat;
  final double? destLng;
  final void Function(double lat, double lng) onSourceCoordsSet;
  final VoidCallback onSourceCoordsCleared;
  final void Function(double lat, double lng) onDestCoordsSet;
  final VoidCallback onComparePressed;
  final void Function(LatLng) onMoveCamera;
  final IPlacesService? placesService;

  const SearchControls({
    super.key,
    required this.sourceController,
    required this.destController,
    required this.navigating,
    required this.showCompare,
    required this.sourceLat,
    required this.sourceLng,
    required this.destLat,
    required this.destLng,
    required this.onSourceCoordsSet,
    required this.onSourceCoordsCleared,
    required this.onDestCoordsSet,
    required this.onComparePressed,
    required this.onMoveCamera,
    this.placesService,
  });

  @override
  State<SearchControls> createState() => _SearchControlsState();
}

class _SearchControlsState extends State<SearchControls> {
  late final IPlacesService _placesService;
  ActiveField _activeField = ActiveField.none;
  List suggestions = [];
  Timer? _debounceTimer;
  bool _loadingSuggestions = false;
  bool _gettingLocation = false;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _placesService = widget.placesService ?? PlacesService.fromEnv();
  }

  Future<void> _useCurrentLocationForSource() async {
    if (widget.sourceLat != null && widget.sourceLng != null) {
      widget.onSourceCoordsCleared();
      return;
    }

    setState(() {
      _gettingLocation = true;
    });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        if (mounted) widget.sourceController.text = 'Location permission denied';
      } else {
        final locationSettings = const LocationSettings(accuracy: LocationAccuracy.high);
        final pos = await Geolocator.getCurrentPosition(locationSettings: locationSettings);
        if (!mounted) return;
        try {
          final placemarks = await geocoding.placemarkFromCoordinates(pos.latitude, pos.longitude);
          if (placemarks.isNotEmpty) {
            final pm = placemarks.first;
            widget.sourceController.text = '${pm.name ?? ''} ${pm.street ?? ''}, ${pm.locality ?? ''}'.trim();
          } else {
            widget.sourceController.text = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
          }
        } catch (_) {
          widget.sourceController.text = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
        }
        widget.onSourceCoordsSet(pos.latitude, pos.longitude);
        widget.onMoveCamera(LatLng(pos.latitude, pos.longitude));
      }
    } catch (_) {
      if (mounted) widget.sourceController.text = 'Unable to get location';
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  void _onSourceChanged(String v) {
    final value = v.trim();
    _debounceTimer?.cancel();
    if (value.length >= 2) {
      setState(() => _loadingSuggestions = true);
      _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
        try {
          final preds = await _placesService.autocomplete(value);
          if (!mounted) return;
          // filter predictions to those containing the input anywhere (case-insensitive)
          final lower = value.toLowerCase();
          final filtered = preds.where((p) => (p.description ?? '').toLowerCase().contains(lower)).toList();
          if (filtered.isEmpty) {
            // if no remote predictions, try nearby placemarks as suggestions when we have a location
            List<Map<String, dynamic>> nearby = [];
            try {
              final perm = await Geolocator.checkPermission();
              if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
                final pos = await Geolocator.getCurrentPosition();
                final placemarks = await geocoding.placemarkFromCoordinates(pos.latitude, pos.longitude);
                for (final pm in placemarks) {
                  final label = '${pm.name ?? ''} ${pm.street ?? ''}, ${pm.locality ?? ''}'.trim();
                  if (label.toLowerCase().contains(lower)) nearby.add({'description': label, 'synthetic': true});
                }
              }
            } catch (_) {}

            if (nearby.isNotEmpty) {
              setState(() {
                suggestions = nearby;
              });
            } else {
              // if nothing from remote or nearby, offer the typed text as a synthetic suggestion
              setState(() {
                suggestions = [
                  {
                    'description': value,
                    'synthetic': true,
                  }
                ];
              });
            }
          } else {
            setState(() {
              suggestions = filtered;
            });
          }
        } catch (_) {
          if (!mounted) return;
          setState(() {
            suggestions = [];
          });
        } finally {
          if (mounted) {
            setState(() {
              _loadingSuggestions = false;
            });
          }
        }
      });
    } else {
      if (mounted) {
        setState(() {
          suggestions = [];
          _loadingSuggestions = false;
        });
      }
    }
  }

  void _onDestChanged(String value) {
    final hasText = value.trim().length >= 2;
    _debounceTimer?.cancel();
    if (hasText) {
      setState(() => _loadingSuggestions = true);
      _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
        try {
          final preds = await _placesService.autocomplete(value);
          if (!mounted) return;
          if (preds.isEmpty) {
            // show typed text as a fallback suggestion so the user can continue
            setState(() => suggestions = [
                  {
                    'description': value,
                    'synthetic': true,
                  }
                ]);
          } else {
            setState(() => suggestions = preds);
          }
        } catch (_) {
          if (!mounted) return;
          setState(() => suggestions = [
                {
                  'description': value,
                  'synthetic': true,
                }
              ]);
        } finally {
          if (mounted) setState(() => _loadingSuggestions = false);
        }
      });
    } else {
      if (mounted) {
        setState(() {
          suggestions = [];
          _loadingSuggestions = false;
        });
      }
    }
  }

  Widget _buildSuggestions() {
    if (_loadingSuggestions) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
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
                widget.sourceController.text = desc;
                if (synthetic) {
                  try {
                    final locations = await geocoding.locationFromAddress(desc);
                    if (locations.isNotEmpty) {
                      final loc = locations.first;
                      widget.onSourceCoordsSet(loc.latitude, loc.longitude);
                      widget.onMoveCamera(LatLng(loc.latitude, loc.longitude));
                    }
                  } catch (_) {}
                } else if (item is AutocompletePrediction && item.placeId != null) {
                  final details = await _placesService.getPlaceDetails(item.placeId!);
                  final lat = details?.geometry?.location?.lat;
                  final lng = details?.geometry?.location?.lng;
                  if (lat != null && lng != null) {
                    widget.onSourceCoordsSet(lat, lng);
                    widget.onMoveCamera(LatLng(lat, lng));
                  }
                }
              } else {
                widget.destController.text = desc;
                if (synthetic) {
                  try {
                    final locations = await geocoding.locationFromAddress(desc);
                    if (locations.isNotEmpty) {
                      final loc = locations.first;
                      widget.onDestCoordsSet(loc.latitude, loc.longitude);
                      widget.onMoveCamera(LatLng(loc.latitude, loc.longitude));
                    }
                  } catch (_) {}
                } else if (item is AutocompletePrediction && item.placeId != null) {
                  final details = await _placesService.getPlaceDetails(item.placeId!);
                  final lat = details?.geometry?.location?.lat;
                  final lng = details?.geometry?.location?.lng;
                  if (lat != null && lng != null) {
                    widget.onDestCoordsSet(lat, lng);
                    widget.onMoveCamera(LatLng(lat, lng));
                  }
                }
              }
              _activeField = ActiveField.none;
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          // Show either a minimal placeholder while navigating, or the source TextField
          if (widget.navigating)
            const SizedBox.shrink()
          else
            TextField(
              controller: widget.sourceController,
              decoration: InputDecoration(
                labelText: 'Source',
                hintText: 'Type origin or use current location',
                prefixIcon: const Icon(Icons.my_location),
                suffixIcon: _gettingLocation
                    ? const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        tooltip: 'Use current location / Clear',
                        icon: widget.sourceLat != null && widget.sourceLng != null ? const Icon(Icons.clear) : const Icon(Icons.gps_fixed),
                        onPressed: _useCurrentLocationForSource,
                      ),
              ),
              onChanged: (v) => _onSourceChanged(v),
              onTap: () => _activeField = ActiveField.source,
            ),
          const SizedBox(height: 8),
          if (!widget.navigating)
            TextField(
              controller: widget.destController,
              decoration: const InputDecoration(
                labelText: 'Destination',
                hintText: 'Start typing destination...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                _activeField = ActiveField.dest;
                _onDestChanged(v);
              },
              onTap: () => _activeField = ActiveField.dest,
            ),
          // suggestions
          _buildSuggestions(),
          const SizedBox(height: 12),
          if (widget.showCompare)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.onComparePressed,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Compare Routes'),
              ),
            ),
        ],
      ),
    );
  }
}
