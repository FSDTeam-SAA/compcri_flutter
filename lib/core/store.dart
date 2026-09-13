import 'package:flutter/material.dart';

import 'api.dart';
import 'api_client.dart';
import 'config.dart';
import 'i18n.dart';
import 'models.dart';
import 'time.dart';

export 'models.dart';

/// Application state backed by the Compcri API.
///
/// Screens read the cached collections synchronously and call the `load*` /
/// mutation methods to talk to the server. Every mutation updates the cache in
/// place so the UI stays responsive without a full refetch.
class AppStore extends ChangeNotifier {
  AppStore({Api? api}) : api = api ?? Api() {
    this.api.client.onUnauthorized = _handleSignedOut;
  }

  final Api api;

  // --- session -----------------------------------------------------------

  AppUser? user;
  CalendarInfo? calendar;
  List<CalendarInfo> calendars = const <CalendarInfo>[];
  SubscriptionInfo? subscription;

  bool booted = false;
  bool onboarded = false;

  /// Set when the session expires mid-session so the shell can bounce to login.
  bool signedOutRemotely = false;

  bool get isSignedIn => user != null && api.client.isAuthenticated;
  bool get isPremium => user?.isPremium ?? false;
  String get calendarId => calendar?.id ?? '';

  // --- cached collections ------------------------------------------------

  List<CalendarEvent> events = const <CalendarEvent>[];
  List<CalendarEvent> sharedEvents = const <CalendarEvent>[];
  List<Person> contacts = const <Person>[];
  List<ContactRequest> contactRequests = const <ContactRequest>[];
  List<Group> groups = const <Group>[];
  List<GroupInvitation> groupInvitations = const <GroupInvitation>[];
  List<AppNotification> notifications = const <AppNotification>[];
  List<Note> notes = const <Note>[];
  List<Delegation> delegations = const <Delegation>[];
  List<ConversationSummary> conversations = const <ConversationSummary>[];

  /// Terms and privacy versions, needed to register.
  String termsVersion = ApiConfig.fallbackLegalVersion;
  String privacyVersion = ApiConfig.fallbackLegalVersion;

  // --- loading flags -----------------------------------------------------

  bool loadingEvents = false;
  bool loadingNetwork = false;
  bool loadingNotifications = false;
  bool loadingNotes = false;

  /// The window currently held in [events].
  DateTime _windowFrom = DateTime.now();
  DateTime _windowTo = DateTime.now();

  // --- derived views -----------------------------------------------------

  int get unreadNotifications =>
      notifications.where((item) => !item.read).length;

  /// Shared events that still need a response.
  List<CalendarEvent> get invitations =>
      sharedEvents.where((event) => event.invited).toList();

  List<CalendarEvent> eventsOn(DateTime day) =>
      [...events, ...sharedEvents]
          .where((event) => DateUtils.isSameDay(event.occurrenceStartAt, day))
          .toList()
        ..sort((a, b) => a.occurrenceStartAt.compareTo(b.occurrenceStartAt));

  List<CalendarEvent> get todayEvents => eventsOn(DateTime.now());

  List<CalendarEvent> get upcomingEvents {
    final now = DateTime.now();
    final list =
        [
            ...events,
            ...sharedEvents,
          ].where((event) => event.occurrenceEndAt.isAfter(now)).toList()
          ..sort((a, b) => a.occurrenceStartAt.compareTo(b.occurrenceStartAt));
    return list;
  }

  CalendarEvent? eventById(String id) {
    for (final event in [...events, ...sharedEvents]) {
      if (event.id == id) return event;
    }
    return null;
  }

  // --- bootstrap ---------------------------------------------------------

  /// Restores a saved session and loads the first screen's data.
  Future<void> bootstrap() async {
    await DeviceTimeZone.resolve();
    onboarded = await api.client.store.onboarded();
    unawaited(loadLegalVersions());
    final session = await api.client.restore();
    if (session != null) {
      try {
        await loadProfile();
        await Future.wait([loadEvents(), loadNetwork(), loadNotifications()]);
      } on ApiException {
        // A stale or rejected session drops the user back to sign-in.
        await signOut(callServer: false);
      }
    }
    booted = true;
    notifyListeners();
  }

  Future<void> markOnboarded() async {
    onboarded = true;
    await api.client.store.setOnboarded();
  }

  /// Registration needs the active legal versions; fall back if unpublished.
  Future<void> loadLegalVersions() async {
    try {
      final documents = await api.legal.list();
      for (final document in documents) {
        if (document.type == 'TERMS') termsVersion = document.version;
        if (document.type == 'PRIVACY') privacyVersion = document.version;
      }
      notifyListeners();
    } on ApiException {
      // Keep the defaults; registration will surface a clear error if wrong.
    }
  }

  Future<void> loadProfile() async {
    final me = await api.users.me();
    user = me.user;
    _adoptLanguage();
    calendar = me.calendar;
    if (calendar != null) {
      calendars = [calendar!];
    }
    notifyListeners();
    unawaited(_loadCalendars());
    unawaited(loadSubscription());
  }

  Future<void> _loadCalendars() async {
    try {
      final all = await api.users.calendars();
      if (all.isEmpty) return;
      calendars = all;
      calendar ??= all.first;
      notifyListeners();
    } on ApiException {
      // Non-fatal: the primary calendar from /users/me is enough.
    }
  }

  Future<void> loadSubscription() async {
    try {
      subscription = await api.subscriptions.mine();
      notifyListeners();
    } on ApiException {
      // Non-fatal.
    }
  }

  // --- authentication ----------------------------------------------------

  Future<void> _adopt(AuthResult result) async {
    await api.client.setSession(result.session);
    user = result.user;
    _adoptLanguage();
    signedOutRemotely = false;
    notifyListeners();
    await loadProfile();
    await Future.wait([loadEvents(), loadNetwork(), loadNotifications()]);
  }

  Future<void> signIn(String email, String password) async =>
      _adopt(await api.auth.login(email, password));

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async => _adopt(
    await api.auth.register(
      email: email,
      password: password,
      displayName: displayName,
      termsVersion: termsVersion,
      privacyVersion: privacyVersion,
    ),
  );

  Future<void> signInWithGoogle(String idToken) async => _adopt(
    await api.auth.google(
      idToken: idToken,
      termsVersion: termsVersion,
      privacyVersion: privacyVersion,
    ),
  );

  Future<void> restoreDeletedAccount(String email, String password) async =>
      _adopt(await api.auth.cancelDeletion(email, password));

  Future<void> signOut({bool callServer = true}) async {
    final refreshToken = api.client.session?.refreshToken;
    if (callServer && refreshToken != null) {
      try {
        await api.auth.logout(refreshToken);
      } on ApiException {
        // Signing out locally matters more than the server round trip.
      }
    }
    await api.client.clearSession();
    _clear();
    notifyListeners();
  }

  void _handleSignedOut() {
    _clear();
    signedOutRemotely = true;
    notifyListeners();
  }

  void _clear() {
    user = null;
    calendar = null;
    calendars = const <CalendarInfo>[];
    subscription = null;
    events = const <CalendarEvent>[];
    sharedEvents = const <CalendarEvent>[];
    contacts = const <Person>[];
    contactRequests = const <ContactRequest>[];
    groups = const <Group>[];
    groupInvitations = const <GroupInvitation>[];
    notifications = const <AppNotification>[];
    notes = const <Note>[];
    delegations = const <Delegation>[];
    conversations = const <ConversationSummary>[];
  }

  // --- profile -----------------------------------------------------------

  Future<void> updateProfile(Map<String, dynamic> changes) async {
    user = await api.users.updateProfile(changes);
    _adoptLanguage();
    notifyListeners();
  }

  /// The profile holds the language, so it follows the user to every device
  /// and the server answers — errors, notifications, emails — in it too.
  void _adoptLanguage() {
    final code = user?.locale;
    if (code != null && code != I18n.locale) unawaited(I18n.apply(code));
  }

  Future<void> updateAvatar(String filePath) async {
    final mediaId = await api.media.upload(
      filePath: filePath,
      purpose: 'AVATAR',
    );
    await updateProfile({'avatarMediaId': mediaId});
  }

  Future<void> changePassword(String current, String next) async {
    await api.users.changePassword(current, next);
    // The server revokes every session, including this one.
    await api.client.clearSession();
    _clear();
    notifyListeners();
  }

  Future<void> setNotificationPreference(String label, bool value) async {
    final key = NotificationPreferences.labelKeys[label];
    if (key == null) return;
    user = await api.users.updateNotificationPreferences({key: value});
    notifyListeners();
  }

  Future<void> setLanguage(String label) =>
      updateProfile({'locale': AppUser.localeForLabel(label)});

  Future<Map<String, dynamic>> deleteAccount({
    required String password,
    required String reason,
  }) async {
    final result = await api.users.requestDeletion(
      password: password,
      reason: reason,
    );
    await api.client.clearSession();
    _clear();
    notifyListeners();
    return result;
  }

  // --- events ------------------------------------------------------------

  Future<void> loadEvents({DateTime? anchor, bool silent = false}) async {
    if (calendarId.isEmpty) return;
    final window = monthWindow(anchor ?? DateTime.now());
    _windowFrom = window.from;
    _windowTo = window.to;
    if (!silent) {
      loadingEvents = true;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        api.events.list(
          calendarId: calendarId,
          from: window.from,
          to: window.to,
        ),
        api.events.shared(from: window.from, to: window.to),
      ]);
      events = results[0];
      sharedEvents = results[1];
    } finally {
      loadingEvents = false;
      notifyListeners();
    }
  }

  /// Ensures [day] falls inside the loaded window, fetching more if not.
  Future<void> ensureWindow(DateTime day) async {
    if (day.isAfter(_windowFrom) && day.isBefore(_windowTo)) return;
    await loadEvents(anchor: day, silent: true);
  }

  Future<EventMutation> createEvent({
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? description,
    String? location,
    String? posterMediaId,
    String? recurrenceRrule,
    List<int> reminderMinutes = const <int>[],
    bool overrideConflicts = false,
  }) async {
    final result = await api.events.create(
      calendarId: calendarId,
      title: title,
      startsAt: startsAt,
      endsAt: endsAt,
      description: description,
      location: location,
      posterMediaId: posterMediaId,
      recurrenceRrule: recurrenceRrule,
      reminderMinutes: reminderMinutes,
      timeZone: calendar?.timeZone ?? DeviceTimeZone.current,
      overrideConflicts: overrideConflicts,
    );
    await loadEvents(anchor: startsAt, silent: true);
    return result;
  }

  Future<EventMutation> updateEvent({
    required CalendarEvent event,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? description,
    String? location,
    Object? posterMediaId,
    String? recurrenceRrule,
    List<int> reminderMinutes = const <int>[],
    bool overrideConflicts = false,
  }) async {
    final result = await api.events.update(
      eventId: event.id,
      version: event.version,
      title: title,
      description: description ?? '',
      location: location ?? '',
      posterMediaId: posterMediaId,
      startsAt: startsAt,
      endsAt: endsAt,
      timeZone: event.timeZone,
      reminderMinutes: reminderMinutes,
      recurrenceRrule: recurrenceRrule,
      overrideConflicts: overrideConflicts,
    );
    await loadEvents(anchor: startsAt, silent: true);
    return result;
  }

  /// Edits just this occurrence of a recurring event, leaving the series alone.
  Future<EventMutation> updateOccurrence({
    required CalendarEvent event,
    required String title,
    required DateTime startsAt,
    required DateTime endsAt,
    String? description,
    String? location,
    bool overrideConflicts = false,
  }) async {
    final result = await api.events.setRecurrenceException(
      eventId: event.id,
      originalStartAt: event.occurrenceStartAt,
      version: event.version,
      title: title,
      description: description ?? '',
      location: location ?? '',
      startsAt: startsAt,
      endsAt: endsAt,
      overrideConflicts: overrideConflicts,
    );
    await loadEvents(anchor: startsAt, silent: true);
    return result;
  }

  /// Cancels a single occurrence without deleting the series.
  Future<void> cancelOccurrence(CalendarEvent event) async {
    await api.events.setRecurrenceException(
      eventId: event.id,
      originalStartAt: event.occurrenceStartAt,
      version: event.version,
      cancelled: true,
    );
    await loadEvents(anchor: event.occurrenceStartAt, silent: true);
  }

  Future<void> deleteEvent(CalendarEvent event) async {
    await api.events.delete(event.id, event.version);
    events = events.where((item) => item.id != event.id).toList();
    notifyListeners();
  }

  Future<void> setEventCompleted(CalendarEvent event, bool completed) async {
    final updated = await api.events.setCompleted(
      eventId: event.id,
      completed: completed,
      version: event.version,
    );
    // The endpoint returns the stored document, which carries no expanded
    // occurrence. Keep this row's occurrence times so a recurring event does
    // not jump back to the start of its series.
    _replaceEvent(
      event.copyWith(
        completedAt: updated.completedAt,
        clearCompletedAt: !completed,
        version: updated.version,
      ),
    );
  }

  Future<void> respondToInvitation(CalendarEvent event, String status) async {
    await api.events.rsvp(event.id, status);
    sharedEvents = sharedEvents
        .map(
          (item) =>
              item.id == event.id ? item.copyWith(rsvpStatus: status) : item,
        )
        .toList();
    notifyListeners();
  }

  Future<void> shareEvent({
    required CalendarEvent event,
    required String targetType,
    required List<String> targetIds,
    required String permission,
  }) => api.events.share(
    eventId: event.id,
    targetType: targetType,
    targetIds: targetIds,
    permission: permission,
  );

  void _replaceEvent(CalendarEvent updated) {
    events = events
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    notifyListeners();
  }

  Future<String> uploadEventPoster(String filePath) =>
      api.media.upload(filePath: filePath, purpose: 'EVENT_POSTER');

  // --- network -----------------------------------------------------------

  Future<void> loadNetwork({bool silent = false}) async {
    if (!silent) {
      loadingNetwork = true;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        api.network.contacts(),
        api.network.contactRequests(),
        api.network.groups(),
        api.network.groupInvitations(),
      ]);
      contacts = results[0] as List<Person>;
      contactRequests = results[1] as List<ContactRequest>;
      groups = results[2] as List<Group>;
      groupInvitations = results[3] as List<GroupInvitation>;
    } finally {
      loadingNetwork = false;
      notifyListeners();
    }
  }

  Future<void> sendContactRequest(String code, String relation) async {
    await api.network.sendContactRequest(contactCode: code, relation: relation);
    await loadNetwork(silent: true);
  }

  Future<void> respondToContactRequest(
    ContactRequest request,
    bool accept, {
    String? relation,
  }) async {
    await api.network.respondToContactRequest(
      requestId: request.id,
      accept: accept,
      relation: relation,
    );
    await loadNetwork(silent: true);
  }

  Future<void> removeContact(Person person) async {
    await api.network.removeContact(person.id);
    contacts = contacts.where((item) => item.id != person.id).toList();
    notifyListeners();
  }

  Future<void> updateContactRelation(Person person, String relation) async {
    await api.network.updateContactRelation(person.id, relation);
    await loadNetwork(silent: true);
  }

  Future<void> createGroup(String name) async {
    await api.network.createGroup(name);
    await loadNetwork(silent: true);
  }

  Future<void> joinGroup(String code) async {
    await api.network.joinGroup(code);
    await loadNetwork(silent: true);
  }

  Future<void> leaveGroup(Group group) async {
    await api.network.leaveGroup(group.id);
    groups = groups.where((item) => item.id != group.id).toList();
    notifyListeners();
  }

  Future<void> respondToGroupInvitation(
    GroupInvitation invitation,
    bool accept,
  ) async {
    await api.network.respondToGroupInvitation(
      invitationId: invitation.id,
      accept: accept,
    );
    await loadNetwork(silent: true);
  }

  // --- notes -------------------------------------------------------------

  /// Notes filed against one event, in the cache's order: pinned first,
  /// then most recently edited.
  List<Note> notesForEvent(String eventId) =>
      notes.where((note) => note.eventId == eventId).toList();

  Future<void> loadNotes({bool silent = false}) async {
    if (!silent) {
      loadingNotes = true;
      notifyListeners();
    }
    try {
      notes = await api.notes.list();
    } finally {
      loadingNotes = false;
      notifyListeners();
    }
  }

  Future<List<Note>> searchNotes(String term) => api.notes.list(search: term);

  Future<Note> createNote({
    required String body,
    String? title,
    String? eventId,
    bool pinned = false,
  }) async {
    final note = await api.notes.create(
      calendarId: calendarId,
      body: body,
      title: title,
      eventId: eventId,
      pinned: pinned,
    );
    notes = [note, ...notes];
    notifyListeners();
    return note;
  }

  /// Uploads a recording; the server transcribes it into the note body.
  Future<Note> createVoiceNote({
    required String filePath,
    String? eventId,
  }) async {
    final note = await api.notes.createFromVoice(
      calendarId: calendarId,
      filePath: filePath,
      eventId: eventId,
    );
    notes = [note, ...notes];
    notifyListeners();
    return note;
  }

  Future<Note> updateNote(
    Note note, {
    String? title,
    String? body,
    String? eventId,
    bool unlinkEvent = false,
    bool? pinned,
  }) async {
    final updated = await api.notes.update(
      note.id,
      title: title,
      body: body,
      eventId: eventId,
      unlinkEvent: unlinkEvent,
      pinned: pinned,
    );
    _replaceNote(updated);
    return updated;
  }

  Future<void> togglePinned(Note note) =>
      updateNote(note, pinned: !note.pinned);

  Future<void> deleteNote(Note note) async {
    await api.notes.delete(note.id);
    notes = notes.where((item) => item.id != note.id).toList();
    notifyListeners();
  }

  /// Keeps the cache in the server's order after an edit.
  void _replaceNote(Note updated) {
    notes =
        [
          for (final note in notes)
            if (note.id == updated.id) updated else note,
        ]..sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          final left = a.updatedAt ?? a.createdAt;
          final right = b.updatedAt ?? b.createdAt;
          if (left == null || right == null) return 0;
          return right.compareTo(left);
        });
    notifyListeners();
  }

  // --- notifications -----------------------------------------------------

  Future<void> loadNotifications({bool silent = false}) async {
    if (!silent) {
      loadingNotifications = true;
      notifyListeners();
    }
    try {
      notifications = await api.notifications.list();
    } finally {
      loadingNotifications = false;
      notifyListeners();
    }
  }

  Future<void> markNotificationRead(AppNotification item) async {
    if (item.read) return;
    await api.notifications.markRead(item.id);
    notifications = notifications
        .map(
          (current) => current.id == item.id
              ? AppNotification(
                  id: current.id,
                  title: current.title,
                  body: current.body,
                  category: current.category,
                  readAt: DateTime.now(),
                  createdAt: current.createdAt,
                  data: current.data,
                )
              : current,
        )
        .toList();
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    await api.notifications.markAllRead();
    await loadNotifications(silent: true);
  }

  Future<void> deleteNotification(AppNotification item) async {
    await api.notifications.remove(item.id);
    notifications = notifications.where((n) => n.id != item.id).toList();
    notifyListeners();
  }

  // --- delegations (secretary access) ------------------------------------

  Future<void> loadDelegations() async {
    delegations = await api.delegations.list();
    notifyListeners();
  }

  Future<void> revokeDelegation(Delegation delegation) async {
    await api.delegations.revoke(delegation.id);
    delegations = delegations
        .where((item) => item.id != delegation.id)
        .toList();
    notifyListeners();
  }

  // --- AI ----------------------------------------------------------------

  Future<void> loadConversations({String? search}) async {
    conversations = await api.ai.conversations(search: search);
    notifyListeners();
  }
}

/// Fire-and-forget helper that documents the intent at the call site.
void unawaited(Future<void> future) {
  future.catchError((Object _) {});
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required super.notifier, required super.child});

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  /// Reads the store without subscribing to rebuilds.
  static AppStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
