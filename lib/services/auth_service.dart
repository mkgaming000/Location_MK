import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Wraps Firebase Anonymous Authentication.
///
/// On first launch the app signs in anonymously and caches the resulting
/// `uid`. The `uid` is used as the `owner_uid` field in the Realtime Database
/// so that DB security rules can ensure only the device owner can write to
/// their own node.
///
/// Auth state is NOT shared across Dart isolates — the background service
/// isolate must call [initialize] independently and will receive its own
/// anonymous UID. Database security rules are designed to handle this:
/// only the UID registered under `user_devices/{uid}/device_id` for the
/// matching device_id may write to `live_locations/{device_id}`. The
/// background service registers its own UID → device_id mapping before
/// starting to publish.
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
    if (_user != null) return _user;
    if (_isInitializing) return _initCompleter!.future;
    _isInitializing = true;
    _initCompleter = Completer<User?>();

    try {
      // Register the auth-state listener exactly once.
      _authStateSub ??= _auth.authStateChanges().listen((User? user) {
        _user = user;
        notifyListeners();
      });

      // If no current user, sign in anonymously.
      if (_auth.currentUser == null) {
        try {
          final cred = await _auth.signInAnonymously();
          _user = cred.user;
        } on FirebaseAuthException catch (e) {
          debugPrint('Anonymous sign-in failed: ${e.code} — ${e.message}');
          _initCompleter!.complete(null);
          _isInitializing = false;
          return null;
        }
      } else {
        _user = _auth.currentUser;
      }

      notifyListeners();
      _initCompleter!.complete(_user);
      _isInitializing = false;
      return _user;
    } catch (e) {
      debugPrint('AuthService.initialize failed: $e');
      _initCompleter!.completeError(e);
      _isInitializing = false;
      rethrow;
    }
  }

  /// Re-authenticates anonymously if the session has expired.
  Future<void> ensureAuthenticated() async {
    if (_auth.currentUser == null) {
      await initialize();
    }
    // Force-refresh the ID token so DB rules see a fresh session.
    try {
      await _auth.currentUser?.getIdToken(true);
    } catch (e) {
      debugPrint('AuthService token refresh failed: $e');
    }
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
