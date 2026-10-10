import 'dart:typed_data';
import 'package:compcri_flutter/core/voice_activity.dart';
import 'package:compcri_flutter/core/speech_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void frames(
    VoiceActivity activity,
    double probability,
    int from,
    int to, {
    bool finishTurn = true,
  }) {
    for (var ms = from; ms <= to; ms += 100) {
      activity.add(
        probability,
        Duration(milliseconds: ms),
        finishTurn: finishTurn,
      );
    }
  }

  test('non-speech noise pauses without sending an empty recording', () {
    final activity = VoiceActivity();
    frames(activity, .02, 0, 11900);
    expect(activity.heardSpeech, isFalse);
    expect(activity.poll(const Duration(seconds: 12)), VoiceTurnDecision.pause);
  });
  test('confirmed speech ends after returning to non-speech room noise', () {
    final activity = VoiceActivity();
    frames(activity, .02, 0, 600);
    frames(activity, .98, 700, 1600);
    frames(activity, .05, 1700, 3300);
    expect(
      activity.poll(const Duration(milliseconds: 3300)),
      VoiceTurnDecision.listen,
    );
    expect(
      activity.poll(const Duration(milliseconds: 3400)),
      VoiceTurnDecision.send,
    );
  });
  test('isolated false positive does not submit room noise', () {
    final activity = VoiceActivity();
    activity.add(.95, const Duration(milliseconds: 700));
    activity.add(.01, const Duration(milliseconds: 800));
    expect(activity.heardSpeech, isFalse);
    expect(activity.poll(const Duration(seconds: 12)), VoiceTurnDecision.pause);
  });
  test('lower confidence can continue speech after a confirmed start', () {
    final activity = VoiceActivity();
    frames(activity, .8, 0, 400);
    frames(activity, .4, 500, 4000);
    expect(activity.poll(const Duration(seconds: 4)), VoiceTurnDecision.listen);
    frames(activity, .1, 4100, 5800);
    expect(
      activity.poll(const Duration(milliseconds: 5800)),
      VoiceTurnDecision.send,
    );
  });
  test('a short pause between words does not submit the sentence', () {
    final activity = VoiceActivity();
    frames(activity, .9, 0, 800);
    frames(activity, .01, 900, 1900);
    expect(
      activity.poll(const Duration(milliseconds: 1900)),
      VoiceTurnDecision.listen,
    );
    frames(activity, .9, 2000, 3000);
    frames(activity, .01, 3100, 4800);
    expect(
      activity.poll(const Duration(milliseconds: 4800)),
      VoiceTurnDecision.send,
    );
  });
  test('a missing classifier stream sends captured speech using wall time', () {
    final activity = VoiceActivity();
    frames(activity, .9, 0, 800);
    expect(
      activity.poll(const Duration(milliseconds: 2600)),
      VoiceTurnDecision.send,
    );
  });
  test('an unavailable classifier never keeps an empty microphone open', () {
    final activity = VoiceActivity();
    expect(activity.poll(const Duration(seconds: 12)), VoiceTurnDecision.pause);
  });
  test(
    'manual recordings do not latch a timeout before hands-free is enabled',
    () {
      final activity = VoiceActivity();
      frames(activity, .01, 0, 15000, finishTurn: false);
      frames(activity, .9, 15100, 15800, finishTurn: false);
      activity.add(.01, const Duration(milliseconds: 15900), finishTurn: false);
      expect(
        activity.poll(const Duration(milliseconds: 16000)),
        VoiceTurnDecision.listen,
      );
      expect(
        activity.poll(const Duration(milliseconds: 17600)),
        VoiceTurnDecision.send,
      );
    },
  );
  test('three successive turns have independent speech and silence state', () {
    for (var turn = 0; turn < 3; turn++) {
      final activity = VoiceActivity();
      expect(activity.heardSpeech, isFalse);
      frames(activity, .01, 0, 600);
      frames(activity, .9, 700, 1400);
      frames(activity, .01, 1500, 3200);
      expect(
        activity.poll(const Duration(milliseconds: 3200)),
        VoiceTurnDecision.send,
      );
    }
  });
  test(
    'voice followed by varying non-speech confidence cannot stay listening',
    () {
      final activity = VoiceActivity();
      frames(activity, .9, 0, 800);
      const noise = [.01, .12, .04, .2, .1];
      for (var ms = 900; ms <= 2600; ms += 100) {
        activity.add(
          noise[(ms ~/ 100) % noise.length],
          Duration(milliseconds: ms),
        );
      }
      expect(
        activity.poll(const Duration(milliseconds: 2600)),
        VoiceTurnDecision.send,
      );
    },
  );
  test('continuous actual speech is kept until the person stops', () {
    final activity = VoiceActivity();
    frames(activity, .95, 0, 20000);
    expect(
      activity.poll(const Duration(seconds: 20)),
      VoiceTurnDecision.listen,
    );
    frames(activity, .01, 20100, 21800);
    expect(
      activity.poll(const Duration(milliseconds: 21800)),
      VoiceTurnDecision.send,
    );
  });
  test('invalid probability readings cannot confirm speech', () {
    final activity = VoiceActivity();
    for (final probability in [double.nan, double.infinity, -160.0, 2.0]) {
      activity.add(probability, const Duration(seconds: 1));
    }
    expect(activity.heardSpeech, isFalse);
    expect(activity.poll(const Duration(seconds: 12)), VoiceTurnDecision.pause);
  });
  test('terminal send is emitted only as one latched decision', () {
    final activity = VoiceActivity();
    frames(activity, .9, 0, 800);
    activity.add(.01, const Duration(milliseconds: 900));
    expect(
      activity.poll(const Duration(milliseconds: 2600)),
      VoiceTurnDecision.send,
    );
    expect(
      activity.add(.9, const Duration(seconds: 3)),
      VoiceTurnDecision.send,
    );
  });
  test(
    'WAV reader skips optional iOS chunks and handles padded chunk sizes',
    () {
      final bytes = Uint8List(54);
      bytes.setRange(0, 4, 'RIFF'.codeUnits);
      bytes.setRange(8, 12, 'WAVE'.codeUnits);
      bytes.setRange(12, 16, 'JUNK'.codeUnits);
      ByteData.sublistView(bytes).setUint32(16, 1, Endian.little);
      bytes.setRange(22, 26, 'fmt '.codeUnits);
      ByteData.sublistView(bytes).setUint32(26, 16, Endian.little);
      bytes.setRange(46, 50, 'data'.codeUnits);
      expect(waveDataOffset(bytes), 54);
      expect(waveDataOffset(Uint8List(44)), isNull);
    },
  );
}
