"""Синтез звуков кухни (заказчик 24.09): пузырь сытости, монеты, жевание,
готовка. Всё считается здесь из синусов и шума — без чужих записей, так что
лицензий не нужно.

    python3 tool/make_sfx.py            # пишет assets/audio/*.mp3

Нужны numpy, scipy и ffmpeg (`pip install imageio-ffmpeg` даёт свой).
Тайминги согласованы с анимациями:
  bubble_fly — FeedBurstLayer.flight (1.25 с), змейка 2.5 полуволны;
  fill       — FeedBurstLayer.count (0.9 с);
  chew       — KitchenScene._eatMotion (6.7 с): укусы в 0.6 и 3.5 с,
               жевки 1.8 Гц от s+0.8 до s+2.55.
"""
import os
import subprocess
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
rng = np.random.default_rng(24)


def t_(dur):
    return np.arange(int(dur * SR)) / SR


def env(t, a, d):
    """Быстрая атака a, экспоненциальный спад d."""
    return np.minimum(t / a, 1.0) * np.exp(-np.maximum(t - a, 0) / d)


def band(x, lo, hi, order=2):
    sos = butter(order, [lo, hi], btype='band', fs=SR, output='sos')
    return sosfilt(sos, x)


def high(x, f):
    return sosfilt(butter(2, f, btype='high', fs=SR, output='sos'), x)


def low(x, f):
    return sosfilt(butter(2, f, btype='low', fs=SR, output='sos'), x)


def sweep(t, f0, f1, k):
    """Частота от f0 к f1 экспонентой с постоянной k; фаза интегралом."""
    f = f1 + (f0 - f1) * np.exp(-t / k)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def put(buf, at, x, gain=1.0):
    # Края кусочка мягкие: обрезанный хвост иначе щёлкает.
    x = x.copy()
    e = min(int(0.004 * SR), len(x) // 2)
    x[:e] *= np.linspace(0, 1, e)
    x[-e:] *= np.linspace(1, 0, e)
    i = int(at * SR)
    n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += gain * x[:n]


def bell(f, dur=0.6, decay=0.18):
    """Мягкий колокольчик: основной тон и две тихие гармоники."""
    t = t_(dur)
    x = (np.sin(2 * np.pi * f * t)
         + 0.35 * np.sin(2 * np.pi * 2.01 * f * t) * np.exp(-t / (decay * 0.5))
         + 0.12 * np.sin(2 * np.pi * 3.02 * f * t) * np.exp(-t / (decay * 0.3)))
    return x * env(t, 0.004, decay)


def coin(f, dur=0.5):
    """Монетка: негармонические обертоны металла, быстрый спад."""
    t = t_(dur)
    x = np.zeros_like(t)
    for r, a, d in [(1, 1, 0.16), (2.76, 0.55, 0.09), (5.40, 0.3, 0.05),
                    (8.93, 0.15, 0.03)]:
        x += a * np.sin(2 * np.pi * f * r * t + rng.uniform(0, 6)) \
            * np.exp(-t / d)
    click = high(rng.standard_normal(len(t)), 4000) * env(t, 0.0005, 0.004)
    return (x + 0.4 * click) * np.minimum(t / 0.001, 1)


def bloop(f0, f1, dur=0.16, k=0.035):
    """«Блоп» капли: тон быстро взлетает вверх."""
    t = t_(dur)
    return sweep(t, f0, f1, k) * env(t, 0.006, dur / 3.2)


def crunch(dur, density, lo, hi):
    """Хруст: редкие щелчки в полосе частот."""
    n = int(dur * SR)
    x = np.zeros(n)
    k = rng.random(n) < density / SR
    x[k] = rng.uniform(-1, 1, k.sum())
    x = band(x, lo, hi)
    t = t_(dur)
    return x * env(t, 0.01, dur / 2.5)


def normalize(x, peak):
    x = x - np.mean(x)
    fade = int(0.01 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / (np.max(np.abs(x)) + 1e-9) * peak


# --- Пузырь -----------------------------------------------------------------

def bubble_born():
    b = np.zeros(int(0.35 * SR))
    put(b, 0.0, bloop(260, 820, 0.18, 0.05))
    put(b, 0.07, bloop(420, 1150, 0.14, 0.035), 0.45)
    return normalize(b, 0.8)


def bubble_fly():
    dur = 1.25
    t = t_(dur)
    u = t / dur
    # Воздух: шум, полоса которого ходит вслед за змейкой.
    noise = rng.standard_normal(len(t))
    centre = 1400 + 700 * np.sin(u * np.pi * 2.5)
    out = np.zeros_like(t)
    step = 512
    for i in range(0, len(t), step):
        c = centre[i]
        n = min(step, len(t) - i)
        out[i:i + n] = band(noise[max(0, i - 2048):i + n], c * 0.75,
                            c * 1.3)[-n:]
    air = out * np.sin(np.pi * u) ** 1.5 * 0.5
    # Тонкий переливчатый свист, покачивается в такт змейке и чуть
    # поднимается к концу пути.
    f = 900 + 260 * u + 90 * np.sin(u * np.pi * 2.5)
    whistle = np.sin(2 * np.pi * np.cumsum(f) / SR) \
        * (np.sin(np.pi * u) ** 2) * 0.22
    # Искорки по пути.
    b = air + whistle
    for at in [0.18, 0.42, 0.63, 0.85, 1.02]:
        put(b, at, bell(2400 + 700 * at, 0.25, 0.05), 0.12)
    return normalize(b, 0.45)


def bubble_pop():
    dur = 0.5
    b = np.zeros(int(dur * SR))
    t = t_(0.08)
    # «Пуньк»: хлопок плёнки — короткий щелчок и падающий тон.
    put(b, 0, high(rng.standard_normal(len(t)), 2500) * env(t, 0.0005, 0.006),
        0.6)
    t = t_(0.12)
    put(b, 0.002, sweep(t, 1500, 380, 0.02) * env(t, 0.002, 0.03))
    for i, f in enumerate([2093, 2637, 3136]):
        put(b, 0.03 + 0.035 * i, bell(f, 0.3, 0.07), 0.25)
    return normalize(b, 0.8)


def fill():
    """Проценты растут: перелив вверх по пентатонике."""
    notes = [523.3, 587.3, 659.3, 784.0, 880.0, 1046.5, 1174.7]
    b = np.zeros(int(1.4 * SR))
    for i, f in enumerate(notes):
        put(b, i * 0.12, bell(f, 0.7, 0.22), 0.7 + 0.05 * i)
    return normalize(b, 0.55)


def coins_spend():
    b = np.zeros(int(0.7 * SR))
    for i, (f, g) in enumerate([(2350, 1), (2050, 0.75), (1850, 0.55)]):
        put(b, i * 0.075, coin(f), g)
    return normalize(b, 0.5)


def coins_earn():
    b = np.zeros(int(0.9 * SR))
    for i, f in enumerate([1900, 2150, 2400, 2800]):
        put(b, i * 0.07, coin(f), 0.8 + 0.07 * i)
    put(b, 0.32, bell(3136, 0.5, 0.12), 0.3)
    return normalize(b, 0.6)


# --- Мишка ест --------------------------------------------------------------

def munch(dur=0.2):
    """Один жевок закрытым ртом: мягкий «чавк» и немного хруста."""
    t = t_(dur)
    squish = band(rng.standard_normal(len(t)), 250, 1300) \
        * np.sin(np.pi * np.minimum(t / dur, 1)) ** 2
    thump = np.sin(2 * np.pi * np.cumsum(140 - 40 * t / dur) / SR) \
        * env(t, 0.01, 0.04)
    x = 0.8 * squish + 0.5 * thump
    put(x, 0.02, crunch(dur * 0.7, 900, 1800, 5000), 0.6)
    return x


def bite():
    """Откусил: хрусткий «кусь»."""
    dur = 0.22
    t = t_(dur)
    return (1.2 * crunch(dur, 2600, 1500, 6500)
            + 0.5 * band(rng.standard_normal(len(t)), 400, 1800)
            * env(t, 0.004, 0.035))


def chew():
    b = np.zeros(int(6.7 * SR))
    for s in [0.6, 3.5]:
        put(b, s + 0.62, bite())
        c0 = s + 0.8
        # Жевки на пиках «munch» (1.8 Гц): u = 0.28, 0.83, 1.39 с.
        for k, u in enumerate([0.278, 0.834, 1.39]):
            put(b, c0 + u - 0.09, munch(0.2 + 0.02 * rng.random()),
                0.75 - 0.12 * k)
    return normalize(b, 0.6)


# --- Готовка ----------------------------------------------------------------

def cook_right():
    """Продукт растворился: «бульк» и искорки."""
    b = np.zeros(int(0.8 * SR))
    put(b, 0, bloop(180, 520, 0.2, 0.06))
    put(b, 0.09, bloop(300, 760, 0.15, 0.04), 0.5)
    for i, f in enumerate([1568, 2093, 2637, 3136]):
        put(b, 0.14 + 0.05 * i, bell(f, 0.4, 0.1), 0.3)
    return normalize(b, 0.7)


def cook_wrong():
    """«Ым-ым»: два мягких мычания закрытым ртом, второе ниже."""
    b = np.zeros(int(0.8 * SR))
    for at, f0, f1 in [(0.0, 260, 230), (0.3, 230, 185)]:
        dur = 0.24
        t = t_(dur)
        f = f0 + (f1 - f0) * t / dur
        ph = 2 * np.pi * np.cumsum(f) / SR
        # Гнусавое «м»: несколько гармоник, мягкий фильтр, плавные края.
        x = sum(a * np.sin(k * ph) for k, a in
                [(1, 1), (2, 0.5), (3, 0.25), (4, 0.12)])
        x = low(x, 900) * np.sin(np.pi * t / dur) ** 1.2
        put(b, at, x)
    return normalize(b, 0.55)


SOUNDS = {
    'bubble_born': bubble_born,
    'bubble_fly': bubble_fly,
    'bubble_pop': bubble_pop,
    'fill': fill,
    'coins_spend': coins_spend,
    'coins_earn': coins_earn,
    'chew': chew,
    'cook_right': cook_right,
    'cook_wrong': cook_wrong,
}


def ffmpeg():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        return 'ffmpeg'


def main():
    os.makedirs(OUT, exist_ok=True)
    wav_dir = sys.argv[1] if len(sys.argv) > 1 else None
    for name, make in SOUNDS.items():
        x = make()
        pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
        wav = os.path.join(wav_dir or OUT, f'{name}.wav')
        wavfile.write(wav, SR, pcm)
        mp3 = os.path.join(OUT, f'{name}.mp3')
        subprocess.run([ffmpeg(), '-y', '-loglevel', 'error', '-i', wav,
                        '-ac', '1', '-b:a', '96k', mp3], check=True)
        if not wav_dir:
            os.remove(wav)
        print(f'{name}: {len(x) / SR:.2f} s, {os.path.getsize(mp3)} B')


if __name__ == '__main__':
    main()
