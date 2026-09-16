import 'package:record/record.dart';

/// Backend connection settings.
///
/// Override at build time:
/// `flutter run --dart-define=API_BASE_URL=https://api.example.com/api/v1`
class ApiConfig {
  const ApiConfig._();

  static const _override = String.fromEnvironment('API_BASE_URL');

  /// Root of the versioned REST API, without a trailing slash.
  static String get baseUrl {
    if (_override.isNotEmpty) return _stripSlash(_override);
    return '${_defaultHost()}/api/v1';
  }

  /// Server root, used for links that live outside `/api/v1`.
  static String get serverUrl {
    if (_override.isNotEmpty) {
      final base = _stripSlash(_override);
      return base.endsWith('/api/v1')
          ? base.substring(0, base.length - '/api/v1'.length)
          : base;
    }
    return _defaultHost();
  }

  /// The deployed backend. For a local server, build with
  /// `--dart-define=API_BASE_URL=http://10.0.2.2:5000/api/v1` on the Android
  /// emulator or `http://localhost:5000/api/v1` elsewhere.
  static String _defaultHost() => 'http://2.25.68.237';

  static String _stripSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  /// Terms/privacy version sent with registration if `/legal` cannot be read.
  /// Matches the version the backend seed publishes; registration is rejected
  /// with `INVALID_TERMS_VERSION` when it does not match an active document.
  static const fallbackLegalVersion = 'v1';

  static const requestTimeout = Duration(seconds: 30);
  static const aiRequestTimeout = Duration(seconds: 120);
}

/// How spoken turns are recorded. Transcription only needs speech-band audio,
/// and 16 kHz mono AAC is a fraction of the size of the 44.1 kHz stereo
/// default, so the upload leaves the phone several times faster on mobile data.
const speechRecordConfig = RecordConfig(
  encoder: AudioEncoder.aacLc,
  sampleRate: 16000,
  numChannels: 1,
  bitRate: 32000,
);
