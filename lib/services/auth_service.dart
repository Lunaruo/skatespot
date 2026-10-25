
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthService {
  static const String baseUrl = 'http://10.0.2.2:3001';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _tokenKey = 'skatespot_jwt';
  static const String _refreshTokenKey = 'skatespot_refresh_token';

  static const Duration _requestTimeout = Duration(seconds: 10);

  // Retourne le jeton d'accès enregistré.
  static Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  // Vérifie si le jeton d'accès est encore valide.
  static bool _isAccessTokenValid(String token) {
    try {
      final parts = token.split('.');

      if (parts.length != 3) {
        return false;
      }

      final payloadBytes = base64Url.decode(
        base64Url.normalize(parts[1]),
      );

      final payload =
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;

      final expiration = payload['exp'];

      if (expiration is! num) {
        return false;
      }

      final expirationDate = DateTime.fromMillisecondsSinceEpoch(
        expiration.toInt() * 1000,
      );

      return expirationDate.isAfter(
        DateTime.now().add(const Duration(seconds: 30)),
      );
    } catch (_) {
      return false;
    }
  }

  // Vérifie la session et renouvelle le jeton d'accès si nécessaire.
  static Future<bool> hasValidSession() async {
    final token = await getToken();

    if (token != null && _isAccessTokenValid(token)) {
      return true;
    }

    // Le jeton d'accès est absent ou expiré :
    // essayer de renouveler la session.
    final newToken = await refreshAccessToken();

    return newToken != null;
  }

  // Inscrit un nouvel utilisateur.
  static Future<void> register({
    required String email,
    required String password,
    String? username,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/register'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
            if (username != null && username.trim().isNotEmpty)
              'username': username.trim(),
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(_readError(response));
    }
  }

  // Connecte l'utilisateur et conserve les deux jetons.
  static Future<void> login({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/auth/login'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode != 200) {
      throw Exception(_readError(response));
    }

    final data =
        jsonDecode(response.body) as Map<String, dynamic>;

    final token = data['token']?.toString();
    final refreshToken = data['refreshToken']?.toString();

    if (token == null ||
        token.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      throw Exception(
        'Le serveur n’a pas retourné les deux jetons de connexion.',
      );
    }

    // Enregistrer le jeton de renouvellement en premier.
    await _storage.write(
      key: _refreshTokenKey,
      value: refreshToken,
    );

    await _storage.write(
      key: _tokenKey,
      value: token,
    );
  }

  // Demande au serveur une nouvelle paire de jetons.
  // Retourne le nouveau jeton d'accès, ou null en cas d'échec.
  static Future<String?> refreshAccessToken() async {
    final refreshToken = await _storage.read(
      key: _refreshTokenKey,
    );

    if (refreshToken == null || refreshToken.isEmpty) {
      await _clearLocalTokens();
      return null;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'refreshToken': refreshToken,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        // Une erreur d'authentification signifie que la session
        // de renouvellement n'est plus utilisable.
        if (response.statusCode == 401) {
          await _clearLocalTokens();
        }

        // En cas d'erreur réseau ou serveur, conserver le jeton
        // de renouvellement pour permettre une nouvelle tentative.
        return null;
      }

      final data =
          jsonDecode(response.body) as Map<String, dynamic>;

      final newToken = data['token']?.toString();
      final newRefreshToken = data['refreshToken']?.toString();

      if (newToken == null ||
          newToken.isEmpty ||
          newRefreshToken == null ||
          newRefreshToken.isEmpty) {
        return null;
      }

      // Enregistrer le nouveau jeton de renouvellement avant
      // de remplacer le jeton d'accès.
      await _storage.write(
        key: _refreshTokenKey,
        value: newRefreshToken,
      );

      await _storage.write(
        key: _tokenKey,
        value: newToken,
      );

      return newToken;
    } catch (_) {
      // Ne pas déconnecter l'utilisateur en cas de panne réseau.
      return null;
    }
  }

  // Déconnexion locale et révocation de la session sur le serveur.
  static Future<void> logout() async {
    final refreshToken = await _storage.read(
      key: _refreshTokenKey,
    );

    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await http
            .post(
              Uri.parse('$baseUrl/api/auth/logout'),
              headers: {
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'refreshToken': refreshToken,
              }),
            )
            .timeout(_requestTimeout);
      }
    } catch (_) {
      // La suppression locale doit fonctionner même si le serveur
      // est inaccessible.
    } finally {
      await _clearLocalTokens();
    }
  }

  // Supprime les deux jetons de l'appareil.
  static Future<void> _clearLocalTokens() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
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
