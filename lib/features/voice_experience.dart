import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import '../core/design.dart';
import '../core/i18n.dart';
import '../core/models.dart';

/// Presentation for voice conversations; recording and messages belong to the
/// conversation controller so switching input methods never loses the thread.
class VoiceExperience extends StatefulWidget {
  const VoiceExperience({
    super.key,
    required this.recording,
    this.transcribed = false,
    required this.busy,
    required this.sending,
    required this.speaking,
    required this.muted,
    required this.seconds,
    required this.level,
    required this.hasMessages,
    required this.hasRetry,
    required this.retryIsEmpty,
    required this.canReplay,
    required this.onRecord,
    required this.onCancel,
    required this.onRetry,
    required this.onDiscard,
    required this.onMute,
    required this.onReplay,
    required this.onSend,
    required this.assistantName,
    required this.onHandsFree,
    required this.onPickVoice,
    required this.handsFree,
    required this.voiceLabel,
    required this.controller,
    required this.scroll,
    required this.messages,
    this.error,
    this.allowance,
    this.allowanceLow = false,
    this.minimal = false,
    this.keyboardOpen = false,
    this.proposals = const SizedBox.shrink(),
    this.onClose,
  });

  /// The turn in flight has been transcribed and the reply is being written.
  final bool transcribed;
  final bool recording,
      busy,
      sending,
      speaking,
      muted,
      hasMessages,
      hasRetry,
      canReplay,
      handsFree,
      allowanceLow;
  final int seconds;
  final double level;
  final String? error;

  /// Remaining AI turns for today, already formatted. Null while unknown.
  final String? allowance;

  /// Display name of the selected reply voice.
  final String voiceLabel;
  final VoidCallback onRecord, onCancel, onRetry, onDiscard, onMute, onReplay;
  final VoidCallback onPickVoice;
  final ValueChanged<bool> onHandsFree;
  final ValueChanged<String> onSend;

  /// A kept recording that holds no speech. Nothing is lost by dropping it,
  /// so the microphone stays live and starts a fresh turn on the next tap.
  final bool retryIsEmpty;

  /// What this user calls the assistant, so the screen names it their way.
  final String assistantName;
  final TextEditingController controller;
  final ScrollController scroll;
  final Widget messages;
  final bool minimal;
  final bool keyboardOpen;
  final Widget proposals;
  final VoidCallback? onClose;

  @override
  State<VoiceExperience> createState() => _VoiceExperienceState();
}

class _VoiceExperienceState extends State<VoiceExperience> {
  static const violet = Color(0xff7c3aed);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 220);
    final disabled = widget.busy || widget.sending;
    if (widget.minimal) return _callView(disabled);
    final keyboardOpen = widget.keyboardOpen;
    final status = widget.recording
        ? 'Listening to you'
        : widget.sending
        ? 'Working on your message'
        : widget.speaking
        ? tr('{name} is speaking', {'name': widget.assistantName})
        : widget.hasRetry
        ? 'Your recording is saved'
        : widget.handsFree
        ? 'Hands-free is on'
        : widget.hasMessages
        ? 'What would you like to do next?'
        : 'A little less typing. A little more living.';
    final hint = widget.recording
        ? widget.handsFree
              ? 'Speak naturally. I’ll send when you pause.'
              : 'Speak naturally. Tap send when you’re done.'
        : widget.sending
        ? widget.transcribed
              ? 'Got it. Writing a reply…'
              : 'Transcribing your words…'
        : widget.speaking
        ? widget.handsFree
              ? 'I’ll start listening again when the reply finishes.'
              : 'You can stop the audio or start another turn.'
        : widget.handsFree
        ? 'The microphone reopens after each reply. Switch it off to take turns manually.'
        : 'Tap the mic to talk. Your words will appear below after sending.';
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            children: keyboardOpen
                ? [widget.messages]
                : [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.of(
                              context,
                            ).surface.withValues(alpha: .8),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.recording
                                    ? Icons.mic_rounded
                                    : widget.handsFree
                                    ? Icons.phone_in_talk_rounded
                                    : Icons.auto_awesome_rounded,
                                size: 14,
                                color: AppPalette.of(context).accent,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                widget.recording
                                    ? tr('LISTENING · {time}', {
                                        'time':
                                            '${widget.seconds ~/ 60}:${(widget.seconds % 60).toString().padLeft(2, '0')}',
                                      })
                                    : widget.sending
                                    ? 'ONE MOMENT'
                                    : widget.speaking
                                    ? 'SPEAKING'
                                    : widget.handsFree
                                    ? 'HANDS-FREE'
                                    : 'YOUR VOICE ASSISTANT',
                                style: TextStyle(
                                  color: AppPalette.of(context).accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.allowance != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: widget.allowanceLow
                                  ? AppPalette.of(
                                      context,
                                    ).wash(const Color(0xfffdeaf0))
                                  : AppPalette.of(
                                      context,
                                    ).surface.withValues(alpha: .8),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              widget.allowance!,
                              style: TextStyle(
                                color: widget.allowanceLow
                                    ? AppPalette.of(
                                        context,
                                      ).foreground(const Color(0xffa33f5c))
                                    : AppPalette.of(context).muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: SizedBox(
                        height: widget.hasMessages ? 134 : 190,
                        child: FittedBox(
                          child: VoiceOrb(
                            size: widget.hasMessages ? 134 : 190,
                            active: widget.recording,
                            onTap: disabled || widget.hasRetry
                                ? null
                                : widget.onRecord,
                          ),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: duration,
                      child: Text(
                        status,
                        key: ValueKey(status),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppPalette.of(context).ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          letterSpacing: -.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppPalette.of(context).muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 34,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(25, (i) {
                          final weight =
                              .25 + .75 * math.sin((i + 1) * 2.4).abs();
                          return AnimatedContainer(
                            duration: duration,
                            width: 4,
                            height: widget.recording
                                ? 5 + widget.level * weight * 29
                                : 4 + math.sin(i * .7).abs() * 5,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: violet.withValues(
                                alpha: widget.recording ? .85 : .22,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Our conversation',
                            style: TextStyle(
                              color: AppPalette.of(context).ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (widget.canReplay &&
                            !widget.recording &&
                            !widget.sending)
                          IconButton(
                            tooltip: tr(
                              widget.speaking ? 'Stop reply' : 'Replay reply',
                            ),
                            onPressed: widget.onReplay,
                            icon: Icon(
                              widget.speaking
                                  ? Icons.stop_circle_outlined
                                  : Icons.volume_up_outlined,
                              color: AppPalette.of(context).accent,
                              size: 21,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!widget.hasMessages)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppPalette.of(
                            context,
                          ).surface.withValues(alpha: .8),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: violet.withValues(alpha: .1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Not sure where to start?',
                              style: TextStyle(
                                color: AppPalette.of(context).ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            for (final suggestion in [
                              'Plan my day',
                              'Help me schedule a meeting',
                            ])
                              TextButton(
                                onPressed: disabled || widget.recording
                                    ? null
                                    : () => widget.controller.text = tr(
                                        suggestion,
                                      ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.north_west_rounded,
                                      size: 15,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        suggestion,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      widget.messages,
                  ],
          ),
        ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              widget.error!,
              style: TextStyle(
                color: AppPalette.of(
                  context,
                ).foreground(const Color(0xffa33f5c)),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: BoxDecoration(
            color: AppPalette.of(context).surface.withValues(alpha: .88),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: violet.withValues(alpha: .1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!keyboardOpen) ...[
                Row(
                  children: [
                    Expanded(
                      child: _CallChip(
                        icon: widget.handsFree
                            ? Icons.phone_in_talk_rounded
                            : Icons.record_voice_over_outlined,
                        label: widget.handsFree
                            ? 'Hands-free on'
                            : 'Hands-free off',
                        selected: widget.handsFree,
                        onTap:
                            !widget.handsFree && (disabled || widget.hasRetry)
                            ? null
                            : () => widget.onHandsFree(!widget.handsFree),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CallChip(
                        icon: Icons.graphic_eq_rounded,
                        label: widget.voiceLabel,
                        selected: false,
                        onTap: disabled ? null : widget.onPickVoice,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (widget.hasRetry) ...[
                const Text(
                  'Retry your recording, or send a typed message instead.',
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: disabled ? null : widget.onDiscard,
                        child: const Text('Discard recording'),
                      ),
                    ),
                    Expanded(
                      child: FilledButton(
                        onPressed: disabled ? null : widget.onRetry,
                        child: const Text('Retry send'),
                      ),
                    ),
                  ],
                ),
              ],
              TextField(
                controller: widget.controller,
                // Left enabled on purpose: disabling a field iOS is holding
                // the keyboard for leaves that keyboard stranded on screen.
                // See the composer in dashboard.dart.
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: widget.sending ? null : widget.onSend,
                decoration: InputDecoration(
                  hintText: tr('Type your message…'),
                  suffixIcon: _sendButton('Send message'),
                ),
              ),
              if (!keyboardOpen) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Only ever a way out of a recording now. The keyboard needs
                    // no button of its own, and the width is held either way so
                    // the talk button does not shift under the thumb.
                    SizedBox(
                      width: 48,
                      child: widget.recording
                          ? IconButton(
                              tooltip: tr('Cancel recording'),
                              onPressed: disabled ? null : widget.onCancel,
                              icon: Icon(
                                Icons.close_rounded,
                                color: AppPalette.of(context).muted,
                              ),
                            )
                          : null,
                    ),
                    Semantics(
                      button: true,
                      label: widget.recording
                          ? tr('Send recording')
                          : tr('Start recording'),
                      child: SizedBox(
                        width: 160,
                        height: 56,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: violet,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed:
                              disabled ||
                                  (widget.hasRetry && !widget.retryIsEmpty)
                              ? null
                              : widget.onRecord,
                          icon: widget.sending && !reduce
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  !widget.recording
                                      ? Icons.mic_rounded
                                      : Icons.arrow_upward_rounded,
                                ),
                          label: Text(
                            widget.sending
                                ? 'Working…'
                                : widget.busy
                                ? 'One moment'
                                : widget.recording
                                ? 'Send now'
                                : 'Tap to talk',
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: widget.muted
                          ? tr('Enable spoken replies')
                          : tr('Mute spoken replies'),
                      onPressed: widget.onMute,
                      icon: Icon(
                        widget.muted
                            ? Icons.volume_off_outlined
                            : Icons.volume_up_outlined,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sendButton(String label) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: widget.controller,
    builder: (context, value, _) => IconButton(
      tooltip: tr(label),
      onPressed: widget.sending || value.text.trim().isEmpty
          ? null
          : () => widget.onSend(value.text),
      icon: Icon(
        Icons.arrow_upward_rounded,
        color: widget.sending || value.text.trim().isEmpty
            ? AppPalette.of(context).muted
            : AppPalette.of(context).accent,
      ),
    ),
  );

  Widget _callView(bool disabled) => Column(
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, box.maxHeight - 24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!widget.keyboardOpen) ...[
                    VoiceOrb(
                      size: math.min(330, math.max(160, box.maxWidth - 48)),
                      active: widget.recording || widget.speaking,
                      onTap: disabled
                          ? null
                          : widget.recording
                          ? widget.onRecord
                          : () => widget.onHandsFree(true),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    widget.recording
                        ? 'Listening to you'
                        : widget.speaking
                        ? tr('{name} is speaking', {
                            'name': widget.assistantName,
                          })
                        : widget.sending
                        ? 'Working on your message'
                        : widget.busy
                        ? 'One moment'
                        : 'Tap the mic to talk',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppPalette.of(context).muted,
                    ),
                  ),
                  if (widget.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      widget.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (widget.hasRetry)
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton(
                          onPressed: disabled ? null : widget.onRetry,
                          child: const Text('Retry send'),
                        ),
                        TextButton(
                          onPressed: disabled ? null : widget.onDiscard,
                          child: const Text('Discard recording'),
                        ),
                      ],
                    ),
                  if (widget.hasMessages &&
                      (widget.keyboardOpen ||
                          !widget.handsFree ||
                          widget.muted ||
                          widget.error != null))
                    widget.messages
                  else
                    widget.proposals,
                ],
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('hands-free-text'),
                controller: widget.controller,
                textInputAction: TextInputAction.send,
                onSubmitted: widget.sending ? null : widget.onSend,
                decoration: InputDecoration(
                  hintText: tr('Ask {name}…', {'name': widget.assistantName}),
                  suffixIcon: _sendButton('Send'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: widget.handsFree
                  ? tr('Mute microphone')
                  : tr('Resume hands-free'),
              onPressed: !widget.handsFree && (disabled || widget.hasRetry)
                  ? null
                  : () => widget.onHandsFree(!widget.handsFree),
              icon: Icon(widget.handsFree ? Icons.mic : Icons.mic_off),
            ),
            IconButton.filledTonal(
              tooltip: tr('End call'),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Compact pill for the call-level toggles that sit above the microphone row.
class _CallChip extends StatelessWidget {
  const _CallChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  static const violet = Color(0xff7c3aed);

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final tint = selected
        ? AppPalette.of(context).accent
        : AppPalette.of(context).muted;
    return Material(
      color: selected ? violet.withValues(alpha: .1) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (selected ? violet : AppPalette.of(context).muted)
                  .withValues(alpha: .25),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: enabled ? tint : tint.withValues(alpha: .4),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  // Two lines, because these are translated: "Hands-free off"
                  // becomes "Mãos livres desativado", which loses its ending to
                  // an ellipsis in the width one line leaves here.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: enabled ? tint : tint.withValues(alpha: .4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Samples report their progress and errors inside the open picker.
class VoicePicker extends StatefulWidget {
  const VoicePicker({
    super.key,
    required this.assistantName,
    required this.selectedVoice,
    required this.onPreview,
    required this.onSelect,
  });
  final String assistantName, selectedVoice;
  final Future<void> Function(String) onPreview;
  final ValueChanged<String> onSelect;

  @override
  State<VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<VoicePicker> {
  String? loadingVoice, error;
  int request = 0;

  Future<void> preview(String voice) async {
    final token = ++request;
    setState(() {
      loadingVoice = voice;
      error = null;
    });
    try {
      await widget.onPreview(voice);
    } catch (_) {
      if (mounted && token == request) {
        setState(() => error = 'That sample could not be played.');
      }
    } finally {
      if (mounted && token == request) setState(() => loadingVoice = null);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 12),
      child: RadioGroup<String>(
        groupValue: widget.selectedVoice,
        onChanged: (voice) {
          if (voice != null) widget.onSelect(voice);
        },
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  tr("{name}'s voice", {'name': widget.assistantName}),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text('Applies to the next spoken reply.'),
              ),
              for (final voice in AriaVoice.all)
                RadioListTile<String>(
                  value: voice.id,
                  title: Text(voice.label),
                  subtitle: Text(voice.tone),
                  secondary: loadingVoice == voice.id
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: tr('Play sample'),
                          onPressed: () => preview(voice.id),
                          icon: const Icon(Icons.play_circle_outline),
                        ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
