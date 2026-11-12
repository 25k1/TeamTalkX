import hashlib
import json
import pathlib
import struct
import sys
import urllib.request
import wave

import numpy as np
import onnx
import onnxruntime as ort
from onnx import numpy_helper

MODEL_URL = (
    "https://raw.githubusercontent.com/snakers4/silero-vad/"
    "bfdc0193023f121ea5b3cc7b176dbed570a68a59/src/silero_vad/data/silero_vad.onnx"
)
MODEL_SHA256 = "1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3"

SAMPLE_RATE = 16000
CHUNK = 512
CONTEXT = 64

ROOT = pathlib.Path(__file__).resolve().parents[2]
WEIGHTS_OUT = ROOT / "assets/vad/silero_vad_v6_2.bin"
FIXTURES = ROOT / "test/fixtures/silero"


def load_model() -> bytes:
    data = urllib.request.urlopen(MODEL_URL, timeout=60).read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != MODEL_SHA256:
        sys.exit(f"Model SHA-256 {digest} does not match {MODEL_SHA256}")
    return data


def weights_16k(model: onnx.ModelProto) -> dict[str, np.ndarray]:
    branch = next(a.g for a in model.graph.node[2].attribute if a.name == "then_branch")
    out = {}
    for node in branch.node:
        name = node.output[0].replace("If_0_then_branch__Inline_0__", "")
        if node.op_type == "Constant" and not name.startswith("/") and not name.startswith("self."):
            out[name] = numpy_helper.to_array(node.attribute[0].t).astype(np.float32)
    return out


def tensors(w: dict[str, np.ndarray]) -> list[tuple[str, np.ndarray]]:
    return [
        ("stft_basis", w["stft.forward_basis_buffer"][:, 0, :]),
        *[
            item
            for i in range(4)
            for item in (
                (f"enc{i}_w", w[f"encoder.{i}.reparam_conv.weight"]),
                (f"enc{i}_b", w[f"encoder.{i}.reparam_conv.bias"]),
            )
        ],
        ("lstm_w", np.concatenate([w["decoder.rnn.weight_ih"], w["decoder.rnn.weight_hh"]], axis=1)),
        ("lstm_b", w["decoder.rnn.bias_ih"] + w["decoder.rnn.bias_hh"]),
        ("head_w", w["decoder.decoder.2.weight"][0, :, 0]),
        ("head_b", w["decoder.decoder.2.bias"]),
    ]


def write_weights(items: list[tuple[str, np.ndarray]]) -> None:
    out = bytearray(b"TTSV") + struct.pack("<II", 1, len(items))
    for _, t in items:
        t = np.ascontiguousarray(t, dtype="<f4")
        out += struct.pack("<I", t.ndim) + struct.pack(f"<{t.ndim}I", *t.shape) + t.tobytes()
    WEIGHTS_OUT.write_bytes(out)


def conv1d(x, w, b, stride, pad):
    if pad:
        x = np.pad(x, ((0, 0), (pad, pad)))
    k = w.shape[2]
    steps = (x.shape[1] - k) // stride + 1
    y = np.stack(
        [np.tensordot(w, x[:, t * stride : t * stride + k], axes=([1, 2], [0, 1])) for t in range(steps)],
        axis=1,
    )
    return y if b is None else y + b[:, None]


def sigmoid(v):
    return 1 / (1 + np.exp(-v))


def forward(t: dict[str, np.ndarray], x, h, c):
    x = np.pad(x, (0, 64), mode="reflect")
    s = conv1d(x[None, :], t["stft_basis"][:, None, :], None, 128, 0)
    e = np.sqrt(s[:129] ** 2 + s[129:] ** 2)
    for i, stride in enumerate([1, 2, 2, 1]):
        e = np.maximum(conv1d(e, t[f"enc{i}_w"], t[f"enc{i}_b"], stride, 1), 0)
    assert e.shape[1] == 1
    g = t["lstm_w"] @ np.concatenate([e[:, 0], h]) + t["lstm_b"]
    gi, gf, gg, go = np.split(g, 4)
    c = sigmoid(gf) * c + sigmoid(gi) * np.tanh(gg)
    h = sigmoid(go) * np.tanh(c)
    p = sigmoid(t["head_w"] @ np.maximum(h, 0) + t["head_b"][0])
    return p, h, c


def vowel(seconds, f0, formants, rng):
    n = int(seconds * SAMPLE_RATE)
    time = np.arange(n) / SAMPLE_RATE
    freq = f0 * (1 + 0.03 * np.sin(2 * np.pi * 5 * time)) * (1 + 0.1 * np.sin(2 * np.pi * 0.7 * time))
    phase = np.cumsum(freq) / SAMPLE_RATE
    pulses = np.zeros(n)
    pulses[np.nonzero(np.diff(np.floor(phase)) > 0)[0]] = 1
    out = np.zeros(n)
    for fc, bandwidth, gain in formants:
        r = np.exp(-np.pi * bandwidth / SAMPLE_RATE)
        a1, a2 = -2 * r * np.cos(2 * np.pi * fc / SAMPLE_RATE), r * r
        y1 = y2 = 0.0
        y = np.zeros(n)
        for i in range(n):
            y[i] = pulses[i] - a1 * y1 - a2 * y2
            y2, y1 = y1, y[i]
        out += gain * y
    out *= 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 2.2 * time))
    out += rng.standard_normal(n) * 0.02 * out.std()
    return out / np.abs(out).max()


def test_audio() -> np.ndarray:
    rng = np.random.default_rng(2026)
    sr = SAMPLE_RATE
    a = [(730, 90, 1), (1090, 110, 0.5), (2440, 120, 0.3)]
    i = [(270, 60, 1), (2290, 100, 0.4), (3010, 120, 0.3)]
    o = [(570, 80, 1), (840, 90, 0.6), (2410, 120, 0.2)]
    t1 = np.arange(sr) / sr
    parts = [
        np.zeros(sr // 2),
        rng.standard_normal(sr // 2) * 0.003,
        0.5 * vowel(0.6, 120, a, rng),
        0.5 * vowel(0.5, 180, i, rng),
        0.5 * vowel(0.7, 140, o, rng),
        np.zeros(sr // 4),
        np.sin(2 * np.pi * 300 * t1) * 0.18 + rng.uniform(-1, 1, sr) * 0.09,
        np.clip(1.8 * vowel(0.6, 200, a, rng), -1, 1),
        rng.standard_normal(sr // 2) * 0.3,
        0.05 + 0.2 * vowel(0.5, 110, o, rng),
        np.full(sr // 4, 0.05),
        np.zeros(sr // 2),
    ]
    x = np.clip(np.concatenate(parts), -1, 32767 / 32768)
    return np.round(x * 32768).astype(np.int16)


def main() -> None:
    model_bytes = load_model()
    w = weights_16k(onnx.load_from_string(model_bytes))
    items = tensors(w)
    t = {name: a.astype(np.float64) for name, a in items}

    pcm = test_audio()
    audio = pcm.astype(np.float32) / 32768
    session = ort.InferenceSession(model_bytes)
    state = np.zeros((2, 1, 128), np.float32)
    h, c = np.zeros(128), np.zeros(128)
    context = np.zeros(CONTEXT, np.float32)
    probs, worst = [], 0.0
    for k in range(len(audio) // CHUNK):
        chunk = audio[k * CHUNK : (k + 1) * CHUNK]
        x = np.concatenate([context, chunk])
        context = chunk[-CONTEXT:]
        out, state = session.run(
            None, {"input": x[None, :], "state": state, "sr": np.array(SAMPLE_RATE, np.int64)}
        )
        p, h, c = forward(t, x.astype(np.float64), h, c)
        worst = max(worst, abs(p - float(out[0, 0])))
        probs.append(float(out[0, 0]))
    print(f"{len(probs)} chunks; reference vs ONNX Runtime, largest difference {worst:.2e}")
    if worst > 1e-5:
        sys.exit("The reference in forward() no longer matches the model")

    write_weights(items)
    FIXTURES.mkdir(parents=True, exist_ok=True)
    with wave.open(str(FIXTURES / "input.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(pcm.astype("<i2").tobytes())
    expected = {
        "model": MODEL_URL,
        "model_sha256": MODEL_SHA256,
        "onnxruntime": ort.__version__,
        "sample_rate": SAMPLE_RATE,
        "chunk": CHUNK,
        "context": CONTEXT,
        "probs": [round(p, 8) for p in probs],
        "final_h": [round(float(v), 8) for v in state[0, 0]],
        "final_c": [round(float(v), 8) for v in state[1, 0]],
    }
    (FIXTURES / "expected.json").write_text(json.dumps(expected, indent=1) + "\n")
    print(f"Wrote {WEIGHTS_OUT.relative_to(ROOT)} ({WEIGHTS_OUT.stat().st_size} bytes) and {FIXTURES.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
