
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

  const Spot({
    required this.id,
    required this.name,
    this.address,
    this.description,
    this.latitude,
    this.longitude,
  });

  factory Spot.fromJson(Map<String, dynamic> json) {
    return Spot(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Spot sans nom',
      address: json['address']?.toString(),
      description: json['description']?.toString(),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
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

  /// Récupère la liste publique des spots.
  static Future<List<Spot>> fetchSpots() async {
    final uri = Uri.parse('$baseUrl/api/spots');

    final response = await http
        .get(uri)
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Erreur API : code ${response.statusCode}',
      );
    }

    final data =
        jsonDecode(response.body) as Map<String, dynamic>;

    final spotsJson = data['spots'] as List<dynamic>;

    return spotsJson
        .map(
          (spot) => Spot.fromJson(
            spot as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  /// Prépare les en-têtes d'une requête protégée.
  static Future<Map<String, String>> authenticatedHeaders() async {
    final token = await AuthService.getToken();

    if (token == null || token.isEmpty) {
      throw const SessionExpiredException(
        _sessionExpiredMessage,
      );
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Crée un spot et renouvelle automatiquement la session
  /// si le serveur refuse le jeton d'accès.
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

    // Première tentative avec le jeton actuellement enregistré.
    var headers = await authenticatedHeaders();

    var response = await _sendCreateRequest(
      uri: uri,
      headers: headers,
      body: body,
    );

    // Si le serveur refuse le jeton, tenter un renouvellement.
    if (response.statusCode == 401) {
      final newToken = await AuthService.refreshAccessToken();

      if (newToken == null || newToken.isEmpty) {
        // Si les jetons ont été supprimés, le serveur a refusé
        // le renouvellement : la session n'est plus valide.
        final remainingToken = await AuthService.getToken();

        if (remainingToken == null || remainingToken.isEmpty) {
          throw const SessionExpiredException(
            _sessionExpiredMessage,
          );
        }

        // Le jeton est toujours conservé : il peut s'agir
        // d'un problème réseau ou serveur. Ne pas déconnecter
        // l'utilisateur sur cette seule base.
        throw Exception(
          'Impossible de renouveler votre session pour le moment. '
          'Vérifiez votre connexion et réessayez.',
        );
      }

      // Réessayer exactement une fois avec le nouveau jeton.
      headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $newToken',
      };

      response = await _sendCreateRequest(
        uri: uri,
        headers: headers,
        body: body,
      );

      // Le serveur refuse encore le jeton : ne pas boucler.
      if (response.statusCode == 401) {
        await AuthService.logout();

        throw const SessionExpiredException(
          _sessionExpiredMessage,
        );
      }
    }

    if (response.statusCode != 200 &&
        response.statusCode != 201) {
      throw Exception(_readError(response));
    }

    final data =
        jsonDecode(response.body) as Map<String, dynamic>;

    final spotData = data['spot'] ?? data;

    if (spotData is! Map<String, dynamic> ||
        spotData['id'] == null) {
      throw Exception(
        'Le serveur n’a pas retourné le spot créé.',
      );
    }

    return Spot.fromJson(spotData);
  }

  /// Effectue une tentative de création.
  static Future<http.Response> _sendCreateRequest({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    return http
        .post(
          uri,
          headers: headers,
          body: body,
        )
        .timeout(_requestTimeout);
  }

  static String _readError(http.Response response) {
    try {
      final data =
          jsonDecode(response.body) as Map<String, dynamic>;

      final message = data['message'] ?? data['error'];

      if (message != null) {
        return message.toString();
      }
    } catch (_) {
      // La réponse n'est pas du JSON exploitable.
    }

    return 'Erreur serveur (${response.statusCode}).';
  }
}
