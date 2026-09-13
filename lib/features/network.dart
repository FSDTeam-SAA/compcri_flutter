import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/design.dart';
import '../core/store.dart';
import 'events.dart';
import '../core/i18n.dart';

class NetworkTab extends StatefulWidget {
  const NetworkTab({super.key});
  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  bool groups = false;
  String query = '', filter = 'All';
  final code = TextEditingController();

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> _addContact() async {
    final store = StoreScope.read(context);
    final input = TextEditingController();
    var relation = 'Friend';

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Add Contact Code', style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ask your contact for the code shown on their profile.',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 12),
              AppField('', hint: 'e.g. JOHN-456-FA', controller: input),
              SelectField(
                'Relation',
                value: relation,
                values: const [
                  'Friend',
                  'Family',
                  'Coworker',
                  'Assistant',
                  'Other',
                ],
                onChanged: (value) => update(() => relation = value),
              ),
              PrimaryButton(
                'Send request',
                onPressed: () {
                  if (input.text.trim().isEmpty) return;
                  Navigator.pop(dialogContext, true);
                },
              ),
            ],
          ),
        ),
      ),
    );

    final value = input.text.trim();
    // The dialog route needs to finish closing before its controller goes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (submitted != true || !mounted) return;

    await runAction(
      context,
      () => store.sendContactRequest(value, relation),
      success: 'Contact request sent',
    );
  }

  Future<void> _createGroup() async {
    final store = StoreScope.read(context);
    final input = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('New group', style: TextStyle(fontSize: 17)),
        content: AppField('', hint: 'Group name', controller: input),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final name = input.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (submitted != true || name.isEmpty || !mounted) return;

    await runAction(
      context,
      () => store.createGroup(name),
      success: 'Group created',
    );
  }

  bool _matchesFilter(Person person) {
    if (filter == 'All') return true;
    final relation = person.relation.toLowerCase();
    return switch (filter) {
      'Friends' => relation == 'friend',
      'Co Workers' => relation == 'coworker',
      'Family' => relation == 'family',
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final needle = query.toLowerCase();
    final people = store.contacts
        .where(
          (person) =>
              person.name.toLowerCase().contains(needle) &&
              _matchesFilter(person),
        )
        .toList();
    final pending =
        store.contactRequests.length + store.groupInvitations.length;

    return Column(
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const SizedBox(width: 40),
              const Expanded(
                child: Center(
                  child: Text('Network', style: TextStyle(fontSize: 16)),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: tr('Requests and invitations'),
                    onPressed: () => go(context, '/requests'),
                    icon: const Icon(Icons.person_add_alt, size: 21),
                  ),
                  if (pending > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xffff4e2c),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '$pending',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [false, true]
              .map(
                (value) => Expanded(
                  child: InkWell(
                    onTap: () => setState(() => groups = value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: groups == value
                                ? purple
                                : const Color(0xffe8e4f0),
                            width: groups == value ? 2 : 1,
                          ),
                        ),
                      ),
                      child: Text(
                        value ? 'Groups' : 'Contacts',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: groups == value ? purple : muted,
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => store.loadNetwork(silent: true),
            child: ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: groups
                  ? _groupsView(store)
                  : _contactsView(store, people),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _contactsView(AppStore store, List<Person> people) => [
    Row(
      children: [
        Expanded(
          child: InviteCode(
            label: 'Your Code',
            code: store.user?.contactCode ?? '—',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PrimaryButton(
            'Add Contact',
            icon: Icons.add,
            onPressed: _addContact,
          ),
        ),
      ],
    ),
    const SizedBox(height: 20),
    Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (value) => setState(() => query = value),
            decoration: InputDecoration(
              hintText: tr('Search contact'),
              prefixIcon: const Icon(Icons.search, color: lilac, size: 22),
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: tr('Filter contacts'),
          icon: const Icon(Icons.filter_list, color: lilac),
          onSelected: (value) => setState(() => filter = value),
          itemBuilder: (_) => ['All', 'Family', 'Friends', 'Co Workers']
              .map(
                (value) => PopupMenuItem(
                  value: value,
                  child: Text(
                    value,
                    style: TextStyle(color: filter == value ? purple : null),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    ),
    const SizedBox(height: 10),
    if (store.loadingNetwork && store.contacts.isEmpty) const LoadingBlock(),
    if (!store.loadingNetwork && people.isEmpty)
      EmptyState(
        store.contacts.isEmpty
            ? 'No contacts yet. Share your code or add someone by theirs.'
            : 'No contacts match this search.',
        icon: Icons.contacts_outlined,
      ),
    ...people.map(
      (person) => PersonTile(
        person: person,
        onTap: () async {
          await go(context, '/contact', person);
          if (mounted) await store.loadNetwork(silent: true);
        },
      ),
    ),
  ];

  List<Widget> _groupsView(AppStore store) => [
    Surface(
      child: Column(
        children: [
          const Icon(Icons.groups, color: Color(0xffbbcbff), size: 36),
          const SizedBox(height: 6),
          const Text('Join a Group', style: TextStyle(color: muted)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: code,
                  decoration: InputDecoration(
                    hintText: tr('Enter invite code'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: PrimaryButton(
                  'Join',
                  onPressed: () async {
                    final value = code.text.trim();
                    if (value.isEmpty) {
                      toast(context, 'Enter an invite code.');
                      return;
                    }
                    final done = await runAction(
                      context,
                      () => store.joinGroup(value),
                      success: 'Joined the group',
                    );
                    if (done && mounted) code.clear();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _createGroup,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create a group'),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    if (store.loadingNetwork && store.groups.isEmpty) const LoadingBlock(),
    if (!store.loadingNetwork && store.groups.isEmpty)
      const EmptyState(
        'You are not in any groups yet.',
        icon: Icons.groups_outlined,
      ),
    ...store.groups.map(
      (group) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Surface(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(
                  Icons.groups_outlined,
                  color: lilac,
                  size: 32,
                ),
                title: Text(group.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  trCount(
                    group.memberCount,
                    '{count} member',
                    '{count} members',
                  ),
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
                trailing: const Icon(Icons.chevron_right, color: muted),
                onTap: () async {
                  await go(context, '/group', group);
                  if (mounted) await store.loadNetwork(silent: true);
                },
              ),
              InviteCode(code: group.code),
            ],
          ),
        ),
      ),
    ),
  ];
}

class InviteCode extends StatelessWidget {
  const InviteCode({super.key, this.label = 'Invite Code', required this.code});
  final String label, code;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: const Color(0xffe0f5f8),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: muted)),
              const SizedBox(height: 6),
              Text(code, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: code));
            toast(context, tr('{label} copied', {'label': tr(label)}));
          },
          child: const Padding(
            padding: EdgeInsets.all(5),
            child: Icon(Icons.copy, size: 14, color: Color(0xffa3c6cd)),
          ),
        ),
      ],
    ),
  );
}

class PersonTile extends StatelessWidget {
  const PersonTile({
    super.key,
    required this.person,
    required this.onTap,
    this.trailing,
  });
  final Person person;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Surface(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: Avatar(
          index: person.avatarIndex,
          url: person.avatar?.secureUrl,
        ),
        title: Text(person.name, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          person.relation.isEmpty ? person.email : person.relation,
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    ),
  );
}

/// Incoming contact requests and group invitations.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).loadNetwork(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final empty =
        store.contactRequests.isEmpty && store.groupInvitations.isEmpty;
    return PageFrame(
      title: 'Requests',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (empty)
            const EmptyState(
              'No pending requests or invitations.',
              icon: Icons.inbox_outlined,
            ),
          if (store.contactRequests.isNotEmpty) ...[
            const Text('Contact requests', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 10),
            ...store.contactRequests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Surface(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Avatar(
                            index: request.person.avatarIndex,
                            url: request.person.avatar?.secureUrl,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(request.person.name),
                                Text(
                                  request.person.email,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: PrimaryButton(
                              'Decline',
                              outline: true,
                              onPressed: () => runAction(
                                context,
                                () => store.respondToContactRequest(
                                  request,
                                  false,
                                ),
                                success: 'Request declined',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PrimaryButton(
                              'Accept',
                              onPressed: () => runAction(
                                context,
                                () => store.respondToContactRequest(
                                  request,
                                  true,
                                  relation: 'Friend',
                                ),
                                success: 'Contact added',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (store.groupInvitations.isNotEmpty) ...[
            const Text('Group invitations', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 10),
            ...store.groupInvitations.map(
              (invitation) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Surface(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.groups_outlined,
                          color: lilac,
                        ),
                        title: Text(invitation.groupName),
                        subtitle: Text(
                          tr('Invited as {role}', {
                            'role': tr(invitation.role.toLowerCase()),
                          }),
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: PrimaryButton(
                              'Decline',
                              outline: true,
                              onPressed: () => runAction(
                                context,
                                () => store.respondToGroupInvitation(
                                  invitation,
                                  false,
                                ),
                                success: 'Invitation declined',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PrimaryButton(
                              'Join',
                              onPressed: () => runAction(
                                context,
                                () => store.respondToGroupInvitation(
                                  invitation,
                                  true,
                                ),
                                success: 'Joined the group',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ContactDetails extends StatefulWidget {
  const ContactDetails({super.key, required this.contact});
  final Person contact;
  @override
  State<ContactDetails> createState() => _ContactDetailsState();
}

class _ContactDetailsState extends State<ContactDetails> {
  int tab = 0;
  List<CalendarEvent> shared = const <CalendarEvent>[];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadShared();
  }

  /// Events this contact shared with the signed-in user, and vice versa.
  Future<void> _loadShared() async {
    final store = StoreScope.read(context);
    final now = DateTime.now();
    try {
      final events = await store.api.network.contactEvents(
        userId: widget.contact.id,
        from: now.subtract(const Duration(days: 30)),
        to: now.add(const Duration(days: 180)),
      );
      if (mounted) setState(() => shared = events);
    } on ApiException catch (error) {
      if (mounted && !error.isNetworkError) toastError(context, error.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<CalendarEvent> get _visible {
    final now = DateTime.now();
    return switch (tab) {
      0 =>
        shared
            .where(
              (event) =>
                  event.occurrenceStartAt.isBefore(now) &&
                  event.occurrenceEndAt.isAfter(now),
            )
            .toList(),
      1 =>
        shared.where((event) => event.occurrenceStartAt.isAfter(now)).toList(),
      _ =>
        shared.where((event) => event.occurrenceEndAt.isBefore(now)).toList(),
    };
  }

  Future<void> _changeRelation() async {
    final store = StoreScope.read(context);
    var relation = widget.contact.relation.isEmpty
        ? 'Friend'
        : widget.contact.relation;
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Relation', style: TextStyle(fontSize: 17)),
          content: SelectField(
            '',
            value:
                const [
                  'Friend',
                  'Family',
                  'Coworker',
                  'Assistant',
                  'Other',
                ].contains(relation)
                ? relation
                : 'Other',
            values: const [
              'Friend',
              'Family',
              'Coworker',
              'Assistant',
              'Other',
            ],
            onChanged: (value) => update(() => relation = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, relation),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !mounted) return;
    await runAction(
      context,
      () => store.updateContactRelation(widget.contact, saved),
      success: 'Relation updated',
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final contact = widget.contact;
    return PageFrame(
      title: 'Contact',
      child: Column(
        children: [
          Surface(
            child: Column(
              children: [
                Row(
                  children: [
                    Avatar(
                      index: contact.avatarIndex,
                      size: 54,
                      url: contact.avatar?.secureUrl,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contact.name,
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            contact.relation.isEmpty
                                ? contact.email
                                : contact.relation,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'relation') {
                          await _changeRelation();
                          return;
                        }
                        if (!context.mounted) return;
                        final confirmed = await confirm(
                          context,
                          'Remove contact?',
                          tr('Remove {name} from your contacts?', {
                            'name': contact.name,
                          }),
                          action: 'Remove',
                          danger: true,
                        );
                        if (!confirmed || !context.mounted) return;
                        final done = await runAction(
                          context,
                          () => store.removeContact(contact),
                          success: 'Contact removed',
                        );
                        if (done && context.mounted) Navigator.pop(context);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'relation',
                          child: Text('Change relation'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove contact'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Phone Number or Whatsapp',
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                          const SizedBox(height: 8),
                          Text(contact.phone.isEmpty ? '—' : contact.phone),
                          const SizedBox(height: 18),
                          const Text(
                            'Profession',
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            contact.profession.isEmpty
                                ? '—'
                                : contact.profession,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Country',
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                          const SizedBox(height: 8),
                          Text(contact.country.isEmpty ? '—' : contact.country),
                          const SizedBox(height: 18),
                          const Text(
                            'City',
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                          const SizedBox(height: 8),
                          Text(contact.city.isEmpty ? '—' : contact.city),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: List.generate(
              3,
              (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    showCheckmark: false,
                    labelPadding: EdgeInsets.zero,
                    label: Text(
                      ['Ongoing', 'Upcoming', 'Past'][i],
                      style: TextStyle(
                        fontSize: 10,
                        color: tab == i ? Colors.white : purple,
                      ),
                    ),
                    selectedColor: purple,
                    backgroundColor: const Color(0xfff0eaff),
                    side: BorderSide.none,
                    selected: tab == i,
                    onSelected: (_) => setState(() => tab = i),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (loading) const LoadingBlock(height: 100),
          if (!loading && _visible.isEmpty)
            const EmptyState(
              'No shared events in this range.',
              icon: Icons.event_available_outlined,
            ),
          ..._visible.map((event) => EventTile(event: event)),
        ],
      ),
    );
  }
}

class GroupDetails extends StatefulWidget {
  const GroupDetails({super.key, required this.group});
  final Group group;
  @override
  State<GroupDetails> createState() => _GroupDetailsState();
}

class _GroupDetailsState extends State<GroupDetails> {
  late Group group = widget.group;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final store = StoreScope.read(context);
    try {
      final fresh = await store.api.network.group(widget.group.id);
      if (mounted) setState(() => group = fresh);
    } on ApiException catch (error) {
      if (mounted && !error.isNetworkError) toastError(context, error.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Group events live on members' calendars and arrive through the shared
  /// events feed, so filter that rather than refetching.
  List<CalendarEvent> _groupEvents(AppStore store) {
    final now = DateTime.now();
    return [...store.events, ...store.sharedEvents]
        .where(
          (event) =>
              event.groupId == group.id && event.occurrenceEndAt.isAfter(now),
        )
        .toList()
      ..sort((a, b) => a.occurrenceStartAt.compareTo(b.occurrenceStartAt));
  }

  Future<void> _invite() async {
    final store = StoreScope.read(context);
    final memberIds = group.members.map((member) => member.person.id).toSet();
    final candidates = store.contacts
        .where((person) => !memberIds.contains(person.id))
        .toList();

    if (candidates.isEmpty) {
      toast(context, 'All of your contacts are already in this group.');
      return;
    }

    final chosen = await showModalBottomSheet<Person>(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Invite a contact')),
            ...candidates.map(
              (person) => ListTile(
                leading: Avatar(
                  index: person.avatarIndex,
                  url: person.avatar?.secureUrl,
                ),
                title: Text(person.name),
                subtitle: Text(
                  person.email,
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.pop(sheetContext, person),
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    await runAction(
      context,
      () =>
          store.api.network.inviteMember(groupId: group.id, userId: chosen.id),
      success: tr('Invitation sent to {name}', {'name': chosen.name}),
    );
  }

  Future<void> _leaveOrDelete() async {
    final store = StoreScope.read(context);
    final owner = group.isOwnedBy(store.user?.id);
    final confirmed = await confirm(
      context,
      owner ? 'Delete group?' : 'Leave group?',
      owner
          ? tr('Deleting removes {group} for every member.', {
              'group': group.name,
            })
          : tr('You will leave {group}.', {'group': group.name}),
      action: owner ? 'Delete' : 'Leave',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    final done = await runAction(context, () async {
      if (owner) {
        await store.api.network.deleteGroup(group.id);
        await store.loadNetwork(silent: true);
      } else {
        await store.leaveGroup(group);
      }
    }, success: owner ? 'Group deleted' : 'You left the group');
    if (done && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final owner = group.isOwnedBy(store.user?.id);
    final events = _groupEvents(store);

    return PageFrame(
      title: 'Group',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.groups_outlined, color: lilac, size: 36),
            title: Text(group.name),
            subtitle: Text(
              '${trCount(group.members.length, '{count} member', '{count} members')}'
              '${owner ? ' · ${tr('you own this group')}' : ''}',
              style: const TextStyle(fontSize: 11, color: muted),
            ),
            trailing: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          InviteCode(code: group.code),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Upcoming events'),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await go(context, '/event/create');
                  if (mounted) await store.loadEvents(silent: true);
                },
                child: const Text('Add New +'),
              ),
            ],
          ),
          if (events.isEmpty)
            const EmptyState(
              'No upcoming events shared with this group.',
              icon: Icons.event_outlined,
            ),
          ...events.map((event) => EventTile(event: event)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Members'),
              const Spacer(),
              TextButton(onPressed: _invite, child: const Text('Invite +')),
            ],
          ),
          ...group.members.map(
            (member) => PersonTile(
              person: member.person,
              trailing: Text(
                member.role.toLowerCase(),
                style: const TextStyle(fontSize: 10, color: muted),
              ),
              onTap: () {
                final contact = store.contacts.firstWhere(
                  (person) => person.id == member.person.id,
                  orElse: () => member.person,
                );
                go(context, '/contact', contact);
              },
            ),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            owner ? 'Delete Group' : 'Leave Group',
            outline: true,
            danger: true,
            onPressed: _leaveOrDelete,
          ),
        ],
      ),
    );
  }
}
