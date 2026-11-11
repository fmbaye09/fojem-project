import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../core/geo/geo_location.dart';
import '../../services/map/map_service.dart';
import '../../services/map/osm_map_service.dart';
import '../../services/map/place_search.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'glow.dart';

/// Choix d'un lieu (départ, arrivée, arrêt, point de ramassage), comme dans
/// les applis de VTC : on tape, on touche un résultat, c'est choisi. Avant
/// toute saisie : la position actuelle, les derniers lieux choisis et les
/// grandes villes ; « Choisir sur la carte » pour un point précis. Rend un
/// [GeoLocation] via `Navigator.pop`.
class LocationPickerScreen extends StatefulWidget {
  final String title;
  final GeoLocation? initial;
  final MapService? mapService;
  final PlaceSearch? placeSearch;

  /// Ligne « Ma position » en tête de liste.
  final bool showCurrentLocation;

  final String hint;

  const LocationPickerScreen({
    super.key,
    required this.title,
    this.initial,
    this.mapService,
    this.placeSearch,
    this.showCurrentLocation = true,
    this.hint = 'Ville, quartier, gare routière…',
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late final MapService _mapService = widget.mapService ?? OsmMapService();
  late final PlaceSearch _placeSearch = widget.placeSearch ?? PlaceSearch(mapService: _mapService);
  final _searchController = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  String _query = '';
  List<PlaceSuggestion> _results = const [];
  List<PlaceSuggestion> _recents = const [];
  bool _isSearching = false;
  int _searchId = 0;
  bool _isLocating = false;
  bool _mapMode = false;

  @override
  void initState() {
    super.initState();
    RecentPlaces.load().then((recents) {
      if (mounted) setState(() => _recents = recents);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    setState(() => _query = query.trim());
    if (query.trim().length < 2) {
      _searchId++;
      setState(() {
        _results = const [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    final id = ++_searchId;
    final results = await _placeSearch.search(query, near: widget.initial);
    if (!mounted || id != _searchId) return;
    setState(() {
      _results = results;
      _isSearching = false;
    });
  }

  Future<void> _pick(GeoLocation location, {String? title}) async {
    await RecentPlaces.add(location, title: title);
    if (mounted) Navigator.of(context).pop(location);
  }

  void _clear() {
    _searchController.clear();
    _onQueryChanged('');
    _focus.requestFocus();
  }

  /// Position GPS actuelle, avec son adresse quand le réseau la donne.
  Future<GeoLocation?> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Activez la localisation de votre téléphone.');
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _snack('FOJËM n’a pas accès à votre position.');
        return null;
      }
      final last = await Geolocator.getLastKnownPosition();
      final pos = last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 5)
          ? last
          : await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 12),
              ),
            );
      try {
        return await _mapService.reverseGeocode(pos.latitude, pos.longitude).timeout(const Duration(seconds: 8));
      } catch (_) {
        return GeoLocation(lat: pos.latitude, lng: pos.longitude, address: 'Ma position');
      }
    } catch (_) {
      _snack('Position introuvable pour le moment. Réessayez ou cherchez une adresse.');
      return null;
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    final here = await _locate();
    if (!mounted) return;
    setState(() => _isLocating = false);
    if (here != null) await _pick(here);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_mapMode) {
      return _MapPicker(
        title: widget.title,
        initial: widget.initial,
        mapService: _mapService,
        locate: _locate,
        onBack: () => setState(() => _mapMode = false),
        onConfirm: (location) => _pick(location),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Retour',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(widget.title, style: AppTextStyles.title2.copyWith(fontSize: 20)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchController,
                focusNode: _focus,
                autofocus: true,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                style: AppTextStyles.bodyLargeSemibold,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          onPressed: _clear,
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                ),
              ),
            ),
            if (_isSearching) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _query.length < 2 ? _startList() : _resultList()),
          ],
        ),
      ),
    );
  }

  /// Avant la saisie : position actuelle, carte, récents, grandes villes.
  Widget _startList() {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (widget.showCurrentLocation)
          _SuggestionTile(
            icon: Icons.my_location_rounded,
            iconColor: AppColors.brandText,
            title: 'Ma position',
            subtitle: 'Utiliser la position du téléphone',
            trailing: _isLocating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            onTap: _isLocating ? null : _useCurrentLocation,
          ),
        _SuggestionTile(
          icon: Icons.map_outlined,
          title: 'Choisir sur la carte',
          subtitle: 'Pour un point précis',
          onTap: () => setState(() => _mapMode = true),
        ),
        if (_recents.isNotEmpty) ...[
          const _SectionLabel('Récents'),
          for (final place in _recents)
            _SuggestionTile(
              icon: Icons.history_rounded,
              title: place.title,
              subtitle: place.subtitle,
              onTap: () => _pick(place.location, title: place.title),
            ),
        ],
        const _SectionLabel('Villes'),
        for (final city in PlaceSearch.cities())
          _SuggestionTile(
            icon: Icons.location_city_rounded,
            title: city.title,
            onTap: () => _pick(city.location, title: city.title),
          ),
      ],
    );
  }

  Widget _resultList() {
    final waiting = _isSearching && _results.isEmpty;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (waiting)
          for (final city in PlaceSearch.matchingCities(_query))
            _SuggestionTile(
              icon: Icons.location_city_rounded,
              title: city.title,
              subtitle: city.subtitle,
              onTap: () => _pick(city.location, title: city.title),
            ),
        for (final place in _results)
          _SuggestionTile(
            icon: _iconFor(place.kind),
            title: place.title,
            subtitle: place.subtitle,
            onTap: () => _pick(place.location, title: place.title),
          ),
        if (!_isSearching && _results.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              'Aucun lieu trouvé pour « $_query ». Essayez le nom du quartier ou de la ville, ou choisissez le point sur la carte.',
              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
        if (!_isSearching || _results.isNotEmpty)
          _SuggestionTile(
            icon: Icons.map_outlined,
            title: 'Choisir sur la carte',
            subtitle: 'Vous ne trouvez pas ? Placez le point vous-même',
            onTap: () => setState(() => _mapMode = true),
          ),
      ],
    );
  }

  static IconData _iconFor(PlaceKind kind) {
    switch (kind) {
      case PlaceKind.city:
        return Icons.location_city_rounded;
      case PlaceKind.busStation:
        return Icons.directions_bus_rounded;
      case PlaceKind.toll:
        return Icons.toll_rounded;
      case PlaceKind.roundabout:
        return Icons.roundabout_right_rounded;
      case PlaceKind.fuelStation:
        return Icons.local_gas_station_rounded;
      case PlaceKind.recent:
        return Icons.history_rounded;
      case PlaceKind.address:
        return Icons.place_outlined;
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Semantics(
        header: true,
        child: Text(text, style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
      ),
    );
  }
}

/// Ligne de résultat : icône dans une pastille grise, nom, précision.
class _SuggestionTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SuggestionTile({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: AppColors.muted, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: iconColor ?? AppColors.textPrimary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyLargeSemibold),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Choix d'un point précis : on déplace la carte sous l'épingle fixe,
/// l'adresse du point s'affiche, on valide.
class _MapPicker extends StatefulWidget {
  final String title;
  final GeoLocation? initial;
  final MapService mapService;
  final Future<GeoLocation?> Function() locate;
  final VoidCallback onBack;
  final ValueChanged<GeoLocation> onConfirm;

  const _MapPicker({
    required this.title,
    required this.initial,
    required this.mapService,
    required this.locate,
    required this.onBack,
    required this.onConfirm,
  });

  @override
  State<_MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<_MapPicker> {
  static const _dakar = ll.LatLng(14.6928, -17.4467);

  final _mapController = MapController();
  Timer? _debounce;
  GeoLocation? _point;
  bool _resolving = false;
  bool _locating = false;
  int _resolveId = 0;

  @override
  void initState() {
    super.initState();
    final start = widget.initial;
    if (start != null) {
      _point = start;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolve(_dakar));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onMoved(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _debounce?.cancel();
    setState(() => _resolving = true);
    _debounce = Timer(const Duration(milliseconds: 500), () => _resolve(camera.center));
  }

  Future<void> _resolve(ll.LatLng center) async {
    final id = ++_resolveId;
    setState(() => _resolving = true);
    GeoLocation place;
    try {
      place = await widget.mapService.reverseGeocode(center.latitude, center.longitude).timeout(const Duration(seconds: 8));
    } catch (_) {
      place = GeoLocation(lat: center.latitude, lng: center.longitude, address: 'Point choisi sur la carte');
    }
    if (!mounted || id != _resolveId) return;
    setState(() {
      _point = place;
      _resolving = false;
    });
  }

  Future<void> _goToMyPosition() async {
    setState(() => _locating = true);
    final here = await widget.locate();
    if (!mounted) return;
    setState(() => _locating = false);
    if (here == null) return;
    _resolveId++;
    setState(() {
      _point = here;
      _resolving = false;
    });
    _mapController.move(ll.LatLng(here.lat, here.lng), 16);
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.initial != null ? ll.LatLng(widget.initial!.lat, widget.initial!.lng) : _dakar;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: start,
                  initialZoom: widget.initial != null ? 16 : 12,
                  onPositionChanged: _onMoved,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'sn.fojem.app',
                  ),
                ],
              ),
            ),
            // Épingle fixe : sa pointe marque le centre de la carte.
            IgnorePointer(
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -22),
                  child: const Icon(Icons.location_on_rounded, size: 48, color: AppColors.brand),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GlassIconButton(icon: Icons.arrow_back_rounded, onPressed: widget.onBack, tooltip: 'Retour'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: AppColors.floatingShadow,
                        ),
                        child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodySemibold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                decoration: AppColors.modalDecoration,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Déplacez la carte pour placer l’épingle',
                                style: AppTextStyles.caption,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _locating ? null : _goToMyPosition,
                              icon: _locating
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.my_location_rounded, size: 18),
                              label: const Text('Ma position'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _resolving || _point == null ? 'Recherche de l’adresse…' : _point!.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyLargeSemibold,
                        ),
                        const SizedBox(height: 16),
                        GlowButton(
                          label: 'Valider ce point',
                          onPressed: _resolving || _point == null ? null : () => widget.onConfirm(_point!),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
