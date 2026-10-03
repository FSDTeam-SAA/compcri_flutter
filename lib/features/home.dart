import 'package:flutter/material.dart' hide Text;
import 'package:intl/intl.dart';

import '../core/design.dart';
import '../core/store.dart';
import '../core/time.dart';
import 'events.dart';
import 'notes.dart';
import '../core/i18n.dart';

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
        ? tr('starting soon')
        : until.inHours > 0
        ? tr('next in {hours}h {minutes}m', {
            'hours': until.inHours,
            'minutes': until.inMinutes % 60,
          })
        : tr('next in {minutes}m', {'minutes': until.inMinutes});
    return RefreshIndicator(
      color: AppPalette.of(context).accent,
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
                    color: AppPalette.of(context).surface.withValues(alpha: .8),
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
                            Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                              color: AppPalette.of(context).accent,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                DateFormat('EEE, MMM d').format(now),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppPalette.of(context).ink,
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
                  tooltip: tr('Notifications'),
                  style: IconButton.styleFrom(
                    backgroundColor: AppPalette.of(
                      context,
                    ).surface.withValues(alpha: .8),
                  ),
                  onPressed: () => go(context, '/notifications'),
                  icon: Icon(
                    Icons.notifications_none_rounded,
                    color: AppPalette.of(context).ink,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: tr('Profile'),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => go(context, '/profile'),
                  child: Avatar(
                    profile: true,
                    size: 44,
                    name: store.user?.name,
                    url: store.user?.avatar?.secureUrl,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            tr('{greeting}, {name}', {
              'greeting': greeting(),
              'name': store.user?.firstNameOrEmail ?? tr('there'),
            }),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppPalette.of(context).ink,
              letterSpacing: -.7,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            today.isEmpty
                ? 'Your day, with a little more breathing room.'
                : '${trCount(today.length, '{count} event today', '{count} events today')}${nextLabel.isEmpty ? '' : ' · $nextLabel'}',
            style: TextStyle(
              fontSize: 13,
              color: AppPalette.of(context).muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Center(child: VoiceOrb(size: 184, onTap: onVoice)),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Tap and say it',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppPalette.of(context).accent,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Make a plan. Leave the details to me.',
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.of(context).muted,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Today',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.of(context).ink,
                  ),
                ),
              ),
              TextButton(
                onPressed: onCalendar,
                child: Text(
                  'View all',
                  style: TextStyle(
                    color: AppPalette.of(context).accent,
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
                    Icon(
                      Icons.wb_sunny_outlined,
                      color: AppPalette.of(context).accent,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'A fresh start',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppPalette.of(context).ink,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Tap + to plan something good.',
                            style: TextStyle(
                              color: AppPalette.of(context).muted,
                              fontSize: 12,
                            ),
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
                                    color: AppPalette.of(context).ink,
                                    decoration: event.completed
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${formatClock(event.start)}${event.location.isEmpty ? ' – ${formatClock(event.end)}' : ' · ${event.location}'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.of(context).muted,
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
                                  color: AppPalette.of(
                                    context,
                                  ).wash(const Color(0xffede9fe)),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Up next',
                                  style: TextStyle(
                                    color: AppPalette.of(context).accent,
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
            Text(
              'Invitations',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppPalette.of(context).ink,
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
    color: AppPalette.of(context).surface.withValues(alpha: .88),
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
        color: AppPalette.of(context).surface.withValues(alpha: .95),
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
                    label: tr(labels[i]),
                    child: Tooltip(
                      message: tr(labels[i]),
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
                                          : AppPalette.of(context).muted,
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
