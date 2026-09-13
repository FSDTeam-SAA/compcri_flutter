import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import '../core/design.dart';
import '../core/i18n.dart';

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
    required this.canReplay,
    required this.onRecord,
    required this.onCancel,
    required this.onRetry,
    required this.onDiscard,
    required this.onMute,
    required this.onReplay,
    required this.onSend,
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
  final TextEditingController controller;
  final ScrollController scroll;
  final Widget messages;

  @override
  State<VoiceExperience> createState() => _VoiceExperienceState();
}

class _VoiceExperienceState extends State<VoiceExperience> {
  bool typing = false;
  static const violet = Color(0xff7c3aed);
  static const ink = Color(0xff241b39);
  static const soft = Color(0xff786b90);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 220);
    final disabled = widget.busy || widget.sending;
    final status = widget.recording
        ? 'Listening to you'
        : widget.sending
        ? 'Working on your message'
        : widget.speaking
        ? 'Aria is speaking'
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
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            children: [
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
                      color: Colors.white.withValues(alpha: .8),
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
                          color: violet,
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
                          style: const TextStyle(
                            color: violet,
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
                            ? const Color(0xfffdeaf0)
                            : Colors.white.withValues(alpha: .8),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        widget.allowance!,
                        style: TextStyle(
                          color: widget.allowanceLow
                              ? const Color(0xffa33f5c)
                              : soft,
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
                  style: const TextStyle(
                    color: ink,
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
                style: const TextStyle(color: soft, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 34,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(25, (i) {
                    final weight = .25 + .75 * math.sin((i + 1) * 2.4).abs();
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
                  const Expanded(
                    child: Text(
                      'Our conversation',
                      style: TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (widget.canReplay && !widget.recording && !widget.sending)
                    IconButton(
                      tooltip: tr(
                        widget.speaking ? 'Stop reply' : 'Replay reply',
                      ),
                      onPressed: widget.onReplay,
                      icon: Icon(
                        widget.speaking
                            ? Icons.stop_circle_outlined
                            : Icons.volume_up_outlined,
                        color: violet,
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
                    color: Colors.white.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: violet.withValues(alpha: .1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Not sure where to start?',
                        style: TextStyle(
                          color: ink,
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
                              : () {
                                  setState(() => typing = true);
                                  widget.controller.text = tr(suggestion);
                                },
                          child: Row(
                            children: [
                              const Icon(Icons.north_west_rounded, size: 15),
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
              style: const TextStyle(color: Color(0xffa33f5c), fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .88),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: violet.withValues(alpha: .1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                      // Mid-turn is the one time flipping this would fight the
                      // recorder, so it waits until the turn settles.
                      onTap: widget.sending || widget.hasRetry
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
              if (widget.hasRetry)
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
                )
              else if (typing && !widget.recording)
                TextField(
                  controller: widget.controller,
                  enabled: !disabled,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: widget.onSend,
                  decoration: InputDecoration(
                    hintText: tr('Type your message…'),
                    suffixIcon: IconButton(
                      tooltip: tr('Send message'),
                      onPressed: disabled
                          ? null
                          : () => widget.onSend(widget.controller.text),
                      icon: const Icon(
                        Icons.arrow_upward_rounded,
                        color: violet,
                      ),
                    ),
                  ),
                ),
              if (typing && !widget.recording) const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: widget.recording
                        ? 'Cancel recording'
                        : typing
                        ? tr('Use microphone')
                        : tr('Type instead'),
                    onPressed: disabled
                        ? null
                        : widget.recording
                        ? widget.onCancel
                        : () => setState(() => typing = !typing),
                    icon: Icon(
                      widget.recording
                          ? Icons.close_rounded
                          : typing
                          ? Icons.mic_none_rounded
                          : Icons.keyboard_alt_outlined,
                      color: soft,
                    ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: disabled || widget.hasRetry
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
                                widget.recording
                                    ? Icons.arrow_upward_rounded
                                    : Icons.mic_rounded,
                              ),
                        label: Text(
                          widget.sending
                              ? 'Working…'
                              : widget.busy
                              ? 'One moment'
                              : widget.recording
                              ? 'Send'
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
                      color: soft,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
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
  static const soft = Color(0xff786b90);

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final tint = selected ? violet : soft;
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
              color: (selected ? violet : soft).withValues(alpha: .25),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
