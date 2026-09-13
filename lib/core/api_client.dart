import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'i18n.dart';

/// A failed API call. [code] mirrors the machine-readable `error.code` the
/// backend returns, so screens can branch on `EVENT_CONFLICT`,
/// `PREMIUM_REQUIRED`, `AI_QUOTA_EXHAUSTED`, and friends.
class ApiException implements Exception {
  ApiException(
    this.message, {
    this.code = 'UNKNOWN',
    this.status = 0,
    this.details,
  });

  final String message;
  final String code;
  final int status;
  final dynamic details;

  bool get isNetworkError => code == 'NETWORK_ERROR' || code == 'TIMEOUT';
  bool get isConflict => code == 'EVENT_CONFLICT';
  bool get isVersionConflict =>
      code == 'EVENT_VERSION_CONFLICT' || code == 'VERSION_CONFLICT';
  bool get needsPremium => code == 'PREMIUM_REQUIRED';

  @override
  String toString() => message;
}

/// Tokens and identity for the signed-in user, persisted between launches.
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    this.refreshExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime? refreshExpiresAt;

  bool get refreshExpired =>
      refreshExpiresAt != null && refreshExpiresAt!.isBefore(DateTime.now());
}

/// How the user likes the voice assistant to behave, remembered between runs.
///
/// [voice] is `null` until the user picks one, which leaves the choice to the
/// server's `OPENAI_TTS_VOICE` default rather than pinning it from the client.
class VoicePrefs {
  const VoicePrefs({this.voice, this.handsFree = false, this.muted = false});

  final String? voice;
  final bool handsFree;
  final bool muted;
}

/// Reads and writes the session to shared preferences.
class SessionStore {
  static const _accessKey = 'auth.accessToken';
  static const _refreshKey = 'auth.refreshToken';
  static const _refreshExpiryKey = 'auth.refreshExpiresAt';
  static const _onboardedKey = 'app.onboarded';
  static const _voiceKey = 'ai.voice';
  static const _handsFreeKey = 'ai.handsFree';
  static const _mutedKey = 'ai.muted';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Session?> read() async {
    final prefs = await _prefs;
    final access = prefs.getString(_accessKey);
    final refresh = prefs.getString(_refreshKey);
    if (access == null || refresh == null) return null;
    final expiry = prefs.getString(_refreshExpiryKey);
    return Session(
      accessToken: access,
      refreshToken: refresh,
      refreshExpiresAt: expiry == null ? null : DateTime.tryParse(expiry),
    );
  }

  Future<void> write(Session session) async {
    final prefs = await _prefs;
    await prefs.setString(_accessKey, session.accessToken);
    await prefs.setString(_refreshKey, session.refreshToken);
    final expiry = session.refreshExpiresAt;
    if (expiry == null) {
      await prefs.remove(_refreshExpiryKey);
    } else {
      await prefs.setString(_refreshExpiryKey, expiry.toIso8601String());
    }
  }

  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_refreshExpiryKey);
  }

  Future<bool> onboarded() async =>
      (await _prefs).getBool(_onboardedKey) ?? false;

  Future<void> setOnboarded() async =>
      (await _prefs).setBool(_onboardedKey, true);

  /// One read for all three so opening the voice screen costs a single await.
  Future<VoicePrefs> voicePrefs() async {
    final prefs = await _prefs;
    return VoicePrefs(
      voice: prefs.getString(_voiceKey),
      handsFree: prefs.getBool(_handsFreeKey) ?? false,
      muted: prefs.getBool(_mutedKey) ?? false,
    );
  }

  /// A null [voice] clears the override and returns to the server default.
  Future<void> setVoice(String? voice) async {
    final prefs = await _prefs;
    if (voice == null) {
      await prefs.remove(_voiceKey);
    } else {
      await prefs.setString(_voiceKey, voice);
    }
  }

  Future<void> setHandsFree(bool value) async =>
      (await _prefs).setBool(_handsFreeKey, value);

  Future<void> setMuted(bool value) async =>
      (await _prefs).setBool(_mutedKey, value);
}

/// Thin REST client over the Compcri API.
///
/// Every successful response is unwrapped from `{ success: true, data }` and
/// every failure is raised as an [ApiException] carrying the server's error
/// code. A 401 triggers one refresh-and-retry; if the refresh itself is
/// rejected the session is cleared and [onUnauthorized] fires so the app can
/// return to the sign-in screen.
class ApiClient {
  ApiClient({http.Client? client, SessionStore? store})
    : _client = client ?? http.Client(),
      _store = store ?? SessionStore();

  final http.Client _client;
  final SessionStore _store;

  Session? _session;
  Future<Session?>? _refreshing;

  /// Invoked when the session can no longer be renewed.
  void Function()? onUnauthorized;

  Session? get session => _session;
  bool get isAuthenticated => _session != null;
  SessionStore get store => _store;

  Future<Session?> restore() async {
    final saved = await _store.read();
    if (saved == null || saved.refreshExpired) {
      if (saved != null) await _store.clear();
      return null;
    }
    _session = saved;
    return saved;
  }

  Future<void> setSession(Session session) async {
    _session = session;
    await _store.write(session);
  }

  Future<void> clearSession() async {
    _session = null;
    await _store.clear();
  }

  // --- verbs -------------------------------------------------------------

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) => _send('GET', path, query: query, auth: auth);

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
    Duration? timeout,
  }) => _send(
    'POST',
    path,
    body: body,
    query: query,
    auth: auth,
    timeout: timeout,
  );

  Future<dynamic> patch(String path, {Object? body, bool auth = true}) =>
      _send('PATCH', path, body: body, auth: auth);

  Future<dynamic> put(String path, {Object? body, bool auth = true}) =>
      _send('PUT', path, body: body, auth: auth);

  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) => _send('DELETE', path, body: body, query: query, auth: auth);

  /// Returns the `meta` block alongside `data` for paginated endpoints.
  Future<({dynamic data, Map<String, dynamic>? meta})> getPaged(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final envelope = await _sendRaw('GET', path, query: query, auth: true);
    return (
      data: envelope['data'],
      meta: envelope['meta'] as Map<String, dynamic>?,
    );
  }

  // --- uploads -----------------------------------------------------------

  /// Content type for a multipart part, derived from the file extension.
  ///
  /// `http` labels every part `application/octet-stream` unless told
  /// otherwise, and both backend upload filters match on MIME type, so an
  /// unlabelled part is rejected as `INVALID_AUDIO_TYPE`/`INVALID_MEDIA_TYPE`.
  static MediaType _contentTypeFor(String filePath, MediaType fallback) {
    final extension = filePath.toLowerCase().split('.').last;
    return switch (extension) {
      'm4a' => MediaType('audio', 'm4a'),
      'mp4' => MediaType('audio', 'mp4'),
      'mp3' || 'mpga' => MediaType('audio', 'mpeg'),
      'wav' => MediaType('audio', 'wav'),
      'ogg' => MediaType('audio', 'ogg'),
      'webm' => MediaType('audio', 'webm'),
      'flac' => MediaType('audio', 'flac'),
      'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'gif' => MediaType('image', 'gif'),
      _ => fallback,
    };
  }

  /// Uploads an image to `POST /media`, returning the created media asset.
  Future<Map<String, dynamic>> uploadImage({
    required String filePath,
    required String purpose,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/media', null))
      ..fields['purpose'] = purpose
      ..files.add(
        await http.MultipartFile.fromPath(
          'image',
          filePath,
          contentType: _contentTypeFor(filePath, MediaType('image', 'jpeg')),
        ),
      );
    final envelope = await _sendMultipart(request);
    return Map<String, dynamic>.from(envelope['data'] as Map);
  }

  /// Uploads a recorded audio clip to a transcription-backed endpoint.
  Future<Map<String, dynamic>> uploadAudio({
    required String path,
    required String filePath,
    String? voice,
    Map<String, String> fields = const <String, String>{},
  }) async {
    final request = http.MultipartRequest('POST', _uri(path, null))
      ..files.add(
        await http.MultipartFile.fromPath(
          'audio',
          filePath,
          contentType: _contentTypeFor(filePath, MediaType('audio', 'm4a')),
        ),
      );
    if (voice != null) request.fields['voice'] = voice;
    request.fields.addAll(fields);
    final envelope = await _sendMultipart(
      request,
      timeout: ApiConfig.aiRequestTimeout,
    );
    return Map<String, dynamic>.from(envelope['data'] as Map);
  }

  /// Opens a server-sent event stream and yields each event's decoded payload.
  ///
  /// Anything that fails before the first event — auth, entitlement, quota —
  /// comes back as an ordinary JSON error response, so it surfaces as an
  /// [ApiException] exactly like every other call. Once the stream is open,
  /// trouble arrives as an event instead, and it is the caller's to read.
  Stream<Map<String, dynamic>> stream(
    String path, {
    Object? body,
    Duration idleTimeout = const Duration(seconds: 45),
  }) => _eventStream(
    () => http.Request('POST', _uri(path, null))
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..body = jsonEncode(body ?? const <String, dynamic>{}),
    idleTimeout: idleTimeout,
  );

  /// Uploads a recorded clip and streams the server's events back, exactly as
  /// [stream] does for a JSON body. The file is read once, so a request renewed
  /// after a 401 sends the same bytes again.
  Stream<Map<String, dynamic>> streamAudio({
    required String path,
    required String filePath,
    Map<String, String> fields = const <String, String>{},
    Duration idleTimeout = const Duration(seconds: 45),
  }) async* {
    final bytes = await File(filePath).readAsBytes();
    final filename = filePath.split(RegExp(r'[\\/]')).last;
    yield* _eventStream(
      () => http.MultipartRequest('POST', _uri(path, null))
        ..fields.addAll(fields)
        ..files.add(
          http.MultipartFile.fromBytes(
            'audio',
            bytes,
            filename: filename,
            contentType: _contentTypeFor(filePath, MediaType('audio', 'm4a')),
          ),
        ),
      idleTimeout: idleTimeout,
    );
  }

  Stream<Map<String, dynamic>> _eventStream(
    http.BaseRequest Function() build, {
    required Duration idleTimeout,
  }) async* {
    Future<http.StreamedResponse> open() {
      final request = build()
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Accept-Language'] = I18n.locale;
      if (_session != null) {
        request.headers['Authorization'] = 'Bearer ${_session!.accessToken}';
      }
      // Headers only arrive once the server has something to say — for a
      // voice turn, after the upload and the transcription — so opening has
      // its own ceiling.
      return _client.send(request).timeout(ApiConfig.aiRequestTimeout);
    }

    try {
      var response = await open();
      if (response.statusCode == 401 && _session != null) {
        await response.stream.drain<void>();
        if (await _refreshSession() != null) response = await open();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // _decode throws the ApiException this deserves, error envelope and all.
        _decode(
          http.Response(
            await response.stream.bytesToString(),
            response.statusCode,
            headers: response.headers,
          ),
        );
        return;
      }

      // A silent connection is the failure worth catching: the server sends a
      // heartbeat comment every 15s, so a gap this long means it is gone.
      final lines = response.stream
          .timeout(
            idleTimeout,
            onTimeout: (sink) => sink.addError(
              ApiException(
                'The assistant stopped responding. Please try again.',
                code: 'TIMEOUT',
              ),
            ),
          )
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      // Each event is one `data:` line: the payload is JSON, and JSON encoding
      // escapes newlines, so no event can span lines and need reassembly.
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) yield decoded;
      }
    } on TimeoutException {
      throw ApiException(
        'The assistant took too long to respond. Please try again.',
        code: 'TIMEOUT',
      );
    } on SocketException {
      throw ApiException(_offlineMessage, code: 'NETWORK_ERROR');
    } on http.ClientException catch (error) {
      throw ApiException(error.message, code: 'NETWORK_ERROR');
    }
  }

  // --- plumbing ----------------------------------------------------------

  Uri _uri(String path, Map<String, dynamic>? query) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('${ApiConfig.baseUrl}$normalized');
    if (query == null || query.isEmpty) return uri;
    final params = <String, String>{};
    query.forEach((key, value) {
      if (value == null) return;
      params[key] = value is DateTime
          ? value.toUtc().toIso8601String()
          : '$value';
    });
    return uri.replace(queryParameters: {...uri.queryParameters, ...params});
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
    Duration? timeout,
  }) async {
    final envelope = await _sendRaw(
      method,
      path,
      body: body,
      query: query,
      auth: auth,
      timeout: timeout,
    );
    return envelope['data'];
  }

  Future<Map<String, dynamic>> _sendRaw(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
    Duration? timeout,
    bool retried = false,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['Accept'] = 'application/json';
    // The server answers errors in the language the app is showing.
    request.headers['Accept-Language'] = I18n.locale;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (auth && _session != null) {
      request.headers['Authorization'] = 'Bearer ${_session!.accessToken}';
    }

    final response = await _execute(
      request,
      timeout ?? ApiConfig.requestTimeout,
    );

    if (response.statusCode == 401 && auth && !retried && _session != null) {
      final renewed = await _refreshSession();
      if (renewed != null) {
        return _sendRaw(
          method,
          path,
          body: body,
          query: query,
          auth: auth,
          timeout: timeout,
          retried: true,
        );
      }
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> _sendMultipart(
    http.MultipartRequest request, {
    Duration? timeout,
    bool retried = false,
  }) async {
    request.headers['Accept'] = 'application/json';
    // The server answers errors in the language the app is showing.
    request.headers['Accept-Language'] = I18n.locale;
    if (_session != null) {
      request.headers['Authorization'] = 'Bearer ${_session!.accessToken}';
    }

    // The stream can only be consumed once, so keep the bytes for a retry.
    // contentType has to ride along: rebuilding the part without it resets
    // it to application/octet-stream, which both upload filters reject.
    final files =
        <
          ({
            String field,
            String? filename,
            MediaType contentType,
            Uint8List bytes,
          })
        >[];
    for (final file in request.files) {
      final chunks = await file.finalize().toList();
      files.add((
        field: file.field,
        filename: file.filename,
        contentType: file.contentType,
        bytes: Uint8List.fromList(chunks.expand((chunk) => chunk).toList()),
      ));
    }

    Future<http.Response> attempt() async {
      final copy = http.MultipartRequest(request.method, request.url)
        ..headers.addAll(request.headers)
        ..fields.addAll(request.fields);
      if (_session != null) {
        copy.headers['Authorization'] = 'Bearer ${_session!.accessToken}';
      }
      for (final file in files) {
        copy.files.add(
          http.MultipartFile.fromBytes(
            file.field,
            file.bytes,
            filename: file.filename,
            contentType: file.contentType,
          ),
        );
      }
      try {
        final streamed = await _client
            .send(copy)
            .timeout(timeout ?? ApiConfig.aiRequestTimeout);
        return await http.Response.fromStream(streamed);
      } on TimeoutException {
        throw ApiException(
          'The upload timed out. Please try again.',
          code: 'TIMEOUT',
        );
      } on SocketException {
        throw ApiException(_offlineMessage, code: 'NETWORK_ERROR');
      } on http.ClientException catch (error) {
        throw ApiException(error.message, code: 'NETWORK_ERROR');
      }
    }

    var response = await attempt();
    if (response.statusCode == 401 && !retried && _session != null) {
      final renewed = await _refreshSession();
      if (renewed != null) response = await attempt();
    }
    return _decode(response);
  }

  Future<http.Response> _execute(http.Request request, Duration timeout) async {
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(
        'The server took too long to respond. Please try again.',
        code: 'TIMEOUT',
      );
    } on SocketException {
      throw ApiException(_offlineMessage, code: 'NETWORK_ERROR');
    } on http.ClientException catch (error) {
      throw ApiException(error.message, code: 'NETWORK_ERROR');
    }
  }

  static String get _offlineMessage => tr(
    'Cannot reach the server at {url}. Check that the API is running and reachable from this device.',
    {'url': ApiConfig.serverUrl},
  );

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic>? body;
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        // Non-JSON bodies fall through to the generic error below.
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body ?? <String, dynamic>{'success': true, 'data': null};
    }

    final error = body?['error'];
    if (error is Map) {
      throw ApiException(
        (error['message'] as String?) ?? 'Request failed',
        code: (error['code'] as String?) ?? 'UNKNOWN',
        status: response.statusCode,
        details: error['details'],
      );
    }
    throw ApiException(
      tr('Request failed with status {status}', {
        'status': response.statusCode,
      }),
      code: 'HTTP_${response.statusCode}',
      status: response.statusCode,
    );
  }

  /// Rotates the refresh token. Concurrent callers share one in-flight call.
  Future<Session?> _refreshSession() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final attempt = _performRefresh();
    _refreshing = attempt;
    return attempt.whenComplete(() => _refreshing = null);
  }

  Future<Session?> _performRefresh() async {
    final current = _session;
    if (current == null) return null;
    try {
      final request = http.Request('POST', _uri('/auth/refresh', null))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'application/json'
        ..headers['Accept-Language'] = I18n.locale
        ..body = jsonEncode({'refreshToken': current.refreshToken});
      final response = await _execute(request, ApiConfig.requestTimeout);
      final data = _decode(response)['data'] as Map<String, dynamic>;
      final renewed = Session(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        refreshExpiresAt: DateTime.tryParse('${data['refreshTokenExpiresAt']}'),
      );
      await setSession(renewed);
      return renewed;
    } on ApiException catch (error) {
      // A network blip should not sign the user out; a rejected token should.
      if (error.isNetworkError) return null;
      await clearSession();
      onUnauthorized?.call();
      return null;
    }
  }

  void close() => _client.close();
}
