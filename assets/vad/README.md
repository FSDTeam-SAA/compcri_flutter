Silero VAD v5 model, bundled for offline speech detection.

Model source: https://cdn.jsdelivr.net/npm/@keyurmaru/vad@0.0.1/silero_vad_v5.onnx
Upstream: https://github.com/snakers4/silero-vad
License: MIT (see LICENSE).
SHA-256: 2623a2953f6ff3d2c1e61740c6cdb7168133479b267dfef114a4a3cc5bdd788f

Native ONNX bindings come from pinned vad 0.0.8. The application owns frame
inference to release all input and output tensors and resets recurrent state
and the waveform context for each recording. Each 512-sample frame is prefixed
with the previous 64 samples (576 model input samples), following the
[upstream ONNX wrapper](https://github.com/snakers4/silero-vad/blob/v5.1.2/src/silero_vad/utils_vad.py).
Audio is 16 kHz mono signed PCM16 inside a WAV recording.
No model download occurs when the microphone starts.
