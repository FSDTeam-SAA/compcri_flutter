import 'package:compcri_flutter/core/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarEvent', () {
    test('parses a plain event and exposes view helpers', () {
      final event = CalendarEvent.fromJson({
        '_id': '65b1f77bcf86cd7994390101',
        'calendarId': '65b1f77bcf86cd7994390100',
        'createdById': '65b1f77bcf86cd7994390001',
        'title': 'Lunch with Ana',
        'description': 'Catch up',
        'location': 'Cafe',
        'startsAt': '2026-09-10T12:00:00.000Z',
        'endsAt': '2026-09-10T13:00:00.000Z',
        'timeZone': 'America/New_York',
        'reminderMinutes': [30],
        '__v': 2,
      });

      expect(event.title, 'Lunch with Ana');
      expect(event.version, 2);
      expect(event.reminder, '30 Minutes');
      expect(event.repeat, 'Never');
      expect(event.completed, isFalse);
      expect(event.isShared, isFalse);
      expect(event.isRecurring, isFalse);
      // Times are surfaced in the device's local zone.
      expect(event.start.hour, event.occurrenceStartAt.toLocal().hour);
    });

    test('uses the expanded occurrence for a recurring event', () {
      final event = CalendarEvent.fromJson({
        '_id': '65b1f77bcf86cd7994390102',
        'title': 'Standup',
        'startsAt': '2026-09-01T09:00:00.000Z',
        'endsAt': '2026-09-01T09:15:00.000Z',
        'occurrenceStartAt': '2026-09-24T09:00:00.000Z',
        'occurrenceEndAt': '2026-09-24T09:15:00.000Z',
        'recurrenceRrule': 'RRULE:FREQ=WEEKLY',
      });

      expect(event.isRecurring, isTrue);
      expect(event.repeat, 'Weekly');
      expect(event.occurrenceStartAt.toUtc().day, 24);
      // The series anchor is preserved for edits.
      expect(event.startsAt.toUtc().day, 1);
    });

    test('treats a pending shared event as an invitation', () {
      final event = CalendarEvent.fromJson({
        '_id': '65b1f77bcf86cd7994390103',
        'title': 'Anniversary party',
        'startsAt': '2026-09-10T18:00:00.000Z',
        'endsAt': '2026-09-10T21:00:00.000Z',
        'sharePermission': 'RESPOND',
        'rsvpStatus': 'PENDING',
      });

      expect(event.isShared, isTrue);
      expect(event.invited, isTrue);
    });

    test('an answered invitation is no longer pending', () {
      final event = CalendarEvent.fromJson({
        '_id': '65b1f77bcf86cd7994390104',
        'title': 'Review',
        'startsAt': '2026-09-10T18:00:00.000Z',
        'endsAt': '2026-09-10T19:00:00.000Z',
        'sharePermission': 'RESPOND',
        'rsvpStatus': 'ACCEPTED',
      });

      expect(event.isShared, isTrue);
      expect(event.invited, isFalse);
    });

    test('maps reminder and repeat labels in both directions', () {
      expect(CalendarEvent.minutesForLabel('1 Hour'), [60]);
      expect(CalendarEvent.minutesForLabel('None'), isEmpty);
      expect(CalendarEvent.reminderLabel(const [10]), '10 Minutes');
      expect(CalendarEvent.reminderLabel(const []), 'None');

      expect(CalendarEvent.rruleForLabel('Daily'), 'RRULE:FREQ=DAILY');
      expect(CalendarEvent.rruleForLabel('Never'), isNull);
      expect(CalendarEvent.repeatLabel('RRULE:FREQ=MONTHLY'), 'Monthly');
      expect(CalendarEvent.repeatLabel(null), 'Never');
    });

    test('completion is derived from completedAt', () {
      final done = CalendarEvent.fromJson({
        '_id': '65b1f77bcf86cd7994390105',
        'title': 'Ship it',
        'startsAt': '2026-09-10T10:00:00.000Z',
        'endsAt': '2026-09-10T11:00:00.000Z',
        'completedAt': '2026-09-10T11:05:00.000Z',
      });

      expect(done.completed, isTrue);
      expect(done.copyWith(clearCompletedAt: true).completed, isFalse);
    });
  });

  group('AppUser', () {
    test('reads the populated avatar and premium state', () {
      final user = AppUser.fromJson({
        '_id': '65b1f77bcf86cd7994390001',
        'email': 'smith@example.com',
        'displayName': 'Smith Josh',
        'plan': 'PREMIUM',
        'premiumUntil': DateTime.now()
            .add(const Duration(days: 20))
            .toIso8601String(),
        'contactCode': 'JOHN-456-FA',
        'locale': 'pt',
        'interests': ['Business', 'Travel'],
        'avatarMediaId': {
          '_id': '65b1f77bcf86cd7994390200',
          'secureUrl': 'https://cdn.example.com/a.jpg',
        },
      });

      expect(user.name, 'Smith Josh');
      expect(user.firstNameOrEmail, 'Smith');
      expect(user.isPremium, isTrue);
      expect(user.avatar?.secureUrl, 'https://cdn.example.com/a.jpg');
      expect(user.languageLabel, 'Português');
      expect(user.interests, ['Business', 'Travel']);
    });

    test('an unpopulated avatar id does not become a broken url', () {
      final user = AppUser.fromJson({
        '_id': '65b1f77bcf86cd7994390002',
        'email': 'a@example.com',
        'avatarMediaId': '65b1f77bcf86cd7994390200',
      });

      expect(user.avatar, isNull);
      expect(user.firstNameOrEmail, 'a');
    });

    test('expired premium is not premium', () {
      final user = AppUser.fromJson({
        '_id': '65b1f77bcf86cd7994390003',
        'email': 'b@example.com',
        'plan': 'PREMIUM',
        'premiumUntil': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      });

      expect(user.isPremium, isFalse);
    });

    test('maps locale labels back to codes', () {
      expect(AppUser.localeForLabel('Español'), 'es');
      expect(AppUser.localeForLabel('English'), 'en');
      expect(AppUser.localeForLabel('nonsense'), 'en');
    });
  });

  group('notification preferences', () {
    test('exposes labelled switches that map back to API keys', () {
      final preferences = NotificationPreferences.fromJson({
        'pushEnabled': true,
        'reminders': false,
      });

      expect(preferences.asLabels['Push Notifications'], isTrue);
      expect(preferences.asLabels['Event Reminders'], isFalse);
      expect(
        NotificationPreferences.labelKeys['New Contact Requests'],
        'contactRequests',
      );
    });
  });

  group('network models', () {
    test('reads the contact/relation pair shape', () {
      final person = Person.fromContact({
        'user': {
          '_id': '65b1f77bcf86cd7994390010',
          'displayName': 'Sarah Martinez',
          'email': 'sarah@example.com',
          'profession': 'Product Manager',
        },
        'relation': 'Coworker',
      });

      expect(person.name, 'Sarah Martinez');
      expect(person.relation, 'Coworker');
      expect(person.profession, 'Product Manager');
      expect(person.avatarIndex, inInclusiveRange(0, 5));
    });

    test('reads a populated group with members', () {
      final group = Group.fromJson({
        '_id': '65b1f77bcf86cd7994390020',
        'name': 'Office colleagues',
        'code': 'OFFI-123-AA',
        'ownerId': '65b1f77bcf86cd7994390001',
        'members': [
          {
            'userId': {
              '_id': '65b1f77bcf86cd7994390001',
              'displayName': 'Smith Josh',
            },
            'role': 'OWNER',
          },
          {
            'userId': {
              '_id': '65b1f77bcf86cd7994390010',
              'displayName': 'Sarah Martinez',
            },
            'role': 'MEMBER',
          },
        ],
      });

      expect(group.memberCount, 2);
      expect(group.members.first.isOwner, isTrue);
      expect(group.isOwnedBy('65b1f77bcf86cd7994390001'), isTrue);
      expect(group.isOwnedBy('65b1f77bcf86cd7994390010'), isFalse);
    });
  });

  group('AI models', () {
    test('reads a turn with a staged action', () {
      final turn = AiTurn.fromJson({
        'message': {
          '_id': '65b1f77bcf86cd7994390030',
          'role': 'ASSISTANT',
          'content': 'I can book that for you.',
        },
        'pendingActions': [
          {
            '_id': '65b1f77bcf86cd7994390031',
            'type': 'CREATE_EVENT',
            'payload': {'title': 'Dentist'},
            'conflictWarnings': [
              {
                'title': 'Standup',
                'startsAt': '2026-09-10T09:00:00.000Z',
                'endsAt': '2026-09-10T09:30:00.000Z',
              },
            ],
          },
        ],
      });

      expect(turn.message.isUser, isFalse);
      expect(turn.pendingActions, hasLength(1));
      expect(turn.pendingActions.first.summary, 'Create "Dentist"');
      expect(turn.pendingActions.first.conflicts.first.title, 'Standup');
      expect(turn.audioBase64, isNull);
    });

    test('ignores unavailable voice audio', () {
      final turn = AiTurn.fromJson({
        'message': {
          '_id': '65b1f77bcf86cd7994390032',
          'role': 'ASSISTANT',
          'content': 'Done.',
        },
        'transcription': {'text': 'book the dentist'},
        'audio': {'available': false},
      });

      expect(turn.transcript, 'book the dentist');
      expect(turn.audioBase64, isNull);
    });

    test('drops superseded messages from a conversation', () {
      final conversation = Conversation.fromJson({
        '_id': '65b1f77bcf86cd7994390040',
        'title': 'Planning',
        'calendarId': '65b1f77bcf86cd7994390100',
        'messages': [
          {'_id': 'a', 'role': 'USER', 'content': 'old', 'supersededAt': '2026-09-10T00:00:00.000Z'},
          {'_id': 'b', 'role': 'USER', 'content': 'new'},
        ],
      });

      expect(conversation.messages, hasLength(1));
      expect(conversation.messages.single.text, 'new');
    });
  });

  group('Delegation', () {
    test('maps presets to the radio list order', () {
      final delegation = Delegation.fromJson({
        '_id': '65b1f77bcf86cd7994390050',
        'preset': 'FULL_ACCESS',
        'delegateId': {
          '_id': '65b1f77bcf86cd7994390010',
          'displayName': 'Sarah Martinez',
          'email': 'sarah@example.com',
        },
      });

      expect(delegation.presetIndex, 6);
      expect(Delegation.presetLabels[delegation.presetIndex], 'Full access');
      expect(delegation.person.relation, 'Secretary');
    });
  });

  group('SubscriptionInfo', () {
    test('summarises the entitlement state', () {
      final subscription = SubscriptionInfo.fromJson({
        'plan': 'PREMIUM',
        'subscription': {
          'status': 'TRIAL',
          'willRenew': true,
          'expiresAt': '2026-09-30T00:00:00.000Z',
          'managementUrl': 'https://apps.apple.com/manage',
        },
      });

      expect(subscription.isPremium, isTrue);
      expect(subscription.label, 'Premium — free trial');
      expect(subscription.managementUrl, isNotNull);
      expect(subscription.expiresAt, isNotNull);
    });
  });

  test('debugFillProperties smoke: TimeOfDay helpers stay consistent', () {
    final event = CalendarEvent(
      id: 'x',
      calendarId: 'c',
      title: 'T',
      startsAt: DateTime(2026, 9, 10, 14, 30),
      endsAt: DateTime(2026, 9, 10, 15, 30),
    );

    expect(event.start, const TimeOfDay(hour: 14, minute: 30));
    expect(event.end, const TimeOfDay(hour: 15, minute: 30));
    expect(event.date, DateTime(2026, 9, 10));
  });
}
