Silero VAD v5 model, bundled for offline speech detection.

Model source: https://cdn.jsdelivr.net/npm/@keyurmaru/vad@0.0.1/silero_vad_v5.onnx
Upstream: https://github.com/snakers4/silero-vad
License: MIT (see LICENSE).
SHA-256: 2623a2953f6ff3d2c1e61740c6cdb7168133479b267dfef114a4a3cc5bdd788f

Native ONNX bindings come from pinned vad 0.0.8. The application owns frame
inference to release all input and output tensors and resets recurrent state
for each recording. Audio is 16 kHz mono signed PCM16 inside a WAV recording.
No model download occurs when the microphone starts.
