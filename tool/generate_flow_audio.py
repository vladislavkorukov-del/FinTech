#!/usr/bin/env python3
"""Original quiet Finora game sounds, generated locally; no third-party samples."""
import math
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / 'assets/finora/match3/audio'
OUT.mkdir(parents=True, exist_ok=True)


def export(name, samples):
    peak = max(1.0, max(abs(x) for x in samples))
    data = b''.join(struct.pack('<h', round(x / peak * 22000)) for x in samples)
    with wave.open(str(OUT / name), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(data)


def bell(t, frequency, decay):
    return math.exp(-t * decay) * (math.sin(math.tau * frequency * t) + .22 * math.sin(math.tau * frequency * 2 * t))


export('tap.wav', [.30 * bell(i / RATE, 880, 24) for i in range(int(RATE * .16))])
export('chime.wav', [sum(.20 * bell(i / RATE - offset, f, 5) for offset, f in [(0, 660), (.08, 880), (.16, 1100)] if i / RATE >= offset) for i in range(RATE)])
# Eight calm bars, Cmaj7 – Am7 – Fmaj7 – G6. Smooth loop boundary.
duration = 24
chords = [(130.8128, 164.8138, 195.9977, 246.9417), (110, 130.8128, 164.8138, 195.9977), (87.3071, 130.8128, 164.8138, 220), (97.9989, 146.8324, 195.9977, 246.9417)]
samples = []
for i in range(RATE * duration):
    t = i / RATE
    bar = int(t / 6)
    local = t % 6
    envelope = math.sin(math.pi * local / 6) ** 2
    pad = sum(math.sin(math.tau * f * t) + .10 * math.sin(math.tau * f * 2 * t) for f in chords[bar]) * .027 * envelope
    beat = int(local / .75)
    note_t = local % .75
    shimmer = .028 * bell(note_t, chords[bar][beat % 4] * 4, 6) * envelope
    samples.append(pad + shimmer)
export('terrace.wav', samples)
print('Generated original loop and two short effects:', OUT)
