"""Generates the telephone ring used by the sales office (Expansion 4): assets/audio/ring.wav.
Run:  python3 tools/gen_audio_stock.py
"""
import math
import struct
import wave

RATE = 22050


def tone(freq_a, freq_b, seconds, warble=20.0, vol=0.35):
    out = []
    n = int(RATE * seconds)
    for i in range(n):
        t = i / RATE
        f = freq_a if int(t * warble * 2) % 2 == 0 else freq_b
        env = min(1.0, t / 0.01) * min(1.0, (seconds - t) / 0.03)
        out.append(vol * env * math.sin(2 * math.pi * f * t) * (0.7 + 0.3 * math.sin(2 * math.pi * 6 * t)))
    return out


def silence(seconds):
    return [0.0] * int(RATE * seconds)


samples = tone(1000, 1250, 0.42) + silence(0.12) + tone(1000, 1250, 0.42)
with wave.open("assets/audio/ring.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
print("wrote assets/audio/ring.wav")
