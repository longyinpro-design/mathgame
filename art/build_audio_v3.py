"""Original synthesized sample soundtrack and SFX; no external recordings."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / 'assets/audio/v3'
OUT.mkdir(parents=True, exist_ok=True)
random.seed(31415)


def write(name, duration, synth):
    samples = []
    for i in range(round(duration * RATE)):
        t = i / RATE
        samples.append(max(-0.92, min(0.92, synth(t, duration))))
    with wave.open(str(OUT / f'{name}.wav'), 'wb') as f:
        f.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        f.writeframes(struct.pack('<' + 'h' * len(samples), *(round(s * 32767) for s in samples)))


def sine(freq, t):
    return math.sin(math.tau * freq * t)


def bell(freq, t, decay=3):
    return (sine(freq, t) + .35 * sine(freq * 2.005, t) + .12 * sine(freq * 3, t)) * math.exp(-decay * t)


# Eight bars: restrained pentatonic music with soft plucked bells and a warm pad.
notes = [220, 261.6256, 329.6276, 391.9954, 329.6276, 261.6256, 293.6648, 220]
def music(t, duration):
    beat = t % 2
    note = notes[int(t / 2) % 8]
    pad = .035 * (sine(110, t) + .5 * sine(164.8138, t))
    pad *= min(1, t / .5, (duration-t) / .5)
    return pad + .12 * bell(note, beat, 2.8) * min(1, beat*40)
write('forest_theme', 16, music)
# Soft filtered noise/wind, deliberately quiet and with seamless endpoint taper.
noise = 0
def ambience(t, d):
    global noise
    noise = .97 * noise + .03 * random.uniform(-1, 1)
    return noise * .25 * min(1, t, d-t) + .01 * sine(78, t) * math.sin(math.pi*t/d)**2
write('forest_air', 12, ambience)
write('pickup', .22, lambda t,d: .28*bell(880,t,14))
write('place', .35, lambda t,d: .27*bell(660,t,10)+.11*bell(1320,t,14))
write('footstep', .13, lambda t,d: .17*random.uniform(-1,1)*math.exp(-t*44)+.13*sine(95,t)*math.exp(-t*35))
write('awaken', 1.3, lambda t,d: (.2*sine(65,t)+.08*random.uniform(-1,1))*math.sin(math.pi*t/d)**2)
write('charge', 1.1, lambda t,d: .19*math.sin(math.tau*(160*t+260*t*t))*math.sin(math.pi*t/d)**1.5)
write('cast', .55, lambda t,d: (.25*math.sin(math.tau*(850*t-520*t*t))+.14*random.uniform(-1,1))*math.exp(-t*7)*min(1,t*80))
write('impact', .4, lambda t,d: .25*bell(330,t,12)+.16*random.uniform(-1,1)*math.exp(-t*24))
write('unbalanced', .8, lambda t,d: .19*(sine(164.81,t)+.5*sine(174.61,t))*math.exp(-t*5)*min(1,t*60))
write('fox', .35, lambda t,d: .12*math.sin(math.tau*(620*t-280*t*t))*math.sin(math.pi*t/d)**2)
write('unlock', 2.2, lambda t,d: sum(.14*bell(f,t-i*.16,3) for i,f in enumerate([261.63,329.63,392,523.25]) if t>=i*.16))
write('reward', 1.7, lambda t,d: sum(.13*bell(f,t-i*.12,3.5) for i,f in enumerate([523.25,659.25,783.99,1046.5]) if t>=i*.12))
print('Generated 13 original PCM WAV assets')
