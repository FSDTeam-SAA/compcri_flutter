import 'package:flutter/material.dart' hide Text;

import '../core/design.dart';
import '../core/i18n.dart';
import '../core/store.dart';

/// The active calendar applies to the dashboard, manual events and new chats.
class CalendarSwitcher extends StatelessWidget {
  const CalendarSwitcher({super.key});

  Future<void> _choose(BuildContext context) async {
    final store = StoreScope.read(context);
    final loaded = await runAction(context, store.refreshCalendars);
    if (!loaded || !context.mounted) return;
    final selected = await showModalBottomSheet<CalendarInfo>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Switch calendar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              for (final calendar in store.calendars)
                ListTile(
                  key: ValueKey('calendar-choice-${calendar.id}'),
                  leading: Icon(
                    calendar.isOwned
                        ? Icons.calendar_month
                        : Icons.supervisor_account_outlined,
                  ),
                  title: Text(
                    calendar.isOwned
                        ? tr('My Calendar')
                        : calendar.ownerName.isNotEmpty
                        ? calendar.ownerName
                        : calendar.name,
                  ),
                  subtitle: Text(
                    calendar.isOwned
                        ? calendar.name
                        : Delegation.presetLabels[Delegation.presets
                              .indexOf(calendar.preset)
                              .clamp(0, Delegation.presets.length - 1)],
                  ),
                  trailing: calendar.id == store.calendarId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, calendar),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await runAction(context, () => store.selectCalendar(selected));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final active = store.calendar;
    if (active == null || store.calendars.length < 2)
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: ListTile(
        key: const ValueKey('calendar-switcher'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          active.isOwned
              ? Icons.calendar_month_outlined
              : Icons.supervisor_account_outlined,
          color: AppPalette.of(context).accent,
        ),
        title: Text(
          active.isOwned
              ? tr('My Calendar')
              : active.ownerName.isNotEmpty
              ? active.ownerName
              : active.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: active.isOwned
            ? null
            : Text(
                Delegation.presetLabels[Delegation.presets
                    .indexOf(active.preset)
                    .clamp(0, Delegation.presets.length - 1)],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: const Icon(Icons.expand_more),
        onTap: () => _choose(context),
      ),
    );
  }
}
