import 'package:flutter/material.dart';

import 'api.dart';
import 'api_client.dart';
import 'config.dart';
import 'i18n.dart';
import 'models.dart';
import 'purchases.dart';
import 'push.dart';
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
  CalendarInfo? primaryCalendar;
  List<CalendarInfo> calendars = const <CalendarInfo>[];
  SubscriptionInfo? subscription;

  bool booted = false;
  ApiException? bootstrapError;
  bool onboarded = false;

  /// Set when the session expires mid-session so the shell can bounce to login.
  bool signedOutRemotely = false;

  bool get isSignedIn => user != null && api.client.isAuthenticated;
  bool get isPremium => user?.isPremium ?? false;
  String get calendarId => calendar?.id ?? '';

  /// The name the assistant answers to, before anyone has renamed it.
  static const defaultAssistantName = 'Aurox Day';

  /// What to call the assistant on screen and in the prompt. Falling back
  /// rather than storing the default at signup means a later change to that
  /// default reaches everyone who never picked a name of their own.
  String get assistantName {
    final chosen = user?.assistantName.trim() ?? '';
    return chosen.isEmpty ? defaultAssistantName : chosen;
  }

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
  bool _eventsLoaded = false;
  int _eventRequest = 0;
  int _accountEpoch = 0;

  // --- derived views -----------------------------------------------------

  int get unreadNotifications =>
      notifications.where((item) => !item.read).length;

  /// Shared events that still need a response.
  List<CalendarEvent> get invitations =>
      sharedEvents.where((event) => event.invited).toList();

  List<CalendarEvent> eventsOn(DateTime day) =>
      visibleEvents
          .where(
            (event) =>
                event.occurrenceStartAt.isBefore(
                  DateTime(day.year, day.month, day.day + 1),
                ) &&
                event.occurrenceEndAt.isAfter(DateUtils.dateOnly(day)),
          )
          .toList()
        ..sort((a, b) => a.occurrenceStartAt.compareTo(b.occurrenceStartAt));

  List<CalendarEvent> get todayEvents => eventsOn(DateTime.now());

  List<CalendarEvent> get visibleEvents {
    final rows = <String, CalendarEvent>{};
    for (final event in [...events, ...sharedEvents]) {
      if (event.isShared && event.rsvpStatus == 'DECLINED') continue;
      rows.putIfAbsent(
        '${event.id}/${event.occurrenceOriginalStartAt.toIso8601String()}',
        () => event,
      );
    }
    return rows.values.toList();
  }

  List<CalendarEvent> get upcomingEvents {
    final now = DateTime.now();
    final list =
        [
            ...visibleEvents,
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
    booted = false;
    bootstrapError = null;
    await DeviceTimeZone.resolve();
    onboarded = await api.client.store.onboarded();
    unawaited(loadLegalVersions());
    final session = await api.client.restore();
    if (session != null) {
      try {
        await loadProfile();
      } on ApiException catch (error) {
        if (!api.client.isAuthenticated || error.status == 403) {
          await signOut(callServer: false);
        } else {
          // Preserve the saved login when the network or server is unavailable.
          bootstrapError = error;
        }
      }
      if (isSignedIn) {
        unawaited(PushMessaging.instance.start(this));
        // The session is good; a list that fails to load is not a reason to
        // sign anyone out. Each screen shows it as unloaded and offers a retry.
        await Future.wait([
          for (final load in [loadEvents, loadNetwork, loadNotifications])
            load().catchError((Object _) {}),
        ]);
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
    final epoch = _accountEpoch;
    final me = await api.users.me();
    if (epoch != _accountEpoch) return;
    user = me.user;
    _adoptLanguage();
    primaryCalendar = me.calendar;
    if (calendar == null || calendar!.isOwned) calendar = primaryCalendar;
    if (calendars.isEmpty && primaryCalendar != null) {
      calendars = [primaryCalendar!];
    }
    notifyListeners();
    unawaited(refreshCalendars());
    unawaited(loadSubscription());
    unawaited(_syncCalendarTimeZone());
  }

  /// Keeps the calendar on the phone's time zone.
  ///
  /// Events are stored against the calendar's zone, and nothing in the app
  /// lets the user change it, so a calendar created while travelling — or
  /// before a move — silently schedules everything in the wrong zone. Adopt
  /// the device zone whenever it differs rather than asking anyone to pick.
  Future<void> _syncCalendarTimeZone() async {
    final epoch = _accountEpoch;
    final current = primaryCalendar;
    final device = DeviceTimeZone.current;
    if (current == null || device.isEmpty || current.timeZone == device) return;
    try {
      await api.events.updateSettings(current.id, {'timeZone': device});
      final me = await api.users.me();
      if (epoch != _accountEpoch) return;
      primaryCalendar = me.calendar;
      if (calendar?.id == current.id) calendar = primaryCalendar;
      calendars = [
        for (final item in calendars)
          if (item.id == current.id && primaryCalendar != null)
            primaryCalendar!
          else
            item,
      ];
      notifyListeners();
      await loadEvents(silent: true);
    } on ApiException {
      // Not worth interrupting anyone for; the stored zone still applies.
    }
  }

  Future<void> refreshCalendars() async {
    final epoch = _accountEpoch;
    final all = await api.users.calendars();
    if (epoch != _accountEpoch || all.isEmpty) return;
    final selected = calendar?.id;
    calendars = all;
    final active = all.where((item) => item.id == selected).firstOrNull;
    calendar = active ?? all.first;
    if (selected != null && calendar!.id != selected) {
      _resetEventWindow();
      notifyListeners();
      await loadEvents(silent: true);
    } else {
      notifyListeners();
    }
  }

  Future<void> selectCalendar(CalendarInfo selected) async {
    if (selected.id == calendarId) return;
    calendar = selected;
    _resetEventWindow();
    notifyListeners();
    await loadEvents(silent: true);
  }

  void _resetEventWindow() {
    ++_eventRequest;
    _eventsLoaded = false;
    events = const [];
    sharedEvents = const [];
  }

  Future<void> loadSubscription() async {
    final epoch = _accountEpoch;
    try {
      final loaded = await api.subscriptions.mine();
      if (epoch != _accountEpoch) return;
      subscription = loaded;
      notifyListeners();
      // The store only learns who is buying once the API has said so, which is
      // here: this is the first point at which the account's store id exists.
      final appUserId = subscription?.appUserId ?? '';
      if (appUserId.isNotEmpty) {
        unawaited(StorePurchases.instance.identify(appUserId));
      }
    } on ApiException {
      // Non-fatal.
    }
  }

  // --- authentication ----------------------------------------------------

  Future<void> _adopt(AuthResult result) async {
    _clear();
    await api.client.setSession(result.session);
    user = result.user;
    _adoptLanguage();
    signedOutRemotely = false;
    notifyListeners();
    await loadProfile();
    unawaited(PushMessaging.instance.start(this));
    await Future.wait([
      for (final load in [loadEvents, loadNetwork, loadNotifications])
        load().catchError((Object _) {}),
    ]);
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

  Future<void> signInWithApple({
    required String identityToken,
    String? fullName,
  }) async => _adopt(
    await api.auth.apple(
      identityToken: identityToken,
      fullName: fullName,
      termsVersion: termsVersion,
      privacyVersion: privacyVersion,
    ),
  );

  Future<void> restoreDeletedAccount(String email, String password) async =>
      _adopt(await api.auth.cancelDeletion(email, password));

  Future<void> signOut({bool callServer = true}) async {
    await PushMessaging.instance.stop(api);
    await StorePurchases.instance.forget();
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
    unawaited(PushMessaging.instance.stop(api));
    _clear();
    signedOutRemotely = true;
    notifyListeners();
  }

  void _clear() {
    ++_accountEpoch;
    bootstrapError = null;
    loadingEvents = loadingNetwork = loadingNotifications = loadingNotes =
        false;
    user = null;
    calendar = null;
    primaryCalendar = null;
    _resetEventWindow();
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
    _adoptTimeFormat();
  }

  /// The profile holds the clock format too, so a choice follows the user to
  /// every device, and the server knows the phone's own setting so reminders
  /// and the assistant write times the way this person reads them.
  void _adoptTimeFormat() {
    final current = user;
    if (current == null) return;
    final format = TimeFormat.fromServer(current.timeFormat);
    if (format != ClockFormat.preference) unawaited(ClockFormat.apply(format));
    final device = ClockFormat.deviceUses24Hour;
    if (current.deviceUses24Hour != device) {
      // Fire and forget: nothing on screen depends on it, and the next
      // profile load carries the stored value.
      unawaited(
        api.users
            .updateProfile({'deviceUses24Hour': device})
            .then(
              (_) {},
              onError: (Object _) {
                // Not worth interrupting anyone; the server falls back to the
                // language's usual format.
              },
            ),
      );
    }
  }

  /// Switches the clock format at once, then saves it to the profile.
  Future<void> setTimeFormat(TimeFormat format) async {
    final previous = ClockFormat.preference;
    await ClockFormat.apply(format);
    notifyListeners();
    if (user == null) return;
    try {
      user = await api.users.updateProfile({'timeFormat': format.server});
      notifyListeners();
    } catch (_) {
      await ClockFormat.apply(previous);
      notifyListeners();
      rethrow;
    }
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
    await PushMessaging.instance.start(this, requestPermission: value);
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
    final selected = calendar!;
    final request = ++_eventRequest;
    final window = monthWindow(anchor ?? DateTime.now());
    if (!silent) {
      loadingEvents = true;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        api.events.list(
          calendarId: selected.id,
          from: window.from,
          to: window.to,
        ),
        if (selected.isOwned)
          api.events.shared(from: window.from, to: window.to)
        else
          Future.value(<CalendarEvent>[]),
      ]);
      if (request != _eventRequest || calendarId != selected.id) return;
      events = results[0];
      sharedEvents = results[1];
      // Only a fetch that succeeded counts as loaded. Recording the window up
      // front let a failed load pass for an empty calendar, and the day view
      // then called the whole day free.
      _windowFrom = window.from;
      _windowTo = window.to;
      _eventsLoaded = true;
    } finally {
      if (request == _eventRequest) {
        loadingEvents = false;
        notifyListeners();
      }
    }
  }

  /// Ensures [day] falls inside the loaded window, fetching more if not.
  /// Whether [day]'s events have actually been fetched, so an empty day
  /// really is free rather than unknown.
  bool hasEventsFor(DateTime day) =>
      _eventsLoaded && !day.isBefore(_windowFrom) && day.isBefore(_windowTo);

  Future<void> ensureWindow(DateTime day) async {
    if (hasEventsFor(day)) return;
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
    List<int> reminderMinutes = const <int>[0],
    bool overrideConflicts = false,
    String? groupId,
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
      // Set when the event is being created from inside a group, so it is
      // stored as a group event instead of a personal one (QA F05).
      groupId: groupId,
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
    List<int>? reminderMinutes,
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
      reminderMinutes: reminderMinutes ?? event.reminderMinutes,
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
    List<int>? reminderMinutes,
    bool overrideConflicts = false,
  }) async {
    final result = await api.events.setRecurrenceException(
      eventId: event.id,
      // Must be the untouched recurrence slot, not the moved time: an
      // occurrence that already carries an override no longer matches its
      // own occurrenceStartAt on the server.
      originalStartAt: event.occurrenceOriginalStartAt,
      version: event.version,
      title: title,
      description: description ?? '',
      location: location ?? '',
      startsAt: startsAt,
      endsAt: endsAt,
      reminderMinutes: reminderMinutes,
      overrideConflicts: overrideConflicts,
    );
    await loadEvents(anchor: startsAt, silent: true);
    return result;
  }

  /// Cancels a single occurrence without deleting the series.
  Future<void> cancelOccurrence(CalendarEvent event) async {
    await api.events.setRecurrenceException(
      eventId: event.id,
      // See updateOccurrence: sending occurrenceStartAt here is what made
      // "delete this event" cancel the series origin instead (QA F08).
      originalStartAt: event.occurrenceOriginalStartAt,
      version: event.version,
      cancelled: true,
    );
    await loadEvents(anchor: event.occurrenceStartAt, silent: true);
  }

  Future<void> deleteEvent(CalendarEvent event) async {
    await api.events.delete(event.id, event.version);
    events = events.where((item) => item.id != event.id).toList();
    sharedEvents = sharedEvents.where((item) => item.id != event.id).toList();
    notifyListeners();
  }

  Future<void> setEventCompleted(CalendarEvent event, bool completed) async {
    CalendarEvent updated;
    try {
      updated = await api.events.setCompleted(
        eventId: event.id,
        completed: completed,
        version: event.version,
      );
    } on ApiException catch (error) {
      // The cached __v goes stale as soon as anything else edits the event —
      // saving a note, for instance — and the retry then failed with an alarm
      // even though the tap was valid (QA P04). Re-read and apply once.
      if (!error.isVersionConflict) rethrow;
      final fresh = await api.events.get(event.id);
      updated = fresh.completed == completed
          ? fresh
          : await api.events.setCompleted(
              eventId: event.id,
              completed: completed,
              version: fresh.version,
            );
    }
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
    // Completion is stored on the series, but every expanded row keeps its
    // own date and occurrence identity when that series state changes.
    CalendarEvent replace(CalendarEvent item) => item.id == updated.id
        ? item.copyWith(
            completedAt: updated.completedAt,
            clearCompletedAt: !updated.completed,
            version: updated.version,
          )
        : item;
    events = events.map(replace).toList();
    sharedEvents = sharedEvents.map(replace).toList();
    notifyListeners();
  }

  Future<String> uploadEventPoster(String filePath) =>
      api.media.upload(filePath: filePath, purpose: 'EVENT_POSTER');

  // --- network -----------------------------------------------------------

  Future<void> loadNetwork({bool silent = false}) async {
    final epoch = _accountEpoch;
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
      if (epoch != _accountEpoch) return;
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
    final epoch = _accountEpoch;
    if (!silent) {
      loadingNotes = true;
      notifyListeners();
    }
    try {
      final loaded = await api.notes.list();
      if (epoch == _accountEpoch) notes = loaded;
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
    final epoch = _accountEpoch;
    if (!silent) {
      loadingNotifications = true;
      notifyListeners();
    }
    try {
      final loaded = await api.notifications.list();
      if (epoch == _accountEpoch) notifications = loaded;
    } finally {
      loadingNotifications = false;
      notifyListeners();
    }
  }

  /// The event a notification is about, as the occurrence it names when it
  /// names one. A reminder for a repeating event otherwise opened the first
  /// date of the series instead of the day it was reminding about.
  Future<CalendarEvent?> eventForNotification(
    Map<String, dynamic>? data,
  ) async {
    final eventId = data?['eventId']?.toString();
    if (eventId == null || eventId.isEmpty) return null;
    // Local time, as every event row is: a UTC value would show its UTC hours.
    final startsAt = DateTime.tryParse(
      '${data?['occurrenceStartAt'] ?? ''}',
    )?.toLocal();
    if (startsAt != null) {
      final loaded = [...events, ...sharedEvents].where(
        (item) =>
            item.id == eventId &&
            item.occurrenceStartAt.isAtSameMomentAs(startsAt),
      );
      if (loaded.isNotEmpty) return loaded.first;
    }
    final fresh = await api.events.get(eventId);
    if (startsAt == null || !fresh.isRecurring) return fresh;
    final slot =
        DateTime.tryParse(
          '${data?['occurrenceOriginalStartAt'] ?? ''}',
        )?.toLocal() ??
        startsAt;
    return fresh.copyWith(
      occurrenceStartAt: startsAt,
      occurrenceEndAt: startsAt.add(fresh.endsAt.difference(fresh.startsAt)),
      occurrenceOriginalStartAt: slot,
    );
  }

  /// Marks the notification [id] read, for a tap on a push that never
  /// passed through the in-app list.
  Future<void> markNotificationIdRead(String id) async {
    final item = notifications.where((item) => item.id == id).firstOrNull;
    if (item != null) return markNotificationRead(item);
    await api.notifications.markRead(id);
    await loadNotifications(silent: true);
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
    final epoch = _accountEpoch;
    final loaded = await api.delegations.list();
    if (epoch != _accountEpoch) return;
    delegations = loaded;
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
    final epoch = _accountEpoch;
    final loaded = await api.ai.conversations(search: search);
    if (epoch != _accountEpoch) return;
    conversations = loaded;
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
