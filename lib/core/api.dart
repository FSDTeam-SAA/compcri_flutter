import 'api_client.dart';
import 'models.dart';
import 'time.dart';

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

List<Map<String, dynamic>> _list(dynamic value) => value is List
    ? value.whereType<Map>().map((item) => item.cast<String, dynamic>()).toList()
    : const <Map<String, dynamic>>[];

/// Everything returned by a successful authentication call.
class AuthResult {
  const AuthResult({required this.user, required this.session});

  final AppUser user;
  final Session session;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
    user: AppUser.fromJson(_map(json['user'])),
    session: Session(
      accessToken: '${json['accessToken']}',
      refreshToken: '${json['refreshToken']}',
      refreshExpiresAt: DateTime.tryParse('${json['refreshTokenExpiresAt']}'),
    ),
  );
}

/// The `/users/me` aggregate.
class MeResponse {
  const MeResponse({required this.user, this.calendar, this.subscription});

  final AppUser user;
  final CalendarInfo? calendar;
  final SubscriptionInfo? subscription;

  factory MeResponse.fromJson(Map<String, dynamic> json) {
    final calendar = json['primaryCalendar'];
    return MeResponse(
      user: AppUser.fromJson(_map(json['user'])),
      calendar: calendar is Map
          ? CalendarInfo.fromJson(calendar.cast<String, dynamic>())
          : null,
      subscription: null,
    );
  }
}

/// Result of creating or updating an event, including advisory conflicts.
class EventMutation {
  const EventMutation({required this.event, this.conflicts = const []});

  final CalendarEvent event;
  final List<EventConflict> conflicts;

  factory EventMutation.fromJson(Map<String, dynamic> json) => EventMutation(
    event: CalendarEvent.fromJson(_map(json['event'])),
    conflicts: EventConflict.listFrom(json['conflicts']),
  );
}

// ---------------------------------------------------------------------------

class AuthApi {
  AuthApi(this._client);
  final ApiClient _client;

  Future<AuthResult> register({
    required String email,
    required String password,
    required String displayName,
    required String termsVersion,
    String? privacyVersion,
  }) async => AuthResult.fromJson(
    _map(
      await _client.post(
        '/auth/register',
        auth: false,
        body: {
          'email': email,
          'password': password,
          if (displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
          'timeZone': DeviceTimeZone.current,
          'termsVersion': termsVersion,
          'privacyVersion': ?privacyVersion,
          'termsAccepted': true,
        },
      ),
    ),
  );

  Future<AuthResult> login(String email, String password) async =>
      AuthResult.fromJson(
        _map(
          await _client.post(
            '/auth/login',
            auth: false,
            body: {'email': email, 'password': password},
          ),
        ),
      );

  Future<AuthResult> google({
    required String idToken,
    String? termsVersion,
    String? privacyVersion,
  }) async => AuthResult.fromJson(
    _map(
      await _client.post(
        '/auth/google',
        auth: false,
        body: {
          'idToken': idToken,
          'timeZone': DeviceTimeZone.current,
          if (termsVersion != null) ...{
            'termsVersion': termsVersion,
            'termsAccepted': true,
          },
          'privacyVersion': ?privacyVersion,
        },
      ),
    ),
  );

  Future<void> logout(String refreshToken) => _client.post(
    '/auth/logout',
    auth: false,
    body: {'refreshToken': refreshToken},
  );

  Future<void> forgotPassword(String email) =>
      _client.post('/auth/forgot-password', auth: false, body: {'email': email});

  /// Returns the single-use reset token.
  Future<String> verifyResetOtp(String email, String code) async {
    final data = _map(
      await _client.post(
        '/auth/verify-reset-otp',
        auth: false,
        body: {'email': email, 'code': code},
      ),
    );
    return '${data['resetToken']}';
  }

  Future<void> resetPassword(String resetToken, String password) =>
      _client.post(
        '/auth/reset-password',
        auth: false,
        body: {'resetToken': resetToken, 'password': password},
      );

  Future<AuthResult> cancelDeletion(String email, String password) async =>
      AuthResult.fromJson(
        _map(
          await _client.post(
            '/auth/cancel-deletion',
            auth: false,
            body: {'email': email, 'password': password},
          ),
        ),
      );
}

class UserApi {
  UserApi(this._client);
  final ApiClient _client;

  Future<MeResponse> me() async => MeResponse.fromJson(_map(await _client.get('/users/me')));

  Future<AppUser> updateProfile(Map<String, dynamic> changes) async =>
      AppUser.fromJson(_map(await _client.patch('/users/me', body: changes)));

  Future<void> changePassword(String current, String next) => _client.put(
    '/users/me/password',
    body: {'currentPassword': current, 'newPassword': next},
  );

  Future<AppUser> updateNotificationPreferences(Map<String, bool> changes) async =>
      AppUser.fromJson(
        _map(await _client.patch('/users/me/notification-preferences', body: changes)),
      );

  /// Owned plus delegated calendars, flattened into one list.
  Future<List<CalendarInfo>> calendars() async {
    final data = _map(await _client.get('/users/me/calendars'));
    final calendars = <CalendarInfo>[];
    for (final entry in _list(data['owned'])) {
      calendars.add(CalendarInfo.fromJson(_map(entry['calendar'])));
    }
    for (final entry in _list(data['delegated'])) {
      final calendar = entry['calendar'];
      if (calendar is! Map) continue;
      calendars.add(
        CalendarInfo.fromJson(
          calendar.cast<String, dynamic>(),
          preset: '${entry['preset']}',
          delegationId: '${entry['delegationId']}',
        ),
      );
    }
    return calendars;
  }

  Future<Map<String, dynamic>> subscriptionManagement() async =>
      _map(await _client.get('/users/me/subscription-management'));

  Future<Map<String, dynamic>> requestDeletion({
    required String password,
    required String reason,
  }) async => _map(
    await _client.post(
      '/users/me/deletion',
      body: {
        'password': password,
        'reason': reason,
        'storeBillingAcknowledged': true,
      },
    ),
  );
}

class EventApi {
  EventApi(this._client);
  final ApiClient _client;

  Future<List<CalendarEvent>> list({
    required String calendarId,
    required DateTime from,
    required DateTime to,
    String? search,
  }) async {
    final data = await _client.get(
      '/calendars/$calendarId/events',
      query: {
        'from': isoUtc(from),
        'to': isoUtc(to),
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    return _list(data).map(CalendarEvent.fromJson).toList();
  }

  /// Events other people shared with this user.
  Future<List<CalendarEvent>> shared({
    required DateTime from,
    required DateTime to,
  }) async {
    final data = await _client.get(
      '/events/shared',
      query: {'from': isoUtc(from), 'to': isoUtc(to)},
    );
    return _list(data).map(CalendarEvent.fromJson).toList();
  }

  Future<CalendarEvent> get(String eventId) async {
    final data = _map(await _client.get('/events/$eventId'));
    return CalendarEvent.fromJson(
      _map(data['event']),
      permissions: _map(data['permissions']),
    );
  }

  Future<EventMutation> create({
    required String calendarId,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? description,
    String? location,
    String? posterMediaId,
    String? recurrenceRrule,
    String? groupId,
    List<int> reminderMinutes = const <int>[],
    String? timeZone,
    bool overrideConflicts = false,
  }) async => EventMutation.fromJson(
    _map(
      await _client.post(
        '/calendars/$calendarId/events',
        body: {
          'title': title,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (location != null && location.isNotEmpty) 'location': location,
          'posterMediaId': ?posterMediaId,
          'startsAt': isoUtc(startsAt),
          'endsAt': isoUtc(endsAt),
          'timeZone': timeZone ?? DeviceTimeZone.current,
          'reminderMinutes': reminderMinutes,
          'recurrenceRrule': ?recurrenceRrule,
          'groupId': ?groupId,
          'overrideConflicts': overrideConflicts,
        },
      ),
    ),
  );

  Future<EventMutation> update({
    required String eventId,
    required int version,
    String? title,
    String? description,
    String? location,
    Object? posterMediaId = _unset,
    DateTime? startsAt,
    DateTime? endsAt,
    String? timeZone,
    List<int>? reminderMinutes,
    Object? recurrenceRrule = _unset,
    bool overrideConflicts = false,
  }) async => EventMutation.fromJson(
    _map(
      await _client.patch(
        '/events/$eventId',
        body: {
          'version': version,
          'title': ?title,
          'description': ?description,
          'location': ?location,
          if (!identical(posterMediaId, _unset)) 'posterMediaId': posterMediaId,
          if (startsAt != null) 'startsAt': isoUtc(startsAt),
          if (endsAt != null) 'endsAt': isoUtc(endsAt),
          'timeZone': ?timeZone,
          'reminderMinutes': ?reminderMinutes,
          if (!identical(recurrenceRrule, _unset))
            'recurrenceRrule': recurrenceRrule,
          'overrideConflicts': overrideConflicts,
        },
      ),
    ),
  );

  Future<void> delete(String eventId, int version) =>
      _client.delete('/events/$eventId', query: {'version': version});

  /// Edits or cancels a single occurrence of a recurring event, leaving the
  /// rest of the series untouched. [originalStartAt] must be the occurrence
  /// start the server generated.
  Future<EventMutation> setRecurrenceException({
    required String eventId,
    required DateTime originalStartAt,
    required int version,
    bool cancelled = false,
    String? title,
    String? description,
    String? location,
    DateTime? startsAt,
    DateTime? endsAt,
    bool overrideConflicts = false,
  }) async => EventMutation.fromJson(
    _map(
      await _client.put(
        '/events/$eventId/recurrence-exception',
        body: {
          'originalStartAt': isoUtc(originalStartAt),
          'cancelled': cancelled,
          'version': version,
          'overrideConflicts': overrideConflicts,
          if (!cancelled)
            'overrides': {
              'title': ?title,
              'description': ?description,
              'location': ?location,
              if (startsAt != null) 'startsAt': isoUtc(startsAt),
              if (endsAt != null) 'endsAt': isoUtc(endsAt),
            },
        },
      ),
    ),
  );

  Future<CalendarEvent> setCompleted({
    required String eventId,
    required bool completed,
    required int version,
  }) async => CalendarEvent.fromJson(
    _map(
      await _client.patch(
        '/events/$eventId/completion',
        body: {'completed': completed, 'version': version},
      ),
    ),
  );

  Future<void> share({
    required String eventId,
    required String targetType,
    required List<String> targetIds,
    required String permission,
  }) => _client.post(
    '/events/$eventId/shares',
    body: {
      'targetType': targetType,
      'targetIds': targetIds,
      'permission': permission,
    },
  );

  Future<List<Map<String, dynamic>>> listShares(String eventId) async =>
      _list(await _client.get('/events/$eventId/shares'));

  Future<void> revokeShare(String eventId, String shareId) =>
      _client.delete('/events/$eventId/shares/$shareId');

  Future<void> rsvp(String eventId, String status) =>
      _client.put('/events/$eventId/rsvp', body: {'status': status});

  Future<List<TimeSlot>> availability({
    required String calendarId,
    required DateTime from,
    required DateTime to,
    int durationMinutes = 30,
  }) async => TimeSlot.listFrom(
    await _client.get(
      '/calendars/$calendarId/availability',
      query: {
        'from': isoUtc(from),
        'to': isoUtc(to),
        'durationMinutes': durationMinutes,
      },
    ),
  );

  Future<Map<String, dynamic>> settings(String calendarId) async =>
      _map(await _client.get('/calendars/$calendarId/settings'));

  Future<Map<String, dynamic>> updateSettings(
    String calendarId,
    Map<String, dynamic> changes,
  ) async => _map(await _client.patch('/calendars/$calendarId/settings', body: changes));
}

/// Sentinel so `null` can be sent explicitly to clear a field.
const _unset = Object();

class NetworkApi {
  NetworkApi(this._client);
  final ApiClient _client;

  Future<List<Person>> contacts({String? search}) async {
    final data = await _client.get(
      '/contacts',
      query: {if (search != null && search.isNotEmpty) 'search': search},
    );
    return _list(data).map(Person.fromContact).toList();
  }

  Future<void> removeContact(String userId) =>
      _client.delete('/contacts/$userId');

  Future<void> updateContactRelation(String userId, String? relation) =>
      _client.patch('/contacts/$userId', body: {'relation': relation});

  Future<List<CalendarEvent>> contactEvents({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final data = await _client.get(
      '/contacts/$userId/events',
      query: {'from': isoUtc(from), 'to': isoUtc(to)},
    );
    return _list(data).map(CalendarEvent.fromJson).toList();
  }

  Future<List<ContactRequest>> contactRequests({bool incoming = true}) async {
    final data = await _client.get(
      '/contact-requests',
      query: {'direction': incoming ? 'incoming' : 'outgoing'},
    );
    return _list(data)
        .map((json) => ContactRequest.fromJson(json, incoming: incoming))
        .toList();
  }

  Future<void> sendContactRequest({
    required String contactCode,
    String? relation,
  }) => _client.post(
    '/contact-requests',
    body: {
      'contactCode': contactCode,
      if (relation != null && relation.isNotEmpty) 'relation': relation,
    },
  );

  Future<void> respondToContactRequest({
    required String requestId,
    required bool accept,
    String? relation,
  }) => _client.put(
    '/contact-requests/$requestId',
    body: {
      'action': accept ? 'ACCEPT' : 'REJECT',
      if (relation != null && relation.isNotEmpty) 'relation': relation,
    },
  );

  Future<List<Group>> groups() async =>
      _list(await _client.get('/groups')).map(Group.fromJson).toList();

  Future<Group> group(String id) async =>
      Group.fromJson(_map(await _client.get('/groups/$id')));

  Future<Group> createGroup(String name) async =>
      Group.fromJson(_map(await _client.post('/groups', body: {'name': name})));

  Future<Group> joinGroup(String code) async =>
      Group.fromJson(_map(await _client.post('/groups/join', body: {'code': code})));

  Future<void> leaveGroup(String id) => _client.post('/groups/$id/leave');

  Future<void> deleteGroup(String id) => _client.delete('/groups/$id');

  Future<void> removeMember(String groupId, String memberId) =>
      _client.delete('/groups/$groupId/members/$memberId');

  Future<void> inviteMember({
    required String groupId,
    required String userId,
    String role = 'MEMBER',
  }) => _client.post(
    '/groups/$groupId/invitations',
    body: {'userId': userId, 'role': role},
  );

  Future<List<GroupInvitation>> groupInvitations() async =>
      _list(await _client.get('/group-invitations'))
          .map(GroupInvitation.fromJson)
          .toList();

  Future<void> respondToGroupInvitation({
    required String invitationId,
    required bool accept,
  }) => _client.put(
    '/group-invitations/$invitationId',
    body: {'action': accept ? 'ACCEPT' : 'REJECT'},
  );

  Future<CalendarEvent> createGroupEvent({
    required String groupId,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? description,
    String? location,
    List<int> reminderMinutes = const <int>[],
    bool overrideConflicts = false,
  }) async {
    final data = _map(
      await _client.post(
        '/groups/$groupId/events',
        body: {
          'title': title,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (location != null && location.isNotEmpty) 'location': location,
          'startsAt': isoUtc(startsAt),
          'endsAt': isoUtc(endsAt),
          'timeZone': DeviceTimeZone.current,
          'reminderMinutes': reminderMinutes,
          'overrideConflicts': overrideConflicts,
        },
      ),
    );
    final event = data['event'];
    return CalendarEvent.fromJson(event is Map ? event.cast<String, dynamic>() : data);
  }
}

class AiApi {
  AiApi(this._client);
  final ApiClient _client;

  Future<AiQuota> quota(String calendarId) async =>
      AiQuota.fromJson(_map(await _client.get('/ai/quota', query: {'calendarId': calendarId})));

  Future<List<ConversationSummary>> conversations({String? search}) async {
    final data = await _client.get(
      '/ai/conversations',
      query: {if (search != null && search.isNotEmpty) 'search': search},
    );
    return _list(data).map(ConversationSummary.fromJson).toList();
  }

  Future<Conversation> createConversation({
    required String calendarId,
    String? title,
  }) async => Conversation.fromJson(
    _map(
      await _client.post(
        '/ai/conversations',
        body: {'calendarId': calendarId, 'title': ?title},
      ),
    ),
  );

  Future<Conversation> conversation(String id) async =>
      Conversation.fromJson(_map(await _client.get('/ai/conversations/$id')));

  Future<void> deleteConversation(String id) =>
      _client.delete('/ai/conversations/$id');

  Future<AiTurn> sendMessage({
    required String conversationId,
    required String content,
  }) async => AiTurn.fromJson(
    _map(
      await _client.post(
        '/ai/conversations/$conversationId/messages',
        body: {'content': content},
        timeout: const Duration(seconds: 120),
      ),
    ),
  );

  /// The same turn as [sendMessage], reported while it happens. The stream
  /// always ends in [AiEventKind.done] or [AiEventKind.error]; failures before
  /// the model speaks throw [ApiException] instead, like any other call.
  Stream<AiStreamEvent> streamMessage({
    required String conversationId,
    required String content,
  }) => _client
      .stream(
        '/ai/conversations/$conversationId/messages/stream',
        body: {'content': content},
      )
      .map(AiStreamEvent.fromJson);

  Future<AiTurn> editMessage({
    required String conversationId,
    required String messageId,
    required String content,
  }) async => AiTurn.fromJson(
    _map(
      await _client.patch(
        '/ai/conversations/$conversationId/messages/$messageId',
        body: {'content': content},
      ),
    ),
  );

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) => _client.delete('/ai/conversations/$conversationId/messages/$messageId');

  Future<AiTurn> sendVoiceMessage({
    required String conversationId,
    required String filePath,
    String? voice,
  }) async => AiTurn.fromJson(
    await _client.uploadAudio(
      path: '/ai/conversations/$conversationId/voice-messages',
      filePath: filePath,
      voice: voice,
    ),
  );

  Future<void> confirmAction(String actionId, {bool overrideConflicts = false}) =>
      _client.post(
        '/ai/actions/$actionId/confirm',
        body: {'overrideConflicts': overrideConflicts},
      );

  Future<void> rejectAction(String actionId) =>
      _client.post('/ai/actions/$actionId/reject');
}

class NoteApi {
  NoteApi(this._client);
  final ApiClient _client;

  Future<List<Note>> list({
    String? search,
    String? eventId,
    bool? pinned,
    int limit = 50,
  }) async {
    final data = await _client.get(
      '/notes',
      query: {
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'eventId': ?eventId,
        'pinned': ?pinned,
        'limit': limit,
      },
    );
    return _list(data).map(Note.fromJson).toList();
  }

  Future<Note> get(String id) async =>
      Note.fromJson(_map(await _client.get('/notes/$id')));

  Future<Note> create({
    required String calendarId,
    required String body,
    String? title,
    String? eventId,
    bool pinned = false,
    List<String> tags = const <String>[],
  }) async => Note.fromJson(
    _map(
      await _client.post(
        '/notes',
        body: {
          'calendarId': calendarId,
          'body': body,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          'eventId': ?eventId,
          if (pinned) 'pinned': true,
          if (tags.isNotEmpty) 'tags': tags,
        },
      ),
    ),
  );

  /// Pass [unlinkEvent] to detach the note from the event it was filed under.
  Future<Note> update(
    String id, {
    String? title,
    String? body,
    String? eventId,
    bool unlinkEvent = false,
    bool? pinned,
    List<String>? tags,
  }) async => Note.fromJson(
    _map(
      await _client.patch(
        '/notes/$id',
        body: {
          if (title != null) 'title': title.trim(),
          if (body != null) 'body': body.trim(),
          if (unlinkEvent) 'eventId': null else 'eventId': ?eventId,
          'pinned': ?pinned,
          'tags': ?tags,
        },
      ),
    ),
  );

  Future<void> delete(String id) => _client.delete('/notes/$id');

  /// Uploads a dictated note; the server transcribes it and stores the text.
  Future<Note> createFromVoice({
    required String calendarId,
    required String filePath,
    String? eventId,
  }) async {
    final data = await _client.uploadAudio(
      path: '/notes/voice',
      filePath: filePath,
      fields: {'calendarId': calendarId, 'eventId': ?eventId},
    );
    return Note.fromJson(_map(data['note']));
  }
}

class NotificationApi {
  NotificationApi(this._client);
  final ApiClient _client;

  Future<List<AppNotification>> list({bool? unread, int limit = 50}) async {
    final result = await _client.getPaged(
      '/notifications',
      query: {if (unread == true) 'unread': 'true', 'limit': limit},
    );
    return _list(result.data).map(AppNotification.fromJson).toList();
  }

  Future<void> markRead(String id) => _client.put('/notifications/$id/read');

  Future<void> markAllRead() => _client.put('/notifications/read-all');

  Future<void> remove(String id) => _client.delete('/notifications/$id');

  Future<void> registerDevice({required String token, required String platform}) =>
      _client.post('/devices', body: {'token': token, 'platform': platform});

  Future<void> unregisterDevice(String token) =>
      _client.delete('/devices', body: {'token': token});
}

class MediaApi {
  MediaApi(this._client);
  final ApiClient _client;

  /// Uploads an image and returns its media id.
  Future<String> upload({required String filePath, required String purpose}) async {
    final asset = await _client.uploadImage(filePath: filePath, purpose: purpose);
    return '${asset['_id']}';
  }

  Future<void> remove(String mediaId) => _client.delete('/media/$mediaId');
}

class LegalApi {
  LegalApi(this._client);
  final ApiClient _client;

  Future<List<LegalDocument>> list({String locale = 'en'}) async {
    final data = await _client.get(
      '/legal',
      auth: false,
      query: {'locale': locale},
    );
    return _list(data).map(LegalDocument.fromJson).toList();
  }

  Future<LegalDocument> document(String type, {String locale = 'en'}) async =>
      LegalDocument.fromJson(
        _map(await _client.get('/legal/$type', auth: false, query: {'locale': locale})),
      );

  Future<void> submitSupportRequest({
    required String name,
    required String email,
    required String note,
    String? phone,
    List<String> mediaIds = const <String>[],
  }) => _client.post(
    '/support-requests',
    body: {
      'name': name,
      'email': email,
      'note': note,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (mediaIds.isNotEmpty) 'mediaIds': mediaIds,
    },
  );
}

class SubscriptionApi {
  SubscriptionApi(this._client);
  final ApiClient _client;

  Future<SubscriptionInfo> mine() async =>
      SubscriptionInfo.fromJson(_map(await _client.get('/subscriptions/me')));

  /// Pulls the latest entitlement state from RevenueCat.
  Future<void> reconcile() => _client.post('/subscriptions/reconcile');
}

class DelegationApi {
  DelegationApi(this._client);
  final ApiClient _client;

  Future<Map<String, dynamic>> lookup(String email) async =>
      _map(await _client.post('/delegations/lookup', body: {'email': email}));

  Future<List<Delegation>> list() async =>
      _list(await _client.get('/delegations')).map(Delegation.fromJson).toList();

  Future<Delegation> createForNewAccount({
    required String email,
    required String displayName,
    required String password,
    required String preset,
  }) async => Delegation.fromJson(
    _map(
      await _client.post(
        '/delegations',
        body: {
          'accountType': 'NEW',
          'email': email,
          'displayName': displayName,
          'password': password,
          'preset': preset,
        },
      ),
    ),
  );

  Future<Delegation> createForExistingAccount({
    required String userId,
    required String preset,
  }) async => Delegation.fromJson(
    _map(
      await _client.post(
        '/delegations',
        body: {'accountType': 'EXISTING', 'userId': userId, 'preset': preset},
      ),
    ),
  );

  Future<Delegation> updatePreset(String id, String preset) async =>
      Delegation.fromJson(_map(await _client.patch('/delegations/$id', body: {'preset': preset})));

  Future<void> revoke(String id) => _client.delete('/delegations/$id');
}

/// One handle onto every endpoint group.
class Api {
  Api([ApiClient? client]) : client = client ?? ApiClient() {
    auth = AuthApi(this.client);
    users = UserApi(this.client);
    events = EventApi(this.client);
    network = NetworkApi(this.client);
    ai = AiApi(this.client);
    notes = NoteApi(this.client);
    notifications = NotificationApi(this.client);
    media = MediaApi(this.client);
    legal = LegalApi(this.client);
    subscriptions = SubscriptionApi(this.client);
    delegations = DelegationApi(this.client);
  }

  final ApiClient client;
  late final AuthApi auth;
  late final UserApi users;
  late final EventApi events;
  late final NetworkApi network;
  late final AiApi ai;
  late final NoteApi notes;
  late final NotificationApi notifications;
  late final MediaApi media;
  late final LegalApi legal;
  late final SubscriptionApi subscriptions;
  late final DelegationApi delegations;
}
