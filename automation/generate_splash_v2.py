"""Generate a premium splash icon for Afterword — v3.

Design: Clean luminous ring matching the app icon's warm amber/orange palette.
The icon uses a warm amber-orange ring (#D4942A core, lighter top-left highlight)
on pure black. The splash should look *exactly* like a premium, slightly elevated
version of the icon — same colour family, same proportions, just subtler glow.

Key differences from the icon:
  - Slightly softer outer bloom (splash is larger on screen)
  - Very subtle top-left specular highlight on the ring (3D depth)
  - No inner secondary ring, no yellow, no gold — warm amber/orange only

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

    # ── Palette — warm amber/orange matching the app icon exactly ──
    # Sampled from the icon: the ring is amber-orange, NOT yellow/gold.
    bright_amber = np.array([0.85, 0.58, 0.16])   # D9941F  — ring core
    warm_amber   = np.array([0.78, 0.52, 0.14])   # C78424  — bloom
    deep_amber   = np.array([0.50, 0.30, 0.08])   # 804D14  — ambient
    highlight    = np.array([0.92, 0.70, 0.30])   # EBB34D  — specular

    img = np.zeros((S, S, 3), dtype=np.float32)

    # ── Ring geometry — match icon proportions ──
    ring_r = S * 0.34          # radius (~68% of canvas width)
    ring_half_w = S * 0.007    # half-width of the ring stroke (thin, like icon)

    ring_dist = np.abs(dist - ring_r)  # distance from ring center-line

    # ── 1. Very subtle ambient warmth (barely visible) ──
    ambient_r = S * 0.50
    ambient = np.exp(-(dist / ambient_r) ** 3.0) * 0.025
    img += ambient[..., None] * deep_amber

    # ── 2. Soft bloom along the ring (warm haze, subtle) ──
    glow_sigma = S * 0.030
    ring_glow = np.exp(-0.5 * (ring_dist / glow_sigma) ** 2) * 0.10
    img += ring_glow[..., None] * warm_amber

    # ── 3. Tighter bloom for ring presence ──
    bloom_sigma = S * 0.012
    ring_bloom = np.exp(-0.5 * (ring_dist / bloom_sigma) ** 2) * 0.30
    img += ring_bloom[..., None] * warm_amber

    # ── 4. The main ring stroke — sharp, bright amber ──
    stroke = np.exp(-0.5 * (ring_dist / ring_half_w) ** 2.5)
    img += stroke[..., None] * bright_amber

    # ── 5. Top-left specular highlight on the ring (3D depth) ──
    # Shift the highlight arc toward upper-left like the icon
    spec_cx = cx - S * 0.06
    spec_cy = cy - S * 0.08
    spec_dist = np.sqrt((x - spec_cx) ** 2 + (y - spec_cy) ** 2)
    spec_ring_dist = np.abs(spec_dist - ring_r)
    # Angular mask: strongest at ~135° (top-left), fades toward bottom-right
    angle = np.arctan2(y - cy, x - cx)
    # Target angle ~-2.36 rad (top-left quadrant)
    angle_weight = np.exp(-0.5 * ((angle + 2.36) / 0.9) ** 2)
    spec_intensity = np.exp(-0.5 * (spec_ring_dist / (ring_half_w * 1.2)) ** 2) * angle_weight * 0.35
    img += spec_intensity[..., None] * highlight

    # ── 6. Very faint inner shadow (depth, like the icon) ──
    inner_shadow_r = ring_r - ring_half_w * 3
    inner_shadow_dist = np.abs(dist - inner_shadow_r)
    inner_shadow_sigma = S * 0.006
    inner_shadow = np.exp(-0.5 * (inner_shadow_dist / inner_shadow_sigma) ** 2) * 0.04
    img += inner_shadow[..., None] * deep_amber

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
