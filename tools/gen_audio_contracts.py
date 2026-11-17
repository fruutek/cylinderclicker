#!/usr/bin/env python3
"""Synthesises the sound effects added by Expansion 3 (contracts and dispatch).
Reuses the oscillator helpers from gen_audio.py and only writes NEW files,
so the existing sounds and music are untouched.
Run:  python3 tools/gen_audio_contracts.py   (needs numpy)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import gen_audio as g  # noqa: E402


def main():
    os.makedirs(g.OUT_DIR, exist_ok=True)
    rng = np.random.default_rng(11)

    # reversing beeper: three short square-wave beeps
    beep = g.mix(0.62, [(i * 0.2, g.note(1020, 0.1, "square", 3.0, 0.002), 1.0) for i in range(3)])
    g.save("beep.wav", beep, 0.35)

    # payment: bright register bell, a coin ring and a final chime
    ding = g.mix(0.9, [
        (0.00, g.note(g.hz(19), 0.5, "bell", 7), 0.9),
        (0.08, g.note(g.hz(24), 0.7, "bell", 5), 0.8),
        (0.17, g.note(g.hz(28), 0.7, "bell", 4), 0.8),
        (0.00, rng.uniform(-1, 1, int(g.SR * 0.04)) * g.env(0.04, 0.001, 70), 0.2),
    ])
    g.save("ding.wav", ding, 0.75)

    # lorry engine: low rumble with a throaty rise and fall
    dur = 1.5
    x = g.t(dur)
    sweep = 62 + 26 * np.sin(np.pi * x / dur)
    phase = 2 * np.pi * np.cumsum(sweep) / g.SR
    rumble = (np.sign(np.sin(phase)) * 0.45 + np.sin(phase * 2) * 0.3) * np.sin(np.pi * x / dur) ** 0.7
    rumble += rng.uniform(-1, 1, len(x)) * 0.12 * np.sin(np.pi * x / dur)
    g.save("engine.wav", rumble, 0.5)

    # contract accepted: a rubber-stamp thump with a paper rustle
    stamp = g.mix(0.25, [
        (0.00, g.note(95, 0.16, "sine", 30, 0.001), 1.0),
        (0.00, rng.uniform(-1, 1, int(g.SR * 0.05)) * g.env(0.05, 0.001, 60), 0.35),
        (0.07, g.note(1500, 0.05, "sine", 70, 0.001), 0.25),
    ])
    g.save("stamp.wav", stamp, 0.6)
    print("contract audio generated in", os.path.normpath(g.OUT_DIR))


if __name__ == "__main__":
    main()
