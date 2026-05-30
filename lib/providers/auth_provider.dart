/// Authentication provider using `local_auth`.
///
/// Manages the biometric auth state for the splash-to-auth flow.
/// The app stays locked (blurred) until [authenticate] succeeds.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class AuthProvider extends ChangeNotifier {
  final LocalAuthentication _auth = LocalAuthentication();

  bool _isAuthenticated = false;
  bool _isAuthenticating = false;
  bool _biometricsAvailable = false;
  String? _errorMessage;

  bool get isAuthenticated => _isAuthenticated;
  bool get isAuthenticating => _isAuthenticating;
  bool get biometricsAvailable => _biometricsAvailable;
  String? get errorMessage => _errorMessage;

  /// Check if the device supports biometrics or device credentials.
  Future<void> checkBiometrics() async {
    try {
      _biometricsAvailable = await _auth.canCheckBiometrics ||
          await _auth.isDeviceSupported();
    } on PlatformException {
      _biometricsAvailable = false;
    }
    notifyListeners();
  }

  /// Trigger biometric/PIN authentication.
  ///
  /// On success, sets [isAuthenticated] = true and navigates to home.
  /// On failure, keeps the lock screen up with an error message.
  Future<bool> authenticate() async {
    if (_isAuthenticating) return false;

    _isAuthenticating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _isAuthenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to access your finances',
        biometricOnly: false, // Allow PIN/pattern fallback
        persistAcrossBackgrounding: true,
      );
    } on PlatformException catch (e) {
      _errorMessage = _mapError(e);
      _isAuthenticated = false;
    }

    _isAuthenticating = false;
    notifyListeners();
    return _isAuthenticated;
  }

  /// Lock the app (e.g., when backgrounded).
  void lock() {
    _isAuthenticated = false;
    notifyListeners();
  }

  String _mapError(PlatformException e) {
    switch (e.code) {
      case 'NotAvailable':
        return 'Biometric authentication is not available on this device.';
      case 'NotEnrolled':
        return 'No biometrics enrolled. Please set up fingerprint or face unlock.';
      case 'LockedOut':
        return 'Too many attempts. Please try again later.';
      case 'PermanentlyLockedOut':
        return 'Biometrics permanently locked. Use your device PIN.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
