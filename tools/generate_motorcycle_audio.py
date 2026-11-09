"""Original motorcycle sound design; deterministic, no recordings or model assets.

Requires numpy. Run from any directory. Four overlapping RPM bands use an uneven
four-stroke twin firing pattern, exhaust resonances and combustion noise. All
loop components are periodic over six seconds, including the filtered noise.
"""
from pathlib import Path
import hashlib
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/audio/commute'
RATE = 44100
rng = np.random.default_rng(20261101)
records = []


def noise(n, low, high):
    f = np.fft.rfftfreq(n, 1 / RATE)
    spectrum = np.fft.rfft(rng.normal(size=n))
    shape = (1 - np.exp(-(f / low)**2)) * np.exp(-(f / high)**2)
    x = np.fft.irfft(spectrum * shape, n)
    return x / max(np.std(x), 1e-8)


def save(name, x, loop=False, rpm=None):
    x = x - np.mean(x)
    # Fixed headroom; no sample reaches digital full scale.
    x *= min(.72 / max(np.max(np.abs(x)), 1e-8), .19 / max(np.std(x), 1e-8))
    if not loop:
        fade = min(int(.012 * RATE), len(x)//3)
        x[:fade] *= np.linspace(0, 1, fade)
        x[-fade:] *= np.linspace(1, 0, fade)
    pcm = np.round(x * 32767).astype('<i2')
    path = OUT / (name + '.wav')
    with wave.open(str(path), 'wb') as wav:
        wav.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        wav.writeframes(pcm.tobytes())
    records.append(dict(file=path.name, seconds=len(x)/RATE, loop=loop, rpm=rpm,
                        peak=float(np.max(np.abs(x))), rms=float(np.std(x)),
                        seam_delta=float(abs(x[0]-x[-1])),
                        sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    return x


def engine(rpm, seconds=6):
    n = int(seconds * RATE)
    t = np.arange(n)/RATE
    cycle = (t * rpm / 120 + .006*np.sin(2*np.pi*3*t)) % 1
    # Two unevenly spaced exhaust pulses per four-stroke cycle.
    pulse = sum(np.exp(-((cycle-offset) % 1) * 75) for offset in (0, .32))
    pulse -= pulse.mean()
    f = np.fft.rfftfreq(n, 1/RATE)
    response = .6*np.exp(-(f/1800)**2)
    for center, width, gain in ((95, 65, 1.9), (220, 130, .8), (610, 250, .24)):
        response += gain*np.exp(-((f-center)/width)**2)
    exhaust = np.fft.irfft(np.fft.rfft(pulse)*response, n)
    exhaust /= max(np.std(exhaust), 1e-8)
    air = noise(n, 85, 1700) * (.15 + .40*pulse.clip(0))
    mechanical = noise(n, 700, 3200)*.065
    return np.tanh((exhaust*.60 + air + mechanical)*1.3)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    engines = {}
    for rpm in (1400, 3000, 5000, 7500):
        engines[rpm] = save('engine-'+str(rpm), engine(rpm), True, rpm)
    n = RATE*6
    t = np.arange(n)/RATE
    save('wind', noise(n, 45, 850)*(.8+.15*np.sin(2*np.pi*t/3)), True)
    save('tires', noise(n, 180, 2300)*(.8+.12*np.sin(2*np.pi*17*t)), True)
    save('intake', noise(n, 250, 1700), True)
    save('brake', noise(n, 950, 4700)*.6+noise(n, 110, 500)*.2, True)
    for name, duration in (('ignition', .85), ('shutdown', .48), ('shift', .13), ('impact', .30)):
        count = int(RATE*duration)
        tt = np.arange(count)/RATE
        if name == 'ignition':
            x = noise(count, 100, 1200)*np.exp(-tt*2)*(.1+.8*np.maximum(0, np.sin(tt*2*np.pi*17))**6)
            x += engine(1400, duration)*np.minimum(tt/.6, 1)*.45
        elif name == 'shutdown':
            x = engine(900, duration)*np.exp(-tt*8)
        else:
            x = noise(count, 65 if name == 'impact' else 240, 1800)*np.exp(-tt*(23 if name == 'impact' else 65))
            x += np.sin(tt*2*np.pi*82)*np.exp(-tt*35)*.4
        save(name, x)
    (OUT/'manifest.json').write_text(json.dumps(dict(
        author='The Picture Shop original procedural sound design',
        generator='tools/generate_motorcycle_audio.py', sample_rate=RATE,
        seed=20261101, files=records), indent=2)+'\n', encoding='utf-8')
    print(f'Generated {len(records)} original cues in {OUT}')
    for r in records:
        assert r['peak'] < .73 and r['rms'] > .01
    audition(engines)


def audition(engines):
    """Short, reproducible engine audition: start, idle, pull, shift, coast, stop.

    This offline reel uses the same bands but omits the separately licensed
    nature loop. The playable preview is authoritative for the interactive mix.
    """
    t = np.arange(RATE*18)/RATE
    rpm = np.interp(t, [0, 3, 6, 6.15, 9, 9.15, 11, 15, 18],
                    [1400, 1400, 6900, 4700, 7200, 5100, 6800, 1400, 1400])
    load = np.interp(t, [0, 2.9, 3.15, 10.8, 11.1, 18], [0, 0, 1, 1, 0, 0])
    speed = np.interp(t, [0, 3, 11, 15, 18], [0, 0, .9, 0, 0])
    fade = np.minimum(t/.8, 1)*np.clip((17-t)/.6, 0, 1)
    result = np.zeros_like(t)
    bands = sorted(engines)
    for i, base in enumerate(bands):
        below = np.ones_like(t) if i == 0 else np.clip((rpm-bands[i-1])/(base-bands[i-1]), 0, 1)
        above = np.ones_like(t) if i == len(bands)-1 else np.clip((bands[i+1]-rpm)/(bands[i+1]-base), 0, 1)
        weight = np.where(rpm <= base, below, above)
        source = engines[base]
        position = np.cumsum(rpm/base) % len(source)
        sample = np.interp(position, np.arange(len(source)+1), np.r_[source, source[0]])
        result += sample*np.sqrt(weight)*fade*(.28+.26*load)*.85
    def read(name):
        with wave.open(str(OUT/(name+'.wav')), 'rb') as wav:
            return np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').astype(float)/32768
    for name, volume in (('wind', speed**1.7*.27*.42), ('tires', speed*.14*.85), ('intake', fade*load*.12*.85)):
        source = read(name)
        result += source[np.arange(len(t)) % len(source)]*volume
    for name, at, gain in (('ignition', 0, .34), ('shift', 6, .187), ('shift', 9, .187), ('shutdown', 16.5, .34)):
        source = read(name)*gain
        offset = int(at*RATE);result[offset:offset+len(source)] += source
    path = ROOT/'output/motorcycle-audio/motorcycle-audition.wav'
    path.parent.mkdir(parents=True, exist_ok=True)
    assert abs(result).max() < .95
    with wave.open(str(path), 'wb') as wav:
        wav.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        wav.writeframes(np.round(result*32767).astype('<i2').tobytes())
    print(f'Audition: {path}')


if __name__ == '__main__':
    main()
