"""Generate a premium splash icon for Afterword — v2.

Design: Inspired by the golden ring app icon — a luminous gold circle
with subtle inner ring and ambient glow on pure black. Minimalist, premium.
Renders at 4608x4608 (4x supersample) then LANCZOS downscales to 1152x1152
for ultra-sharp, crispy results.

Usage:
    python automation/generate_splash_v2.py
    -> overwrites assets/splash_icon.png
"""

from PIL import Image, ImageDraw, ImageFilter

RENDER = 4608      # 4x supersample
FINAL = 1152


def ring(draw, cx, cy, radius, width, color):
    """Draw an anti-aliased ring (circle outline)."""
    r_out = radius + width / 2
    r_in = radius - width / 2
    draw.ellipse([cx - r_out, cy - r_out, cx + r_out, cy + r_out], fill=color)
    draw.ellipse([cx - r_in, cy - r_in, cx + r_in, cy + r_in], fill=(0, 0, 0, 0))


def soft_glow(size, cx, cy, radius, color, peak_alpha, blur_r):
    """Create a blurred radial glow layer."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 60
    for i in range(steps):
        t = i / steps
        r = int(radius * (1 - t * 0.5))
        a = int(peak_alpha * (1 - t) ** 2.2)
        if a < 1:
            continue
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*color, a))
    return layer.filter(ImageFilter.GaussianBlur(radius=blur_r))


def main():
    S = RENDER
    cx, cy = S // 2, S // 2

    # Colors — match the golden ring app icon palette
    bright_gold = (230, 180, 50)     # E6B432 — the hot center of the ring stroke
    warm_gold = (212, 168, 75)       # D4A84B — main ring color
    amber = (200, 150, 40)           # dimmer outer
    dark_gold = (120, 90, 20)        # subtle inner ring

    # Main ring geometry
    ring_radius = int(S * 0.30)      # ~30% of canvas = prominent but not huge
    ring_width = int(S * 0.014)      # thick enough to read as a bold ring

    # ── Canvas ──
    img = Image.new("RGBA", (S, S), (0, 0, 0, 255))

    # ── 1. Wide ambient glow behind ring ──
    glow1 = soft_glow(S, cx, cy, int(S * 0.40), warm_gold, peak_alpha=18, blur_r=int(S * 0.06))
    img = Image.alpha_composite(img, glow1)

    # ── 2. Tighter warm glow on the ring path ──
    glow2 = soft_glow(S, cx, cy, ring_radius, bright_gold, peak_alpha=35, blur_r=int(S * 0.025))
    img = Image.alpha_composite(img, glow2)

    # ── 3. Main golden ring ──
    ring_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring_layer)

    # Outer bright ring
    ring(rd, cx, cy, ring_radius, ring_width, (*bright_gold, 255))

    # Slight gradient feel: draw a thinner, brighter inner edge
    ring(rd, cx, cy, ring_radius - ring_width * 0.15, int(ring_width * 0.35), (*((245, 210, 90)), 180))

    img = Image.alpha_composite(img, ring_layer)

    # ── 4. Subtle inner secondary ring (like a vault echo) ──
    inner_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    id = ImageDraw.Draw(inner_layer)
    inner_r = int(ring_radius * 0.78)
    inner_w = max(2, int(ring_width * 0.18))
    ring(id, cx, cy, inner_r, inner_w, (*dark_gold, 45))
    img = Image.alpha_composite(img, inner_layer)

    # ── 5. Hot specular highlights on the ring (top-left and bottom-right) ──
    spec_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(spec_layer)

    import math
    # Top-left specular arc — brighter segment of the ring
    for angle_deg in range(-60, 30):
        a = math.radians(angle_deg)
        px = cx + ring_radius * math.cos(a)
        py = cy + ring_radius * math.sin(a)
        dot_r = ring_width * 0.6
        # Brightness falls off from center of highlight
        center_deg = -15
        dist = abs(angle_deg - center_deg) / 45
        alpha = int(60 * max(0, 1 - dist ** 1.5))
        if alpha > 0:
            sd.ellipse([px - dot_r, py - dot_r, px + dot_r, py + dot_r],
                       fill=(255, 240, 180, alpha))

    spec_layer = spec_layer.filter(ImageFilter.GaussianBlur(radius=int(S * 0.006)))
    img = Image.alpha_composite(img, spec_layer)

    # ── 6. Very subtle outer haze ring (barely visible) ──
    haze = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(haze)
    outer_haze_r = int(ring_radius * 1.15)
    ring(hd, cx, cy, outer_haze_r, max(2, int(ring_width * 0.12)), (*amber, 18))
    haze = haze.filter(ImageFilter.GaussianBlur(radius=int(S * 0.004)))
    img = Image.alpha_composite(img, haze)

    # ── 7. Downscale 4x with LANCZOS for crispy output ──
    final = img.resize((FINAL, FINAL), Image.LANCZOS)

    # Convert to opaque RGB
    final_rgb = Image.new("RGB", (FINAL, FINAL), (0, 0, 0))
    final_rgb.paste(final, mask=final.split()[3])

    out = "assets/splash_icon.png"
    final_rgb.save(out, "PNG", optimize=True)
    print(f"✅ Saved {out} ({FINAL}x{FINAL}, supersampled from {RENDER}x{RENDER})")


if __name__ == "__main__":
    main()
