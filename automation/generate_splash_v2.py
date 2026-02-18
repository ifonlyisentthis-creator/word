"""Generate a premium splash icon for Afterword — v2.

Design: "The Sentinel" — a luminous crystalline light form emerging from void.
Cool white/silver core, ethereal aura, cinematic 6-pointed lens-star.
Pixel-perfect smooth gradients via numpy (no banding).
Pure black + ghostly white/silver. No gold, no ring.

Renders at 2304x2304 then LANCZOS downscales to 1152x1152.

Usage:
    python automation/generate_splash_v2.py
    -> overwrites assets/splash_icon.png
"""

import math
import numpy as np
from PIL import Image, ImageFilter

RENDER = 2304      # 2x supersample (numpy is pixel-perfect, less need for 4x)
FINAL = 1152


def main():
    S = RENDER
    cx, cy = S / 2, S / 2

    # Build coordinate grids
    y, x = np.mgrid[0:S, 0:S].astype(np.float32)
    dx = x - cx
    dy = y - cy
    dist = np.sqrt(dx ** 2 + dy ** 2)
    angle = np.arctan2(dy, dx)

    # Start with pure black
    img = np.zeros((S, S, 3), dtype=np.float32)

    # ── 1. Wide atmospheric aura (deep blue-gray) ──
    r_atmo = S * 0.42
    atmo = np.exp(-(dist / r_atmo) ** 1.8) * 0.08
    img += atmo[..., None] * np.array([0.35, 0.42, 0.55])

    # ── 2. Mid-range ethereal glow (ice silver) ──
    r_mid = S * 0.24
    mid_glow = np.exp(-(dist / r_mid) ** 2.0) * 0.18
    img += mid_glow[..., None] * np.array([0.70, 0.78, 0.88])

    # ── 3. Inner luminous bloom (bright silver-white) ──
    r_inner = S * 0.11
    inner = np.exp(-(dist / r_inner) ** 1.6) * 0.55
    img += inner[..., None] * np.array([0.85, 0.90, 0.95])

    # ── 4. Cinematic 6-pointed lens star ──
    # Each ray is a narrow Gaussian along its direction, tapering with distance
    num_rays = 6
    ray_length = S * 0.36
    ray_width_sigma = S * 0.008  # thinness of rays

    rays = np.zeros((S, S), dtype=np.float32)
    for i in range(num_rays):
        a = (i / num_rays) * math.pi + math.pi / 12  # offset from axes
        cos_a, sin_a = math.cos(a), math.sin(a)
        # Project each pixel onto the ray axis
        proj = dx * cos_a + dy * sin_a     # distance along ray
        perp = -dx * sin_a + dy * cos_a    # perpendicular distance

        # Taper width: thinner at tips
        taper = np.clip(1.0 - np.abs(proj) / ray_length, 0, 1) ** 0.5
        width = ray_width_sigma * (1.0 + 2.0 * taper)
        # Gaussian cross-section
        cross = np.exp(-0.5 * (perp / np.maximum(width, 1e-6)) ** 2)
        # Fade with distance from center
        fade = np.exp(-(np.abs(proj) / ray_length) ** 1.3) * taper
        rays += cross * fade

    rays = np.clip(rays, 0, 1)
    # Rays are silver-white
    img += rays[..., None] * 0.30 * np.array([0.82, 0.86, 0.92])

    # ── 5. Secondary 12-point micro-rays (fainter, interleaved) ──
    micro_rays = np.zeros((S, S), dtype=np.float32)
    micro_length = S * 0.20
    micro_sigma = S * 0.004

    for i in range(12):
        a = (i / 12) * math.pi + math.pi / 24
        cos_a, sin_a = math.cos(a), math.sin(a)
        proj = dx * cos_a + dy * sin_a
        perp = -dx * sin_a + dy * cos_a
        taper = np.clip(1.0 - np.abs(proj) / micro_length, 0, 1) ** 0.6
        width = micro_sigma * (1.0 + 1.5 * taper)
        cross = np.exp(-0.5 * (perp / np.maximum(width, 1e-6)) ** 2)
        fade = np.exp(-(np.abs(proj) / micro_length) ** 1.5) * taper
        micro_rays += cross * fade

    micro_rays = np.clip(micro_rays, 0, 1)
    img += micro_rays[..., None] * 0.12 * np.array([0.70, 0.78, 0.88])

    # ── 6. Bright core — the sentinel's heart ──
    r_core = S * 0.045
    core = np.exp(-(dist / r_core) ** 1.4) * 0.95
    img += core[..., None] * np.array([1.0, 1.0, 1.0])

    # White-hot center point
    r_hot = S * 0.012
    hot = np.exp(-(dist / r_hot) ** 1.0)
    img += hot[..., None] * np.array([1.0, 1.0, 1.0])

    # ── 7. Subtle outer halo ring ──
    halo_r = S * 0.32
    halo_sigma = S * 0.008
    ring_dist = np.abs(dist - halo_r)
    halo_ring = np.exp(-(ring_dist / halo_sigma) ** 2) * 0.06
    img += halo_ring[..., None] * np.array([0.60, 0.68, 0.78])

    # ── Clamp and convert ──
    img = np.clip(img, 0, 1)
    img_uint8 = (img * 255).astype(np.uint8)
    pil_img = Image.fromarray(img_uint8, "RGB")

    # Downscale with LANCZOS
    final = pil_img.resize((FINAL, FINAL), Image.LANCZOS)

    out = "assets/splash_icon.png"
    final.save(out, "PNG", optimize=True)
    print(f"✅ {out} ({FINAL}x{FINAL}, supersampled from {RENDER}x{RENDER})")


if __name__ == "__main__":
    main()
