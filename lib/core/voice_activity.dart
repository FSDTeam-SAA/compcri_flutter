enum VoiceTurnDecision { listen, send, pause }

/// Uses speech probability, never meter amplitude, to end spoken turns.
class VoiceActivity {
  static const pauseAfterSpeech = Duration(milliseconds: 1800);
  static const noSpeechTimeout = Duration(seconds: 12);
  static const _speechConfirmation = Duration(milliseconds: 200);
  Duration _now = Duration.zero;
  Duration? _candidate, _lastSpeech, _lastSample;
  bool _voiced = false;
  bool heardSpeech = false;
  VoiceTurnDecision _decision = VoiceTurnDecision.listen;
  // The model is initialized before the mic starts.
  bool get ready => true;

  VoiceTurnDecision add(
    double probability,
    Duration elapsed, {
    bool finishTurn = true,
  }) {
    if (elapsed > _now) _now = elapsed;
    if (!probability.isFinite || probability < 0 || probability > 1) {
      return finishTurn ? poll(elapsed) : VoiceTurnDecision.listen;
    }
    if (_lastSample != null &&
        elapsed - _lastSample! > const Duration(milliseconds: 600)) {
      _candidate = null;
      _voiced = false;
    }
    _lastSample = elapsed;
    if (probability >= (_voiced ? .35 : .6)) {
      _candidate ??= elapsed;
      if (_voiced || elapsed - _candidate! >= _speechConfirmation) {
        _voiced = true;
        heardSpeech = true;
        _lastSpeech = elapsed;
      }
    } else {
      _voiced = false;
      _candidate = null;
    }
    return finishTurn ? poll(elapsed) : VoiceTurnDecision.listen;
  }

  VoiceTurnDecision poll(Duration elapsed) {
    if (elapsed > _now) _now = elapsed;
    if (_decision != VoiceTurnDecision.listen) return _decision;
    if (heardSpeech && _lastSpeech != null) {
      final candidateActive =
          _candidate != null &&
          _lastSample != null &&
          _now - _lastSample! < const Duration(milliseconds: 600);
      if (!candidateActive && _now - _lastSpeech! >= pauseAfterSpeech) {
        _decision = VoiceTurnDecision.send;
      }
    } else if (_now >= noSpeechTimeout) {
      _decision = VoiceTurnDecision.pause;
    }
    return _decision;
  }
}
