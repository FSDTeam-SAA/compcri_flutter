import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Raised when a provider sheet fails for a reason worth telling the user
/// about. A cancelled sheet returns null instead, because backing out is not
/// an error and should not raise a red snackbar.
class FederatedAuthException implements Exception {
  FederatedAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What Apple returns for a sign-in: the token the API verifies, plus the name
/// Apple only discloses the first time this Apple ID authorises the app.
class AppleIdentity {
  const AppleIdentity({required this.identityToken, this.fullName});
  final String identityToken;
  final String? fullName;
}

/// The two provider sheets, reduced to the token our API expects.
class FederatedAuth {
  const FederatedAuth._();

  /// The OAuth client the backend verifies tokens against. Passing it as the
  /// server client makes Android return an ID token at all, and keeps the
  /// audience identical on both platforms.
  static const _serverClientId =
      '63352646426-mlmi4cgkbhv50q6koq71lii0o7dhbgqj.apps.googleusercontent.com';
  static const _iosClientId =
      '63352646426-u95p49vkf48gdipn750bag3s5oh6vv8j.apps.googleusercontent.com';

  static bool _googleReady = false;

  /// Returns a Google ID token, or null when the user dismissed the sheet.
  static Future<String?> googleIdToken() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(
        clientId: Platform.isIOS ? _iosClientId : null,
        serverClientId: _serverClientId,
      );
      _googleReady = true;
    }
    try {
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw FederatedAuthException('Google did not return a sign-in token.');
      }
      return token;
    } on GoogleSignInException catch (error) {
      // ignore: avoid_print
      print('GOOGLE_DEBUG code=${error.code} desc=${error.description} '
          'details=${error.details}');
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      // An unregistered signing certificate fails here rather than on the
      // account sheet, so the code is worth showing: without it the button
      // simply appears to do nothing.
      throw FederatedAuthException(
        'Google sign-in failed (${error.code.name}). '
        '${error.description ?? ''}'.trim(),
      );
    }
  }

  /// Returns the Apple identity token, or null when the sheet was dismissed.
  static Future<AppleIdentity?> apple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final token = credential.identityToken;
      if (token == null) {
        throw FederatedAuthException('Apple did not return a sign-in token.');
      }
      final name = [credential.givenName, credential.familyName]
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .join(' ');
      return AppleIdentity(
        identityToken: token,
        fullName: name.isEmpty ? null : name,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) return null;
      throw FederatedAuthException('Apple sign-in failed. Please try again.');
    } on SignInWithAppleException {
      throw FederatedAuthException('Apple sign-in is not available here.');
    }
  }
}
