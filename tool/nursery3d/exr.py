"""Чтение EXR из рендера Blender в numpy (линейный свет, строки сверху вниз)."""

import bpy
import numpy as np


def load(path):
    img = bpy.data.images.load(str(path), check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1].copy()


def to_srgb(lin):
    lin = np.clip(lin, 0, None)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)
