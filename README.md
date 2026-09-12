# Aurox Day

Flutter client for the Compcri AI Calendar API. The UI was built from the supplied
Figma exports; every screen now reads and writes through the REST backend in
`../compcri-backend`.

## Run

Start the API and its worker first:

```sh
cd ../compcri-backend
npm install
npm run db:migrate     # once
npm run seed           # once — publishes the legal documents registration needs
npm run dev
npm run dev:worker     # reminders and scheduled jobs
```

Then the app:

```sh
flutter pub get
flutter run
```

### Pointing at a different API

The default base URL is `http://10.0.2.2:5000/api/v1` on Android (the emulator's
route to your host machine) and `http://localhost:5000/api/v1` everywhere else.
Override it at build time:

```sh
flutter run --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

On a physical device use your machine's LAN address, and add that host to
`android/app/src/main/res/xml/network_security_config.xml` if it is plain HTTP.

## Architecture

| File | Responsibility |
| --- | --- |
| `lib/core/config.dart` | Base URL resolution and timeouts |
| `lib/core/api_client.dart` | HTTP transport: envelope unwrapping, `ApiException`, bearer auth, refresh-and-retry, multipart upload, session persistence |
| `lib/core/api.dart` | One typed method per backend route, grouped by area |
| `lib/core/models.dart` | Dart models mirroring the API documents |
| `lib/core/store.dart` | `AppStore` — session, cached collections, and every mutation |
| `lib/core/time.dart` | Device IANA time zone, UTC serialisation, date helpers |
| `lib/core/design.dart` | Theme, shared widgets, `runTask`/`runAction` request helpers |
| `lib/features/` | Screens: auth, dashboard/chat/calendar, events, network, settings |

`AppStore` is exposed through `StoreScope` (an `InheritedNotifier`). Screens read
the cached lists synchronously and call store methods to talk to the server;
`runTask`/`runAction` wrap a request in a spinner and turn an `ApiException` into
a snackbar.

### Session handling

Access and refresh tokens are persisted in shared preferences. A `401` triggers
one refresh-and-retry, and concurrent requests share a single refresh call. If
the refresh itself is rejected the session is cleared and the app returns to
sign-in; a network blip does not sign the user out.

### Concurrency and conflicts

Events use the backend's optimistic-concurrency `__v`, so the detail screen
refetches before mutating. `EVENT_CONFLICT` responses are surfaced as a dialog
listing the overlapping events and the free slots the server suggests, with the
option to schedule anyway (`overrideConflicts`).

## What is wired

- **Auth** — register (with the active terms version), sign in, forgot/verify/reset
  with the six-digit OTP, restore an account that is pending deletion, logout.
- **Profile** — read/update, avatar upload to Cloudinary, password change (which
  revokes every session), notification preferences, language, account deletion
  with its recovery window.
- **Calendar** — range queries with recurrence expansion, create/edit/delete,
  completion, conflicts with suggested alternatives, poster upload, reminders
  and repeat rules. Editing or deleting a repeating event asks whether you mean
  this occurrence or the whole series, and routes to the recurrence-exception
  endpoint accordingly.
- **Sharing** — share with contacts or groups at VIEW_ONLY / RESPOND / EDIT, and
  RSVP to what others share with you.
- **Network** — contacts by code, contact requests, relations, groups (create,
  join, invite, leave, delete), group invitations.
- **AI** — conversations, text turns, voice turns (record → transcribe → reply →
  spoken answer), message edit/delete, and the confirm/reject gate for every
  calendar change the assistant stages.
- **Hands-free calling** — a toggle on the voice screen keeps the turn-taking
  going by itself: the reply finishes speaking, the microphone reopens, and a
  pause of about two seconds ends the turn and sends it. A turn nobody speaks
  into is dropped after twelve seconds rather than holding the microphone, and
  every recording stops at two minutes so it cannot exceed the server's
  `OPENAI_VOICE_MAX_FILE_MB` upload ceiling. Turning the toggle on starts the
  first turn; a failed turn switches it off and keeps the recording for retry.
  This is still the chained turn-based pipeline, not a realtime
  speech-to-speech session — the backend leaves those out of v1.
- **Reply voice** — any of the API's thirteen `OPENAI_TTS_VOICES` can be picked
  on the voice screen and is sent with the next voice turn. The choice,
  hands-free, and mute are remembered between launches in shared preferences
  (`ai.voice`, `ai.handsFree`, `ai.muted`); leaving the voice unset keeps the
  server's configured default.
- **Daily allowance** — `GET /ai/quota` is shown as a chip on the voice screen
  and, once it runs low, beside the chat title. Typed and spoken turns share
  the allowance, and exhausting it stops a hands-free session rather than
  looping into repeated rejections.
- **Notifications** — inbox, read/read-all/delete, deep-link into the event.
- **Secretaries** — delegation lookup, create for a new or existing account,
  change preset, revoke.
- **Subscription** — live entitlement state, store-managed billing, reconcile.
- **Legal & support** — terms/privacy fetched from the API, support requests.

## Not wired, and why

- **Google sign-in** — needs an OAuth client ID in the app and `GOOGLE_CLIENT_IDS`
  on the server. The endpoint (`AuthApi.google`) is implemented and ready.
- **In-app purchase** — the backend deliberately leaves prices and offerings to
  the RevenueCat mobile SDK. The app shows plans, hands off to the store, and
  reconciles entitlements afterwards; wiring `purchases_flutter` is the
  remaining step. No card details are collected in-app, by design.
- **Push notifications** — device registration (`POST /devices`) is implemented
  in `NotificationApi`, but calling it needs `firebase_messaging` plus a
  `google-services.json` / `GoogleService-Info.plist`. The in-app inbox works
  without it.

## Tests

```sh
flutter test
flutter analyze
```

53 tests: transport behaviour (envelope, error codes, refresh-and-retry,
single-flight refresh, expired-token restore), model parsing for every API
document, and widget flows against a mock backend (session restore, sign-in,
notification badge, contacts, event creation payload, sign-out, voice upload
and retry, and the remembered reply voice reaching the upload).
