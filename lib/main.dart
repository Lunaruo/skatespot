
import 'package:flutter/material.dart';

import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SkateSpotApp());
}

class SkateSpotApp extends StatelessWidget {
  const SkateSpotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SkateSpot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<bool> _authenticationFuture;

  @override
  void initState() {
    super.initState();
    _authenticationFuture = _checkAuthentication();
  }

  Future<bool> _checkAuthentication() async {
  return AuthService.hasValidSession();
}

  void _onLoginSuccess() {
    setState(() {
      _authenticationFuture = Future<bool>.value(true);
    });
  }

  Future<void> _logout() async {
    await AuthService.logout();

    if (!mounted) return;

    setState(() {
      _authenticationFuture = Future<bool>.value(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _authenticationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Impossible de vérifier la connexion.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _authenticationFuture =
                              _checkAuthentication();
                        });
                      },
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.data == true) {
          return HomeScreen(onLogout: _logout);
        }

        return LoginScreen(
          onLoginSuccess: _onLoginSuccess,
        );
      },
    );
  }
}
