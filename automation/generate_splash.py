"""Generate a premium splash icon for Afterword.

Design: Minimalist geometric vault shield with subtle amber glow.
Renders at 2304x2304 (2x supersample) then downscales to 1152x1152.
No text. Pure black background. Premium, dark, aesthetic.

Usage:
    python automation/generate_splash.py
    -> writes assets/splash_icon.png
"""

import math
from PIL import Image, ImageDraw, ImageFilter

# Render at 2x for supersampling
RENDER = 2304
FINAL = 1152

def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))

def draw_glow(draw, cx, cy, radius, color, alpha_max=80, steps=40):
    """Draw a soft radial glow."""
    for i in range(steps):
        t = i / steps
        r = int(radius * (1 - t * 0.7))
        a = int(alpha_max * (1 - t) ** 2)
        c = (*color, a)
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c)

def draw_shield(draw, cx, cy, size, outline_color, outline_width=6, glow_color=None):
    """Draw a geometric shield shape — pointed bottom, rounded top."""
    # Shield as a polygon: wide top, tapered to a point at bottom
    w = size * 0.48  # half-width at top
    h = size * 0.58  # total height
    top_y = cy - h * 0.42
    mid_y = cy + h * 0.15
    bot_y = cy + h * 0.58

    # Build smooth shield path
    points = []
    # Top-left curve to top-right
    num_top = 30
    for i in range(num_top + 1):
        t = i / num_top
        angle = math.pi + t * math.pi  # 180 to 360 degrees
        rx = w * 0.92
        ry = h * 0.22
        x = cx + rx * math.cos(angle)
        y = top_y + ry * 0.5 + ry * math.sin(angle) * 0.5
        points.append((x, y))

    # Right side down to point
    num_side = 20
    for i in range(1, num_side + 1):
        t = i / num_side
        x = cx + w * (1 - t ** 1.3)
        y = mid_y + (bot_y - mid_y) * t
        points.append((x, y))

    # Left side back up
    for i in range(1, num_side):
        t = 1 - i / num_side
        x = cx - w * (1 - t ** 1.3)
        y = mid_y + (bot_y - mid_y) * t
        points.append((x, y))

    # Draw outline
    draw.polygon(points, outline=outline_color, fill=None)

    # Thicken the outline
    for offset in range(1, outline_width):
        scaled = []
        for px, py in points:
            dx = px - cx
            dy = py - cy
            dist = math.sqrt(dx * dx + dy * dy) or 1
            nx = dx / dist
            ny = dy / dist
            scaled.append((px - nx * offset * 0.5, py - ny * offset * 0.5))
        draw.polygon(scaled, outline=(*outline_color[:3], max(40, outline_color[3] - offset * 8)))

    return points

def draw_keyhole(draw, cx, cy, size, color):
    """Draw a minimalist keyhole — circle + tapered slot below."""
    circle_r = size * 0.055
    slot_w = size * 0.028
    slot_h = size * 0.10

    # Circle part
    draw.ellipse(
        [cx - circle_r, cy - circle_r, cx + circle_r, cy + circle_r],
        fill=color,
    )

    # Tapered slot
    top_w = slot_w
    bot_w = slot_w * 0.5
    slot_top = cy + circle_r * 0.4
    slot_bot = slot_top + slot_h
    draw.polygon([
        (cx - top_w, slot_top),
        (cx + top_w, slot_top),
        (cx + bot_w, slot_bot),
        (cx - bot_w, slot_bot),
    ], fill=color)

def draw_concentric_arcs(draw, cx, cy, size, color, count=3):
    """Draw subtle concentric arc lines around the shield for a tech feel."""
    for i in range(count):
        r = size * (0.52 + i * 0.06)
        arc_alpha = max(10, 35 - i * 10)
        c = (*color[:3], arc_alpha)
        # Draw partial arcs
        bbox = [cx - r, cy - r, cx + r, cy + r]
        draw.arc(bbox, start=200, end=340, fill=c, width=2 + (2 - i))

def main():
    S = RENDER
    cx, cy = S // 2, S // 2

    # Colors
    gold = (212, 168, 75)       # D4A84B
    warm_amber = (232, 195, 106)  # E8C36A
    dark_gold = (139, 105, 20)

    # Create RGBA canvas — pure black
    img = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    glow_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)

    # 1. Ambient glow behind the shield
    draw_glow(glow_draw, cx, cy, int(S * 0.38), gold, alpha_max=30, steps=50)
    draw_glow(glow_draw, cx, cy, int(S * 0.25), warm_amber, alpha_max=18, steps=30)

    # Blur the glow
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=40))
    img = Image.alpha_composite(img, glow_layer)

    # 2. Main drawing layer
    main_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(main_layer)

    shield_size = S * 0.65

    # Concentric tech arcs
    draw_concentric_arcs(draw, cx, cy, shield_size, gold, count=3)

    # Shield outline — gold with transparency
    shield_color = (*gold, 200)
    draw_shield(draw, cx, cy, shield_size, shield_color, outline_width=8)

    # Inner shield (slightly smaller, dimmer)
    inner_color = (*dark_gold, 60)
    draw_shield(draw, cx, int(cy + shield_size * 0.01), shield_size * 0.88,
                inner_color, outline_width=3)

    # Keyhole
    keyhole_color = (*warm_amber, 220)
    draw_keyhole(draw, cx, int(cy - shield_size * 0.02), shield_size, keyhole_color)

    # 3. Specular dot — top center of shield for premium depth
    spec_r = int(shield_size * 0.02)
    spec_y = int(cy - shield_size * 0.28)
    draw.ellipse(
        [cx - spec_r, spec_y - spec_r, cx + spec_r, spec_y + spec_r],
        fill=(255, 255, 255, 40),
    )

    img = Image.alpha_composite(img, main_layer)

    # 4. Final subtle vignette
    vignette = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    vig_draw = ImageDraw.Draw(vignette)
    for i in range(60):
        t = i / 60
        r = int(S * 0.7 * (1 - t * 0.3))
        a = int(t * t * 80)
        vig_draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=None,
            outline=(0, 0, 0, a),
            width=int(S * 0.02),
        )

    # 5. Downscale with LANCZOS for best quality
    final = img.resize((FINAL, FINAL), Image.LANCZOS)

    # Convert to RGB (no alpha for splash PNG)
    final_rgb = Image.new("RGB", (FINAL, FINAL), (0, 0, 0))
    final_rgb.paste(final, mask=final.split()[3])

    out_path = "assets/splash_icon.png"
    final_rgb.save(out_path, "PNG", optimize=True)
    print(f"Saved {out_path} ({FINAL}x{FINAL})")

if __name__ == "__main__":
    main()
