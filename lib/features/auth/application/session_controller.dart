import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/api_exception.dart';
import '../../profile/data/profile_service.dart';
import '../../profile/domain/user_profile.dart';
import '../data/auth_service.dart';

enum SessionStatus {
  initializing,
  signedOut,
  signingIn,
  loadingProfile,
  authenticated,
  signingOut,
  failure,
}

class SessionController extends ChangeNotifier {
  SessionController({AuthService? authService, ProfileService? profileService})
    : _authService = authService ?? AuthService(),
      _profileService = profileService ?? ProfileService();

  final AuthService _authService;
  final ProfileService _profileService;

  bool _isUpdatingProfile = false;
  String? _profileUpdateError;

  bool get isUpdatingProfile => _isUpdatingProfile;
  String? get profileUpdateError => _profileUpdateError;

  StreamSubscription<AuthState>? _authSubscription;

  SessionStatus _status = SessionStatus.initializing;
  UserProfile? _profile;
  String? _errorMessage;

  SessionStatus get status => _status;
  UserProfile? get profile => _profile;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    _authSubscription = _authService.authStateChanges.listen(
      (authState) {
        if (authState.event == AuthChangeEvent.signedOut) {
          _profile = null;
          _status = SessionStatus.signedOut;
          notifyListeners();
        }
      },
      onError: (Object _, StackTrace _) {
        _errorMessage = 'Authentication status could not be updated.';
        _status = SessionStatus.failure;
        notifyListeners();
      },
    );

    if (_authService.currentSession == null) {
      _status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }

    await _loadProfile();
  }

  Future<void> signIn({required String email, required String password}) async {
    _status = SessionStatus.signingIn;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.signIn(email: email, password: password);

      await _loadProfile();
    } on AuthServiceException catch (error) {
      _profile = null;
      _errorMessage = error.message;
      _status = SessionStatus.signedOut;
      notifyListeners();
    }
  }

  Future<void> retryProfile() async {
    if (_authService.currentSession == null) {
      _status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }

    await _loadProfile();
  }

  Future<void> signOut() async {
    _status = SessionStatus.signingOut;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.signOut();
    } on AuthServiceException catch (error) {
      _errorMessage = error.message;
      _status = SessionStatus.authenticated;
      notifyListeners();
      return;
    }

    _profile = null;
    _status = SessionStatus.signedOut;
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    _status = SessionStatus.loadingProfile;
    _errorMessage = null;
    notifyListeners();

    try {
      _profile = await _profileService.getOwnProfile();
      _status = SessionStatus.authenticated;
      notifyListeners();
    } on ApiException catch (error) {
      if (error.statusCode == 401 ||
          error.code == 'PROFILE_REQUIRED' ||
          error.code == 'ACCOUNT_INACTIVE') {
        try {
          await _authService.signOut();
        } on AuthServiceException {
          // The local application still rejects this session.
        }

        _profile = null;
        _errorMessage = error.message;
        _status = SessionStatus.signedOut;
        notifyListeners();
        return;
      }

      _errorMessage = error.message;
      _status = SessionStatus.failure;
      notifyListeners();
    } on FormatException {
      _errorMessage = 'The server returned invalid profile information.';
      _status = SessionStatus.failure;
      notifyListeners();
    }
  }

  Future<bool> updateFullName(String fullName) async {
    if (_profile == null) {
      return false;
    }

    _isUpdatingProfile = true;
    _profileUpdateError = null;
    notifyListeners();

    try {
      _profile = await _profileService.updateFullName(fullName);

      return true;
    } on ApiException catch (error) {
      _profileUpdateError = error.message;

      if (error.statusCode == 401 || error.code == 'ACCOUNT_INACTIVE') {
        try {
          await _authService.signOut();
        } on AuthServiceException {
          // The local application still rejects the session.
        }

        _profile = null;
        _status = SessionStatus.signedOut;
      }

      return false;
    } on FormatException {
      _profileUpdateError = 'The server returned invalid profile information.';
      return false;
    } finally {
      _isUpdatingProfile = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _profileService.close();
    super.dispose();
  }
}
