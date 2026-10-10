import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
// The pinned vad version supplies the native, 16 KB-aligned ONNX runtime.
// Keep inference here to release every input/output tensor after each frame.
// ignore: implementation_imports
import 'package:vad/src/platform/native/onnxruntime/ort_session.dart';
// ignore: implementation_imports
import 'package:vad/src/platform/native/onnxruntime/ort_value.dart';

typedef SpeechFrame = void Function(double probability, Duration audioTime);
typedef SpeechMonitorFactory = Future<SpeechMonitor> Function();

/// Reads the PCM already being recorded, without opening a second microphone.
abstract class SpeechMonitor {
  static Future<SpeechMonitor> create() async {
    final bytes = await rootBundle.load('assets/vad/silero_vad_v5.onnx');
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(1)
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    try {
      final session = OrtSession.fromBuffer(
        bytes.buffer.asUint8List(),
        options,
      );
      return _SileroSpeechMonitor(session, options);
    } catch (_) {
      options.release();
      rethrow;
    }
  }

  Future<void> start(String path, SpeechFrame onFrame, void Function() onError);
  Future<void> stop();
  Future<void> dispose();
}

class _SileroSpeechMonitor implements SpeechMonitor {
  _SileroSpeechMonitor(this.session, this.options);
  final OrtSession session;
  final OrtSessionOptions options;
  Float32List _state = Float32List(256);
  final List<int> _pending = [];
  int _samples = 0;
  Timer? _timer;
  RandomAccessFile? _file;
  Future<void>? _reading;
  int _generation = 0;
  int? _position;
  bool _disposed = false;

  @override
  Future<void> start(
    String path,
    SpeechFrame onFrame,
    void Function() onError,
  ) async {
    await stop();
    if (_disposed) throw StateError('Speech detector is closed.');
    _state.fillRange(0, _state.length, 0);
    _pending.clear();
    _samples = 0;
    final generation = ++_generation;
    _position = null;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_reading != null || generation != _generation) return;
      _reading = _read(path, generation, onFrame)
          .catchError((Object _) {
            if (generation == _generation) onError();
          })
          .whenComplete(() => _reading = null);
    });
  }

  Future<void> _read(String path, int generation, SpeechFrame onFrame) async {
    if (_file == null) {
      if (!await File(path).exists()) return;
      _file = await File(path).open();
    }
    final file = _file!;
    if (generation != _generation) return;
    final length = await file.length();
    if (_position == null) {
      if (length < 44) return;
      await file.setPosition(0);
      final header = await file.read(length.clamp(44, 4096));
      _position = waveDataOffset(header);
      // Android's recorder reserves 44 zero bytes until it closes the WAV.
      if (_position == null &&
          Platform.isAndroid &&
          header.take(44).every((byte) => byte == 0)) {
        _position = 44;
      }
      if (_position == null) return;
    }
    final count = ((length - _position!).clamp(0, 32000) ~/ 2) * 2;
    if (count == 0 || generation != _generation) return;
    await file.setPosition(_position!);
    final bytes = await file.read(count);
    _position = _position! + bytes.length;
    if (generation != _generation) return;
    _pending.addAll(bytes);
    while (_pending.length >= 1024 && generation == _generation) {
      final pcm = ByteData.sublistView(
        Uint8List.fromList(_pending.sublist(0, 1024)),
      );
      _pending.removeRange(0, 1024);
      final frame = Float32List(512);
      for (var i = 0; i < 512; i++) {
        frame[i] = pcm.getInt16(i * 2, Endian.little) / 32768;
      }
      final probability = _infer(frame);
      onFrame(probability, Duration(microseconds: _samples * 1000000 ~/ 16000));
      _samples += 512;
    }
  }

  double _infer(Float32List frame) {
    final input = OrtValueTensor.createTensorWithDataList(frame, [1, 512]);
    final state = OrtValueTensor.createTensorWithDataList(_state, [2, 1, 128]);
    final rate = OrtValueTensor.createTensorWithData(16000);
    final run = OrtRunOptions();
    List<OrtValue?> outputs = [];
    try {
      outputs = session.run(run, {'input': input, 'state': state, 'sr': rate});
      final probability = (outputs[0]!.value as List<List<double>>)[0][0];
      final nextState = outputs[1]!.value as List<List<List<double>>>;
      _state = Float32List.fromList(
        nextState.expand((x) => x.expand((y) => y)).toList(),
      );
      return probability;
    } finally {
      for (final output in outputs) {
        output?.release();
      }
      input.release();
      state.release();
      rate.release();
      run.release();
    }
  }

  @override
  Future<void> stop() async {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    await _reading;
    final file = _file;
    _file = null;
    if (file != null) await file.close();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    session.release();
    options.release();
  }
}

/// iOS WAV headers can contain extra chunks; don't assume a fixed offset.
int? waveDataOffset(Uint8List bytes) {
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final name = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    if (name == 'data') return offset + 8;
    final size = data.getUint32(offset + 4, Endian.little);
    offset += 8 + size + (size % 2);
  }
  return null;
}
