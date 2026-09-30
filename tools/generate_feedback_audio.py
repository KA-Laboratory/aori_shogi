"""Original deterministic procedural effects; no recordings or third-party samples.

Run from any directory. --check verifies delivered assets without rewriting them.
"""
import argparse
import math
from pathlib import Path
import struct
import wave

ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
RATE = 48000
# duration in milliseconds, (onset seconds, fundamental Hz, relative level)
SOUNDS = {
    'piece_pick': (60, [(0, 740, 1)]),
    'piece_place': (100, [(0, 620, 1)]),
    'piece_promote': (180, [(0, 620, 1), (.045, 1046.5, .5)]),
    'notice': (160, [(0, 660, 1), (.075, 830, .8)]),
    'taunt_hit': (180, [(0, 240, 1)]),
    'taunt_miss': (100, [(0, 320, 1)]),
    'result_win': (650, [(0, 523.25, 1), (.19, 659.25, .9), (.38, 783.99, .85)]),
    'result_loss': (500, [(0, 659.25, 1), (.22, 440, .85)]),
}

def synthesize(duration, notes):
    count = RATE * duration // 1000
    samples = []
    for index in range(count):
        t = index / RATE
        total = 0.0
        for onset, hz, level in notes:
            local = t - onset
            if local < 0:
                continue
            envelope = min(1, local / .005) * math.exp(-local / .047)
            total += level * envelope * (
                math.sin(math.tau * hz * local)
                + .28 * math.sin(math.tau * hz * 2.67 * local)
                + .10 * math.sin(math.tau * hz * 4.13 * local))
        total *= min(1, t / .005, (count - 1 - index) / (RATE * .020))
        samples.append(total)
    # Remove DC with a window that remains exactly zero at both file edges.
    window = [min(1, i / (RATE * .005), (count - 1 - i) / (RATE * .020)) for i in range(count)]
    correction = sum(samples) / sum(window)
    samples = [value - correction * weight for value, weight in zip(samples, window)]
    scale = .68 / max(abs(value) for value in samples)
    return [round(value * scale * 32767) for value in samples]

def check():
    total = 0
    assert len(list(ROOT.glob('*.wav'))) == 8
    for name, (duration, _) in SOUNDS.items():
        path = ROOT / f'{name}.wav'
        with wave.open(str(path), 'rb') as wav:
            assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getcomptype()) == (1, 2, RATE, 'NONE')
            assert wav.getnframes() == duration * RATE // 1000
            samples = struct.unpack('<' + 'h' * wav.getnframes(), wav.readframes(wav.getnframes()))
        peak = max(abs(value) for value in samples) / 32768
        dc = abs(sum(samples) / len(samples) / 32768)
        assert peak <= 10 ** (-3 / 20)
        assert dc <= .001
        assert samples[0] == samples[-1] == 0
        first = next(i for i, value in enumerate(samples) if abs(value) > 1)
        last = next(i for i, value in enumerate(reversed(samples)) if abs(value) > 1)
        assert first <= RATE * .010 and last <= RATE * .010
        assert path.stat().st_size == 44 + len(samples) * 2
        total += path.stat().st_size
        print(f'{name}: {duration} ms, {path.stat().st_size} bytes, peak {20 * math.log10(peak):.2f} dBFS, DC {dc:.7f}')
    assert total == 185632 and total <= 204800
    print(f'PASS: 8 WAV files, {total} bytes total; physical listening acceptance remains required.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if not args.check:
        ROOT.mkdir(parents=True, exist_ok=True)
        for name, (duration, notes) in SOUNDS.items():
            samples = synthesize(duration, notes)
            with wave.open(str(ROOT / f'{name}.wav'), 'wb') as wav:
                wav.setparams((1, 2, RATE, len(samples), 'NONE', 'not compressed'))
                wav.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
    check()
