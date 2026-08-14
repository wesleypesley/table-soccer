#!/usr/bin/env python3
"""Generate the crowd audio beds procedurally.

The project ships no external assets — the pitch, caps and ball are all drawn
in code — so the audio is synthesised the same way rather than downloaded.
Python stdlib only (`wave`, `math`, `random`); no numpy, no samples.

    python3 tools/gen_audio.py

Writes:
    audio/crowd_ambient.wav   seamless murmur bed, loops under play
    audio/crowd_cheer.wav     goal celebration: swell, peak, decay

Re-running is deterministic (fixed seed), so regenerating never produces a
gratuitous diff.
"""

import math
import os
import random
import struct
import wave

RATE = 22050
SEED = 20260812


def _write(path, samples):
    """16-bit mono PCM."""
    peak = max(1e-9, max(abs(s) for s in samples))
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s / peak * 0.85)) * 32767))
        for s in samples
    )
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print("%-28s %5.1fs  %6.1f kB" % (path, len(samples) / RATE, len(frames) / 1024))


def _lowpass(src, alpha):
    out, prev = [], 0.0
    for s in src:
        prev += alpha * (s - prev)
        out.append(prev)
    return out


def crowd_ambient(seconds=6.0):
    """A murmur bed: heavily low-passed noise, slowly swelling.

    Loops seamlessly — the tail is cross-faded back over the head, so a
    looping player has no click at the seam.
    """
    rng = random.Random(SEED)
    n = int(RATE * seconds)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    body = _lowpass(_lowpass(noise, 0.020), 0.020)          # distant murmur
    detail = _lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], 0.12)

    out = []
    for i in range(n):
        t = i / RATE
        # two slow swells so the bed breathes instead of sitting flat
        swell = 0.72 + 0.18 * math.sin(2 * math.pi * 0.07 * t) \
                     + 0.10 * math.sin(2 * math.pi * 0.031 * t + 1.3)
        out.append((body[i] * 1.0 + detail[i] * 0.12) * swell)

    xf = int(RATE * 0.5)                                     # crossfade the seam
    for i in range(xf):
        a = i / xf
        out[i] = out[i] * a + out[n - xf + i] * (1.0 - a)
    return out[: n - xf]


def crowd_cheer(seconds=3.2):
    """Goal celebration: fast swell to a roar, then a long decay."""
    rng = random.Random(SEED + 1)
    n = int(RATE * seconds)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    body = _lowpass(noise, 0.055)                            # roar
    bright = _lowpass([rng.uniform(-1.0, 1.0) for _ in range(n)], 0.35)  # whistles

    out = []
    for i in range(n):
        t = i / RATE
        attack = min(1.0, t / 0.18)                          # sharp onset
        decay = math.exp(-max(0.0, t - 0.5) * 1.05)
        env = attack * decay
        # a couple of whistle tones riding the top of the roar
        whistle = 0.05 * env * (
            math.sin(2 * math.pi * 2100 * t) * max(0.0, math.sin(2 * math.pi * 1.7 * t))
            + math.sin(2 * math.pi * 2670 * t) * max(0.0, math.sin(2 * math.pi * 1.1 * t + 2.0))
        )
        out.append((body[i] * 1.0 + bright[i] * 0.28) * env + whistle)
    return out


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(here, "audio")
    os.makedirs(out_dir, exist_ok=True)
    _write(os.path.join(out_dir, "crowd_ambient.wav"), crowd_ambient())
    _write(os.path.join(out_dir, "crowd_cheer.wav"), crowd_cheer())


if __name__ == "__main__":
    main()
