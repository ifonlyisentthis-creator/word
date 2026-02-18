"""Generate splash icon for Afterword — exact copy of the app icon.

Takes the actual ic_launcher.png icon, upscales it to 1152x1152 with
LANCZOS resampling so the splash looks pixel-identical to the icon
but at high resolution.

Usage:
    python automation/generate_splash_v2.py
    -> overwrites assets/splash_icon.png
"""

from PIL import Image

FINAL = 1152
ICON = "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"


def main():
    icon = Image.open(ICON).convert("RGB")
    splash = icon.resize((FINAL, FINAL), Image.LANCZOS)

    out = "assets/splash_icon.png"
    splash.save(out, "PNG", optimize=True)
    print(f"✅ {out} ({FINAL}x{FINAL}, upscaled from {icon.size[0]}x{icon.size[1]})")


if __name__ == "__main__":
    main()
