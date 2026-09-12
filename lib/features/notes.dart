import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/design.dart';
import '../core/store.dart';
import '../core/time.dart';

/// The notes inbox: everything the user typed or dictated, newest first with
/// pinned notes held at the top.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final search = TextEditingController();
  String term = '';

  @override
  void initState() {
    super.initState();
    search.addListener(() => setState(() => term = search.text.trim()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).loadNotes(silent: true);
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  /// Filters the cache as the user types; every note the list holds is already
  /// on the device, so this needs no round trip.
  List<Note> _visible(List<Note> notes) {
    if (term.isEmpty) return notes;
    final needle = term.toLowerCase();
    return notes
        .where(
          (note) =>
              note.title.toLowerCase().contains(needle) ||
              note.body.toLowerCase().contains(needle),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final notes = _visible(store.notes);

    return PageFrame(
      title: 'Notes',
      scroll: false,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      bottom: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              'Write a note',
              icon: Icons.edit_outlined,
              outline: true,
              onPressed: () => openNoteEditor(context),
            ),
          ),
          const SizedBox(width: 12),
          const VoiceNoteButton(),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppField(
            '',
            hint: 'Search your notes',
            controller: search,
            icon: Icons.search,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => store.loadNotes(silent: true),
              child: store.loadingNotes && store.notes.isEmpty
                  ? const LoadingBlock()
                  : notes.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          term.isEmpty
                              ? 'No notes yet. Tap the mic to say one, or write it down.'
                              : 'No notes match "$term".',
                          icon: Icons.sticky_note_2_outlined,
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: notes.length,
                      itemBuilder: (_, index) => NoteTile(note: notes[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One note row — used in the inbox, on the home tab, and under an event.
class NoteTile extends StatelessWidget {
  const NoteTile({super.key, required this.note, this.onChanged});
  final Note note;

  /// Called after an edit or delete so the parent can refresh.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final stamp = [
      relativeTime(note.updatedAt ?? note.createdAt),
      note.durationLabel,
    ].where((part) => part.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xffeee4ff).withValues(alpha: .65),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await openNoteEditor(context, note: note);
            onChanged?.call();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  note.isVoice ? Icons.mic_none : Icons.sticky_note_2_outlined,
                  size: 19,
                  color: lilac,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15),
                      ),
                      if (note.body != note.title) ...[
                        const SizedBox(height: 4),
                        Text(
                          note.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (stamp.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          stamp,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    note.pinned ? Icons.push_pin : Icons.more_vert,
                    size: 19,
                    color: note.pinned ? purple : null,
                  ),
                  onSelected: (value) async {
                    if (value == 'pin') {
                      final done = await runAction(
                        context,
                        () => store.togglePinned(note),
                        showSpinner: false,
                      );
                      if (done) onChanged?.call();
                      return;
                    }
                    if (!context.mounted) return;
                    final confirmed = await confirm(
                      context,
                      'Delete note?',
                      'This note will be removed from your list.',
                      action: 'Delete',
                      danger: true,
                    );
                    if (!confirmed || !context.mounted) return;
                    final done = await runAction(
                      context,
                      () => store.deleteNote(note),
                      success: 'Note deleted',
                    );
                    if (done) onChanged?.call();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'pin',
                      child: Text(note.pinned ? 'Unpin' : 'Pin to top'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the editor for [note], or a blank one filed against [eventId].
Future<void> openNoteEditor(
  BuildContext context, {
  Note? note,
  String? eventId,
}) => Navigator.push<void>(
  context,
  MaterialPageRoute(builder: (_) => NoteEditor(note: note, eventId: eventId)),
);

class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, this.note, this.eventId});

  /// Null when composing a new note.
  final Note? note;

  /// Files a new note against an event — set when opened from event details.
  final String? eventId;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final title = TextEditingController(text: widget.note?.title ?? '');
  late final body = TextEditingController(text: widget.note?.body ?? '');
  late bool pinned = widget.note?.pinned ?? false;

  bool get isNew => widget.note == null;

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = StoreScope.read(context);
    if (body.text.trim().isEmpty) {
      toast(context, 'Write something first.');
      return;
    }
    final saved = await runTask<Note>(
      context,
      () => isNew
          // An empty title lets the server derive one from the text.
          ? store.createNote(
              body: body.text,
              title: title.text,
              eventId: widget.eventId,
              pinned: pinned,
            )
          : store.updateNote(
              widget.note!,
              title: title.text,
              body: body.text,
              pinned: pinned,
            ),
      success: isNew ? 'Note saved' : 'Note updated',
    );
    if (saved != null && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return PageFrame(
      title: isNew ? 'New note' : 'Note',
      bottom: AsyncButton('Save note', onPressed: _save),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null && note.isVoice)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Surface(
                child: Row(
                  children: [
                    const Icon(Icons.mic_none, size: 18, color: purple),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        note.durationLabel.isEmpty
                            ? 'Dictated note'
                            : 'Dictated note · ${note.durationLabel}',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          AppField('Title', hint: 'Optional', controller: title),
          AppField(
            'Note',
            hint: 'What do you want to remember?',
            controller: body,
            lines: 8,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: pinned,
            title: const Text('Pin to top', style: TextStyle(fontSize: 14)),
            onChanged: (value) => setState(() => pinned = value),
          ),
        ],
      ),
    );
  }
}

/// Records a spoken note and hands the audio to the server, which transcribes
/// it into the note body. The recording itself is never stored.
class VoiceNoteButton extends StatefulWidget {
  const VoiceNoteButton({super.key, this.onSaved, this.eventId});
  final VoidCallback? onSaved;
  final String? eventId;
  @override
  State<VoiceNoteButton> createState() => _VoiceNoteButtonState();
}

class _VoiceNoteButtonState extends State<VoiceNoteButton> {
  final recorder = AudioRecorder();
  bool recording = false;

  @override
  void dispose() {
    recorder.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final store = StoreScope.read(context);
    if (recording) {
      final path = await recorder.stop();
      if (!mounted) return;
      setState(() => recording = false);
      if (path == null) return;
      final note = await runTask<Note>(
        context,
        () => store.createVoiceNote(filePath: path, eventId: widget.eventId),
        success: 'Note saved',
      );
      if (note != null) widget.onSaved?.call();
      return;
    }

    try {
      if (!await recorder.hasPermission()) {
        if (mounted) {
          toastError(context, 'Microphone permission is required to record.');
        }
        return;
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/note-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (mounted) setState(() => recording = true);
    } catch (error) {
      if (mounted) toastError(context, 'Recording is unavailable: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: recording ? 'Stop recording and save note' : 'Record a spoken note',
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _toggle,
      child: Container(
        width: 56,
        height: 48,
        decoration: BoxDecoration(
          gradient: recording ? null : violetGradient,
          color: recording ? const Color(0xffff4e2c) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          recording ? Icons.stop : Icons.mic_none,
          color: Colors.white,
          size: 23,
        ),
      ),
    ),
  );
}

/// The home tab's notes section: the most recent notes plus a way in.
class NotesPreview extends StatelessWidget {
  const NotesPreview({super.key, required this.onAll});
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final notes = StoreScope.of(context).notes.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: Text('Notes', style: TextStyle(fontSize: 16))),
            TextButton(onPressed: onAll, child: const Text('All notes')),
          ],
        ),
        if (notes.isEmpty)
          // Keeps a way into notes on a brand-new account.
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              'Nothing noted yet. Tap "All notes" to say or write one.',
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          )
        else
          ...notes.map((note) => NoteTile(note: note)),
      ],
    );
  }
}
