import 'package:flutter/material.dart' hide Text;

import '../core/design.dart';
import '../core/i18n.dart';
import '../core/models.dart';
import '../core/time.dart';

/// Shared by typed and spoken conversations; history belongs to the account.
class ConversationHistory extends StatefulWidget {
  const ConversationHistory({
    super.key,
    required this.items,
    required this.premium,
    required this.onOpen,
    required this.onNew,
    required this.onSave,
    required this.onDelete,
    required this.onDeleteAll,
    required this.onDownload,
    required this.onUpgrade,
    this.loading = false,
    this.error,
    required this.onRefresh,
    this.disabled = false,
  });

  final List<ConversationSummary> items;
  final bool premium, loading, disabled;
  final String? error;
  final ValueChanged<ConversationSummary> onOpen, onSave, onDelete;
  final VoidCallback onNew, onDeleteAll, onDownload, onUpgrade;
  final Future<void> Function() onRefresh;

  @override
  State<ConversationHistory> createState() => _ConversationHistoryState();
}

class _ConversationHistoryState extends State<ConversationHistory> {
  String query = '';
  bool savedOnly = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final savedTab = widget.premium && savedOnly;
    final items =
        widget.items
            .where(
              (item) =>
                  (!savedTab || item.saved) &&
                  item.title.toLowerCase().contains(query.trim().toLowerCase()),
            )
            .toList()
          ..sort(
            (a, b) => (b.updatedAt ?? DateTime(1970)).compareTo(
              a.updatedAt ?? DateTime(1970),
            ),
          );
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final recent = items
        .where(
          (item) =>
              item.updatedAt != null &&
              !item.updatedAt!.toLocal().isBefore(today),
        )
        .toList();
    final earlier = items.where((item) => !recent.contains(item)).toList();
    final days =
        widget.items.firstOrNull?.historyRetentionDays ??
        (widget.premium ? 30 : 7);
    return Drawer(
      width: (MediaQuery.sizeOf(context).width * .88).clamp(0, 390),
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conversation history',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colors.ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        _pill(widget.premium ? tr('Pro') : tr('Free')),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(Icons.add, color: colors.ink),
              title: const Text(
                'New conversation',
                style: TextStyle(fontSize: 15),
              ),
              onTap: widget.disabled ? null : widget.onNew,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
              child: TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  hintText: tr('Search history'),
                  hintStyle: TextStyle(fontSize: 13, color: colors.muted),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: colors.muted,
                    size: 21,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colors.accent.withValues(alpha: .35),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: widget.onRefresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _card(
                      Icons.access_time_rounded,
                      tr('{days}-day history', {'days': days}),
                      widget.premium
                          ? tr(
                              'Unsaved conversations are automatically deleted after {days} days.',
                              {'days': days},
                            )
                          : tr(
                              'Conversations are automatically deleted after {days} days.',
                              {'days': days},
                            ),
                    ),
                    if (widget.premium) ...[
                      const SizedBox(height: 14),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(
                              'Recent',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: const Icon(Icons.bookmark_border, size: 16),
                            label: Text(
                              'Saved',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                        selected: {savedOnly},
                        showSelectedIcon: false,
                        onSelectionChanged: (value) =>
                            setState(() => savedOnly = value.first),
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: colors.wash(
                            const Color(0xffead9ff),
                          ),
                          selectedForegroundColor: colors.accent,
                          side: BorderSide(color: colors.border),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ],
                    if (widget.error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        widget.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onRefresh,
                        child: const Text('Try Again'),
                      ),
                    ],
                    if (items.isEmpty && !widget.loading) ...[
                      const SizedBox(height: 28),
                      Text(
                        query.trim().isNotEmpty
                            ? tr('No conversations found.')
                            : savedTab
                            ? tr('No saved chats yet.')
                            : tr('No conversations yet.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                      const SizedBox(height: 20),
                    ],
                    for (final group in [
                      (tr('Today'), recent),
                      (tr('Earlier'), earlier),
                    ])
                      if (group.$2.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 23, bottom: 8),
                          child: Text(
                            group.$1,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        for (final item in group.$2) _row(item, now, days),
                      ],
                    const SizedBox(height: 24),
                    if (widget.premium)
                      _card(
                        Icons.bookmark_border_rounded,
                        tr('Tap the bookmark to save.'),
                        tr('Saved conversations stay until you delete them.'),
                      )
                    else
                      _card(
                        Icons.auto_awesome,
                        tr('Keep what matters'),
                        tr(
                          'Get 30 days of history and save important conversations with Pro.',
                        ),
                        action: Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: PrimaryButton(
                            'Explore Pro',
                            onPressed: widget.onUpgrade,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.items.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      onPressed: widget.disabled ? null : widget.onDownload,
                      icon: const Icon(Icons.download_outlined, size: 17),
                      label: const Text(
                        'Download all',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: widget.disabled ? null : widget.onDeleteAll,
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 17),
                      label: const Text(
                        'Delete all history',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: AppPalette.of(context).wash(const Color(0xfff2e9ff)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppPalette.of(context).accent,
      ),
    ),
  );

  Widget _card(IconData icon, String title, String detail, {Widget? action}) {
    final colors = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.wash(const Color(0xfff6f0ff)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 24, color: colors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ?action,
        ],
      ),
    );
  }

  Widget _row(ConversationSummary item, DateTime now, int days) {
    final colors = AppPalette.of(context);
    final expires = item.expiresAt ?? item.updatedAt?.add(Duration(days: days));
    final dueSoon =
        !item.saved &&
        expires != null &&
        expires.difference(now) <= const Duration(days: 1);
    final tomorrow =
        expires != null &&
        DateUtils.dateOnly(expires.toLocal()).isAfter(DateUtils.dateOnly(now));
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: .55)),
        ),
      ),
      child: InkWell(
        onTap: widget.disabled ? null : () => widget.onOpen(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.ink,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          relativeTime(item.updatedAt),
                          style: TextStyle(fontSize: 11, color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  if (widget.premium)
                    IconButton(
                      tooltip: item.saved
                          ? tr('Unsave conversation')
                          : tr('Save conversation'),
                      onPressed: widget.disabled
                          ? null
                          : () => widget.onSave(item),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        item.saved ? Icons.bookmark : Icons.bookmark_border,
                        size: 21,
                        color: item.saved ? colors.accent : colors.muted,
                      ),
                    ),
                  IconButton(
                    tooltip: tr('Delete conversation'),
                    onPressed: widget.disabled
                        ? null
                        : () => widget.onDelete(item),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
              if (item.saved)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: _pill(tr('Saved')),
                ),
              if (dueSoon)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.wash(const Color(0xfffff1d9)),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: colors.foreground(const Color(0xffb77522)),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          tomorrow
                              ? tr('Will be deleted tomorrow')
                              : tr('Will be deleted today'),
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.foreground(const Color(0xffb77522)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
