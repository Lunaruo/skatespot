import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../services/spot_service.dart';
import '../spots/create_spot_screen.dart';
import 'spot_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.onSessionExpired,
    required this.onLogout,
  });

  final Future<void> Function() onSessionExpired;
  final Future<void> Function() onLogout;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const LatLng _initialCenter = LatLng(50.6292, 3.0573);

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchTimer;
  Timer? _mapTimer;
  List<Map<String, dynamic>> _rideMyParkEntries = [];
  List<Spot> _nativeSpots = [];
  List<Map<String, dynamic>> _searchResults = [];

  LatLng? _userPosition;
  bool _isLoadingRideMyPark = true;
  bool _isLoadingNative = true;
  bool _isSearching = false;
  bool _showSearchResults = false;
  bool _isLocating = false;
  bool _isSelectingLocation = false;
  bool _isOpeningCreateScreen = false;
  bool _isLoggingOut = false;

  String? _rideMyParkError;
  String? _nativeError;
  String? _searchError;

  int _searchRequestId = 0;
  int _mapRequestId = 0;
  int _nativeRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadRideMyPark();
    _loadNativeSpots();

    // La carte reste utilisable même si la permission est refusée.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _locateUser();
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _mapTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  double? _coordinate(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
  }

  bool _hasValidCoordinates(Map<String, dynamic> entry) {
    final lat = _coordinate(entry['latitude']);
    final lon = _coordinate(entry['longitude']);
    return lat != null &&
        lon != null &&
        lat.isFinite &&
        lon.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lon >= -180 &&
        lon <= 180;
  }

  bool _isNative(Map<String, dynamic> entry) => entry['_source'] == 'skatespot';

  String _name(Map<String, dynamic> entry) =>
      (entry['title'] ?? entry['name'] ?? 'Spot sans nom').toString();

  String _address(Map<String, dynamic> entry) =>
      (entry['formattedAddress'] ??
              entry['formatted_address'] ??
              entry['address'] ??
              'Adresse non renseignée')
          .toString();

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // Géolocalisation uniquement pendant l'utilisation de l'application.
  Future<void> _locateUser() async {
    if (_isLocating || !mounted) return;
    setState(() => _isLocating = true);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError(
          'La localisation est désactivée. Active-la dans les paramètres du téléphone.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError(
          'Localisation bloquée. Autorise SkateSpot dans les paramètres de l’application.',
        );
      }
      if (permission == LocationPermission.denied) {
        throw StateError(
          'Localisation refusée. Tu peux toujours parcourir la carte manuellement.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;

      final point = LatLng(position.latitude, position.longitude);
      setState(() => _userPosition = point);
      _mapController.move(point, 15);
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message.toString()
          : 'Position indisponible. Déplace la carte manuellement.';
      _message(message);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // Source externe : RideMyPark, limitée à la zone visible.
  Future<void> _loadRideMyPark({LatLngBounds? bounds, double zoom = 12}) async {
    if (!mounted) return;
    final requestId = ++_mapRequestId;
    setState(() {
      _isLoadingRideMyPark = true;
      _rideMyParkError = null;
    });

    try {
      final visibleBounds =
          bounds ??
          LatLngBounds(const LatLng(50.52, 2.90), const LatLng(50.74, 3.22));
      final bbox = [
        visibleBounds.west,
        visibleBounds.south,
        visibleBounds.east,
        visibleBounds.north,
      ].join(',');

      final uri = Uri.https(
        'api.ridemypark.com',
        '/wp-json/rmp/v2/explore/clusters',
        {
          'zoom': zoom.round().clamp(0, 22).toString(),
          'bbox': bbox,
          'type': 'spot',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Erreur RideMyPark (${response.statusCode}).');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['success'] != true ||
          decoded['data'] is! List) {
        throw const FormatException('Réponse RideMyPark invalide.');
      }

      final entries = (decoded['data'] as List)
          .whereType<Map>()
          .map(
            (item) => {
              ...Map<String, dynamic>.from(item),
              '_source': 'ridemypark',
            },
          )
          .where(_hasValidCoordinates)
          .toList();

      if (!mounted || requestId != _mapRequestId) return;
      setState(() {
        _rideMyParkEntries = entries;
        _isLoadingRideMyPark = false;
      });
    } catch (error) {
      if (!mounted || requestId != _mapRequestId) return;
      setState(() {
        _rideMyParkError = error.toString();
        _isLoadingRideMyPark = false;
      });
    }
  }

  // Base SkateSpot : uniquement les spots sans externalId.
  Future<void> _loadNativeSpots() async {
    if (!mounted) return;
    final requestId = ++_nativeRequestId;
    setState(() {
      _isLoadingNative = true;
      _nativeError = null;
    });
    try {
      final spots = await SpotService.fetchNativeSpots();
      if (!mounted || requestId != _nativeRequestId) return;
      setState(() {
        _nativeSpots = spots;
        _isLoadingNative = false;
      });
    } catch (error) {
      if (!mounted || requestId != _nativeRequestId) return;
      setState(() {
        _nativeError = error.toString();
        _isLoadingNative = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    final camera = _mapController.camera;
    await Future.wait([
      _loadRideMyPark(bounds: camera.visibleBounds, zoom: camera.zoom),
      _loadNativeSpots(),
    ]);
  }

  void _onMapEvent(MapEvent event) {
    if (event is! MapEventMoveEnd) return;
    _mapTimer?.cancel();
    _mapTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final camera = _mapController.camera;
      _loadRideMyPark(bounds: camera.visibleBounds, zoom: camera.zoom);
    });
  }

  // Recherche dans les deux sources, même règle anti-doublon.
  void _onSearchChanged(String text) {
    _searchTimer?.cancel();
    ++_searchRequestId;
    final query = text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _showSearchResults = false;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _showSearchResults = true;
      _searchResults = [];
      _searchError = null;
    });
    _searchTimer = Timer(
      const Duration(milliseconds: 450),
      () => _searchSpots(query),
    );
  }

  Future<List<Map<String, dynamic>>> _searchRideMyPark(String query) async {
    final uri = Uri.https('api.ridemypark.com', '/wp-json/rmp/v2/search', {
      'q': query,
      'limit': '8',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Recherche RideMyPark indisponible.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['success'] != true ||
        decoded['data'] is! List) {
      throw const FormatException('Résultats RideMyPark invalides.');
    }
    return (decoded['data'] as List)
        .whereType<Map>()
        .map(
          (item) => {
            ...Map<String, dynamic>.from(item),
            '_source': 'ridemypark',
          },
        )
        .where(
          (item) =>
              '${item['listing_type'] ?? ''}'.toLowerCase() == 'spot' &&
              _hasValidCoordinates(item),
        )
        .toList();
  }

  Future<void> _searchSpots(String query) async {
    if (query.trim().isEmpty || !mounted) return;
    final requestId = ++_searchRequestId;
    setState(() {
      _isSearching = true;
      _showSearchResults = true;
      _searchError = null;
    });

    List<Map<String, dynamic>> external = [];
    List<Spot> native = [];
    bool externalFailed = false;
    bool nativeFailed = false;

    await Future.wait<void>([
      () async {
        try {
          external = await _searchRideMyPark(query);
        } catch (_) {
          externalFailed = true;
        }
      }(),
      () async {
        try {
          native = await SpotService.searchNativeSpots(query);
        } catch (_) {
          nativeFailed = true;
        }
      }(),
    ]);

    if (!mounted || requestId != _searchRequestId) return;
    setState(() {
      _searchResults = [
        ...native.map((s) => {...s.toMap(), '_source': 'skatespot'}),
        ...external,
      ];
      _isSearching = false;
      _showSearchResults = true;
      _searchError = externalFailed && nativeFailed
          ? 'Les recherches RideMyPark et SkateSpot sont indisponibles.'
          : externalFailed
          ? 'RideMyPark est indisponible : résultats SkateSpot seulement.'
          : nativeFailed
          ? 'SkateSpot est indisponible : résultats RideMyPark seulement.'
          : null;
    });
  }

  void _selectSearchResult(Map<String, dynamic> entry) {
    final lat = _coordinate(entry['latitude']);
    final lon = _coordinate(entry['longitude']);
    if (lat == null || lon == null) return;
    _searchTimer?.cancel();
    ++_searchRequestId;
    FocusScope.of(context).unfocus();
    setState(() {
      _showSearchResults = false;
      _isSearching = false;
    });
    _mapController.move(LatLng(lat, lon), 16);
    _openSpot(entry);
  }

  // Même fiche pour RideMyPark et SkateSpot, sans confondre les identifiants.
  void _openSpot(Map<String, dynamic> entry) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => SpotDetailScreen(spot: entry)),
    );
  }

  void _onMarkerTap(Map<String, dynamic> entry) {
    if (entry['type'] == 'cluster') {
      final lat = _coordinate(entry['latitude']);
      final lon = _coordinate(entry['longitude']);
      if (lat == null || lon == null) return;
      _mapController.move(
        LatLng(lat, lon),
        (_mapController.camera.zoom + 2).clamp(0, 19).toDouble(),
      );
      return;
    }
    _openSpot(entry);
  }

  // Étape création : placer le viseur sur le futur spot.
  void _startSelectingLocation() {
    _searchTimer?.cancel();
    ++_searchRequestId;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSelectingLocation = true;
      _showSearchResults = false;
      _searchResults = [];
      _isSearching = false;
    });
  }

  Future<void> _confirmLocation() async {
    if (_isOpeningCreateScreen) return;
    final position = _mapController.camera.center;
    setState(() => _isOpeningCreateScreen = true);

    try {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => CreateSpotScreen(
            latitude: position.latitude,
            longitude: position.longitude,
            onSessionExpired: widget.onSessionExpired,
          ),
        ),
      );
      if (!mounted) return;
      setState(() => _isSelectingLocation = false);
      if (created == true) {
        await _loadNativeSpots();
        if (mounted) {
          _message('Nouveau spot disponible sur la carte !');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningCreateScreen = false);
      }
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    try {
      await widget.onLogout();
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    for (final entry in _rideMyParkEntries) {
      final cluster = entry['type'] == 'cluster';
      markers.add(
        Marker(
          point: LatLng(
            _coordinate(entry['latitude'])!,
            _coordinate(entry['longitude'])!,
          ),
          width: cluster ? 54 : 44,
          height: cluster ? 54 : 44,
          child: GestureDetector(
            onTap: _isSelectingLocation ? null : () => _onMarkerTap(entry),
            child: Container(
              decoration: BoxDecoration(
                color: cluster ? Colors.deepPurple : Colors.teal,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 5),
                ],
              ),
              alignment: Alignment.center,
              child: cluster
                  ? Text(
                      '${entry['count'] ?? 0}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : const Icon(Icons.location_on, color: Colors.white),
            ),
          ),
        ),
      );
    }

    for (final spot in _nativeSpots) {
      if (!spot.hasValidCoordinates) continue;
      markers.add(
        Marker(
          point: LatLng(spot.latitude!, spot.longitude!),
          width: 46,
          height: 46,
          child: GestureDetector(
            onTap: _isSelectingLocation
                ? null
                : () => _openSpot({...spot.toMap(), '_source': 'skatespot'}),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.deepOrange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 5),
                ],
              ),
              child: const Icon(Icons.skateboarding, color: Colors.white),
            ),
          ),
        ),
      );
    }

    if (_userPosition != null) {
      markers.add(
        Marker(
          point: _userPosition!,
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4),
              ],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildSearchBar() {
    return Material(
      elevation: 5,
      borderRadius: BorderRadius.circular(14),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          _onSearchChanged(value);
          setState(() {});
        },
        onSubmitted: (value) {
          _searchTimer?.cancel();
          ++_searchRequestId;
          if (value.trim().isNotEmpty) _searchSpots(value.trim());
        },
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Rechercher un spot, une ville...',
          prefixIcon: const Icon(Icons.search, color: Colors.teal),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Effacer',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: _isSearching
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 14),
                    Text('Recherche en cours...'),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchError != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _searchError!,
                        style: const TextStyle(color: Colors.deepOrange),
                      ),
                    ),
                  if (_searchResults.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Aucun spot trouvé.'),
                    ),
                  if (_searchResults.isNotEmpty)
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = _searchResults[index];
                          final native = _isNative(entry);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: native
                                  ? Colors.deepOrange
                                  : Colors.teal,
                              child: Icon(
                                native
                                    ? Icons.skateboarding
                                    : Icons.location_on,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              _name(entry),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _address(entry),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  native ? 'SkateSpot' : 'RideMyPark',
                                  style: TextStyle(
                                    color: native
                                        ? Colors.deepOrange
                                        : Colors.teal,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _selectSearchResult(entry),
                          );
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SkateSpot'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Ma position',
            onPressed: _isLocating ? null : _locateUser,
            icon: _isLocating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: _isLoggingOut ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 12,
              minZoom: 3,
              maxZoom: 19,
              onMapEvent: _onMapEvent,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.skatespot.app',
              ),
              MarkerLayer(markers: _buildMarkers()),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    '© OpenStreetMap contributors',
                    onTap: () {},
                  ),
                  TextSourceAttribution(
                    'Données de spots : RideMyPark',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          if (!_isSelectingLocation) ...[
            Positioned(top: 12, left: 12, right: 12, child: _buildSearchBar()),
            if (_showSearchResults)
              Positioned(
                top: 76,
                left: 12,
                right: 12,
                child: _buildSearchResults(),
              ),
            if ((_rideMyParkError != null || _nativeError != null) &&
                !_showSearchResults)
              Positioned(
                top: 80,
                left: 12,
                right: 12,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_rideMyParkError != null)
                          const Text('RideMyPark est indisponible.'),
                        if (_nativeError != null)
                          const Text(
                            'Impossible de charger les spots SkateSpot.',
                          ),
                        TextButton(
                          onPressed: _refreshAll,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 14,
              left: 12,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on, color: Colors.teal, size: 18),
                          SizedBox(width: 6),
                          Text('RideMyPark'),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.skateboarding,
                            color: Colors.deepOrange,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text('SkateSpot'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              right: 16,
              child: FloatingActionButton.extended(
                heroTag: 'startSpotCreation',
                tooltip: 'Ajouter un nouveau spot',
                onPressed: _startSelectingLocation,
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Ajouter un spot'),
              ),
            ),
          ] else ...[
            // Le viseur reste fixe pendant que la carte se déplace dessous.
            const Center(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 42),
                  child: Icon(
                    Icons.location_pin,
                    color: Colors.deepOrange,
                    size: 52,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Déplace la carte pour placer le repère sur le spot. '
                    'Puis confirme son emplacement.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 22,
              left: 16,
              right: 16,
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isOpeningCreateScreen
                            ? null
                            : () =>
                                  setState(() => _isSelectingLocation = false),
                        icon: const Icon(Icons.close),
                        label: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _isOpeningCreateScreen
                            ? null
                            : _confirmLocation,
                        icon: const Icon(Icons.check),
                        label: const Text('Confirmer la position'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_isLoadingRideMyPark || _isLoadingNative)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
