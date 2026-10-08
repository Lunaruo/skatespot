import 'package:flutter/material.dart';

import 'screens/home/home_screen.dart';

void main() {
  runApp(const SkateSpotApp());
}

class SkateSpotApp extends StatelessWidget {
  const SkateSpotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SkateSpot',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
