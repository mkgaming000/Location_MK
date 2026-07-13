import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/logger.dart';

/// Wraps Firebase Anonymous Authentication.
///
/// On first launch the app signs in anonymously and caches the resulting
/// `uid`. The `uid` is used as the `owner_uid` field in the Realtime Database
/// so that DB security rules can ensure only the device owner can write to
/// their own node.
class AuthService with ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<User?>? _authStateSub;
  bool _isInitializing = false;
  Completer<User?>? _initCompleter;

  User? _user;
  User? get currentUser => _user;
  String? get uid => _user?.uid;
  bool get isAuthenticated => _user != null;

  /// Initializes the auth listener and signs in anonymously if needed.
  /// Returns the current user (after sign-in completes).
  ///
  /// Safe to call multiple times — concurrent callers will await the same
  /// initialization.
  Future<User?> initialize() async {
    // If we already have a user, return immediately.
    if (_user != null) return _user;

    // If initialization is in progress, wait for it.
    if (_isInitializing) return _initCompleter!.future;

    _isInitializing = true;
    _initCompleter = Completer<User?>();

    try {
      // Register the auth-state listener exactly once.
      // IMPORTANT: Only update _user if the new user is non-null OR
      // if we haven't set it yet. This prevents the listener from
      // overwriting _user with null during sign-in transitions.
      _authStateSub ??= _auth.authStateChanges().listen((User? user) {
        if (user != null) {
          _user = user;
          notifyListeners();
        } else if (_user == null) {
          // Only set to null if we never had a user.
          notifyListeners();
        }
        // If user is null but _user is non-null, DON'T overwrite —
        // this is a transient state during sign-in.
      });

      // If no current user, sign in anonymously.
      if (_auth.currentUser == null) {
        try {
          AppLogger.info('Signing in anonymously...');
          final cred = await _auth.signInAnonymously();
          _user = cred.user;
          AppLogger.info('Anonymous sign-in successful. UID: ${_user?.uid}');
        } on FirebaseAuthException catch (e) {
          AppLogger.error('Anonymous sign-in failed: ${e.code}', e);
          _initCompleter!.complete(null);
          _isInitializing = false;
          return null;
        }
      } else {
        _user = _auth.currentUser;
        AppLogger.info('Already authenticated. UID: ${_user?.uid}');
      }

      notifyListeners();
      _initCompleter!.complete(_user);
      _isInitializing = false;
      return _user;
    } catch (e, st) {
      AppLogger.error('AuthService.initialize failed', e, st);
      _initCompleter!.completeError(e);
      _isInitializing = false;
      rethrow;
    }
  }

  /// Ensures the user is authenticated. If not, signs in anonymously.
  /// Returns true if authenticated, false otherwise.
  Future<bool> ensureAuthenticated() async {
    // If we have a cached user, verify it's still valid.
    if (_user != null && _auth.currentUser != null) {
      // Refresh the token to ensure DB rules see a fresh session.
      try {
        await _auth.currentUser?.getIdToken(true);
        return true;
      } catch (e) {
        AppLogger.error('Token refresh failed, re-signing in', e);
        // Fall through to re-initialize.
      }
    }

    // Not authenticated — sign in.
    final user = await initialize();
    return user != null;
  }

  /// Signs out — should never be called in normal operation since the app
  /// uses anonymous auth, but exposed for completeness.
  Future<void> signOut() async {
    await _auth.signOut();
    _user = null;
    notifyListeners();
  }

  /// Releases the auth-state listener. Called only on app teardown.
  @override
  void dispose() {
    _authStateSub?.cancel();
    _authStateSub = null;
    super.dispose();
  }
}
