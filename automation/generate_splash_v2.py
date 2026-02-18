"""Generate a premium splash icon for Afterword — v2.

Design: Elevated golden ring — inspired by the app icon's warm circle.
A single prominent ring with soft ambient glow, subtle inner ring for depth.
Properly sized to fill the splash area. Smooth gradients via numpy.
No rays, no flashlight, no cold tones. Pure black + warm gold.

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

    # Palette — warm gold matching the app icon
    bright_gold = np.array([0.92, 0.72, 0.22])   # E6B838
    warm_gold   = np.array([0.84, 0.66, 0.30])   # D6A84D
    deep_gold   = np.array([0.55, 0.40, 0.12])   # 8C661F
    amber_glow  = np.array([0.50, 0.35, 0.08])   # 805914

    img = np.zeros((S, S, 3), dtype=np.float32)

    # ── Ring geometry ──
    ring_r = S * 0.34          # radius — fills ~68% of the canvas width
    ring_half_w = S * 0.008    # half-width of the ring stroke

    ring_dist = np.abs(dist - ring_r)  # distance from ring center-line

    # ── 1. Wide ambient warmth behind the ring ──
    ambient_r = S * 0.42
    ambient = np.exp(-(dist / ambient_r) ** 2.5) * 0.04
    img += ambient[..., None] * amber_glow

    # ── 2. Soft glow along the ring path (warm haze) ──
    glow_sigma = S * 0.04
    ring_glow = np.exp(-0.5 * (ring_dist / glow_sigma) ** 2) * 0.14
    img += ring_glow[..., None] * warm_gold

    # ── 3. Tighter bloom on the ring ──
    bloom_sigma = S * 0.016
    ring_bloom = np.exp(-0.5 * (ring_dist / bloom_sigma) ** 2) * 0.35
    img += ring_bloom[..., None] * warm_gold

    # ── 4. The main ring stroke — sharp, bright gold ──
    stroke = np.exp(-0.5 * (ring_dist / ring_half_w) ** 2.5)
    img += stroke[..., None] * bright_gold

    # ── 5. Brighter inner edge (specular highlight on the ring) ──
    inner_edge_r = ring_r - ring_half_w * 0.3
    inner_edge_dist = np.abs(dist - inner_edge_r)
    inner_edge_sigma = ring_half_w * 0.4
    inner_highlight = np.exp(-0.5 * (inner_edge_dist / inner_edge_sigma) ** 2) * 0.45
    img += inner_highlight[..., None] * np.array([0.96, 0.82, 0.38])

    # ── 6. Subtle inner secondary ring (depth, like the icon) ──
    inner_ring_r = ring_r * 0.88
    inner_ring_half_w = S * 0.002
    inner_ring_dist = np.abs(dist - inner_ring_r)
    inner_ring = np.exp(-0.5 * (inner_ring_dist / inner_ring_half_w) ** 2.5) * 0.12
    img += inner_ring[..., None] * deep_gold

    # ── 7. Very faint outer haze ring (barely visible) ──
    outer_haze_r = ring_r * 1.06
    outer_haze_sigma = S * 0.003
    outer_haze_dist = np.abs(dist - outer_haze_r)
    outer_haze = np.exp(-0.5 * (outer_haze_dist / outer_haze_sigma) ** 2) * 0.06
    img += outer_haze[..., None] * deep_gold

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
