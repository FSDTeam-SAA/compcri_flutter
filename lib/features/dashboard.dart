import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/api_client.dart';
import '../core/design.dart';
import '../core/markdown.dart';
import '../core/store.dart';
import '../core/time.dart';
import 'calendar.dart';
export 'calendar.dart' show CalendarTab;
import 'network.dart';
import 'home.dart';
import 'voice_experience.dart';
export 'home.dart' show HomeTab;

export '../core/time.dart' show monthName;

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard>
    with SingleTickerProviderStateMixin {
  int tab = 0;
  late final AnimationController reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = StoreScope.read(context);
      // A resumed session already has data; a fresh sign-in does not.
      if (store.events.isEmpty) store.loadEvents(silent: true);
      if (store.notifications.isEmpty) store.loadNotifications(silent: true);
      if (store.contacts.isEmpty) store.loadNetwork(silent: true);
      if (store.notes.isEmpty) store.loadNotes(silent: true);
    });
  }

  void selectTab(int value) {
    if (value == tab) return;
    setState(() => tab = value);
    if (!MediaQuery.disableAnimationsOf(context)) reveal.forward(from: 0);
  }

  @override
  void dispose() {
    reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Backdrop(
    child: Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: reveal,
          child: IndexedStack(
            index: tab,
            children: [
              HomeTab(
                onCalendar: () => selectTab(2),
                onVoice: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const VoiceScreen()),
                ),
              ),
              const ChatTab(),
              const CalendarTab(),
              const NetworkTab(),
            ],
          ),
        ),
      ),
      // Calendar has its own add affordance, and Chat's "New chat" button
      // sits exactly where the FAB would land.
      floatingActionButton: tab == 1 || tab == 2
          ? null
          : CreateEventButton(
              onPressed: () async {
                await go(context, '/event/create');
                if (context.mounted) {
                  await runAction(
                    context,
                    () => StoreScope.read(context).loadEvents(silent: true),
                  );
                }
              },
            ),
      bottomNavigationBar: DashboardNav(selected: tab, onSelected: selectTab),
    ),
  );
}

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StoreScope.read(context).loadConversations();
    });
  }

  void _openChat(
    BuildContext context, {
    String? prompt,
    String? conversationId,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ConversationScreen(prompt: prompt, conversationId: conversationId),
      ),
    );
  }

  static const _prompts = [
    "What's on my schedule today?",
    'Find free time this week',
    'Schedule a block tomorrow morning',
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final chats = store.conversations;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 2),
          child: Row(
            children: [
              const SizedBox(width: 44),
              const Expanded(
                child: Center(
                  child: Text(
                    'AI Chat',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Chat history',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ConversationScreen(showHistory: true),
                  ),
                ),
                icon: const Icon(Icons.menu, size: 21, color: muted),
              ),
            ],
          ),
        ),
        if (!store.isPremium)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Surface(
              color: const Color(0xffe2edff),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_outlined, color: purple),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'The AI assistant is part of Premium.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => go(context, '/subscription'),
                    child: const Text('Upgrade'),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VoiceOrb(
                        size: 185,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const VoiceScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Click and Say',
                        style: TextStyle(
                          color: Color(0xff9956ff),
                          fontFamily: 'Inter',
                          fontSize: 25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  itemCount: chats.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 12),
                        child: Row(
                          children: [
                            const Text(
                              'Recent chats',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${chats.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final conversation = chats[index - 1];
                    return _ChatRow(
                      conversation: conversation,
                      onOpen: () =>
                          _openChat(context, conversationId: conversation.id),
                      onDelete: () async {
                        final confirmed = await confirm(
                          context,
                          'Delete chat?',
                          'This conversation will be removed.',
                          action: 'Delete',
                          danger: true,
                        );
                        if (!confirmed || !context.mounted) return;
                        await runAction(context, () async {
                          await store.api.ai.deleteConversation(
                            conversation.id,
                          );
                          await store.loadConversations();
                        }, success: 'Chat deleted');
                      },
                    );
                  },
                ),
        ),
        // Tall enough that the chips are never clipped at the baseline.
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _prompts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _PromptChip(
              label: _prompts[index],
              onTap: () => _openChat(context, prompt: _prompts[index]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: PrimaryButton(
            'New chat',
            icon: Icons.add,
            onPressed: () => _openChat(context),
          ),
        ),
      ],
    );
  }
}

/// One row in the recent-chat list.
class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.conversation,
    required this.onOpen,
    required this.onDelete,
  });

  final ConversationSummary conversation;
  final VoidCallback onOpen;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white.withValues(alpha: .84),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xfff0eafa)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xfff3edff),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: purple,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        relativeTime(conversation.updatedAt),
                        style: const TextStyle(fontSize: 11.5, color: muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete chat',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 19,
                    color: Color(0xffff9a9a),
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A one-tap starter prompt. Sized by its own padding so the text never clips.
class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .8),
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: lilac.withValues(alpha: .55)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, size: 14, color: lilac),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xff4a3f66),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    this.prompt,
    this.conversationId,
    this.showHistory = false,
    this.audioPath,
    this.voiceMode = false,
  });

  final String? prompt;
  final String? conversationId;
  final bool showHistory;
  final bool voiceMode;

  /// A recording captured on the voice screen, sent as the opening turn.
  final String? audioPath;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final scaffold = GlobalKey<ScaffoldState>();
  final player = AudioPlayer();
  final recorder = AudioRecorder();

  List<ChatMessage> messages = [];
  List<PendingAction> pendingActions = [];
  String? conversationId;

  /// The one reply that should type itself out. Only ever the turn that just
  /// arrived, and only for voice, which answers in one piece — a typed turn
  /// streams for real, and reopening a conversation renders history whole.
  String? typingId;

  /// The answer being streamed right now, and the tools it is running to get
  /// there. Both are cleared the moment the saved turn arrives.
  String streamingText = '';
  List<String> activeTools = const [];
  String title = 'New chat';
  String historyQuery = '';
  bool sending = false;
  bool loading = false;
  bool started = false;
  bool recording = false;
  bool recorderBusy = false;
  bool speaking = false;
  bool mutedAudio = false;
  String? voiceError;
  String? retryAudioPath;
  String? lastAudio;
  int recordingSeconds = 0;
  double soundLevel = 0;
  Timer? recordingTimer;
  StreamSubscription<Amplitude>? amplitudeSubscription;
  StreamSubscription<PlayerState>? playbackSubscription;
  StreamSubscription<void>? completionSubscription;

  // --- hands-free calling -------------------------------------------------

  /// Keeps the microphone turn-taking on its own: the reply finishes speaking,
  /// the app listens again, and a pause ends the turn. Off by default because
  /// it holds the microphone open between turns.
  bool handsFree = false;
  String? preferredVoice;

  /// Guards the auto-listen hop so a late playback event cannot start a second
  /// recorder after the user has already left or switched off.
  bool autoListenQueued = false;

  /// Silence tracking for the current recording. [heardSpeech] stops a silent
  /// room from ending the turn before the user has said anything.
  bool heardSpeech = false;
  double silenceSeconds = 0;
  AiQuota? quota;

  /// Ends a turn once the user has been quiet this long after speaking.
  static const _silenceToEndTurn = Duration(milliseconds: 1800);

  /// Gives up on a hands-free turn nobody spoke into, so the loop does not
  /// hold the microphone forever.
  static const _silenceToGiveUp = Duration(seconds: 12);

  /// Hard cap on one recording. The server rejects uploads over
  /// `OPENAI_VOICE_MAX_FILE_MB`; stopping first turns a failed upload into a
  /// sent turn.
  static const _maxRecording = Duration(minutes: 2);

  /// dBFS-normalised level above which we treat the input as speech.
  static const _speechThreshold = 0.28;

  @override
  void initState() {
    super.initState();
    conversationId = widget.conversationId;
    playbackSubscription = player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => speaking = state == PlayerState.playing);
    });
    // The reply finishing is the cue to listen again; PlayerState alone does
    // not distinguish "finished" from "stopped by the user".
    completionSubscription = player.onPlayerComplete.listen((_) {
      if (mounted) _afterReply();
    });
    _restoreVoicePrefs();
  }

  /// Remembered settings are a convenience, never a precondition: if storage
  /// is unavailable the screen opens on the defaults rather than failing.
  Future<void> _restoreVoicePrefs() async {
    final store = StoreScope.read(context);
    try {
      final prefs = await store.api.client.store.voicePrefs();
      if (!mounted) return;
      setState(() {
        handsFree = prefs.handsFree;
        mutedAudio = prefs.muted;
        preferredVoice = prefs.voice;
      });
    } catch (_) {
      // Keep the defaults.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) return;
    started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      unawaited(_loadQuota());
      if (conversationId != null) await _loadConversation(conversationId!);
      if (!mounted) return;
      if (widget.audioPath != null) {
        await _sendVoice(widget.audioPath!);
      } else if (widget.prompt != null) {
        await _send(widget.prompt!);
      }
      if (widget.showHistory && mounted) {
        scaffold.currentState?.openEndDrawer();
      }
    });
  }

  /// Best-effort: the allowance is a hint on screen, never a gate that can
  /// block sending because a refresh failed.
  Future<void> _loadQuota() async {
    final store = StoreScope.read(context);
    if (store.calendarId.isEmpty) return;
    try {
      final latest = await store.api.ai.quota(store.calendarId);
      if (mounted) setState(() => quota = latest);
    } on ApiException {
      // Leave the previous figure on screen rather than showing nothing.
    }
  }

  @override
  void dispose() {
    // Stop the loop before tearing down, so no queued hop outlives the screen.
    handsFree = false;
    autoListenQueued = false;
    input.dispose();
    scroll.dispose();
    recordingTimer?.cancel();
    amplitudeSubscription?.cancel();
    playbackSubscription?.cancel();
    completionSubscription?.cancel();
    if (recording) unawaited(recorder.cancel());
    final unsent = retryAudioPath;
    if (unsent != null) unawaited(_deleteAudio(unsent));
    player.dispose();
    recorder.dispose();
    super.dispose();
  }

  Future<void> _loadConversation(String id) async {
    setState(() => loading = true);
    final store = StoreScope.read(context);
    try {
      final conversation = await store.api.ai.conversation(id);
      if (!mounted) return;
      setState(() {
        conversationId = conversation.id;
        title = conversation.title;
        messages = [...conversation.messages];
      });
      _scrollToEnd();
    } on ApiException catch (error) {
      if (mounted) toastError(context, error.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Creates the conversation lazily so an abandoned "New chat" leaves nothing
  /// behind on the server.
  Future<String?> _ensureConversation(AppStore store) async {
    final existing = conversationId;
    if (existing != null) return existing;
    if (store.calendarId.isEmpty) {
      toastError(context, 'No calendar is available yet. Pull to refresh.');
      return null;
    }
    final conversation = await store.api.ai.createConversation(
      calendarId: store.calendarId,
    );
    if (mounted) {
      setState(() {
        conversationId = conversation.id;
        title = conversation.title;
      });
    }
    unawaited(store.loadConversations());
    return conversation.id;
  }

  Future<void> _send(String value) async {
    final text = value.trim();
    if (text.isEmpty ||
        sending ||
        recording ||
        recorderBusy ||
        loading ||
        retryAudioPath != null) {
      return;
    }
    final store = StoreScope.read(context);
    input.clear();

    setState(() {
      sending = true;
      voiceError = null;
      messages = [
        ...messages,
        ChatMessage(id: 'local-${messages.length}', text: text, isUser: true),
      ];
    });
    _scrollToEnd();

    try {
      final id = await _ensureConversation(store);
      if (id == null) {
        throw StateError('No calendar is available yet. Please try again.');
      }
      // The turn is watched as it happens. Leaving the screen mid-answer just
      // cancels the subscription: the server finishes and saves it either way,
      // so it is waiting in the conversation when the user comes back.
      var delivered = false;
      await for (final event in store.api.ai.streamMessage(
        conversationId: id,
        content: text,
      )) {
        if (!mounted) return;
        switch (event.kind) {
          case AiEventKind.delta:
            setState(() => streamingText += event.text ?? '');
            _followTyping();
          case AiEventKind.tools:
            setState(() => activeTools = event.tools);
          case AiEventKind.reset:
            setState(() => streamingText = '');
          case AiEventKind.done:
            final turn = event.turn!;
            delivered = true;
            // The live bubble hands over to the saved one in the same frame,
            // or the answer would briefly appear twice.
            setState(() {
              messages = [...messages, turn.message];
              pendingActions = turn.pendingActions;
              streamingText = '';
              activeTools = const [];
            });
            _scrollToEnd();
          case AiEventKind.error:
            throw ApiException(
              event.text ?? 'AI assistant is temporarily unavailable',
              code: event.code ?? 'AI_UNAVAILABLE',
            );
        }
      }
      // A stream that stops without saying it finished means the connection
      // died mid-answer. Treat it as the failure it is, so the message comes
      // back for another try instead of leaving a question with no reply.
      if (!delivered) {
        throw ApiException(
          'The reply was cut off. Please try again.',
          code: 'AI_STREAM_INCOMPLETE',
        );
      }
      unawaited(_loadQuota());
    } catch (error) {
      if (!mounted) return;
      // Drop the optimistic bubble so the user can edit and retry.
      setState(() => messages = messages.sublist(0, messages.length - 1));
      input.text = text;
      if (error is ApiException) {
        _explain(error);
      } else {
        setState(
          () => voiceError = 'Could not send your message. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
          streamingText = '';
          activeTools = const [];
        });
      }
    }
  }

  /// Records straight into the open conversation. Staying on this screen is
  /// what keeps a second voice turn in the same chat instead of starting a
  /// new one, and it drops a full screen transition from every turn.
  Future<void> _toggleVoice() async {
    if (sending || loading || recorderBusy || retryAudioPath != null) return;
    setState(() {
      recorderBusy = true;
      voiceError = null;
    });
    try {
      if (recording) {
        final path = await recorder.stop();
        _stopMeter();
        if (!mounted) {
          if (path != null) await _deleteAudio(path);
          return;
        }
        setState(() => recording = false);
        if (path == null) {
          throw StateError('No recording was captured. Please try again.');
        }
        await _sendVoice(path);
      } else {
        await player.stop();
        if (!await recorder.hasPermission()) {
          throw StateError(
            'Allow microphone access in your device settings, or type your message below.',
          );
        }
        if (!mounted) return;
        final directory = await getTemporaryDirectory();
        if (!mounted) return;
        final path =
            '${directory.path}/aurox-${DateTime.now().microsecondsSinceEpoch}.m4a';
        await recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        if (!mounted) {
          await recorder.cancel();
          return;
        }
        setState(() {
          recording = true;
          recordingSeconds = 0;
          soundLevel = 0;
          heardSpeech = false;
          silenceSeconds = 0;
        });
        recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => recordingSeconds++);
          // Stop just under the server's upload ceiling instead of letting the
          // turn fail after the user has already spoken it.
          if (recordingSeconds >= _maxRecording.inSeconds) {
            unawaited(_stopAtLimit());
          }
        });
        amplitudeSubscription = recorder
            .onAmplitudeChanged(const Duration(milliseconds: 100))
            .listen((value) {
              if (!mounted) return;
              final level = ((value.current + 55) / 55).clamp(0.0, 1.0);
              setState(() => soundLevel = level);
              if (handsFree) _watchForPause(level);
            }, onError: (_) {});
      }
    } catch (error) {
      if (mounted) {
        setState(() => voiceError = '$error'.replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => recorderBusy = false);
    }
  }

  void _stopMeter() {
    recordingTimer?.cancel();
    recordingTimer = null;
    amplitudeSubscription?.cancel();
    amplitudeSubscription = null;
    heardSpeech = false;
    silenceSeconds = 0;
  }

  /// Sends what was captured when a recording hits the length ceiling, then
  /// explains why the turn ended by itself. The note is set after the turn
  /// because starting one clears the error line.
  Future<void> _stopAtLimit() async {
    await _toggleVoice();
    if (!mounted) return;
    setState(
      () =>
          voiceError = 'That reached the longest recording I can send at once.',
    );
  }

  /// Ends a hands-free turn on a pause. Called once per amplitude tick, so the
  /// counter advances by the sampling interval rather than by wall clock.
  void _watchForPause(double level) {
    if (!recording || recorderBusy || sending) return;
    if (level >= _speechThreshold) {
      heardSpeech = true;
      silenceSeconds = 0;
      return;
    }
    silenceSeconds += 0.1;
    // Someone who has spoken gets a short pause; an empty room gets a long one
    // before the loop lets go of the microphone.
    if (heardSpeech) {
      if (silenceSeconds >= _silenceToEndTurn.inMilliseconds / 1000) {
        unawaited(_toggleVoice());
      }
    } else if (silenceSeconds >= _silenceToGiveUp.inSeconds) {
      setState(
        () => voiceError =
            'I did not catch anything. Tap the mic when you are ready.',
      );
      unawaited(_cancelRecording());
    }
  }

  /// Runs when a spoken reply finishes. In hands-free mode this is what makes
  /// the exchange feel like a call instead of a walkie-talkie.
  void _afterReply() {
    if (!handsFree || !mounted) return;
    if (autoListenQueued || recording || sending || recorderBusy) return;
    autoListenQueued = true;
    // A beat of silence between the reply ending and the microphone opening
    // stops the tail of the reply bleeding into the next recording.
    Future<void>.delayed(const Duration(milliseconds: 400), () async {
      autoListenQueued = false;
      if (!mounted || !handsFree) return;
      if (recording || sending || recorderBusy || retryAudioPath != null) {
        return;
      }
      if (quota?.exhausted ?? false) {
        setState(() {
          handsFree = false;
          voiceError = "You've used today's AI messages. Try again tomorrow.";
        });
        return;
      }
      await _toggleVoice();
    });
  }

  /// Switching hands-free off mid-call should hand control back immediately,
  /// not after the turn in flight finishes.
  Future<void> _setHandsFree(bool value) async {
    setState(() {
      handsFree = value;
      voiceError = null;
    });
    final store = StoreScope.read(context);
    unawaited(store.api.client.store.setHandsFree(value));
    if (!value) {
      autoListenQueued = false;
      if (recording) await _cancelRecording();
      return;
    }
    // Turning it on is itself the "start the call" gesture.
    if (!recording && !sending && !recorderBusy && retryAudioPath == null) {
      await _toggleVoice();
    }
  }

  Future<void> _setMuted(bool value) async {
    setState(() => mutedAudio = value);
    final store = StoreScope.read(context);
    unawaited(store.api.client.store.setMuted(value));
    if (value) {
      await player.stop();
    }
  }

  /// Lets the user pick which voice reads the replies. The choice is sent with
  /// the next voice turn, so it takes effect without restarting the chat.
  Future<void> _pickVoice() async {
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .7,
          maxChildSize: .9,
          builder: (_, controller) => RadioGroup<String?>(
            groupValue: preferredVoice,
            onChanged: (value) => Navigator.pop(sheetContext, value),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    "Aria's voice",
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Applies to the next spoken reply.',
                    style: TextStyle(fontSize: 12, color: Color(0xff786b90)),
                  ),
                ),
                const RadioListTile<String?>(
                  value: null,
                  title: Text('App default'),
                  subtitle: Text('Whatever the server is configured with'),
                ),
                for (final voice in AriaVoice.all)
                  RadioListTile<String?>(
                    value: voice.id,
                    title: Text(voice.label),
                    subtitle: Text(voice.tone),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    // A dismissed sheet returns null, which is also "App default" — compare
    // against the value that was showing to tell the two apart.
    if (chosen == preferredVoice) return;
    setState(() => preferredVoice = chosen);
    final store = StoreScope.read(context);
    unawaited(store.api.client.store.setVoice(chosen));
  }

  Future<void> _cancelRecording() async {
    if (recorderBusy) return;
    setState(() => recorderBusy = true);
    try {
      await recorder.cancel();
      _stopMeter();
      if (mounted) {
        setState(() {
          recording = false;
          soundLevel = 0;
          recordingSeconds = 0;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => voiceError = 'Could not cancel recording. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => recorderBusy = false);
    }
  }

  Future<void> _deleteAudio(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _discardAudio() async {
    final path = retryAudioPath;
    setState(() {
      retryAudioPath = null;
      voiceError = null;
    });
    if (path != null) await _deleteAudio(path);
  }

  Future<void> _playReply(String audio) async {
    if (mutedAudio) return;
    try {
      await player.play(BytesSource(base64Decode(audio)));
    } catch (_) {
      if (mounted) {
        setState(
          () => voiceError =
              'Audio playback is unavailable. You can read the reply below.',
        );
        // No audio means no completion event, so drive the loop by hand.
        _afterReply();
      }
    }
  }

  Future<void> _sendVoice(String path) async {
    if (sending) return;
    final store = StoreScope.read(context);
    final placeholder = 'voice-${DateTime.now().microsecondsSinceEpoch}';
    var delivered = false;
    setState(() {
      sending = true;
      retryAudioPath = null;
      voiceError = null;
      messages = [
        ...messages,
        ChatMessage(
          id: placeholder,
          text: 'Transcribing your voice message…',
          isUser: true,
          pending: true,
        ),
      ];
    });
    _scrollToEnd();
    try {
      final id = await _ensureConversation(store);
      if (id == null) {
        throw StateError(
          'No calendar is available yet. Your recording is ready to retry.',
        );
      }
      final turn = await store.api.ai.sendVoiceMessage(
        conversationId: id,
        filePath: path,
        voice: preferredVoice,
      );
      delivered = true;
      if (!mounted) return;
      setState(() {
        messages = [
          for (final message in messages)
            if (message.id == placeholder)
              ChatMessage(
                id: '$placeholder-transcript',
                text: turn.transcript?.trim().isNotEmpty == true
                    ? turn.transcript!
                    : 'Transcript unavailable for this recording.',
                isUser: true,
              )
            else
              message,
          turn.message,
        ];
        pendingActions = turn.pendingActions;
        lastAudio = turn.audioBase64;
        typingId = turn.message.id;
      });
      _scrollToEnd();
      unawaited(_loadQuota());
      final spoken = turn.audioBase64;
      if (spoken != null && !mutedAudio) {
        unawaited(_playReply(spoken));
      } else {
        // Nothing will play, so no completion event is coming. Keep a
        // hands-free call moving instead of stalling on a silent turn.
        _afterReply();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          retryAudioPath = path;
          voiceError = error is ApiException
              ? error.message
              : '$error'.replaceFirst('Bad state: ', '');
          // A failed turn should not silently re-open the microphone; the
          // recording is kept for an explicit retry.
          handsFree = false;
        });
        if (error is ApiException && error.needsPremium) _explain(error);
      }
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
          messages = messages.where((m) => m.id != placeholder).toList();
        });
      }
      if (delivered || !mounted) await _deleteAudio(path);
    }
  }

  /// Turns the assistant's specific failure codes into next steps.
  void _explain(ApiException error) {
    if (error.needsPremium) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Premium required'),
          content: const Text(
            'The AI assistant is included with Premium. Upgrade to plan your week by chat or voice.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                go(context, '/subscription');
              },
              child: const Text('See plans'),
            ),
          ],
        ),
      );
      return;
    }
    if (error.code == 'AI_QUOTA_EXHAUSTED') {
      toastError(
        context,
        "You've used today's AI messages. Try again tomorrow.",
      );
      return;
    }
    toastError(context, error.message);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Keeps an answer that is still arriving in view — but only for a reader who
  /// is already at the bottom. Scrolling up to re-read an earlier turn stays
  /// put. It runs after the frame so it measures the text that just landed,
  /// not the extent from before it.
  void _followTyping() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final position = scroll.position;
      if (position.maxScrollExtent - position.pixels > 140) return;
      position.jumpTo(position.maxScrollExtent);
    });
  }

  Future<void> _resolveAction(PendingAction action, bool confirmIt) async {
    final store = StoreScope.read(context);
    final done = await runAction(
      context,
      () async {
        if (confirmIt) {
          await store.api.ai.confirmAction(action.id);
          await store.loadEvents(silent: true);
        } else {
          await store.api.ai.rejectAction(action.id);
        }
      },
      success: confirmIt ? 'Applied to your calendar' : 'Discarded',
      onError: (error) async {
        if (!error.isConflict) {
          toastError(context, error.message);
          return;
        }
        final proceed = await confirm(
          context,
          'Schedule overlap',
          'This change overlaps an existing event. Apply it anyway?',
          action: 'Apply',
        );
        if (!proceed || !mounted) return;
        await runAction(context, () async {
          await store.api.ai.confirmAction(action.id, overrideConflicts: true);
          await store.loadEvents(silent: true);
        }, success: 'Applied to your calendar');
        if (mounted) {
          setState(
            () => pendingActions = pendingActions
                .where((item) => item.id != action.id)
                .toList(),
          );
        }
      },
    );
    if (done && mounted) {
      setState(
        () => pendingActions = pendingActions
            .where((item) => item.id != action.id)
            .toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (widget.voiceMode) {
      return Backdrop(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Voice with Aria'),
            actions: [
              IconButton(
                tooltip: 'Chat history',
                onPressed:
                    sending ||
                        recording ||
                        recorderBusy ||
                        retryAudioPath != null
                    ? null
                    : () => scaffold.currentState?.openEndDrawer(),
                icon: const Icon(Icons.history_rounded),
              ),
            ],
          ),
          key: scaffold,
          endDrawer: _historyDrawer(store),
          body: SafeArea(
            top: false,
            child: VoiceExperience(
              recording: recording,
              busy: recorderBusy || loading,
              sending: sending,
              speaking: speaking,
              muted: mutedAudio,
              seconds: recordingSeconds,
              level: soundLevel,
              hasMessages: messages.isNotEmpty,
              hasRetry: retryAudioPath != null,
              canReplay: lastAudio != null,
              error: voiceError,
              handsFree: handsFree,
              voiceLabel: AriaVoice.find(preferredVoice)?.label ?? 'Voice',
              allowance: quota == null
                  ? null
                  : '${quota!.remaining} LEFT TODAY',
              allowanceLow: quota?.low ?? false,
              controller: input,
              scroll: scroll,
              onRecord: _toggleVoice,
              onCancel: _cancelRecording,
              onRetry: () {
                final path = retryAudioPath;
                if (path != null) _sendVoice(path);
              },
              onDiscard: _discardAudio,
              onHandsFree: (value) => unawaited(_setHandsFree(value)),
              onPickVoice: () => unawaited(_pickVoice()),
              onMute: () => unawaited(_setMuted(!mutedAudio)),
              onReplay: () {
                if (speaking) {
                  unawaited(player.stop());
                } else if (lastAudio != null) {
                  unawaited(_setMuted(false));
                  unawaited(_playReply(lastAudio!));
                }
              },
              onSend: _send,
              messages: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < messages.length; i++)
                    _bubble(messages[i], i),
                  if (sending) _inFlight(),
                  _pendingCards(),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Backdrop(
      child: Scaffold(
        key: scaffold,
        appBar: AppBar(
          title: Text(messages.isEmpty ? 'New chat' : title),
          actions: [
            // Typed and spoken turns draw on the same daily allowance, so the
            // warning belongs here too — but only once it matters.
            if (quota != null && (quota!.low || quota!.exhausted))
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    quota!.exhausted
                        ? 'None left today'
                        : '${quota!.remaining} left today',
                    style: const TextStyle(
                      color: Color(0xffa33f5c),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Chat history',
              onPressed:
                  sending || recording || recorderBusy || retryAudioPath != null
                  ? null
                  : () => scaffold.currentState?.openEndDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ],
        ),
        endDrawer: _historyDrawer(store),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: loading
                    ? const LoadingBlock(height: 260)
                    : messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VoiceOrb(active: recording, onTap: _toggleVoice),
                            const SizedBox(height: 18),
                            Text(
                              recording
                                  ? 'Listening… tap to send'
                                  : 'Click and Say',
                              style: const TextStyle(
                                color: lilac,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.all(20),
                        itemCount: messages.length + 1,
                        itemBuilder: (context, i) {
                          if (i < messages.length) return _bubble(messages[i], i);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (sending) _inFlight(),
                              _pendingCards(),
                            ],
                          );
                        },
                      ),
              ),
              // A turn in flight is announced by the typing bubble in the
              // thread itself, so only the microphone still needs a line here.
              if (recording)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic, size: 14, color: purple),
                      SizedBox(width: 10),
                      Text(
                        'Listening… tap stop to send',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              if (voiceError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Text(
                    voiceError!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (retryAudioPath != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: sending ? null : _discardAudio,
                      child: const Text('Discard recording'),
                    ),
                    TextButton(
                      onPressed: sending
                          ? null
                          : () => _sendVoice(retryAudioPath!),
                      child: const Text('Retry send'),
                    ),
                  ],
                ),
              if (recording)
                TextButton(
                  onPressed: recorderBusy ? null : _cancelRecording,
                  child: const Text('Cancel recording'),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                child: TextField(
                  controller: input,
                  enabled: !sending && !recording && !recorderBusy,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: 'Ask anything',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: recording
                              ? 'Stop and send'
                              : 'Record a voice message',
                          onPressed: sending ? null : _toggleVoice,
                          icon: Icon(
                            recording ? Icons.stop_circle : Icons.mic_none,
                            size: 21,
                            color: recording ? purple : null,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Send message',
                          onPressed: sending || recording || recorderBusy
                              ? null
                              : () => _send(input.text),
                          icon: const Icon(
                            Icons.arrow_upward,
                            color: purple,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pendingCards() {
    if (pendingActions.isEmpty) return const SizedBox.shrink();
    return Column(
      children: pendingActions
          .map(
            (action) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Surface(
                color: const Color(0xfffff4e0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.pending_actions,
                          size: 18,
                          color: Color(0xffb87b00),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            action.summary,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    if (action.conflicts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Overlaps ${action.conflicts.first.title}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            'Discard',
                            outline: true,
                            onPressed: () => _resolveAction(action, false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrimaryButton(
                            'Confirm',
                            onPressed: () => _resolveAction(action, true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  /// What the user typed is shown exactly as typed. The assistant answers in
  /// Markdown, so its side is rendered rather than printed, and the reply that
  /// just landed types itself out on the way in.
  Widget _bubble(ChatMessage message, int index) {
    final assistant = !message.isUser;
    final body = TextStyle(
      fontSize: 13,
      height: 1.45,
      // The stand-in voice bubble reads as provisional until the transcript
      // replaces it.
      fontStyle: message.pending ? FontStyle.italic : FontStyle.normal,
      color: message.pending ? muted : const Color(0xff151518),
    );
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: widget.voiceMode ? 320 : 288),
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 5),
        decoration: _bubbleSkin(assistant, message.isUser),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.voiceMode) ...[
              Text(
                message.pending
                    ? 'Your recording'
                    : message.isUser
                    ? 'You said'
                    : 'Aria',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xff7c3aed),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
            ],
            SelectionArea(
              child: assistant && !message.pending
                  ? StreamedMarkdown(
                      message.text,
                      style: body,
                      animate: message.id == typingId,
                      onDone: () {
                        if (mounted && typingId == message.id) {
                          setState(() => typingId = null);
                        }
                      },
                      onTick: _followTyping,
                    )
                  : Text(message.text, style: body),
            ),
            _messageActions(message, index),
          ],
        ),
      ),
    );
  }

  /// The squared-off corner points back at whoever is speaking, which tells
  /// the two sides apart at a glance even before the colour registers.
  BoxDecoration _bubbleSkin(bool assistant, bool isUser) => BoxDecoration(
    color: isUser
        ? const Color(0xffede5fc)
        : Colors.white.withValues(alpha: .92),
    border: Border.all(color: const Color(0xff7c3aed).withValues(alpha: .09)),
    borderRadius: BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(assistant ? 6 : 20),
      bottomRight: Radius.circular(assistant ? 20 : 6),
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xff7c3aed).withValues(alpha: .05),
        blurRadius: 14,
        offset: const Offset(0, 5),
      ),
    ],
  );

  /// Quiet by design, and only offering what applies: a server-side id is 24
  /// hex characters, so the optimistic local bubbles can't be edited or
  /// deleted until the turn comes back.
  Widget _messageActions(ChatMessage message, int index) {
    final saved = message.id.length == 24;
    Widget button(
      String tooltip,
      IconData icon,
      VoidCallback? onPressed, {
      Color color = muted,
    }) => IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 26),
      icon: Icon(
        icon,
        size: 14,
        color: onPressed == null ? muted.withValues(alpha: .4) : color,
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button('Copy message', Icons.copy_outlined, () {
          Clipboard.setData(ClipboardData(text: message.text));
          toast(context, 'Message copied');
        }),
        if (message.isUser && saved)
          button(
            'Edit and resend',
            Icons.edit_outlined,
            sending ? null : () => _editMessage(message),
          ),
        if (saved)
          button(
            'Delete message',
            Icons.delete_outline,
            sending ? null : () => _deleteMessage(message, index),
            color: const Color(0xffff9a9a),
          ),
      ],
    );
  }

  /// Plain-language names for the tools, so the wait says what is actually
  /// happening instead of leaking the model's vocabulary at the user.
  static const _toolLabels = {
    'list_events': 'Checking your calendar',
    'find_availability': 'Looking for a free slot',
    'search_notes': 'Reading your notes',
    'list_contacts': 'Looking up your contacts',
    'list_groups': 'Checking your groups',
    'propose_create_event': 'Preparing an event',
    'propose_update_event': 'Preparing a change',
    'propose_delete_event': 'Preparing a deletion',
    'propose_create_note': 'Preparing a note',
  };

  /// The waiting bubble sits where the answer will appear, so the reply grows
  /// out of the same spot instead of shoving the thread down from elsewhere.
  Widget _typingBubble() {
    final work = activeTools
        .map((tool) => _toolLabels[tool])
        .nonNulls
        .toSet()
        .join(' · ');
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: _bubbleSkin(true, false),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TypingDots(),
            if (work.isNotEmpty) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  work,
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The answer as it arrives. Half-typed Markdown is repaired on every frame,
  /// so a bold run resolves as it lands rather than flashing its asterisks,
  /// and the caret marks where the model has got to.
  Widget _liveBubble() => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(maxWidth: widget.voiceMode ? 320 : 288),
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: _bubbleSkin(true, false),
      child: MarkdownText(
        '${StreamedMarkdown.repair(streamingText)}▍',
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: Color(0xff151518),
        ),
      ),
    ),
  );

  /// Whichever of the two applies: dots and the work in progress until the
  /// first word lands, the answer itself from then on.
  Widget _inFlight() =>
      streamingText.isEmpty ? _typingBubble() : _liveBubble();

  Future<void> _editMessage(ChatMessage message) async {
    final id = conversationId;
    if (id == null) return;
    final controller = TextEditingController(text: message.text);
    final edited = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Edit message'),
        content: TextField(controller: controller, maxLines: 4),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Resend'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (edited == null || edited.trim().isEmpty || !mounted) return;

    final store = StoreScope.read(context);
    setState(() => sending = true);
    try {
      final turn = await store.api.ai.editMessage(
        conversationId: id,
        messageId: message.id,
        content: edited.trim(),
      );
      if (!mounted) return;
      setState(() => pendingActions = turn.pendingActions);
      await _loadConversation(id);
    } on ApiException catch (error) {
      if (mounted) _explain(error);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _deleteMessage(ChatMessage message, int index) async {
    final id = conversationId;
    if (id == null) return;
    final store = StoreScope.read(context);
    final done = await runAction(
      context,
      () =>
          store.api.ai.deleteMessage(conversationId: id, messageId: message.id),
      showSpinner: false,
    );
    if (done && mounted) {
      setState(() => messages = [...messages]..removeAt(index));
    }
  }

  Widget _historyDrawer(AppStore store) {
    final needle = historyQuery.toLowerCase();
    final items = store.conversations
        .where((item) => item.title.toLowerCase().contains(needle))
        .toList();
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: const Text('Chat history'),
              trailing: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New chat'),
              onTap: () {
                setState(() {
                  messages = [];
                  pendingActions = [];
                  conversationId = null;
                  title = 'New chat';
                });
                Navigator.pop(context);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                onChanged: (value) => setState(() => historyQuery = value),
                decoration: const InputDecoration(
                  hintText: 'Search chat history',
                  prefixIcon: Icon(Icons.search, size: 20, color: muted),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState('No saved chats yet.')
                  : ListView(
                      children: items
                          .map(
                            (item) => ListTile(
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                relativeTime(item.updatedAt),
                                style: const TextStyle(fontSize: 10),
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _loadConversation(item.id);
                              },
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a continuous voice conversation without navigating away after each turn.
class VoiceScreen extends StatelessWidget {
  const VoiceScreen({super.key, this.conversationId});
  final String? conversationId;
  @override
  Widget build(BuildContext context) =>
      ConversationScreen(conversationId: conversationId, voiceMode: true);
}
