import 'package:flutter/material.dart';
import 'i18n.dart';

/// Helpers shared by every model.
String? _id(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is Map) return value['_id']?.toString();
  return value.toString();
}

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse('$value')?.toLocal();

String _string(dynamic value, [String fallback = '']) =>
    value == null ? fallback : '$value';

List<String> _strings(dynamic value) =>
    value is List ? value.map((item) => '$item').toList() : const <String>[];

/// A Cloudinary-backed image. The API populates `avatarMediaId` and
/// `posterMediaId` when it can, and leaves a bare id when it cannot.
class MediaAsset {
  const MediaAsset({required this.id, required this.secureUrl});

  final String id;
  final String secureUrl;

  static MediaAsset? parse(dynamic value) {
    if (value == null) return null;
    if (value is Map && value['secureUrl'] != null) {
      return MediaAsset(
        id: _string(value['_id']),
        secureUrl: _string(value['secureUrl']),
      );
    }
    return null;
  }

  static Map<String, dynamic> toJsonMap(Map<String, dynamic> json) => json;
}

class NotificationPreferences {
  const NotificationPreferences({
    this.pushEnabled = true,
    this.reminders = true,
    this.invitations = true,
    this.groupUpdates = true,
    this.contactRequests = true,
    this.subscriptionUpdates = true,
  });

  final bool pushEnabled,
      reminders,
      invitations,
      groupUpdates,
      contactRequests,
      subscriptionUpdates;

  factory NotificationPreferences.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    bool read(String key) => data[key] as bool? ?? true;
    return NotificationPreferences(
      pushEnabled: read('pushEnabled'),
      reminders: read('reminders'),
      invitations: read('invitations'),
      groupUpdates: read('groupUpdates'),
      contactRequests: read('contactRequests'),
      subscriptionUpdates: read('subscriptionUpdates'),
    );
  }

  /// The switch rows the settings screen renders, in display order.
  Map<String, bool> get asLabels => {
    'Push Notifications': pushEnabled,
    'Event Reminders': reminders,
    'Invitation Alerts': invitations,
    'Group Updates': groupUpdates,
    'New Contact Requests': contactRequests,
    'Subscription Updates': subscriptionUpdates,
  };

  static const labelKeys = {
    'Push Notifications': 'pushEnabled',
    'Event Reminders': 'reminders',
    'Invitation Alerts': 'invitations',
    'Group Updates': 'groupUpdates',
    'New Contact Requests': 'contactRequests',
    'Subscription Updates': 'subscriptionUpdates',
  };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.displayName = '',
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.profession = '',
    this.country = '',
    this.city = '',
    this.locale = 'en',
    this.interests = const <String>[],
    this.aiPersonalizationConsent = false,
    this.avatar,
    this.contactCode = '',
    this.plan = 'FREE',
    this.premiumUntil,
    this.status = 'ACTIVE',
    this.notificationPreferences = const NotificationPreferences(),
  });

  final String id, email, displayName, firstName, lastName;
  final String phone,
      profession,
      country,
      city,
      locale,
      contactCode,
      plan,
      status;
  final List<String> interests;
  final bool aiPersonalizationConsent;
  final MediaAsset? avatar;
  final DateTime? premiumUntil;
  final NotificationPreferences notificationPreferences;

  bool get isPremium =>
      plan == 'PREMIUM' &&
      (premiumUntil == null || premiumUntil!.isAfter(DateTime.now()));

  String get firstNameOrEmail {
    if (displayName.trim().isNotEmpty) {
      return displayName.trim().split(' ').first;
    }
    if (firstName.trim().isNotEmpty) return firstName.trim();
    return email.split('@').first;
  }

  String get name => displayName.trim().isNotEmpty
      ? displayName.trim()
      : [firstName, lastName].where((part) => part.isNotEmpty).join(' ').trim();

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: _string(json['_id']),
    email: _string(json['email']),
    displayName: _string(json['displayName']),
    firstName: _string(json['firstName']),
    lastName: _string(json['lastName']),
    phone: _string(json['phone']),
    profession: _string(json['profession']),
    country: _string(json['country']),
    city: _string(json['city']),
    locale: _string(json['locale'], 'en'),
    interests: _strings(json['interests']),
    aiPersonalizationConsent:
        json['aiPersonalizationConsent'] as bool? ?? false,
    avatar: MediaAsset.parse(json['avatarMediaId']),
    contactCode: _string(json['contactCode']),
    plan: _string(json['plan'], 'FREE'),
    premiumUntil: _date(json['premiumUntil']),
    status: _string(json['status'], 'ACTIVE'),
    notificationPreferences: NotificationPreferences.fromJson(
      json['notificationPreferences'] as Map<String, dynamic>?,
    ),
  );

  static const locales = {'en': 'English', 'pt': 'Português', 'es': 'Español'};

  String get languageLabel => locales[locale] ?? 'English';

  static String localeForLabel(String label) => locales.entries
      .firstWhere(
        (entry) => entry.value == label,
        orElse: () => const MapEntry('en', 'English'),
      )
      .key;
}

class CalendarAvailability {
  const CalendarAvailability({
    this.workingDays = const [1, 2, 3, 4, 5],
    this.workdayStart = '09:00',
    this.workdayEnd = '17:00',
  });

  final List<int> workingDays;
  final String workdayStart, workdayEnd;

  factory CalendarAvailability.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    final days = data['workingDays'];
    return CalendarAvailability(
      workingDays: days is List
          ? days.map((day) => (day as num).toInt()).toList()
          : const [1, 2, 3, 4, 5],
      workdayStart: _string(data['workdayStart'], '09:00'),
      workdayEnd: _string(data['workdayEnd'], '17:00'),
    );
  }

  Map<String, dynamic> toJson() => {
    'workingDays': workingDays,
    'workdayStart': workdayStart,
    'workdayEnd': workdayEnd,
  };
}

class CalendarInfo {
  const CalendarInfo({
    required this.id,
    required this.name,
    required this.timeZone,
    this.ownerId,
    this.ownerName = '',
    this.preset = 'OWNER',
    this.delegationId,
    this.availability = const CalendarAvailability(),
  });

  final String id, name, timeZone, preset, ownerName;
  final String? ownerId, delegationId;
  final CalendarAvailability availability;

  bool get isOwned => preset == 'OWNER';

  factory CalendarInfo.fromJson(
    Map<String, dynamic> json, {
    String preset = 'OWNER',
    String? delegationId,
  }) {
    final owner = json['ownerId'];
    return CalendarInfo(
      id: _string(json['_id'], _string(json['calendarId'])),
      name: _string(json['name'], 'Calendar'),
      timeZone: _string(json['timeZone'], 'UTC'),
      ownerId: _id(owner),
      ownerName: owner is Map ? _string(owner['displayName']) : '',
      preset: preset,
      delegationId: delegationId,
      availability: CalendarAvailability.fromJson(
        json['availability'] as Map<String, dynamic>?,
      ),
    );
  }
}

/// One event, or one expanded occurrence of a recurring event.
class CalendarEvent {
  CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    DateTime? occurrenceStartAt,
    DateTime? occurrenceEndAt,
    DateTime? occurrenceOriginalStartAt,
    this.createdById = '',
    this.description = '',
    this.location = '',
    this.timeZone = 'UTC',
    this.reminderMinutes = const <int>[],
    this.recurrenceRrule,
    this.poster,
    this.groupId,
    this.completedAt,
    this.version = 0,
    this.sharePermission,
    this.shareSource,
    this.rsvpStatus,
    this.canEdit = true,
    this.canDelete = true,
    this.canRespond = false,
  }) : occurrenceStartAt = occurrenceStartAt ?? startsAt,
       occurrenceEndAt = occurrenceEndAt ?? endsAt,
       occurrenceOriginalStartAt =
           occurrenceOriginalStartAt ?? occurrenceStartAt ?? startsAt;

  final String id, calendarId, createdById;
  final String title, description, location, timeZone;

  /// The series anchor. For a recurring event this is the first occurrence.
  final DateTime startsAt, endsAt;

  /// The instant this particular row represents.
  final DateTime occurrenceStartAt, occurrenceEndAt;

  /// The untouched recurrence slot this row was generated from. Equal to
  /// [occurrenceStartAt] until the occurrence is moved, after which only this
  /// value still identifies the date to the API. Always send it as
  /// `originalStartAt` when editing or cancelling a single occurrence.
  final DateTime occurrenceOriginalStartAt;

  final List<int> reminderMinutes;
  final String? recurrenceRrule, groupId;
  final MediaAsset? poster;
  final DateTime? completedAt;

  /// Mongoose `__v`, required by every mutating endpoint.
  final int version;

  final String? sharePermission, shareSource, rsvpStatus;
  final bool canEdit, canDelete, canRespond;

  bool get completed => completedAt != null;
  bool get hasPoster => poster != null;
  bool get isRecurring =>
      recurrenceRrule != null && recurrenceRrule!.trim().isNotEmpty;

  /// True when this row came from someone else's calendar.
  bool get isShared => sharePermission != null;

  /// Shared events awaiting a response drive the invitation UI.
  bool get invited =>
      isShared && (rsvpStatus == null || rsvpStatus == 'PENDING');

  // --- view helpers ------------------------------------------------------

  DateTime get date => DateUtils.dateOnly(occurrenceStartAt);
  TimeOfDay get start => TimeOfDay.fromDateTime(occurrenceStartAt);
  TimeOfDay get end => TimeOfDay.fromDateTime(occurrenceEndAt);

  String get reminder => reminderLabel(reminderMinutes);
  String get repeat => repeatLabel(recurrenceRrule);

  factory CalendarEvent.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? permissions,
  }) {
    final startsAt = _date(json['startsAt']) ?? DateTime.now();
    final endsAt =
        _date(json['endsAt']) ?? startsAt.add(const Duration(hours: 1));
    final reminders = json['reminderMinutes'];
    return CalendarEvent(
      id: _string(json['_id']),
      calendarId: _string(_id(json['calendarId'])),
      createdById: _string(_id(json['createdById'])),
      title: _string(json['title']),
      description: _string(json['description']),
      location: _string(json['location']),
      timeZone: _string(json['timeZone'], 'UTC'),
      startsAt: startsAt,
      endsAt: endsAt,
      occurrenceStartAt: _date(json['occurrenceStartAt']) ?? startsAt,
      occurrenceEndAt: _date(json['occurrenceEndAt']) ?? endsAt,
      occurrenceOriginalStartAt: _date(json['occurrenceOriginalStartAt']),
      reminderMinutes: reminders is List
          ? reminders.map((value) => (value as num).toInt()).toList()
          : const <int>[],
      recurrenceRrule: json['recurrenceRrule'] as String?,
      poster: MediaAsset.parse(json['posterMediaId']),
      groupId: _id(json['groupId']),
      completedAt: _date(json['completedAt']),
      version: (json['__v'] as num?)?.toInt() ?? 0,
      sharePermission: json['sharePermission'] as String?,
      shareSource: json['shareSource'] as String?,
      rsvpStatus: json['rsvpStatus'] as String?,
      canEdit: permissions?['edit'] as bool? ?? true,
      canDelete: permissions?['delete'] as bool? ?? true,
      canRespond: permissions?['respond'] as bool? ?? false,
    );
  }

  CalendarEvent copyWith({
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? rsvpStatus,
    int? version,
    DateTime? occurrenceStartAt,
    DateTime? occurrenceEndAt,
    DateTime? occurrenceOriginalStartAt,
  }) => CalendarEvent(
    id: id,
    calendarId: calendarId,
    createdById: createdById,
    title: title,
    description: description,
    location: location,
    timeZone: timeZone,
    startsAt: startsAt,
    endsAt: endsAt,
    occurrenceStartAt: occurrenceStartAt ?? this.occurrenceStartAt,
    occurrenceEndAt: occurrenceEndAt ?? this.occurrenceEndAt,
    occurrenceOriginalStartAt:
        occurrenceOriginalStartAt ?? this.occurrenceOriginalStartAt,
    reminderMinutes: reminderMinutes,
    recurrenceRrule: recurrenceRrule,
    poster: poster,
    groupId: groupId,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    version: version ?? this.version,
    sharePermission: sharePermission,
    shareSource: shareSource,
    rsvpStatus: rsvpStatus ?? this.rsvpStatus,
    canEdit: canEdit,
    canDelete: canDelete,
    canRespond: canRespond,
  );

  // --- label mapping -----------------------------------------------------

  static const reminderOptions = ['None', '10 Minutes', '30 Minutes', '1 Hour'];
  static const repeatOptions = ['Never', 'Daily', 'Weekly', 'Monthly'];

  static String reminderLabel(List<int> minutes) {
    if (minutes.isEmpty) return 'None';
    switch (minutes.first) {
      case 10:
        return '10 Minutes';
      case 30:
        return '30 Minutes';
      case 60:
        return '1 Hour';
      default:
        return '${minutes.first} Minutes';
    }
  }

  static List<int> minutesForLabel(String label) {
    switch (label) {
      case '10 Minutes':
        return [10];
      case '30 Minutes':
        return [30];
      case '1 Hour':
        return [60];
      default:
        return const <int>[];
    }
  }

  static String repeatLabel(String? rrule) {
    final value = rrule?.toUpperCase() ?? '';
    if (value.contains('FREQ=DAILY')) return 'Daily';
    if (value.contains('FREQ=WEEKLY')) return 'Weekly';
    if (value.contains('FREQ=MONTHLY')) return 'Monthly';
    if (value.contains('FREQ=YEARLY')) return 'Yearly';
    return 'Never';
  }

  static String? rruleForLabel(String label) {
    switch (label) {
      case 'Daily':
        return 'RRULE:FREQ=DAILY';
      case 'Weekly':
        return 'RRULE:FREQ=WEEKLY';
      case 'Monthly':
        return 'RRULE:FREQ=MONTHLY';
      case 'Yearly':
        return 'RRULE:FREQ=YEARLY';
      default:
        return null;
    }
  }
}

/// A conflicting occurrence reported by `EVENT_CONFLICT`.
class EventConflict {
  const EventConflict({
    required this.title,
    required this.startsAt,
    required this.endsAt,
  });

  final String title;
  final DateTime startsAt, endsAt;

  factory EventConflict.fromJson(Map<String, dynamic> json) => EventConflict(
    title: _string(json['title'], 'Untitled event'),
    startsAt: _date(json['startsAt']) ?? DateTime.now(),
    endsAt: _date(json['endsAt']) ?? DateTime.now(),
  );

  static List<EventConflict> listFrom(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => EventConflict.fromJson(item.cast<String, dynamic>()))
            .toList()
      : const <EventConflict>[];
}

/// A free slot suggested alongside a conflict.
class TimeSlot {
  const TimeSlot({
    required this.startsAt,
    required this.endsAt,
    this.reason = 'FREE_SLOT',
  });

  final DateTime startsAt, endsAt;

  /// Why it was suggested: `AFTER_CONFLICT`, `BEFORE_CONFLICT` or `FREE_SLOT`.
  final String reason;

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
    startsAt: _date(json['startsAt']) ?? DateTime.now(),
    endsAt: _date(json['endsAt']) ?? DateTime.now(),
    reason: _string(json['reason'], 'FREE_SLOT'),
  );

  static List<TimeSlot> listFrom(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => TimeSlot.fromJson(item.cast<String, dynamic>()))
            .toList()
      : const <TimeSlot>[];
}

/// The verdict on a proposed time: what it overlaps, and the nearest free
/// times instead. [enforced] means saving it anyway takes an explicit override.
class ConflictReport {
  const ConflictReport({
    this.conflicts = const <EventConflict>[],
    this.alternatives = const <TimeSlot>[],
    this.enforced = true,
  });

  final List<EventConflict> conflicts;
  final List<TimeSlot> alternatives;
  final bool enforced;

  bool get clear => conflicts.isEmpty;

  factory ConflictReport.fromJson(Map<String, dynamic> json) => ConflictReport(
    conflicts: EventConflict.listFrom(json['conflicts']),
    alternatives: TimeSlot.listFrom(json['alternatives']),
    enforced: json['enforced'] != false,
  );
}

/// A person in the address book: contact, group member, or assistant.
class Person {
  const Person({
    required this.id,
    required this.name,
    this.relation = '',
    this.email = '',
    this.phone = '',
    this.profession = '',
    this.country = '',
    this.city = '',
    this.contactCode = '',
    this.avatar,
    this.role,
  });

  final String id, name, relation, email, phone, profession, country, city;
  final String contactCode;
  final MediaAsset? avatar;
  final String? role;

  /// Deterministic index into the bundled placeholder avatars.
  int get avatarIndex =>
      id.isEmpty ? 0 : id.codeUnits.fold(0, (a, b) => a + b) % 6;

  factory Person.fromUser(Map<String, dynamic> json, {String relation = ''}) =>
      Person(
        id: _string(json['_id']),
        name: _string(json['displayName']).trim().isEmpty
            ? _string(json['email']).split('@').first
            : _string(json['displayName']),
        relation: relation,
        email: _string(json['email']),
        phone: _string(json['phone']),
        profession: _string(json['profession']),
        country: _string(json['country']),
        city: _string(json['city']),
        contactCode: _string(json['contactCode']),
        avatar: MediaAsset.parse(json['avatarMediaId']),
      );

  /// `GET /contacts` returns `{ user, relation }` pairs.
  factory Person.fromContact(Map<String, dynamic> json) => Person.fromUser(
    (json['user'] as Map).cast<String, dynamic>(),
    relation: _string(json['relation']),
  );
}

class ContactRequest {
  const ContactRequest({
    required this.id,
    required this.person,
    required this.incoming,
    this.relation = '',
    this.createdAt,
  });

  final String id;
  final Person person;
  final bool incoming;
  final String relation;
  final DateTime? createdAt;

  factory ContactRequest.fromJson(
    Map<String, dynamic> json, {
    required bool incoming,
  }) {
    final counterpart = incoming ? json['senderId'] : json['receiverId'];
    return ContactRequest(
      id: _string(json['_id']),
      incoming: incoming,
      relation: _string(json['senderRelation']),
      createdAt: _date(json['createdAt']),
      person: counterpart is Map
          ? Person.fromUser(counterpart.cast<String, dynamic>())
          : Person(id: _string(_id(counterpart)), name: 'Unknown'),
    );
  }
}

class GroupMember {
  const GroupMember({required this.person, required this.role});

  final Person person;
  final String role;

  bool get isOwner => role == 'OWNER';

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    final user = json['userId'];
    return GroupMember(
      role: _string(json['role'], 'MEMBER'),
      person: user is Map
          ? Person.fromUser(user.cast<String, dynamic>())
          : Person(id: _string(_id(user)), name: 'Member'),
    );
  }
}

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.code,
    this.ownerId = '',
    this.members = const <GroupMember>[],
    this.memberCount = 0,
  });

  final String id, name, code, ownerId;
  final List<GroupMember> members;
  final int memberCount;

  bool isOwnedBy(String? userId) => userId != null && ownerId == userId;

  factory Group.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'];
    final members = rawMembers is List
        ? rawMembers
              .whereType<Map>()
              .map((item) => GroupMember.fromJson(item.cast<String, dynamic>()))
              .toList()
        : const <GroupMember>[];
    return Group(
      id: _string(json['_id']),
      name: _string(json['name']),
      code: _string(json['code']),
      ownerId: _string(_id(json['ownerId'])),
      members: members,
      memberCount: rawMembers is List ? rawMembers.length : 0,
    );
  }
}

class GroupInvitation {
  const GroupInvitation({
    required this.id,
    required this.groupName,
    required this.groupId,
    this.role = 'MEMBER',
  });

  final String id, groupName, groupId, role;

  factory GroupInvitation.fromJson(Map<String, dynamic> json) {
    final group = json['groupId'];
    return GroupInvitation(
      id: _string(json['_id']),
      groupId: _string(_id(group)),
      groupName: group is Map ? _string(group['name'], 'Group') : 'Group',
      role: _string(json['role'], 'MEMBER'),
    );
  }
}

/// A note the user typed or dictated. Notes are personal: they are never
/// visible to assistants who hold delegated access to the calendar.
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    this.source = 'TEXT',
    this.eventId,
    this.pinned = false,
    this.tags = const <String>[],
    this.durationSeconds,
    this.createdAt,
    this.updatedAt,
  });

  final String id, title, body, source;
  final String? eventId;
  final bool pinned;
  final List<String> tags;
  final double? durationSeconds;
  final DateTime? createdAt, updatedAt;

  bool get isVoice => source == 'VOICE';

  /// `0:14` — the spoken length shown beside a dictated note.
  String get durationLabel {
    final seconds = durationSeconds?.round();
    if (seconds == null || seconds <= 0) return '';
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    final voice = json['voice'] is Map
        ? (json['voice'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final seconds = voice['durationSeconds'];
    return Note(
      id: _string(json['_id']),
      title: _string(json['title'], 'Note'),
      body: _string(json['body']),
      source: _string(json['source'], 'TEXT'),
      eventId: _id(json['eventId']),
      pinned: json['pinned'] == true,
      tags: _strings(json['tags']),
      durationSeconds: seconds is num ? seconds.toDouble() : null,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    this.readAt,
    this.createdAt,
    this.data,
  });

  final String id, title, body, category;
  final DateTime? readAt, createdAt;
  final Map<String, dynamic>? data;

  bool get read => readAt != null;
  String? get eventId => _id(data?['eventId']);

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: _string(json['_id']),
        title: _string(json['title']),
        body: _string(json['body']),
        category: _string(json['category'], 'REMINDER'),
        readAt: _date(json['readAt']),
        createdAt: _date(json['createdAt']),
        data: json['data'] is Map
            ? (json['data'] as Map).cast<String, dynamic>()
            : null,
      );

  IconData get icon => switch (category) {
    'REMINDER' => Icons.alarm,
    'INVITATION' => Icons.mail_outline,
    'GROUP_UPDATE' => Icons.groups_outlined,
    'CONTACT_REQUEST' => Icons.person_add_alt,
    'SECURITY' => Icons.lock_outline,
    'SUBSCRIPTION' => Icons.workspace_premium_outlined,
    _ => Icons.notifications_none,
  };
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    this.createdAt,
    this.pending = false,
  });

  final String id, text;
  final bool isUser, pending;
  final DateTime? createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: _string(json['_id']),
    text: _string(json['content']),
    isUser: _string(json['role']) == 'USER',
    createdAt: _date(json['createdAt']),
  );
}

/// A calendar mutation the assistant staged and the user must confirm.
class PendingAction {
  const PendingAction({
    required this.id,
    required this.type,
    required this.payload,
    this.conflicts = const <EventConflict>[],
    this.alternatives = const <TimeSlot>[],
  });

  final String id, type;
  final Map<String, dynamic> payload;
  final List<EventConflict> conflicts;

  /// Free times the proposal can be booked at instead of its clashing one.
  final List<TimeSlot> alternatives;

  ConflictReport get conflictReport =>
      ConflictReport(conflicts: conflicts, alternatives: alternatives);

  String get title => _string(payload['title']);

  /// A proposed note carries its text in `body`; the title may be derived.
  String get _noteLabel {
    final text = _string(
      payload['title'],
      _string(payload['body'], tr('this note')),
    );
    return text.length <= 60 ? text : '${text.substring(0, 60).trimRight()}…';
  }

  String get summary {
    final title = _string(payload['title'], tr('this event'));
    return switch (type) {
      'CREATE_EVENT' => tr('Create "{title}"', {'title': title}),
      'UPDATE_EVENT' => tr('Update "{title}"', {'title': title}),
      'DELETE_EVENT' => tr('Delete "{title}"', {'title': title}),
      'CREATE_NOTE' => tr('Save note "{note}"', {'note': _noteLabel}),
      _ => tr('Apply this change'),
    };
  }

  factory PendingAction.fromJson(Map<String, dynamic> json) => PendingAction(
    id: _string(json['_id']),
    type: _string(json['type']),
    payload: json['payload'] is Map
        ? (json['payload'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{},
    conflicts: EventConflict.listFrom(json['conflictWarnings']),
    alternatives: TimeSlot.listFrom(json['suggestedTimes']),
  );

  static List<PendingAction> listFrom(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => PendingAction.fromJson(item.cast<String, dynamic>()))
            .toList()
      : const <PendingAction>[];
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    this.updatedAt,
  });

  final String id, title;
  final DateTime? updatedAt;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary(
        id: _string(json['_id']),
        title: _string(json['title'], 'New chat'),
        updatedAt: _date(json['updatedAt']),
      );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.calendarId,
    this.messages = const <ChatMessage>[],
  });

  final String id, title, calendarId;
  final List<ChatMessage> messages;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final raw = json['messages'];
    return Conversation(
      id: _string(json['_id']),
      title: _string(json['title'], 'New chat'),
      calendarId: _string(_id(json['calendarId'])),
      messages: raw is List
          ? raw
                .whereType<Map>()
                .where((item) => item['supersededAt'] == null)
                .map(
                  (item) => ChatMessage.fromJson(item.cast<String, dynamic>()),
                )
                .toList()
          : const <ChatMessage>[],
    );
  }
}

/// The result of one assistant turn.
/// One moment in a streamed turn.
///
/// `delta` carries the next slice of the answer, `tools` names the calendar
/// work happening behind it, `reset` retracts text the model is about to
/// replace — notes it wrote before calling a tool, or a half-written answer
/// from a provider that then failed — and `done` closes with the saved turn.
enum AiEventKind {
  transcript,
  delta,
  tools,
  reset,
  done,
  audio,
  audioError,
  error,
}

class AiStreamEvent {
  const AiStreamEvent(
    this.kind, {
    this.text,
    this.tools = const [],
    this.turn,
    this.code,
    this.audio,
    this.last = false,
  });

  final AiEventKind kind;
  final String? text;
  final List<String> tools;
  final AiTurn? turn;

  /// One base64 MP3 piece of a spoken reply, on an [AiEventKind.audio];
  /// [last] marks the final piece.
  final String? audio;
  final bool last;

  /// The backend's machine-readable error code, on an [AiEventKind.error].
  final String? code;

  factory AiStreamEvent.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'transcript':
        final transcription = json['transcription'];
        return AiStreamEvent(
          AiEventKind.transcript,
          text: transcription is Map ? transcription['text'] as String? : null,
        );
      case 'audio':
        return AiStreamEvent(
          AiEventKind.audio,
          audio: json['base64'] as String?,
          last: json['last'] == true,
        );
      case 'audio_error':
        return AiStreamEvent(
          AiEventKind.audioError,
          text: json['message'] as String?,
          code: json['code'] as String?,
        );
      case 'delta':
        return AiStreamEvent(
          AiEventKind.delta,
          text: json['text'] as String? ?? '',
        );
      case 'tools':
        return AiStreamEvent(
          AiEventKind.tools,
          tools: [
            for (final name in (json['tools'] ?? json['names']) as List? ?? [])
              '$name',
          ],
        );
      case 'reset':
        return const AiStreamEvent(AiEventKind.reset);
      case 'done':
        return AiStreamEvent(AiEventKind.done, turn: AiTurn.fromJson(json));
      default:
        return AiStreamEvent(
          AiEventKind.error,
          text: json['message'] as String?,
          code: json['code'] as String?,
        );
    }
  }
}

class AiTurn {
  const AiTurn({
    required this.message,
    this.pendingActions = const <PendingAction>[],
    this.transcript,
    this.audioBase64,
  });

  final ChatMessage message;
  final List<PendingAction> pendingActions;
  final String? transcript;
  final String? audioBase64;

  factory AiTurn.fromJson(Map<String, dynamic> json) {
    final audio = json['audio'];
    final transcription = json['transcription'];
    return AiTurn(
      message: ChatMessage.fromJson(
        (json['message'] as Map).cast<String, dynamic>(),
      ),
      pendingActions: PendingAction.listFrom(json['pendingActions']),
      transcript: transcription is Map
          ? transcription['text'] as String?
          : null,
      audioBase64: audio is Map && audio['available'] == true
          ? audio['base64'] as String?
          : null,
    );
  }
}

class AiQuota {
  const AiQuota({
    required this.used,
    required this.limit,
    required this.remaining,
  });

  final int used, limit, remaining;

  factory AiQuota.fromJson(Map<String, dynamic> json) => AiQuota(
    used: (json['used'] as num?)?.toInt() ?? 0,
    limit: (json['limit'] as num?)?.toInt() ?? 0,
    remaining: (json['remaining'] as num?)?.toInt() ?? 0,
  );

  /// The server counts a voice turn exactly like a typed one, so this gates
  /// both input methods.
  bool get exhausted => limit > 0 && remaining <= 0;

  /// Worth warning about before the user starts a hands-free session that
  /// would burn the rest without noticing.
  bool get low => limit > 0 && remaining > 0 && remaining <= 3;
}

/// A spoken voice the API accepts for replies, mirroring the backend's
/// `OPENAI_TTS_VOICES` enum. Sending an id outside this list is rejected by
/// the server's schema, so the picker is the single source of truth.
///
/// Tone hints are approximate — they exist to make 13 rows distinguishable,
/// not to promise an exact character.
class AriaVoice {
  const AriaVoice(this.id, this.label, this.tone);

  final String id, label, tone;

  static const all = <AriaVoice>[
    AriaVoice('alloy', 'Alloy', 'Balanced and neutral'),
    AriaVoice('ash', 'Ash', 'Low and steady'),
    AriaVoice('ballad', 'Ballad', 'Warm and unhurried'),
    AriaVoice('coral', 'Coral', 'Bright and friendly'),
    AriaVoice('echo', 'Echo', 'Even and measured'),
    AriaVoice('fable', 'Fable', 'Expressive storyteller'),
    AriaVoice('onyx', 'Onyx', 'Deep and grounded'),
    AriaVoice('nova', 'Nova', 'Crisp and energetic'),
    AriaVoice('sage', 'Sage', 'Calm and thoughtful'),
    AriaVoice('shimmer', 'Shimmer', 'Light and airy'),
    AriaVoice('verse', 'Verse', 'Natural and conversational'),
    AriaVoice('marin', 'Marin', 'Soft and clear'),
    AriaVoice('cedar', 'Cedar', 'Rounded and mellow'),
  ];

  /// Falls back to the first entry so a stored id from a future build never
  /// leaves the picker without a selection.
  static AriaVoice? find(String? id) {
    if (id == null) return null;
    for (final voice in all) {
      if (voice.id == id) return voice;
    }
    return null;
  }
}

class SubscriptionInfo {
  const SubscriptionInfo({
    required this.plan,
    required this.status,
    this.productId,
    this.expiresAt,
    this.willRenew = false,
    this.managementUrl,
  });

  final String plan, status;
  final String? productId, managementUrl;
  final DateTime? expiresAt;
  final bool willRenew;

  bool get isPremium => plan == 'PREMIUM';

  String get label => switch (status) {
    'TRIAL' => 'Premium — free trial',
    'ACTIVE' => 'Premium',
    'GRACE' => 'Premium — payment issue',
    'CANCELLED' => 'Premium — cancels at period end',
    'EXPIRED' => 'Free Plan',
    // No store subscription on file (status defaults to FREE). An admin-granted
    // premium has no RevenueCat record, so fall back to the plan the gates read.
    _ => isPremium ? 'Premium' : 'Free Plan',
  };

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    final subscription = json['subscription'];
    final data = subscription is Map
        ? subscription.cast<String, dynamic>()
        : const <String, dynamic>{};
    return SubscriptionInfo(
      plan: _string(json['plan'], 'FREE'),
      status: _string(data['status'], 'FREE'),
      productId: data['productId'] as String?,
      expiresAt: _date(data['expiresAt']) ?? _date(json['premiumUntil']),
      willRenew: data['willRenew'] as bool? ?? false,
      managementUrl: data['managementUrl'] as String?,
    );
  }
}

/// Delegated calendar access — the app calls these "secretaries".
class Delegation {
  const Delegation({
    required this.id,
    required this.person,
    required this.preset,
  });

  final String id, preset;
  final Person person;

  int get presetIndex => presets.indexOf(preset).clamp(0, presets.length - 1);

  static const presets = [
    'ADD_ONLY',
    'EDIT_ONLY',
    'ADD_EDIT',
    'DELETE_ONLY',
    'VIEW_EDIT_ALL',
    'VIEW_OWN',
    'FULL_ACCESS',
  ];

  static const presetLabels = [
    'Add events only',
    'Edit events only',
    'Add and edit events only',
    'Delete events only',
    'View and edit all events',
    'View only the events created by that person',
    'Full access',
  ];

  factory Delegation.fromJson(Map<String, dynamic> json) {
    final delegate = json['delegateId'];
    return Delegation(
      id: _string(json['_id']),
      preset: _string(json['preset'], 'VIEW_OWN'),
      person: delegate is Map
          ? Person.fromUser(
              delegate.cast<String, dynamic>(),
              relation: 'Secretary',
            )
          : Person(id: _string(_id(delegate)), name: 'Assistant'),
    );
  }
}

class LegalDocument {
  const LegalDocument({
    required this.type,
    required this.version,
    required this.title,
    required this.content,
  });

  final String type, version, title, content;

  factory LegalDocument.fromJson(Map<String, dynamic> json) => LegalDocument(
    type: _string(json['type']),
    version: _string(json['version'], '1.0'),
    title: _string(json['title']),
    content: _string(json['content']),
  );
}
