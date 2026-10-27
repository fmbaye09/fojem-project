import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../core/geo/geo_location.dart';
import '../../services/map/map_service.dart';
import '../../services/map/osm_map_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Sélection d'un point (recherche d'adresse OSM + tap sur la carte + position GPS actuelle) —
/// réutilisé pour départ/arrivée/étapes/ramassage. Retourne un [GeoLocation] via `Navigator.pop`.
class LocationPickerScreen extends StatefulWidget {
  final String title;
  final GeoLocation? initial;
  final MapService? mapService;

  const LocationPickerScreen({
    super.key,
    required this.title,
    this.initial,
    this.mapService,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late final MapService _mapService = widget.mapService ?? OsmMapService();
  final _searchController = TextEditingController();
  final _mapController = MapController();
  Timer? _debounce;
  List<GeoLocation> _results = [];
  bool _isSearching = false;
  bool _isLocatingGps = false;
  GeoLocation? _selected;

  static const _dakar = ll.LatLng(14.6928, -17.4467);

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    if (widget.initial != null) {
      _searchController.text = widget.initial!.address;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isSearching = true);
    final results = await _mapService.searchAddress(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _isSearching = false;
    });
  }

  void _selectResult(GeoLocation location) {
    setState(() {
      _selected = location;
      _results = [];
      _searchController.text = location.address;
    });
    _mapController.move(ll.LatLng(location.lat, location.lng), 15);
  }

  Future<void> _onMapTap(ll.LatLng point) async {
    final address = await _mapService.reverseGeocode(point.latitude, point.longitude);
    if (!mounted) return;
    setState(() {
      _selected = address;
      _searchController.text = address.address;
    });
  }

  Future<void> _useCurrentGpsLocation() async {
    setState(() => _isLocatingGps = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez activer le GPS sur votre appareil.')),
        );
        setState(() => _isLocatingGps = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission de localisation refusée.')),
        );
        setState(() => _isLocatingGps = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final geocoded = await _mapService.reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _selected = geocoded;
        _results = [];
        _searchController.text = geocoded.address;
        _isLocatingGps = false;
      });
      _mapController.move(ll.LatLng(pos.latitude, pos.longitude), 15);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLocatingGps = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'obtenir votre position GPS actuelle.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _selected != null
        ? ll.LatLng(_selected!.lat, _selected!.lng)
        : _dakar;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isLocatingGps ? null : _useCurrentGpsLocation,
            icon: _isLocatingGps
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                : const Icon(Icons.my_location_rounded, size: 18, color: AppColors.primary),
            label: Text(
              'Ma position',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Rechercher un quartier, une gare ou une adresse...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _searchController.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _results = []);
                            },
                            icon: const Icon(Icons.clear, size: 18),
                          )
                        : null,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          if (_results.isNotEmpty)
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, index) {
                  final r = _results[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.place_outlined, color: AppColors.primary),
                    title: Text(
                      r.address,
                      style: AppTextStyles.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectResult(r),
                  );
                },
              ),
            )
          else ...[
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: _selected != null ? 14 : 11,
                      onTap: (_, point) => _onMapTap(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'sn.fojem.app',
                      ),
                      if (_selected != null)
                        MarkerLayer(markers: [
                          Marker(
                            point: ll.LatLng(_selected!.lat, _selected!.lng),
                            width: 44,
                            height: 44,
                            child: const Icon(Icons.location_on, color: AppColors.primary, size: 42),
                          ),
                        ]),
                    ],
                  ),
                  Positioned(
                    right: AppSpacing.md,
                    bottom: 64,
                    child: FloatingActionButton.small(
                      heroTag: 'loc_picker_gps_btn',
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.primary,
                      onPressed: _isLocatingGps ? null : _useCurrentGpsLocation,
                      child: _isLocatingGps
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            )
                          : const Icon(Icons.my_location_rounded),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        _selected != null
                            ? '📍 ${_selected!.address}'
                            : 'Touchez la carte ou utilisez le bouton GPS pour choisir le point exact',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _selected == null ? null : () => Navigator.of(context).pop(_selected),
                  icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
                  label: const Text('Confirmer ce point exact', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMd),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
