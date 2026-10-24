import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Which platform, app version and copy of the app is calling, for the
/// admin's download and usage reports. Nothing here names the person; the
/// install id is random and lives only as long as the app stays installed.
class ClientIdentity {
  ClientIdentity._();

  static const _installKey = 'app.installId';

  static String? _platform;
  static String? _version;
  static String? _installId;
  static bool _preexisting = false;

  static String? get installId => _installId;

  /// Adds the identity headers to an outgoing request. A no-op until
  /// [prepare] has run on a phone.
  static void stamp(Map<String, String> headers) {
    if (_platform != null) headers['X-Client-Platform'] = _platform!;
    if (_version != null) headers['X-App-Version'] = _version!;
    if (_installId != null) headers['X-Install-Id'] = _installId!;
  }

  /// Reads or creates this copy's install id. Runs first thing at launch, so
  /// a phone that already holds a session or finished onboarding is known to
  /// have had the app before launches were reported.
  static Future<void> prepare() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_installKey);
      if (id == null) {
        _preexisting =
            prefs.containsKey('app.onboarded') ||
            prefs.containsKey('auth.refreshToken');
        id = _newId();
        await prefs.setString(_installKey, id);
      }
      final info = await PackageInfo.fromPlatform();
      _platform = Platform.isIOS ? 'ios' : 'android';
      _version = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
      _installId = id;
    } catch (_) {
      // Reports are a convenience; the app never waits on them.
    }
  }

  /// Counts this launch. The first one from a new install id is a download.
  static Future<void> reportLaunch({http.Client? client}) async {
    final id = _installId;
    if (id == null) return;
    final http.Client sender = client ?? http.Client();
    try {
      await sender
          .post(
            Uri.parse('${ApiConfig.baseUrl}/app/installs'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'installId': id,
              'platform': _platform,
              'appVersion': ?_version,
              'osVersion': Platform.operatingSystemVersion.length > 80
                  ? Platform.operatingSystemVersion.substring(0, 80)
                  : Platform.operatingSystemVersion,
              'locale': Platform.localeName.length > 20
                  ? Platform.localeName.substring(0, 20)
                  : Platform.localeName,
              if (_preexisting) 'preexisting': true,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Offline or the server is down: the next launch reports instead.
    } finally {
      if (client == null) sender.close();
    }
  }

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
