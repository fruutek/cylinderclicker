#!/usr/bin/env python3
"""Synthesises all Cylinder Clicker sound effects and the music loop.

Everything is generated from simple oscillators, so the audio is original
and licence-free. Run:  python3 tools/gen_audio.py
"""
import os
import wave
import numpy as np

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
SR = 22050


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(dur, attack=0.004, decay=6.0):
    x = t(dur)
    return np.minimum(1.0, x / attack) * np.exp(-decay * x)


def note(freq, dur, wave_shape="sine", decay=6.0, attack=0.004):
    x = t(dur)
    if wave_shape == "sine":
        w = np.sin(2 * np.pi * freq * x)
    elif wave_shape == "tri":
        w = 2 * np.abs(2 * ((x * freq) % 1.0) - 1) - 1
    elif wave_shape == "square":
        w = np.sign(np.sin(2 * np.pi * freq * x)) * 0.5
    elif wave_shape == "bell":
        w = np.sin(2 * np.pi * freq * x) + 0.4 * np.sin(2 * np.pi * freq * 2.01 * x) + 0.2 * np.sin(2 * np.pi * freq * 3.02 * x)
        w /= 1.6
    return w * env(dur, attack, decay)


def mix(length, parts):
    out = np.zeros(int(SR * length))
    for start, sig, gain in parts:
        i = int(SR * start)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += sig[:n] * gain
    return out


def save(name, sig, peak=0.8):
    sig = sig / max(1e-9, np.max(np.abs(sig))) * peak
    fade = min(len(sig) // 2, int(SR * 0.004))
    sig[-fade:] *= np.linspace(1, 0, fade)
    data = (sig * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT_DIR, name), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())


def hz(semitones_from_a4):
    return 440.0 * 2 ** (semitones_from_a4 / 12.0)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rng = np.random.default_rng(3)

    # click: short metallic tap
    noise = rng.uniform(-1, 1, int(SR * 0.05)) * env(0.05, 0.001, 90)
    click = mix(0.07, [(0, noise, 0.5), (0, note(1400, 0.06, "sine", 55, 0.001), 0.6), (0, note(2100, 0.04, "sine", 80, 0.001), 0.3)])
    save("click.wav", click, 0.6)

    # sale: bright two-note "cha-ching"
    sale = mix(0.45, [(0.0, note(hz(14), 0.2, "bell", 14), 0.8), (0.07, note(hz(19), 0.36, "bell", 9), 1.0)])
    save("sale.wav", sale, 0.7)

    # purchase: rising arpeggio
    buy = mix(0.5, [(i * 0.06, note(hz(s), 0.3, "tri", 10), 0.9) for i, s in enumerate((3, 7, 10, 15))])
    save("buy.wav", buy, 0.7)

    # denied: low double buzz
    deny = mix(0.25, [(0.0, note(150, 0.09, "square", 12), 1.0), (0.11, note(120, 0.12, "square", 12), 1.0)])
    save("deny.wav", deny, 0.45)

    # automation fanfare
    fan = mix(1.0, [(i * 0.11, note(hz(s), 0.5, "bell", 6), 0.9) for i, s in enumerate((3, 7, 10, 15, 19))])
    save("fanfare.wav", fan, 0.75)

    # station finished: soft low thunk
    thunk = mix(0.12, [(0, note(110, 0.11, "sine", 35, 0.002), 1.0), (0, rng.uniform(-1, 1, int(SR * 0.03)) * env(0.03, 0.001, 120), 0.25)])
    save("thunk.wav", thunk, 0.5)

    # ui blip
    save("blip.wav", note(880, 0.06, "tri", 40), 0.4)

    # music: a gentle 4-chord loop (C - Am - F - G), plucked arpeggios over a soft pad
    bpm = 84.0
    beat = 60.0 / bpm
    chords = [(-9, -5, -2), (-12, -9, -5), (-16, -12, -9), (-14, -10, -7)]   # C, Am, F, G (semitones from A4)
    melody = [
        [3, None, 7, 10, None, 7, 3, None], [0, None, 3, 7, None, 3, 0, None],
        [-4, None, 0, 3, None, 8, 3, None], [-2, None, 2, 5, None, 10, 5, 2],
        [3, 7, 10, None, 15, None, 10, 7], [0, 3, 7, None, 12, None, 7, 3],
        [-4, 0, 3, None, 8, None, 5, 3], [-2, 2, 5, 2, 10, None, 5, None],
    ]
    bars = 8
    total = bars * 4 * beat
    parts = []
    for b in range(bars):
        ch = chords[b % 4]
        t0 = b * 4 * beat
        for s in ch:   # pad
            x = t(4 * beat)
            pad = np.sin(2 * np.pi * hz(s) * x) * np.minimum(1, x / 0.4) * np.minimum(1, (4 * beat - x) / 0.5)
            parts.append((t0, pad, 0.10))
        parts.append((t0, note(hz(ch[0] - 12), 1.6, "sine", 2.0, 0.01), 0.30))            # bass
        parts.append((t0 + 2 * beat, note(hz(ch[0] - 12), 1.2, "sine", 2.5, 0.01), 0.22))
        for i, s in enumerate(melody[b]):   # plucks on 8th notes
            if s is not None:
                parts.append((t0 + i * beat / 2, note(hz(s), 0.9, "tri", 4.5, 0.006), 0.26))
    music = mix(total, parts)
    save("music.wav", music, 0.6)
    print("audio generated in", os.path.normpath(OUT_DIR))


if __name__ == "__main__":
    main()
