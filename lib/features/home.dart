import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/design.dart';
import '../core/store.dart';
import '../core/time.dart';
import 'events.dart';
import 'notes.dart';

const _ink = Color(0xff1e1930);
const _muted = Color(0xff6f6688);
const _violet = Color(0xff7c3aed);

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.onCalendar, required this.onVoice});
  final VoidCallback onCalendar, onVoice;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final now = DateTime.now();
    final today = store.todayEvents;
    final next = today
        .where(
          (event) => event.occurrenceStartAt.isAfter(now) && !event.completed,
        )
        .firstOrNull;
    final until = next?.occurrenceStartAt.difference(now);
    final nextLabel = until == null
        ? ''
        : until.inMinutes < 1
        ? 'starting soon'
        : until.inHours > 0
        ? 'next in ${until.inHours}h ${until.inMinutes % 60}m'
        : 'next in ${until.inMinutes}m';
    return RefreshIndicator(
      color: _violet,
      onRefresh: () async {
        try {
          await Future.wait([
            store.loadEvents(silent: true),
            store.loadNotifications(silent: true),
            store.loadNotes(silent: true),
          ]);
        } catch (error) {
          if (context.mounted) {
            toastError(context, 'Could not refresh. Please try again.');
          }
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 96),
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: Colors.white.withValues(alpha: .8),
                    shape: StadiumBorder(
                      side: BorderSide(color: _violet.withValues(alpha: .12)),
                    ),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: onCalendar,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                              color: _violet,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                DateFormat('EEE, MMM d').format(now),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: store.unreadNotifications > 0,
                label: Text(
                  store.unreadNotifications > 9
                      ? '9+'
                      : '${store.unreadNotifications}',
                ),
                child: IconButton(
                  tooltip: 'Notifications',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: .8),
                  ),
                  onPressed: () => go(context, '/notifications'),
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    color: Color(0xff4a3f66),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'Profile',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => go(context, '/profile'),
                  child: Avatar(
                    profile: true,
                    size: 44,
                    url: store.user?.avatar?.secureUrl,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '${greeting()}, ${store.user?.firstNameOrEmail ?? 'there'}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -.7,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            today.isEmpty
                ? 'Your day, with a little more breathing room.'
                : '${today.length} ${today.length == 1 ? 'event' : 'events'} today${nextLabel.isEmpty ? '' : ' · $nextLabel'}',
            style: const TextStyle(fontSize: 13, color: _muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          Center(child: VoiceOrb(size: 184, onTap: onVoice)),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'Tap and say it',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _violet,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Make a plan. Leave the details to me.',
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Today',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              TextButton(
                onPressed: onCalendar,
                child: const Text(
                  'View all',
                  style: TextStyle(
                    color: _violet,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (store.loadingEvents && today.isEmpty)
            const LoadingBlock()
          else if (today.isEmpty)
            _HomeCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(
                      Icons.wb_sunny_outlined,
                      color: _violet,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'A fresh start',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Tap + to plan something good.',
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...today.take(3).map((event) {
              final color = event.isShared ? _violet : const Color(0xff22b3c4);
              final upcoming = event == next;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HomeCard(
                  onTap: () async {
                    await go(context, '/event', event);
                    if (context.mounted) {
                      await runAction(
                        context,
                        () => store.loadEvents(silent: true),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(17),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 4,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                    decoration: event.completed
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${event.start.format(context)}${event.location.isEmpty ? ' – ${event.end.format(context)}' : ' · ${event.location}'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (upcoming) ...[
                            const SizedBox(width: 8),
                            Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xffede9fe),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Up next',
                                  style: TextStyle(
                                    color: _violet,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
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
            }),
          if (store.invitations.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Invitations',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 12),
            ...store.invitations.map(
              (event) => EventTile(
                event: event,
                onChanged: () => store.loadEvents(silent: true),
              ),
            ),
          ],
          const SizedBox(height: 12),
          NotesPreview(onAll: () => go(context, '/notes')),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .88),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: _violet.withValues(alpha: .1)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: child),
  );
}

class DashboardNav extends StatelessWidget {
  const DashboardNav({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(16, 6, 16, 20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .95),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _violet.withValues(alpha: .1)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff3a2660).withValues(alpha: .12),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const labels = ['Home', 'AI Chat', 'Calendar', 'Network'];
          final unit = (constraints.maxWidth - 18) / 4.9;
          return Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  width: unit * (selected == i ? 1.9 : 1),
                  child: Semantics(
                    button: true,
                    selected: selected == i,
                    label: labels[i],
                    child: Tooltip(
                      message: labels[i],
                      child: Material(
                        color: selected == i ? _violet : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => onSelected(i),
                          child: SizedBox(
                            height: 52,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      [
                                        Icons.home_outlined,
                                        Icons.chat_bubble_outline_rounded,
                                        Icons.calendar_month_outlined,
                                        Icons.people_outline_rounded,
                                      ][i],
                                      color: selected == i
                                          ? Colors.white
                                          : const Color(0xff8b7fb0),
                                      size: 23,
                                    ),
                                    if (selected == i) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        labels[i],
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}
