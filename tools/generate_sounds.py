"""Synthesizes the bundled reminder tunes (royalty-free, generated from scratch).

Usage: python3 tools/generate_sounds.py <output_dir>
Writes 22.05 kHz mono WAVs, then converts to OGG if ffmpeg is available.
"""
import os, subprocess, sys, wave
import numpy as np

SR = 22050

def env(n, attack=0.01, decay=0.6):
    t = np.arange(n) / SR
    a = np.minimum(1.0, t / max(attack, 1e-4))
    return a * np.exp(-t / decay)

def tone(freq, dur, harmonics=((1, 1.0),), attack=0.01, decay=0.6):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = sum(amp * np.sin(2 * np.pi * freq * h * t) for h, amp in harmonics)
    return s * env(n, attack, decay)

def place(track, sig, at):
    i = int(at * SR)
    end = min(len(track), i + len(sig))
    track[i:end] += sig[: end - i]

def note(name):
    names = {'C': -9, 'D': -7, 'E': -5, 'F': -4, 'G': -2, 'A': 0, 'B': 2}
    base, octv = name[:-1], int(name[-1])
    semis = names[base[0]] + (1 if '#' in base else 0) + (octv - 4) * 12
    return 440.0 * 2 ** (semis / 12)

BELL = ((1, 1.0), (2.76, 0.4), (5.4, 0.15), (8.9, 0.05))
MARIMBA = ((1, 1.0), (4.0, 0.25), (10.0, 0.05))
PIANOISH = ((1, 1.0), (2, 0.5), (3, 0.25), (4, 0.12))

def melody(seq, length, harm, decay, gap_tail=0.0):
    tr = np.zeros(int(length * SR))
    for at, n, dur in seq:
        place(tr, tone(note(n), dur, harm, decay=decay), at)
    return tr

def gentle_chime():
    seq = [(0.0, 'E5', 1.6), (0.4, 'G5', 1.6), (0.8, 'C6', 2.0), (1.6, 'G5', 1.6), (2.0, 'E5', 2.0)]
    return melody(seq, 4.0, BELL, 0.8)

def morning_marimba():
    seq, t = [], 0.0
    for n in ['C5', 'E5', 'G5', 'C6', 'G5', 'E5', 'D5', 'G5', 'B5', 'D6', 'B5', 'G5']:
        seq.append((t, n, 0.6)); t += 0.18
    return melody(seq, 3.0, MARIMBA, 0.25)

def classic_beep():
    tr = np.zeros(int(2.0 * SR))
    for i in range(4):
        b = tone(1000, 0.12, ((1, 1.0), (3, 0.2)), attack=0.003, decay=10)
        place(tr, b, i * 0.25)
    return tr

def digital_alarm():
    tr = np.zeros(int(1.6 * SR))
    for k in range(2):
        for i in range(4):
            b = tone(2000 if i % 2 == 0 else 2400, 0.07, ((1, 1.0),), attack=0.002, decay=10)
            place(tr, b, k * 0.8 + i * 0.1)
    return tr

def soft_bells():
    seq = [(0.0, 'A4', 2.5), (0.0, 'E5', 2.5), (1.2, 'C#5', 2.5), (1.2, 'A5', 2.5), (2.4, 'E5', 2.5), (2.4, 'B5', 2.5)]
    return melody(seq, 5.0, BELL, 1.1)

def water_drop():
    tr = np.zeros(int(2.2 * SR))
    for at, f0 in [(0.0, 900), (0.35, 1200), (1.1, 1000)]:
        n = int(0.25 * SR)
        t = np.arange(n) / SR
        f = f0 * (1 + 1.8 * t / 0.25)  # upward chirp like a droplet
        ph = 2 * np.pi * np.cumsum(f) / SR
        place(tr, np.sin(ph) * env(n, 0.002, 0.06), at)
    return tr

def ding_dong():
    seq = [(0.0, 'E5', 1.5), (0.7, 'C5', 2.0)]
    return melody(seq, 3.0, PIANOISH, 0.7)

def rising_alert():
    seq, t = [], 0.0
    for n in ['C5', 'D5', 'E5', 'F5', 'G5', 'A5', 'B5', 'C6']:
        seq.append((t, n, 0.35)); t += 0.12
    return melody(seq, 1.8, ((1, 1.0), (2, 0.3), (3, 0.2)), 0.2)

def heartbeat_pulse():
    tr = np.zeros(int(1.4 * SR))
    for at in (0.0, 0.25):
        place(tr, tone(80, 0.25, ((1, 1.0), (2, 0.4)), attack=0.005, decay=0.08), at)
        place(tr, tone(660, 0.2, ((1, 0.3),), attack=0.005, decay=0.08), at)
    return tr

def lullaby():
    seq, t = [], 0.0
    for n, d in [('G4', .5), ('G4', .5), ('B4', 1.0), ('G4', .5), ('G4', .5), ('B4', 1.0), ('G4', .5), ('B4', .5), ('E5', .75), ('D5', .75), ('C5', 1.0)]:
        seq.append((t, n, 1.4)); t += d * 0.6
    return melody(seq, t + 1.2, PIANOISH, 0.6)

SOUNDS = {
    'gentle_chime': gentle_chime, 'morning_marimba': morning_marimba, 'classic_beep': classic_beep,
    'digital_alarm': digital_alarm, 'soft_bells': soft_bells, 'water_drop': water_drop,
    'ding_dong': ding_dong, 'rising_alert': rising_alert, 'heartbeat_pulse': heartbeat_pulse,
    'lullaby': lullaby,
}

def write(path, sig):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * 0.85
    fade = int(0.02 * SR)
    sig[-fade:] *= np.linspace(1, 0, fade)
    data = (sig * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())

if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, fn in SOUNDS.items():
        wav = os.path.join(out, f'tune_{name}.wav')
        write(wav, fn())
        ogg = wav[:-4] + '.ogg'
        if subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '5', ogg]).returncode == 0:
            os.remove(wav)
    print('generated', len(SOUNDS))
