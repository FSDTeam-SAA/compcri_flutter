# Design implementation handoff

The supplied folder contains 62 PNG exports, including component snippets and alternate states. The screen families are implemented with native layouts and shared design controls. API work is deferred.

| Reference family | Implementation |
| --- | --- |
| Splash, Onboarding 1/2/3 | Splash and swipeable onboarding; 1.2 is an alternate first-page illustration |
| Login, Create Account, account-ready | Auth forms and success dialog |
| Forgot password, OTP variants, Create New Password | Recovery flow with four-digit input |
| Profile setup, Edit Profile, Main profile | Editable setup and dedicated read-only summary |
| Home without/after event | Reactive empty and populated Home |
| AI Chat, New Chat, conversation, Chat History, After Click Voice | AI landing, conversation, drawer, message controls and voice UI |
| Calendar | Selectable week/date and event timeline |
| Add New, Create Event | Shared create/edit form with overlap state |
| Event creator variants | Details, edit/delete/share, completed state |
| Receiver, Share Event | Invitation acceptance and contact/group selection |
| Contacts and Groups variants, Add contact, Filter | Search/filter, dialog, contact tabs, joining and group details |
| Profile and General Settings | Settings navigation and account actions |
| Assistant variants | Secretary list, form, permissions and full-access dialog |
| Notification and status | Notification list, unread state and preferences |
| Subscription variants and component cards | Animated folded-card stack with selectable front plan |
| Subscription process, Add card, payment success | Summary, preview coupon, card form and success dialog |
| Language and language component | Selected-language UI |
| Contact Us, Terms, Privacy, Delete Account | Corresponding forms and content screens |

## Review status

All screen families above have UI implementations. The latest review added press feedback, tab fades, reduced-motion handling, searchable chat history, and a full 24-hour calendar that displays multiple events in the same hour.

Validation: 58 UI tests passed. Coverage includes 320/393 px layouts, 320x568 keyboard behavior, event creation/editing/completion/deletion, tabs and chat, subscription switching and coupons, and received-invitation acceptance. Static analysis is clean. Earlier navigation test failures were resolved by targeting the actual create button and waiting for route transitions.

Rendered previews are in design_review/rendered/. These checks establish layout and interaction correctness, not exact pixel equivalence. Source assets are raster exports; the background and brand are recreated, and dedicated Figma assets/font tokens plus physical-device review remain useful for final visual signoff.

## API phase

A sibling `compcri-backend` directory was located, but endpoint contracts and authentication have not been inspected or connected. Next: inspect backend routes and DTOs, map repositories to the local models, implement session persistence, and connect auth/profile/events/contacts/groups/secretaries/notifications/chat/subscriptions in that order. Replace sample invitation/contact data and local-only operations with server results.

The UI language preference is stored locally; translated strings are not yet supplied. Time-zone selection is retained on the event model; actual conversion belongs in the scheduling/API implementation. All state is currently ephemeral. Terms/privacy text follows the supplied mockups.


## Build
Android debug APK built successfully at build/app/outputs/flutter-apk/app-debug.apk. Android and iOS display names are Aurox Day. iOS compilation and physical-device visual review were not performed on this Windows host.
