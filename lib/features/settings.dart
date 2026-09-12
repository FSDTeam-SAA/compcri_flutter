import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/design.dart';
import '../core/store.dart';
import '../core/time.dart';
import 'events.dart';
import 'network.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.route, this.arguments});
  final String route;
  final Object? arguments;

  @override
  Widget build(BuildContext context) {
    switch (route) {
      case '/profile':
        return const ProfileScreen();
      case '/setup':
        return const ProfileForm(setup: true);
      case '/profile/edit':
        return const ProfileForm();
      case '/profile/view':
        return const ProfileSummary();
      case '/general':
        return PageFrame(
          title: 'General Settings',
          child: Surface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                settingsRow(
                  context,
                  Icons.lock_outline,
                  'Change Password',
                  '/password',
                ),
                settingsRow(
                  context,
                  Icons.delete_outline,
                  'Delete Account',
                  '/delete',
                  danger: true,
                ),
              ],
            ),
          ),
        );
      case '/password':
        return const PasswordScreen();
      case '/delete':
        return const DeleteScreen();
      case '/notifications':
        return const NotificationsScreen();
      case '/notification-settings':
        return const NotificationSettingsScreen();
      case '/language':
        return const LanguageScreen();
      case '/assistants':
        return const AssistantsScreen();
      case '/assistant/add':
        return const AssistantForm();
      case '/assistant/edit':
        return AssistantForm(
          delegation: arguments is Delegation ? arguments! as Delegation : null,
        );
      case '/subscription':
        return const SubscriptionScreen();
      case '/summary':
        return SummaryScreen(plan: arguments is String ? arguments! as String : 'Premium Monthly');
      case '/contact-us':
        return const ContactUsScreen();
      case '/terms':
        return const LegalScreen();
      case '/privacy':
        return const LegalScreen(privacy: true);
      default:
        return const PageFrame(
          title: 'Page not found',
          child: Text('Please return to the previous screen.'),
        );
    }
  }
}

Widget settingsRow(
  BuildContext context,
  IconData icon,
  String title,
  String route, {
  bool danger = false,
}) => ListTile(
  dense: true,
  leading: Icon(icon, size: 21, color: danger ? const Color(0xffff684a) : muted),
  title: Text(
    title,
    style: TextStyle(
      fontSize: 13,
      color: danger ? const Color(0xffff684a) : null,
    ),
  ),
  trailing: const Icon(Icons.chevron_right, size: 21, color: muted),
  onTap: () => go(context, route),
);

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final user = store.user;
    return PageFrame(
      title: 'Profile',
      child: Column(
        children: [
          Surface(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Avatar(
                profile: true,
                size: 48,
                url: user?.avatar?.secureUrl,
              ),
              title: Text(user?.name ?? 'Your profile'),
              subtitle: Text(
                user?.email ?? '',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
              trailing: const Icon(Icons.chevron_right, color: muted),
              onTap: () => go(context, '/profile/view'),
            ),
          ),
          const SizedBox(height: 12),
          if (user != null)
            InviteCode(label: 'Your Code', code: user.contactCode),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff4c95ff), Color(0xffa34cff)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars_rounded, color: Colors.white, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.isPremium
                            ? 'Premium is active'
                            : 'Upgrade to Premium',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        store.subscription?.label ??
                            'More possibilities, every day',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: .2),
                  ),
                  onPressed: () => go(context, '/subscription'),
                  child: Text(
                    store.isPremium ? 'Manage' : 'Get Premium',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Surface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                settingsRow(
                  context,
                  Icons.edit_outlined,
                  'Edit Profile',
                  '/profile/edit',
                ),
                settingsRow(context, Icons.tune, 'General Settings', '/general'),
                settingsRow(
                  context,
                  Icons.sticky_note_2_outlined,
                  'Notes',
                  '/notes',
                ),
                settingsRow(
                  context,
                  Icons.account_balance_wallet_outlined,
                  'Subscription',
                  '/subscription',
                ),
                settingsRow(
                  context,
                  Icons.notifications_none,
                  'Notification',
                  '/notification-settings',
                ),
                settingsRow(context, Icons.language, 'Language', '/language'),
                settingsRow(
                  context,
                  Icons.person_outline,
                  'Secretary Access',
                  '/assistants',
                ),
                settingsRow(
                  context,
                  Icons.verified_user_outlined,
                  'Terms & Condition',
                  '/terms',
                ),
                settingsRow(
                  context,
                  Icons.privacy_tip_outlined,
                  'Privacy Policy',
                  '/privacy',
                ),
                settingsRow(
                  context,
                  Icons.mail_outline,
                  'Contact Us',
                  '/contact-us',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            'Logout',
            outline: true,
            danger: true,
            onPressed: () async {
              final confirmed = await confirm(
                context,
                'Log out?',
                'You will need to sign in again.',
                action: 'Logout',
              );
              if (!confirmed || !context.mounted) return;
              await runAction(context, store.signOut);
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class ProfileForm extends StatefulWidget {
  const ProfileForm({super.key, this.setup = false});
  final bool setup;
  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      phone = TextEditingController(),
      profession = TextEditingController(),
      country = TextEditingController(),
      city = TextEditingController();

  String language = 'English';
  final interests = <String>{};
  bool consent = false, initialized = false;

  static const _catalog = [
    'Technology',
    'Business',
    'Music',
    'Travel',
    'Education',
    'Sports',
    'Design',
    'Food',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    final user = StoreScope.of(context).user;
    if (user == null) return;
    name.text = user.name;
    phone.text = user.phone;
    profession.text = user.profession;
    country.text = user.country;
    city.text = user.city;
    language = user.languageLabel;
    interests.addAll(user.interests);
    consent = user.aiPersonalizationConsent;
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    profession.dispose();
    country.dispose();
    city.dispose();
    super.dispose();
  }

  Future<void> _changeAvatar() async {
    final path = await pickImagePath(context);
    if (path == null || !mounted) return;
    final store = StoreScope.read(context);
    await runAction(
      context,
      () => store.updateAvatar(path),
      success: 'Profile photo updated',
    );
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    final store = StoreScope.read(context);
    final done = await runAction(
      context,
      () => store.updateProfile({
        'displayName': name.text.trim(),
        'phone': phone.text.trim(),
        'profession': profession.text.trim(),
        'country': country.text.trim(),
        'city': city.text.trim(),
        'locale': AppUser.localeForLabel(language),
        'interests': interests.toList(),
        'aiPersonalizationConsent': consent,
      }),
      success: 'Profile saved',
    );
    if (!done || !mounted) return;
    if (widget.setup) {
      home(context);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return PageFrame(
      title: widget.setup ? null : 'Edit Profile',
      auth: true,
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.setup) ...[
              const SizedBox(height: 45),
              const Center(child: Brand()),
              const SizedBox(height: 28),
              const Text(
                'Profile Setup',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
            ],
            Center(
              child: Stack(
                children: [
                  Avatar(
                    profile: true,
                    size: 84,
                    url: store.user?.avatar?.secureUrl,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: InkWell(
                      onTap: _changeAvatar,
                      child: const CircleAvatar(
                        radius: 13,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.add, size: 20, color: muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            AppField(
              'Display Name',
              hint: 'Enter full name',
              controller: name,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter your name' : null,
            ),
            AppField(
              'Phone Number or WhatsApp',
              hint: '+1 555 0100',
              controller: phone,
              keyboard: TextInputType.phone,
            ),
            AppField(
              'Profession',
              hint: 'Profession',
              controller: profession,
            ),
            SelectField(
              'Language',
              value: language,
              values: AppUser.locales.values.toList(),
              onChanged: (value) => setState(() => language = value),
            ),
            Row(
              children: [
                Expanded(
                  child: AppField(
                    'Country',
                    hint: 'Country',
                    controller: country,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppField('City', hint: 'City', controller: city),
                ),
              ],
            ),
            const Text('Interests (optional)'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _catalog
                  .map(
                    (value) => ChoiceChip(
                      label: Text(
                        value,
                        style: TextStyle(
                          fontSize: 10,
                          color: interests.contains(value)
                              ? Colors.white
                              : muted,
                        ),
                      ),
                      selected: interests.contains(value),
                      showCheckmark: false,
                      selectedColor: const Color(0xffa294ef),
                      backgroundColor: const Color(0xfffff6f8),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                      onSelected: (selected) => setState(
                        () => selected
                            ? interests.add(value)
                            : interests.remove(value),
                      ),
                    ),
                  )
                  .toList(),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: consent,
              onChanged: (value) => setState(() => consent = value!),
              title: const Text(
                'Allow Aria to use my interests to personalize my experience and recommend relevant events.',
                style: TextStyle(fontSize: 10),
              ),
            ),
            const SizedBox(height: 24),
            AsyncButton(
              widget.setup ? 'Setup Profile' : 'Save',
              onPressed: _save,
            ),
            if (widget.setup)
              TextButton(
                onPressed: () => home(context),
                child: const Text('Skip for now'),
              ),
          ],
        ),
      ),
    );
  }
}

class ProfileSummary extends StatelessWidget {
  const ProfileSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final user = StoreScope.of(context).user;
    Widget value(String label, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xffe9e7ff),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              text.isEmpty ? '—' : text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );

    return PageFrame(
      title: 'Your Profile',
      auth: true,
      actions: [
        IconButton(
          tooltip: 'Edit profile',
          onPressed: () => go(context, '/profile/edit'),
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Avatar(
              profile: true,
              size: 84,
              url: user?.avatar?.secureUrl,
            ),
          ),
          const SizedBox(height: 22),
          value('Display Name', user?.name ?? ''),
          value('Email', user?.email ?? ''),
          value('Phone Number or WhatsApp', user?.phone ?? ''),
          value('Profession', user?.profession ?? ''),
          Row(
            children: [
              Expanded(child: value('Country', user?.country ?? '')),
              const SizedBox(width: 16),
              Expanded(child: value('City', user?.city ?? '')),
            ],
          ),
          const Text('Interests', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: (user?.interests ?? const <String>[])
                .map(
                  (interest) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xffe9e7ff),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      interest,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController(), password = TextEditingController();

  @override
  void dispose() {
    current.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    final store = StoreScope.read(context);
    final done = await runAction(
      context,
      () => store.changePassword(current.text, password.text),
      success: 'Password changed. Please sign in again.',
    );
    // Changing the password revokes every session, including this one.
    if (done && mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Change Password',
    child: Form(
      key: form,
      child: Column(
        children: [
          const Surface(
            color: Color(0xffe2edff),
            child: Text(
              'Changing your password signs you out of every device.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          const SizedBox(height: 16),
          AppField(
            'Current Password',
            controller: current,
            password: true,
            hint: '********',
            validator: (v) =>
                (v?.isNotEmpty ?? false) ? null : 'Enter your current password',
          ),
          AppField(
            'New Password',
            controller: password,
            password: true,
            hint: '********',
            validator: (v) =>
                (v?.length ?? 0) >= 10 ? null : 'Use at least 10 characters',
          ),
          AppField(
            'Confirm Password',
            password: true,
            hint: '********',
            validator: (v) =>
                v == password.text ? null : 'Passwords do not match',
          ),
          AsyncButton('Save', onPressed: _save),
        ],
      ),
    ),
  );
}

class DeleteScreen extends StatefulWidget {
  const DeleteScreen({super.key});
  @override
  State<DeleteScreen> createState() => _DeleteScreenState();
}

class _DeleteScreenState extends State<DeleteScreen> {
  static const _reasons = [
    "I don't use the app anymore",
    "I'm concerned about my privacy",
    "I'm taking a break",
    "I'm creating a different account",
    "The app doesn't meet my needs",
    'I experienced technical issues',
    'Other reason',
  ];

  int reason = 0;
  final password = TextEditingController();

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (password.text.isEmpty) {
      toast(context, 'Enter your password to confirm.');
      return;
    }
    final confirmed = await confirm(
      context,
      'Delete account?',
      'Your account is recoverable for a limited time, then permanently removed.',
      action: 'Delete',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    final store = StoreScope.read(context);
    final result = await runTask<Map<String, dynamic>>(
      context,
      () => store.deleteAccount(
        password: password.text,
        reason: _reasons[reason],
      ),
    );
    if (result == null || !mounted) return;

    final purgeAt = DateTime.tryParse('${result['recoverableUntil']}');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Account scheduled for deletion'),
        content: Text(
          purgeAt == null
              ? 'You can restore your account by signing in during the recovery window.'
              : 'You can restore your account by signing in before ${formatDay(purgeAt)}.\n\nDeleting the account does not cancel an App Store or Play Store subscription.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Delete Account',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Are you sure to delete your account?',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        const Text(
          'Deleting your account removes your profile, settings, events, and network. Your account stays recoverable for a grace period; after that the data is permanently deleted. Store subscriptions must be cancelled separately in the App Store or Play Store.',
          style: TextStyle(color: muted, height: 1.4),
        ),
        const SizedBox(height: 26),
        const Text('Why are you leaving?'),
        const SizedBox(height: 8),
        ...List.generate(
          _reasons.length,
          (i) => ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              reason == i ? Icons.radio_button_checked : Icons.radio_button_off,
              color: reason == i ? purple : muted,
              size: 21,
            ),
            title: Text(
              _reasons[i],
              style: const TextStyle(color: muted, fontSize: 13),
            ),
            onTap: () => setState(() => reason = i),
          ),
        ),
        const SizedBox(height: 12),
        AppField(
          'Confirm with your password',
          controller: password,
          password: true,
          hint: '********',
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                'Cancel',
                outline: true,
                danger: true,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(child: AsyncButton('Delete', danger: true, onPressed: _delete)),
          ],
        ),
      ],
    ),
  );
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool unreadOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).loadNotifications(silent: true);
    });
  }

  /// Notifications that reference an event deep-link into it.
  Future<void> _open(AppNotification item) async {
    final store = StoreScope.read(context);
    await store.markNotificationRead(item);
    final eventId = item.eventId;
    if (eventId == null || !mounted) return;
    final event = await runTask(
      context,
      () => store.api.events.get(eventId),
      showSpinner: false,
    );
    if (event != null && mounted) go(context, '/event', event);
  }

  /// Notifications arrive newest-first, so a day heading is emitted whenever
  /// the calendar day changes as the list is walked.
  static String _dayLabel(DateTime? value) {
    if (value == null) return 'Earlier';
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(value);
    final difference = today.difference(day).inDays;
    if (difference <= 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return DateFormat('EEEE').format(day);
    return formatDay(day);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final items = store.notifications
        .where((item) => !unreadOnly || !item.read)
        .toList();
    final unread = store.unreadNotifications;

    final rows = <Widget>[];
    String? heading;
    for (final item in items) {
      final label = _dayLabel(item.createdAt);
      if (label != heading) {
        heading = label;
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: 4, top: rows.isEmpty ? 0 : 14, bottom: 10),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: muted,
                letterSpacing: .4,
              ),
            ),
          ),
        );
      }
      rows.add(
        _NotificationCard(
          item: item,
          onTap: () => _open(item),
          onDismissed: () => store.deleteNotification(item),
        ),
      );
    }

    return PageFrame(
      title: 'Notifications',
      actions: [
        if (unread > 0)
          TextButton(
            onPressed: () => runAction(
              context,
              store.markAllNotificationsRead,
              showSpinner: false,
            ),
            child: const Text('Read all'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final value in [false, true])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FilterChip(
                    label: value ? 'Unread' : 'All',
                    // The unread tab carries the count so the badge in the
                    // header has an obvious home on this screen.
                    count: value ? unread : null,
                    selected: unreadOnly == value,
                    onTap: () => setState(() => unreadOnly = value),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (store.loadingNotifications && items.isEmpty) const LoadingBlock(),
          if (!store.loadingNotifications && items.isEmpty)
            EmptyState(
              unreadOnly
                  ? 'Nothing unread. You are all caught up.'
                  : 'No notifications yet.',
              icon: Icons.notifications_none,
            ),
          ...rows,
        ],
      ),
    );
  }
}

/// Soft background tints per notification category, so the list scans by
/// colour before it is read.
const _categoryTints = {
  'REMINDER': (Color(0xfff3edff), purple),
  'INVITATION': (Color(0xffe2edff), Color(0xff2563eb)),
  'GROUP_UPDATE': (Color(0xffe0f5f8), Color(0xff14818f)),
  'CONTACT_REQUEST': (Color(0xffe9f8ee), Color(0xff15803d)),
  'SECURITY': (Color(0xffffeceb), Color(0xffdc2626)),
  'SUBSCRIPTION': (Color(0xfffdf0dd), Color(0xffb45309)),
};

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.onTap,
    required this.onDismissed,
  });

  final AppNotification item;
  final VoidCallback onTap;
  final Future<void> Function() onDismissed;

  @override
  Widget build(BuildContext context) {
    final tint = _categoryTints[item.category] ?? _categoryTints['REMINDER']!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDismissed(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: const Color(0xffffeceb),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.delete_outline,
            color: Color(0xffdc2626),
            size: 21,
          ),
        ),
        child: Material(
          color: item.read
              ? Colors.white.withValues(alpha: .84)
              : const Color(0xfff7f4ff),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: item.read
                      ? const Color(0xfff0eafa)
                      : purple.withValues(alpha: .28),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tint.$1,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(item.icon, color: tint.$2, size: 20),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.3,
                                    fontWeight: item.read
                                        ? FontWeight.w600
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (!item.read)
                                Container(
                                  margin: const EdgeInsets.only(top: 5, left: 8),
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: purple,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.body,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: Color(0xff4a4360),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            relativeTime(item.createdAt),
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? purple : Colors.white.withValues(alpha: .8),
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? purple : const Color(0xfff0eafa),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : muted,
                ),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: .25)
                        : const Color(0xffede9fe),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : purple,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final preferences =
        store.user?.notificationPreferences ?? const NotificationPreferences();
    return PageFrame(
      title: 'Notification',
      child: Surface(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          children: preferences.asLabels.entries
              .map(
                (entry) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(entry.key, style: const TextStyle(fontSize: 13)),
                  value: entry.value,
                  activeThumbColor: Colors.white,
                  activeTrackColor: purple,
                  onChanged: (value) => runAction(
                    context,
                    () => store.setNotificationPreference(entry.key, value),
                    showSpinner: false,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final current = store.user?.languageLabel ?? 'English';
    return PageFrame(
      title: 'Language',
      child: Surface(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: AppUser.locales.values
              .map(
                (label) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label, style: const TextStyle(fontSize: 13)),
                  trailing: current == label
                      ? const Icon(Icons.check, color: purple, size: 18)
                      : null,
                  onTap: () => runAction(
                    context,
                    () => store.setLanguage(label),
                    success: 'Language updated',
                    showSpinner: false,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class AssistantsScreen extends StatefulWidget {
  const AssistantsScreen({super.key});
  @override
  State<AssistantsScreen> createState() => _AssistantsScreenState();
}

class _AssistantsScreenState extends State<AssistantsScreen> {
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = StoreScope.read(context);
    try {
      await store.loadDelegations();
    } on ApiException catch (error) {
      if (mounted && !error.isNetworkError) toastError(context, error.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return PageFrame(
      title: 'Secretary Access',
      child: Column(
        children: [
          PrimaryButton(
            'Add Secretary',
            icon: Icons.add,
            outline: true,
            onPressed: () async {
              await go(context, '/assistant/add');
              await _load();
            },
          ),
          const SizedBox(height: 14),
          if (loading) const LoadingBlock(),
          if (!loading && store.delegations.isEmpty)
            const EmptyState(
              'Add a secretary to help manage your calendar.',
              icon: Icons.person_outline,
            ),
          ...store.delegations.map(
            (delegation) => PersonTile(
              person: delegation.person,
              trailing: const Icon(Icons.chevron_right, color: muted),
              onTap: () async {
                await go(context, '/assistant/edit', delegation);
                await _load();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AssistantForm extends StatefulWidget {
  const AssistantForm({super.key, this.delegation});
  final Delegation? delegation;
  @override
  State<AssistantForm> createState() => _AssistantFormState();
}

class _AssistantFormState extends State<AssistantForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();

  int permission = 0;

  /// Set once a lookup finds an existing account for the entered email.
  String? existingUserId;
  bool lookedUp = false;

  bool get editing => widget.delegation != null;

  @override
  void initState() {
    super.initState();
    final delegation = widget.delegation;
    if (delegation != null) {
      name.text = delegation.person.name;
      email.text = delegation.person.email;
      permission = delegation.presetIndex;
    }
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  /// The API tells us whether this email already has an account, which decides
  /// between linking it and creating one.
  Future<void> _lookup() async {
    if (!email.text.contains('@')) {
      toast(context, 'Enter an email first.');
      return;
    }
    final store = StoreScope.read(context);
    final result = await runTask<Map<String, dynamic>>(
      context,
      () => store.api.delegations.lookup(email.text.trim()),
    );
    if (result == null || !mounted) return;
    final exists = result['exists'] == true;
    final user = result['user'];
    setState(() {
      lookedUp = true;
      existingUserId = exists && user is Map ? '${user['_id']}' : null;
      if (exists && user is Map && name.text.trim().isEmpty) {
        name.text = '${user['displayName'] ?? ''}';
      }
    });
    toast(
      context,
      exists
          ? 'Found an existing account — it will be linked.'
          : 'No account yet — one will be created with the password you set.',
    );
  }

  Future<void> _submit() async {
    if (!form.currentState!.validate()) return;
    final store = StoreScope.read(context);
    final preset = Delegation.presets[permission];

    if (preset == 'FULL_ACCESS') {
      final proceed = await confirm(
        context,
        'Full calendar access',
        'This person will be able to view and manage your entire calendar. Continue?',
      );
      if (!proceed || !mounted) return;
    }

    final delegation = widget.delegation;
    final done = await runAction(
      context,
      () async {
        if (delegation != null) {
          await store.api.delegations.updatePreset(delegation.id, preset);
        } else if (existingUserId != null) {
          await store.api.delegations.createForExistingAccount(
            userId: existingUserId!,
            preset: preset,
          );
        } else {
          await store.api.delegations.createForNewAccount(
            email: email.text.trim(),
            displayName: name.text.trim(),
            password: password.text,
            preset: preset,
          );
        }
        await store.loadDelegations();
      },
      success: delegation == null ? 'Secretary added' : 'Permission updated',
    );
    if (done && mounted) Navigator.pop(context);
  }

  Future<void> _revoke() async {
    final delegation = widget.delegation;
    if (delegation == null) return;
    final confirmed = await confirm(
      context,
      'Remove permission?',
      '${delegation.person.name} will lose access to your calendar.',
      action: 'Remove',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final store = StoreScope.read(context);
    final done = await runAction(
      context,
      () => store.revokeDelegation(delegation),
      success: 'Access revoked',
    );
    if (done && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: editing ? 'Secretary' : 'Add Secretary',
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (editing) ...[
            Center(
              child: Avatar(
                size: 110,
                index: widget.delegation!.person.avatarIndex,
                url: widget.delegation!.person.avatar?.secureUrl,
              ),
            ),
            const SizedBox(height: 25),
          ],
          AppField(
            'Name',
            controller: name,
            hint: 'Enter full name',
            readOnly: editing,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a name' : null,
          ),
          AppField(
            'Email',
            controller: email,
            hint: 'Enter their email',
            keyboard: TextInputType.emailAddress,
            readOnly: editing,
            validator: (v) =>
                v != null && v.contains('@') ? null : 'Enter an email',
          ),
          if (!editing) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _lookup,
                child: const Text('Check this email'),
              ),
            ),
            if (existingUserId == null)
              AppField(
                'Password for their new account',
                controller: password,
                password: true,
                hint: '********',
                validator: (v) => existingUserId != null || (v?.length ?? 0) >= 10
                    ? null
                    : 'Use at least 10 characters',
              ),
            if (lookedUp && existingUserId != null)
              const Surface(
                color: Color(0xffe2edff),
                child: Text(
                  'This email already has an account. Their existing sign-in keeps working.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
            const SizedBox(height: 16),
          ],
          const Text('Permission', style: TextStyle(fontSize: 16)),
          ...List.generate(
            Delegation.presetLabels.length,
            (i) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                permission == i
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: permission == i ? const Color(0xff628dff) : muted,
                size: 21,
              ),
              title: Text(
                Delegation.presetLabels[i],
                style: const TextStyle(fontSize: 13),
              ),
              onTap: () => setState(() => permission = i),
            ),
          ),
          const SizedBox(height: 24),
          AsyncButton(
            editing ? 'Save Changes' : 'Add Assistant / Secretary',
            onPressed: _submit,
          ),
          if (editing) ...[
            const SizedBox(height: 12),
            PrimaryButton(
              'Remove Permission',
              outline: true,
              danger: true,
              onPressed: _revoke,
            ),
          ],
        ],
      ),
    ),
  );
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  /// One card, plus the sliver of every card parked behind it.
  static const _cardHeight = 380.0;
  static const _peek = 76.0;
  static const _slide = Duration(milliseconds: 380);

  /// How much of the finger's travel the deck follows while a swipe is in
  /// flight — damped so the stack never slides out of its own box.
  static const _follow = .45;

  int selected = 2;
  double _drag = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).loadSubscription();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final order = [
      for (var i = 0; i < 3; i++)
        if (i != selected) i,
      selected,
    ];
    return PageFrame(
      title: 'Subscription Plan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Surface(
            color: const Color(0xffe2edff),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current plan: ${store.subscription?.label ?? (store.isPremium ? 'Premium' : 'Free Plan')}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (store.subscription?.expiresAt != null)
                        Text(
                          '${store.subscription!.willRenew ? 'Renews' : 'Ends'} ${formatDay(store.subscription!.expiresAt!)}',
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh from the store',
                  onPressed: () => runAction(
                    context,
                    () async {
                      await store.api.subscriptions.reconcile();
                      await store.loadSubscription();
                      await store.loadProfile();
                    },
                    success: 'Subscription refreshed',
                  ),
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
          ),
          if (store.subscription?.managementUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: PrimaryButton(
                'Manage subscription',
                outline: true,
                icon: Icons.open_in_new,
                onPressed: () async {
                  final url = Uri.tryParse(store.subscription!.managementUrl!);
                  if (url == null) return;
                  if (!await launchUrl(
                    url,
                    mode: LaunchMode.externalApplication,
                  )) {
                    if (context.mounted) {
                      toastError(context, 'Could not open the store.');
                    }
                  }
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: SizedBox(
              height: _cardHeight + _peek * 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => setState(() => _dragging = true),
                onVerticalDragUpdate: _slideBy,
                onVerticalDragEnd: _settle,
                onVerticalDragCancel: () => setState(() {
                  _dragging = false;
                  _drag = 0;
                }),
                child: AnimatedContainer(
                  duration: _dragging || MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : _slide,
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(0, _drag * _follow, 0),
                  child: Stack(
                    children: [
                      for (final i in order)
                        AnimatedPositioned(
                          key: ValueKey(i),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : _slide,
                          curve: Curves.easeInOutCubic,
                          top: order.indexOf(i) * _peek,
                          left: (2 - order.indexOf(i)) * 4.0,
                          right: (2 - order.indexOf(i)) * 4.0,
                          height: _cardHeight,
                          child: GestureDetector(
                            onTap: () => setState(() => selected = i),
                            child: ClipPath(
                              clipper: PlanClipper(),
                              child: ColoredBox(
                                color: i == 0
                                    ? Colors.black
                                    : i == 1
                                    ? const Color(0xffe9e7ef)
                                    : const Color(0xff5419de),
                                child: Padding(
                                  padding: const EdgeInsets.all(1),
                                  child: ClipPath(
                                    clipper: PlanClipper(),
                                    child: Container(
                                      padding: const EdgeInsets.fromLTRB(
                                        18,
                                        18,
                                        18,
                                        12,
                                      ),
                                      color: i == 0
                                          ? Colors.black
                                          : i == 1
                                          ? Colors.white
                                          : const Color(0xff5419de),
                                      child: planContent(
                                        context,
                                        i,
                                        selected == i,
                                        store,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A swipe walks the deck along the axis the cards are stacked on: up pulls
  /// the next plan forward, down goes back. Past either end the travel is
  /// throttled so the stack visibly refuses rather than sliding into nothing.
  void _slideBy(DragUpdateDetails details) {
    setState(() {
      _drag = (_drag + details.delta.dy).clamp(
        selected < 2 ? -_peek : -_peek * .25,
        selected > 0 ? _peek : _peek * .25,
      );
    });
  }

  void _settle(DragEndDetails details) {
    final flick = details.primaryVelocity ?? 0;
    var next = selected;
    if (_drag <= -_peek * .35 || flick <= -520) {
      next = selected + 1;
    } else if (_drag >= _peek * .35 || flick >= 520) {
      next = selected - 1;
    }
    setState(() {
      selected = next.clamp(0, 2);
      _drag = 0;
      _dragging = false;
    });
  }

  Widget planContent(
    BuildContext context,
    int i,
    bool active,
    AppStore store,
  ) {
    final ink = i == 1 ? Colors.black : Colors.white;
    final features = i == 0
        ? ['Up to 50 events/month', 'Basic reminders', 'Manual event entry']
        : [
            '7 days Free Trial',
            'Everything in Free, plus AI',
            'Unlimited events',
            'AI scheduling & suggestions',
            'Smart conflict detection',
          ];
    final isCurrent = i == 0 ? !store.isPremium : store.isPremium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ['Free Plan', 'Premium Monthly', 'Premium Yearly'][i],
          style: TextStyle(
            color: ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          i == 0
              ? 'Perfect for getting started'
              : 'Powerful AI for your schedule',
          style: TextStyle(color: ink.withValues(alpha: .6), fontSize: 10),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                features.first,
                style: TextStyle(
                  color: ink.withValues(alpha: .7),
                  fontSize: 11,
                ),
              ),
            ),
            Text(
              [r'$0', r'$8.99', r'$79.99'][i],
              style: TextStyle(
                color: ink,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              i == 2 ? '/year' : '/month',
              style: TextStyle(color: ink.withValues(alpha: .7), fontSize: 9),
            ),
          ],
        ),
        if (active) ...[
          const SizedBox(height: 18),
          for (final feature in features.skip(1))
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 17,
                    color: ink.withValues(alpha: .7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      feature,
                      style: TextStyle(
                        color: ink.withValues(alpha: .7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: i == 0
                    ? Colors.grey
                    : i == 1
                    ? purple
                    : Colors.white,
                foregroundColor: i == 2 ? purple : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              onPressed: () {
                if (isCurrent) {
                  toast(context, 'This is your current plan.');
                  return;
                }
                go(
                  context,
                  '/summary',
                  i == 1 ? 'Premium Monthly' : 'Premium Yearly',
                );
              },
              child: Text(
                isCurrent
                    ? 'Current Plan'
                    : i == 1
                    ? 'Get Premium Monthly'
                    : 'Get Premium Yearly',
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (i == 2)
            Center(
              child: Text(
                r'Only $6.67/month · Save $27.89 every year',
                style: TextStyle(color: ink.withValues(alpha: .6), fontSize: 9),
              ),
            ),
        ],
      ],
    );
  }
}

class PlanClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(18, 0)
    ..lineTo(size.width * .37, 0)
    ..quadraticBezierTo(size.width * .43, 0, size.width * .46, 12)
    ..lineTo(size.width * .54, 45)
    ..quadraticBezierTo(size.width * .56, 52, size.width * .6, 52)
    ..lineTo(size.width - 18, 52)
    ..quadraticBezierTo(size.width, 52, size.width, 70)
    ..lineTo(size.width, size.height - 18)
    ..quadraticBezierTo(size.width, size.height, size.width - 18, size.height)
    ..lineTo(18, size.height)
    ..quadraticBezierTo(0, size.height, 0, size.height - 18)
    ..lineTo(0, 18)
    ..quadraticBezierTo(0, 0, 18, 0)
    ..close();
  @override
  bool shouldReclip(PlanClipper oldClipper) => false;
}

/// Purchases run through the App Store / Play Store via RevenueCat, so this
/// screen explains the hand-off and reconciles entitlements afterwards.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key, required this.plan});
  final String plan;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final yearly = plan == 'Premium Yearly';
    final price = yearly ? r'$79.99 / year' : r'$8.99 / month';

    return PageFrame(
      title: 'Summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Surface(
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Plan', style: TextStyle(color: muted)),
                    const Spacer(),
                    Text(plan),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    const Text('Price', style: TextStyle(color: muted)),
                    const Spacer(),
                    Text(
                      price,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const Divider(),
                const Row(
                  children: [
                    Text('Trial', style: TextStyle(color: muted)),
                    Spacer(),
                    Text('7 days free'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Surface(
            color: Color(0xffe2edff),
            child: Text(
              'Premium is billed by the App Store or Play Store. Complete the purchase there, then tap Refresh below and your account unlocks automatically.',
              style: TextStyle(fontSize: 12, color: muted, height: 1.4),
            ),
          ),
          const SizedBox(height: 18),
          AsyncButton(
            'I completed the purchase — refresh',
            icon: Icons.refresh,
            onPressed: () async {
              await runAction(
                context,
                () async {
                  await store.api.subscriptions.reconcile();
                  await store.loadSubscription();
                  await store.loadProfile();
                },
                success: 'Subscription refreshed',
              );
              if (context.mounted && store.isPremium) Navigator.pop(context);
            },
          ),
          const SizedBox(height: 10),
          const Text(
            'In-app purchase needs the RevenueCat SDK and store products configured for this build.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }
}

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});
  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      note = TextEditingController();
  bool initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    final user = StoreScope.of(context).user;
    if (user == null) return;
    name.text = user.name;
    email.text = user.email;
    phone.text = user.phone;
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!form.currentState!.validate()) return;
    final store = StoreScope.read(context);
    final done = await runAction(
      context,
      () => store.api.legal.submitSupportRequest(
        name: name.text.trim(),
        email: email.text.trim(),
        phone: phone.text.trim(),
        note: note.text.trim(),
      ),
      success: 'Thanks — support has your message.',
    );
    if (done && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Contact Us',
    child: Form(
      key: form,
      child: Column(
        children: [
          AppField(
            'Name',
            controller: name,
            hint: 'Your name',
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter your name' : null,
          ),
          AppField(
            'Email Address',
            controller: email,
            hint: 'email@example.com',
            keyboard: TextInputType.emailAddress,
            validator: (v) =>
                v != null && v.contains('@') ? null : 'Enter your email',
          ),
          AppField(
            'Phone Number',
            controller: phone,
            hint: 'Optional',
            keyboard: TextInputType.phone,
          ),
          AppField(
            'Note',
            controller: note,
            hint: 'Describe what you need...',
            lines: 5,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Write your message' : null,
          ),
          AsyncButton('Send', onPressed: _send),
        ],
      ),
    ),
  );
}

class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, this.privacy = false});
  final bool privacy;
  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  LegalDocument? document;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = StoreScope.read(context);
    try {
      final locale = store.user?.locale ?? 'en';
      final fetched = await store.api.legal.document(
        widget.privacy ? 'privacy' : 'terms',
        locale: locale,
      );
      if (mounted) setState(() => document = fetched);
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: widget.privacy ? 'Privacy Policy' : 'Terms & Condition',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading) const LoadingBlock(height: 220),
        if (!loading && error != null)
          EmptyState(
            error!,
            icon: Icons.description_outlined,
            action: PrimaryButton(
              'Try again',
              outline: true,
              onPressed: () {
                setState(() {
                  loading = true;
                  error = null;
                });
                _load();
              },
            ),
          ),
        if (document != null) ...[
          Text(
            document!.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Version ${document!.version}',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 16),
          SelectableText(
            document!.content,
            textAlign: TextAlign.justify,
            style: const TextStyle(color: muted, fontSize: 14, height: 1.55),
          ),
        ],
      ],
    ),
  );
}
