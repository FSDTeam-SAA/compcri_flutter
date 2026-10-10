import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:compcri_flutter/core/speech_monitor.dart';
import 'package:compcri_flutter/core/voice_activity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Silero rejects loud noise and resets across three spoken turns',
    (tester) async {
      const speech = String.fromEnvironment('SPEECH_QA_WAV');
      expect(speech, isNotEmpty);
      final directory = await Directory.systemTemp.createTemp(
        'speech-detector-qa',
      );
      final monitor = await SpeechMonitor.create();
      addTearDown(() async {
        await monitor.dispose();
        await directory.delete(recursive: true);
      });
      // Loud steady fan-like sound, louder than the old amplitude cutoff.
      final noise = Uint8List(16000 * 2 * 3);
      final values = ByteData.sublistView(noise);
      for (var sample = 0; sample < noise.length ~/ 2; sample++) {
        values.setInt16(
          sample * 2,
          (5000 * sin(2 * pi * 150 * sample / 16000)).round(),
          Endian.little,
        );
      }
      final noiseFile = File('${directory.path}/noise.wav');
      await noiseFile.writeAsBytes(_wave(noise));
      final finished = Completer<void>();
      var noiseSpeech = false;
      await monitor.start(noiseFile.path, (probability, time) {
        if (probability >= .6) {
          noiseSpeech = true;
        }
        if (time >= const Duration(milliseconds: 2900) &&
            !finished.isCompleted) {
          finished.complete();
        }
      }, () => finished.completeError(StateError('Native inference failed')));
      await finished.future.timeout(const Duration(seconds: 15));
      await monitor.stop();
      expect(noiseSpeech, isFalse);

      final source = base64Decode(speech);
      final offset = waveDataOffset(source)!;
      final samples = Uint8List.fromList([
        ...source.sublist(offset),
        ...Uint8List(32000 * 3),
      ]);
      final speechFile = File('${directory.path}/speech.wav');
      await speechFile.writeAsBytes(_wave(samples));
      for (var turn = 0; turn < 3; turn++) {
        final activity = VoiceActivity();
        final sent = Completer<void>();
        var peak = 0.0;
        await monitor.start(speechFile.path, (probability, time) {
          peak = max(peak, probability);
          final decision = activity.add(probability, time);
          if (decision == VoiceTurnDecision.send && !sent.isCompleted) {
            sent.complete();
          }
        }, () => sent.completeError(StateError('Native inference failed')));
        await sent.future.timeout(const Duration(seconds: 15));
        await monitor.stop();
        expect(
          peak,
          greaterThan(.6),
          reason: 'Turn $turn must contain detected speech',
        );
        expect(activity.heardSpeech, isTrue);
      }
    },
  );
}

Uint8List _wave(Uint8List samples) {
  final bytes = Uint8List(44 + samples.length);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, 36 + samples.length, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, samples.length, Endian.little);
  bytes.setRange(44, bytes.length, samples);
  return bytes;
}
