
import 'dart:convert';

import 'package:http/http.dart' as http;

class Spot {
  final String id;
  final String name;
  final String? address;
  final String? description;

  const Spot({
    required this.id,
    required this.name,
    this.address,
    this.description,
  });

  factory Spot.fromJson(Map<String, dynamic> json) {
    return Spot(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Spot sans nom',
      address: json['address']?.toString(),
      description: json['description']?.toString(),
    );
  }
}

class SpotService {
  // Adresse du PC hôte depuis un émulateur Android.
  static const String baseUrl = 'http://10.0.2.2:3001';

  static Future<List<Spot>> fetchSpots() async {
    final uri = Uri.parse('$baseUrl/api/spots');

    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
        'Erreur API : code ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body)
        as Map<String, dynamic>;

    final spotsJson = data['spots'] as List<dynamic>;

    return spotsJson
        .map(
          (spot) => Spot.fromJson(
            spot as Map<String, dynamic>,
          ),
        )
        .toList();
  }
}
