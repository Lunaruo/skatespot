import 'package:flutter/material.dart';
import '../map/map_screen.dart';

import '../../services/spot_service.dart';
import '../spots/create_spot_screen.dart';

class HomeScreen extends StatefulWidget {
  final Future<void> Function() onLogout;

  const HomeScreen({
    super.key,
    required this.onLogout,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Spot>> _spotsFuture;

  bool _isLoggingOut = false;
  bool _isOpeningCreateScreen = false;

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  void _loadSpots() {
    _spotsFuture = SpotService.fetchSpots();
  }

  void _retry() {
    setState(_loadSpots);
  }

  Future<void> _openCreateSpot() async {
    if (_isOpeningCreateScreen) return;

    setState(() => _isOpeningCreateScreen = true);

    try {
      final created = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => CreateSpotScreen(
            onSessionExpired: widget.onLogout,
          ),
        ),
      );

      if (!mounted) return;

      if (created == true) {
        setState(_loadSpots);
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
      if (mounted) {
        setState(() => _isLoggingOut = false);
      }
    }
  }

  Future<void> _refreshSpots() async {
    setState(_loadSpots);

    try {
      await _spotsFuture;
    } catch (_) {
      // Le FutureBuilder affiche l'erreur et permet de réessayer.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SkateSpot'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Afficher la carte',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MapScreen(),
                ),
              );
            },
            icon: const Icon(Icons.map_outlined),
          ),
          IconButton(
            tooltip: 'Créer un spot',
            onPressed: _isOpeningCreateScreen
                ? null
                : _openCreateSpot,
            icon: const Icon(Icons.add_location_alt),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: _isLoggingOut ? null : _logout,
            icon: _isLoggingOut
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder<List<Spot>>(
        future: _spotsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Impossible de charger les spots.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _retry,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }

          final spots = snapshot.data ?? [];

          if (spots.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshSpots,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 200),
                  Center(
                    child: Text(
                      'Aucun spot disponible pour le moment.',
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshSpots,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: spots.length,
              itemBuilder: (context, index) {
                final spot = spots[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spot.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge,
                        ),
                        if (spot.address != null &&
                            spot.address!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(spot.address!),
                              ),
                            ],
                          ),
                        ],
                        if (spot.description != null &&
                            spot.description!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(spot.description!),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}