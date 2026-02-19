"""Generate splash icon for Afterword — exact copy of the chrome icon.

Takes viewer/android-chrome-512x512.png (standard square PNG, no
adaptive-icon rounded corners) and:
  1. Pastes it centred on a 1152x1152 black canvas at ~55% size
     so the glow never clips on any device
  2. The black border guarantees no edge-clipping on ANY screen

Why not upscale only?  The source is 512px — placing it centred on a
larger black canvas means native splash configs can use 'image' mode
and the ring will always have safe margin.

Usage:
    python automation/generate_splash_v2.py
    -> overwrites assets/splash_icon.png
"""

from PIL import Image

FINAL = 1152
SOURCE = "viewer/android-chrome-512x512.png"
# Ring occupies ~55% of canvas → generous black margin on all edges
RING_SIZE = int(FINAL * 0.62)      # 714px — slight upscale from 512


def main():
    icon = Image.open(SOURCE).convert("RGB")
    ring = icon.resize((RING_SIZE, RING_SIZE), Image.LANCZOS)

    canvas = Image.new("RGB", (FINAL, FINAL), (0, 0, 0))
    offset = (FINAL - RING_SIZE) // 2
    canvas.paste(ring, (offset, offset))

    out = "assets/splash_icon.png"
    canvas.save(out, "PNG", optimize=True)
    print(f"✅ {out} ({FINAL}x{FINAL}, ring {RING_SIZE}px centred from {SOURCE})")


if __name__ == "__main__":
    main()
