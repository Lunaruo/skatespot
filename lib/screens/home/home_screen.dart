
import 'package:flutter/material.dart';

import '../../services/spot_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Spot>> _spotsFuture;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SkateSpot'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Spot>>(
        future: _spotsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
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
                    const Icon(
                      Icons.wifi_off,
                      size: 48,
                    ),
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
            return const Center(
              child: Text(
                'Aucun spot disponible pour le moment.',
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              _retry();
              await _spotsFuture;
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: spots.length,
              itemBuilder: (context, index) {
                final spot = spots[index];

                return Card(
                  margin: const EdgeInsets.only(
                    bottom: 12,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
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
