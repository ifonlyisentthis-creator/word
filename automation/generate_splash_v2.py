"""Generate splash icon for Afterword — pixel-perfect amber ring.

The app icon (ic_launcher.png) is an adaptive icon with rounded corners,
so upscaling it clips the ring. This script generates a clean ring from
scratch with numpy, matching the icon's exact amber/orange colour and
proportions, on a pure-black square canvas with NO rounded corners.

The ring is sized to ~55% of the canvas so it fits comfortably within
the native splash display area on all devices with no edge clipping.

Renders at 2304x2304 then LANCZOS downscales to 1152x1152.

Usage:
    python automation/generate_splash_v2.py
    -> overwrites assets/splash_icon.png
"""

import numpy as np
from PIL import Image

RENDER = 2304
FINAL = 1152


def main():
    S = RENDER
    cx, cy = S / 2, S / 2

    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)

    # ── Palette — sampled from the actual icon ring ──
    bright_amber = np.array([0.85, 0.58, 0.16])   # D9941F  — ring stroke
    warm_amber   = np.array([0.78, 0.52, 0.14])   # C78424  — bloom
    deep_amber   = np.array([0.50, 0.30, 0.08])   # 804D14  — ambient

    img = np.zeros((S, S, 3), dtype=np.float32)

    # ── Ring geometry — 55% of canvas so no edge clipping ──
    ring_r = S * 0.275         # radius (~55% of canvas width)
    ring_half_w = S * 0.006    # half-width of the ring stroke

    ring_dist = np.abs(dist - ring_r)

    # 1. Subtle ambient warmth
    ambient_r = S * 0.45
    ambient = np.exp(-(dist / ambient_r) ** 3.0) * 0.020
    img += ambient[..., None] * deep_amber

    # 2. Soft bloom along the ring
    glow_sigma = S * 0.025
    ring_glow = np.exp(-0.5 * (ring_dist / glow_sigma) ** 2) * 0.10
    img += ring_glow[..., None] * warm_amber

    # 3. Tighter bloom
    bloom_sigma = S * 0.010
    ring_bloom = np.exp(-0.5 * (ring_dist / bloom_sigma) ** 2) * 0.28
    img += ring_bloom[..., None] * warm_amber

    # 4. Main ring stroke — sharp, bright amber
    stroke = np.exp(-0.5 * (ring_dist / ring_half_w) ** 2.5)
    img += stroke[..., None] * bright_amber

    # ── Clamp and convert ──
    img = np.clip(img, 0, 1)
    img_uint8 = (img * 255).astype(np.uint8)
    pil_img = Image.fromarray(img_uint8, "RGB")

    final = pil_img.resize((FINAL, FINAL), Image.LANCZOS)

    out = "assets/splash_icon.png"
    final.save(out, "PNG", optimize=True)
    print(f"✅ {out} ({FINAL}x{FINAL}, supersampled from {RENDER}x{RENDER})")


if __name__ == "__main__":
    main()
