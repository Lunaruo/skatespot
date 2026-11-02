import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class Spot {
  final String id;
  final String name;
  final String? address;
  final String? description;
  final double? latitude;
  final double? longitude;

  final String? externalId;
  final String? externalSource;

  const Spot({
    required this.id,
    required this.name,
    this.address,
    this.description,
    this.latitude,
    this.longitude,
    this.externalId,
    this.externalSource,
  });

  factory Spot.fromJson(Map<String, dynamic> json) {
    return Spot(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Spot sans nom',
      address: json['address']?.toString(),
      description: json['description']?.toString(),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      externalId: _optionalString(json['externalId']),
      externalSource: _optionalString(json['externalSource']),
    );
  }

  static String? _optionalString(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();

    return text.isEmpty ? null : text;
  }

  static double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.'));
    }

    return null;
  }

  /// Un spot natif SkateSpot ne possède pas
  /// d'identifiant externe RideMyPark.
  bool get isNativeSpot => externalId == null;

  /// Vérifie que le spot possède une position valide.
  bool get hasValidCoordinates {
    final lat = latitude;
    final lng = longitude;

    if (lat == null || lng == null) return false;

    return lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  /// Prépare les informations pour les écrans Flutter.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'title': name,
      'address': address,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'externalId': externalId,
      'externalSource': externalSource,
      'isNativeSpot': isNativeSpot,
    };
  }

  /// Recherche textuelle dans les informations du spot.
  bool matchesQuery(String query) {
    final normalizedQuery = query.trim().toLowerCase();

    if (normalizedQuery.isEmpty) return true;

    final searchableText = [
      name,
      address ?? '',
      description ?? '',
    ].join(' ').toLowerCase();

    return searchableText.contains(normalizedQuery);
  }
}

class SessionExpiredException implements Exception {
  final String message;

  const SessionExpiredException(this.message);

  @override
  String toString() => message;
}

class SpotService {
  static const String baseUrl = 'http://10.0.2.2:3001';

  static const Duration _requestTimeout = Duration(seconds: 10);

  static const String _sessionExpiredMessage =
      'Votre session a expiré. Veuillez vous reconnecter.';

  /// Récupère tous les spots présents dans PostgreSQL.
  static Future<List<Spot>> fetchSpots() async {
    final uri = Uri.parse('$baseUrl/api/spots');

    final response = await http.get(uri).timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception('Erreur API : code ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic> || decoded['spots'] is! List) {
      throw Exception('Format de réponse des spots invalide.');
    }

    final spotsJson = decoded['spots'] as List;

    return spotsJson
        .whereType<Map>()
        .map((spot) => Spot.fromJson(Map<String, dynamic>.from(spot)))
        .toList();
  }

  /// Récupère uniquement les spots natifs SkateSpot.
  ///
  /// Les spots importés depuis RideMyPark sont exclus
  /// pour éviter de les afficher deux fois sur la carte.
  static Future<List<Spot>> fetchNativeSpots() async {
    final spots = await fetchSpots();

    return spots
        .where((spot) => spot.isNativeSpot && spot.hasValidCoordinates)
        .toList();
  }

  /// Recherche parmi les spots créés directement
  /// dans SkateSpot.
  ///
  /// La recherche RideMyPark sera fusionnée avec
  /// ces résultats dans MapScreen.
  static Future<List<Spot>> searchNativeSpots(String query) async {
    final normalizedQuery = query.trim();

    if (normalizedQuery.isEmpty) {
      return [];
    }

    final spots = await fetchNativeSpots();

    return spots.where((spot) => spot.matchesQuery(normalizedQuery)).toList();
  }

  /// Prépare les en-têtes d'une requête protégée.
  static Future<Map<String, String>> authenticatedHeaders() async {
    final token = await AuthService.getToken();

    if (token == null || token.isEmpty) {
      throw const SessionExpiredException(_sessionExpiredMessage);
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Crée un spot avec renouvellement éventuel du JWT.
  static Future<Spot> createSpot({
    required String name,
    required double latitude,
    required double longitude,
    String? address,
    String? description,
  }) async {
    if (name.trim().isEmpty) {
      throw Exception('Le nom du spot est obligatoire.');
    }

    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw Exception('Les coordonnées GPS sont invalides.');
    }

    final uri = Uri.parse('$baseUrl/api/spots');

    final body = jsonEncode({
      'name': name.trim(),
      'latitude': latitude,
      'longitude': longitude,
      if (address != null && address.trim().isNotEmpty)
        'address': address.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });

    var headers = await authenticatedHeaders();

    var response = await _sendCreateRequest(
      uri: uri,
      headers: headers,
      body: body,
    );

    if (response.statusCode == 401) {
      final newToken = await AuthService.refreshAccessToken();

      if (newToken == null || newToken.isEmpty) {
        final remainingToken = await AuthService.getToken();

        if (remainingToken == null || remainingToken.isEmpty) {
          throw const SessionExpiredException(_sessionExpiredMessage);
        }

        throw Exception(
          'Impossible de renouveler votre session '
          'pour le moment. Vérifiez votre connexion '
          'et réessayez.',
        );
      }

      headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $newToken',
      };

      response = await _sendCreateRequest(
        uri: uri,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 401) {
        await AuthService.logout();

        throw const SessionExpiredException(_sessionExpiredMessage);
      }
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_readError(response));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    final spotData = data['spot'] ?? data;

    if (spotData is! Map<String, dynamic> || spotData['id'] == null) {
      throw Exception('Le serveur n’a pas retourné le spot créé.');
    }

    return Spot.fromJson(spotData);
  }

  static Future<http.Response> _sendCreateRequest({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    return http
        .post(uri, headers: headers, body: body)
        .timeout(_requestTimeout);
  }

  static String _readError(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final message = data['message'] ?? data['error'];

      if (message != null) {
        return message.toString();
      }
    } catch (_) {
      // Réponse non JSON.
    }

    return 'Erreur serveur (${response.statusCode}).';
  }
}
