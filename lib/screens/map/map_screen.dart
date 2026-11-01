
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'spot_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const LatLng _initialCenter = LatLng(50.6292, 3.0573);

  final MapController _mapController = MapController();
  final TextEditingController _searchController =
  TextEditingController();

  Timer? _searchTimer;

  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _searchResults = [];

  bool _isLoading = true;
  bool _isSearching = false;
  bool _showSearchResults = false;

  String? _error;
  String? _searchError;

  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // --------------------------------------------------
  // CHARGEMENT DES SPOTS SUR LA CARTE
  // --------------------------------------------------

  Future<void> _loadSpots({
    LatLngBounds? bounds,
    double zoom = 12,
  }) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final visibleBounds = bounds ??
          LatLngBounds(
            const LatLng(50.52, 2.90),
            const LatLng(50.74, 3.22),
          );

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

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception(
          'RideMyPark a répondu avec le code ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic> ||
          decoded['success'] != true) {
        throw Exception('Réponse RideMyPark invalide.');
      }

      final data = decoded['data'];

      if (data is! List) {
        throw Exception('Format des spots inattendu.');
      }

      final entries = data
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .where((entry) {
        final latitude =
        double.tryParse('${entry['latitude'] ?? ''}');

        final longitude =
        double.tryParse('${entry['longitude'] ?? ''}');

        return latitude != null &&
            longitude != null &&
            latitude >= -90 &&
            latitude <= 90 &&
            longitude >= -180 &&
            longitude <= 180;
      }).toList();

      if (!mounted) return;

      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  // --------------------------------------------------
  // RECHERCHE RIDEMYPARK
  // --------------------------------------------------

  void _onSearchChanged(String query) {
    _searchTimer?.cancel();

    final value = query.trim();

    if (value.isEmpty) {
      _searchRequestId++;

      setState(() {
        _searchResults = [];
        _isSearching = false;
        _showSearchResults = false;
        _searchError = null;
      });

      return;
    }

    setState(() {
      _showSearchResults = true;
      _searchError = null;
    });

    // Attendre que l'utilisateur termine sa saisie.
    _searchTimer = Timer(
      const Duration(milliseconds: 450),
          () => _searchSpots(value),
    );
  }

  Future<void> _searchSpots(String query) async {
    if (!mounted || query.trim().isEmpty) return;

    final requestId = ++_searchRequestId;

    setState(() {
      _isSearching = true;
      _showSearchResults = true;
      _searchError = null;
    });

    try {
      final uri = Uri.https(
        'api.ridemypark.com',
        '/wp-json/rmp/v2/search',
        {
          'q': query.trim(),
          'limit': '8',
        },
      );

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception(
          'Erreur de recherche (${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic> ||
          decoded['success'] != true) {
        throw Exception('Réponse de recherche invalide.');
      }

      final data = decoded['data'];

      if (data is! List) {
        throw Exception('Format des résultats inattendu.');
      }

      final results = data
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .where((entry) {
        final type =
        '${entry['listing_type'] ?? ''}'.toLowerCase();

        final latitude =
        double.tryParse('${entry['latitude'] ?? ''}');

        final longitude =
        double.tryParse('${entry['longitude'] ?? ''}');

        return type == 'spot' &&
            latitude != null &&
            longitude != null &&
            latitude >= -90 &&
            latitude <= 90 &&
            longitude >= -180 &&
            longitude <= 180;
      }).toList();

      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _searchResults = results;
        _isSearching = false;
        _showSearchResults = true;
      });
    } catch (error) {
      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _searchResults = [];
        _isSearching = false;
        _searchError = error.toString();
        _showSearchResults = true;
      });
    }
  }

  // --------------------------------------------------
  // SÉLECTION D'UN RÉSULTAT
  // --------------------------------------------------

  void _selectSearchResult(Map<String, dynamic> entry) {
    final latitude =
    double.tryParse('${entry['latitude'] ?? ''}');

    final longitude =
    double.tryParse('${entry['longitude'] ?? ''}');

    if (latitude == null || longitude == null) return;

    _searchTimer?.cancel();

    FocusScope.of(context).unfocus();

    setState(() {
      _showSearchResults = false;
      _isSearching = false;
    });

    // Centrer la carte sur le spot.
    _mapController.move(
      LatLng(latitude, longitude),
      16,
    );

    // Ouvrir directement la fiche RideMyPark.
    _openSpot(entry);
  }

  void _openSpot(Map<String, dynamic> entry) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => SpotDetailScreen(
          spot: entry,
        ),
      ),
    );
  }

  // --------------------------------------------------
  // GESTION DES MARQUEURS
  // --------------------------------------------------

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd) {
      final camera = _mapController.camera;

      _loadSpots(
        bounds: camera.visibleBounds,
        zoom: camera.zoom,
      );
    }
  }

  void _onMarkerTap(Map<String, dynamic> entry) {
    // Les marqueurs violets représentent plusieurs spots.
    if (entry['type'] == 'cluster') {
      final latitude =
      double.tryParse('${entry['latitude'] ?? ''}');

      final longitude =
      double.tryParse('${entry['longitude'] ?? ''}');

      if (latitude == null || longitude == null) return;

      _mapController.move(
        LatLng(latitude, longitude),
        (_mapController.camera.zoom + 2)
            .clamp(0, 22)
            .toDouble(),
      );

      return;
    }

    // Un marqueur individuel ouvre la fiche détaillée.
    _openSpot(entry);
  }

  // --------------------------------------------------
  // BARRE DE RECHERCHE
  // --------------------------------------------------

  Widget _buildSearchBar() {
    return Material(
      elevation: 5,
      borderRadius: BorderRadius.circular(14),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        onSubmitted: (value) {
          _searchTimer?.cancel();
          _searchSpots(value.trim());
        },
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Rechercher un skatepark, une ville...',
          prefixIcon: const Icon(
            Icons.search,
            color: Colors.teal,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            tooltip: 'Effacer',
            icon: const Icon(Icons.close),
            onPressed: () {
              _searchController.clear();
              _onSearchChanged('');
            },
          )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // RÉSULTATS DE RECHERCHE
  // --------------------------------------------------

  Widget _buildSearchResults() {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: 340,
        ),
        child: _isSearching
            ? const Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
              SizedBox(width: 14),
              Text('Recherche en cours...'),
            ],
          ),
        )
            : _searchError != null
            ? Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Impossible de rechercher les spots.\n'
                '$_searchError',
            style: const TextStyle(
              color: Colors.red,
            ),
          ),
        )
            : _searchResults.isEmpty
            ? const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Aucun skatepark trouvé.',
            textAlign: TextAlign.center,
          ),
        )
            : ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _searchResults.length,
          separatorBuilder: (_, _) =>
          const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = _searchResults[index];

            final name =
                entry['title']?.toString() ??
                    'Spot sans nom';

            final address =
                entry['formattedAddress']
                    ?.toString() ??
                    'Adresse non renseignée';

            return ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.teal,
                child: Icon(
                  Icons.location_on,
                  color: Colors.white,
                ),
              ),
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(
                Icons.chevron_right,
              ),
              onTap: () {
                _selectSearchResult(entry);
              },
            );
          },
        ),
      ),
    );
  }

  // --------------------------------------------------
  // AFFICHAGE PRINCIPAL
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final markers = _entries.map((entry) {
      final latitude =
      double.parse('${entry['latitude']}');

      final longitude =
      double.parse('${entry['longitude']}');

      final isCluster = entry['type'] == 'cluster';

      return Marker(
        point: LatLng(latitude, longitude),
        width: isCluster ? 54 : 44,
        height: isCluster ? 54 : 44,
        child: GestureDetector(
          onTap: () => _onMarkerTap(entry),
          child: Container(
            decoration: BoxDecoration(
              color: isCluster
                  ? Colors.deepPurple
                  : Colors.teal,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 5,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: isCluster
                ? Text(
              '${entry['count'] ?? 0}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            )
                : const Icon(
              Icons.location_on,
              color: Colors.white,
            ),
          ),
        ),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte des spots'),
        actions: [
          IconButton(
            tooltip: 'Recentrer sur Lille',
            onPressed: () {
              _mapController.move(_initialCenter, 12);
              _loadSpots();
            },
            icon: const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () {
              final camera = _mapController.camera;

              _loadSpots(
                bounds: camera.visibleBounds,
                zoom: camera.zoom,
              );
            },
            icon: const Icon(Icons.refresh),
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
                urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.skatespot.app',
              ),
              MarkerLayer(markers: markers),
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

          // Barre de recherche.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _buildSearchBar(),
          ),

          // Résultats de recherche.
          if (_showSearchResults)
            Positioned(
              top: 76,
              left: 12,
              right: 12,
              child: _buildSearchResults(),
            ),

          // Indicateur de chargement de la carte.
          if (_isLoading)
            const Positioned(
              top: 68,
              left: 12,
              right: 12,
              child: LinearProgressIndicator(),
            ),

          // Erreur de chargement de la carte.
          if (_error != null)
            Positioned(
              top: 76,
              left: 12,
              right: 12,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        'Impossible de charger les spots.\n$_error',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      TextButton(
                        onPressed: () {
                          final camera = _mapController.camera;

                          _loadSpots(
                            bounds: camera.visibleBounds,
                            zoom: camera.zoom,
                          );
                        },
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
