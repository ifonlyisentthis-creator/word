"""Generate a premium splash icon for Afterword — v2.

Design: Tall geometric shield with elegant keyhole, subtle amber glow.
Renders at 2304x2304 (2x supersample) then downscales to 1152x1152.
No text. Pure black background. Minimalist. Premium.

Usage:
    python automation/generate_splash_v2.py
    -> overwrites assets/splash_icon.png
"""

import math
from PIL import Image, ImageDraw, ImageFilter

RENDER = 2304
FINAL = 1152


def radial_glow(img, cx, cy, radius, color, peak_alpha=50, blur=60):
    """Paint a soft radial glow on an RGBA image."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    steps = 80
    for i in range(steps):
        t = i / steps
        r = int(radius * (1 - t * 0.6))
        a = int(peak_alpha * (1 - t) ** 2.5)
        if a < 1:
            continue
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*color, a))
    layer = layer.filter(ImageFilter.GaussianBlur(radius=blur))
    return Image.alpha_composite(img, layer)


def shield_points(cx, cy, w, h, steps=120):
    """Generate a tall, elegant shield polygon.
    
    The shape: wide rounded top tapering to a sharp point at the bottom.
    Think: heraldic shield / vault emblem.
    """
    pts = []
    
    # Top arc — semicircle across the top
    arc_steps = steps // 2
    arc_cy = cy - h * 0.20  # center of the top arc
    arc_rx = w * 0.50
    arc_ry = h * 0.28
    for i in range(arc_steps + 1):
        t = i / arc_steps
        angle = math.pi + t * math.pi  # 180° → 360° (left to right)
        x = cx + arc_rx * math.cos(angle)
        y = arc_cy + arc_ry * math.sin(angle)
        pts.append((x, y))

    # Right side — smooth curve from top-right down to the bottom point
    side_steps = steps // 4
    top_right_x = cx + arc_rx
    top_right_y = arc_cy
    bot_x = cx
    bot_y = cy + h * 0.50
    
    for i in range(1, side_steps + 1):
        t = i / side_steps
        # Bezier-like curve: starts going down, curves inward to the point
        x = top_right_x + (bot_x - top_right_x) * (t ** 1.4)
        y = top_right_y + (bot_y - top_right_y) * t
        pts.append((x, y))

    # Left side — mirror of right (bottom to top-left)
    top_left_x = cx - arc_rx
    top_left_y = arc_cy
    
    for i in range(side_steps - 1, 0, -1):
        t = i / side_steps
        x = top_left_x + (bot_x - top_left_x) * (t ** 1.4)
        y = top_left_y + (bot_y - top_left_y) * t
        pts.append((x, y))

    return pts


def draw_shield_outline(draw, pts, color, width=4):
    """Draw the shield as a thick anti-aliased outline."""
    n = len(pts)
    for i in range(n):
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        draw.line([p1, p2], fill=color, width=width)


def draw_keyhole(draw, cx, cy, scale, color):
    """Draw a refined keyhole — circle + elegant tapered slot."""
    cr = scale * 0.045  # circle radius
    sw = scale * 0.022  # slot width at top
    sh = scale * 0.095  # slot height
    bw = scale * 0.010  # slot width at bottom

    # Circle
    draw.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=color)

    # Tapered slot below circle
    slot_top = cy + cr * 0.5
    slot_bot = slot_top + sh
    draw.polygon([
        (cx - sw, slot_top),
        (cx + sw, slot_top),
        (cx + bw, slot_bot),
        (cx - bw, slot_bot),
    ], fill=color)


def main():
    S = RENDER
    cx, cy = S // 2, S // 2

    # Colors
    gold = (212, 168, 75)
    warm_amber = (232, 195, 106)
    pale_gold = (255, 240, 200)
    dim_gold = (100, 80, 30)

    # Black RGBA canvas
    img = Image.new("RGBA", (S, S), (0, 0, 0, 255))

    # ── 1. Ambient glow ──
    img = radial_glow(img, cx, cy, int(S * 0.42), gold, peak_alpha=22, blur=80)
    img = radial_glow(img, cx, cy, int(S * 0.28), warm_amber, peak_alpha=12, blur=50)

    # ── 2. Main drawing ──
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    shield_w = S * 0.55
    shield_h = S * 0.62

    # Outer shield
    pts = shield_points(cx, cy, shield_w, shield_h)
    draw_shield_outline(draw, pts, (*gold, 180), width=7)

    # Inner shield (smaller, dimmer)
    inner_pts = shield_points(cx, int(cy + shield_h * 0.008), shield_w * 0.84, shield_h * 0.84)
    draw_shield_outline(draw, inner_pts, (*dim_gold, 55), width=3)

    # Keyhole — centered, slightly above the vertical middle of the shield
    keyhole_cy = int(cy + shield_h * 0.02)
    draw_keyhole(draw, cx, keyhole_cy, shield_w, (*pale_gold, 200))

    # Subtle top specular highlight
    spec_r = int(shield_w * 0.015)
    spec_y = int(cy - shield_h * 0.36)
    draw.ellipse(
        [cx - spec_r, spec_y - spec_r, cx + spec_r, spec_y + spec_r],
        fill=(255, 255, 255, 30),
    )

    # ── 3. Subtle concentric arcs at top (tech/vault feel) ──
    for i in range(3):
        r = int(shield_w * (0.56 + i * 0.055))
        alpha = max(8, 28 - i * 9)
        bbox = [cx - r, cy - r, cx + r, cy + r]
        draw.arc(bbox, start=210, end=330, fill=(*gold, alpha), width=2)

    img = Image.alpha_composite(img, layer)

    # ── 4. Soft shield fill glow (very subtle, inside the shield) ──
    inner_glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ig_draw = ImageDraw.Draw(inner_glow)
    ig_draw.polygon(pts, fill=(*gold, 6))
    inner_glow = inner_glow.filter(ImageFilter.GaussianBlur(radius=20))
    img = Image.alpha_composite(img, inner_glow)

    # ── 5. Downscale with LANCZOS ──
    final = img.resize((FINAL, FINAL), Image.LANCZOS)

    # Convert to RGB (splash PNG must be opaque)
    final_rgb = Image.new("RGB", (FINAL, FINAL), (0, 0, 0))
    final_rgb.paste(final, mask=final.split()[3])

    out = "assets/splash_icon.png"
    final_rgb.save(out, "PNG", optimize=True)
    print(f"Saved {out} ({FINAL}x{FINAL})")


if __name__ == "__main__":
    main()
