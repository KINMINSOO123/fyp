import 'dart:async';

import 'package:flutter/material.dart';

import '../../home/presentation/home_screen.dart';
import '../application/session_controller.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final SessionController _sessionController;

  @override
  void initState() {
    super.initState();

    _sessionController = SessionController();
    unawaited(_sessionController.initialize());
  }

  @override
  void dispose() {
    _sessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _sessionController,
      builder: (context, _) {
        final status = _sessionController.status;
        final profile = _sessionController.profile;

        if (status == SessionStatus.initializing ||
            status == SessionStatus.loadingProfile) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (status == SessionStatus.signedOut ||
            status == SessionStatus.signingIn) {
          return LoginScreen(sessionController: _sessionController);
        }

        if ((status == SessionStatus.authenticated ||
                status == SessionStatus.signingOut) &&
            profile != null) {
          return HomeScreen(
            profile: profile,
            sessionController: _sessionController,
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      _sessionController.errorMessage ??
                          'Unable to load your account.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () async {
                        await _sessionController.retryProfile();
                      },
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _sessionController.signOut();
                      },
                      child: const Text('Log Out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
