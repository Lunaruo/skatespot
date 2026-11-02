import 'package:flutter/material.dart';

import '../map/map_screen.dart';

/// L'accueil de SkateSpot est désormais la carte interactive.
/// Le callback de déconnexion continue d'être géré par AuthGate.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return MapScreen(onSessionExpired: onLogout, onLogout: onLogout);
  }
}
