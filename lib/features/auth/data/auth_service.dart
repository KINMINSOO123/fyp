import 'package:supabase_flutter/supabase_flutter.dart';

class AuthServiceException implements Exception {
  const AuthServiceException(this.message);

  final String message;
}

class AuthService {
  AuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      if (response.session == null) {
        throw const AuthServiceException(
          'Authentication did not create a session.',
        );
      }
    } on AuthException {
      throw const AuthServiceException(
        'The email address or password is incorrect.',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } on AuthException {
      throw const AuthServiceException('Unable to log out. Please try again.');
    }
  }
}
