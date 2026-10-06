"""
Build the in-game GUI textures for the Master Farmer launcher.

The "clean_no_text" card assets have flat color blocks painted over the art,
so the full-art panels are sliced out of the high-res mockup sheet instead
(MF-gui-images.png) and the dynamic text areas are erased so the plugin can
draw them live.

Output: plugin/scripts_data/master_farmer/gui/*.png
Run:    python tools/build_gui_assets.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "MF-gui-images.png"
OUT = ROOT / "plugin" / "scripts_data" / "master_farmer" / "gui"

# Panel bounds inside MF-gui-images.png (inclusive-exclusive)
MAIN_BOX = (147, 9, 1389, 597)      # 1242 x 588
PRODUCT_BOX = (21, 612, 752, 1010)  # 731 x 398

PRODUCT_UPSCALE = 1.5               # product art is lower-res than the main panel


def erase(img, box, sample_band=4):
    """Fill `box` with a vertical gradient sampled from just above and below it."""
    a = np.asarray(img).astype(float)
    x0, y0, x1, y1 = box
    top = a[max(y0 - sample_band, 0):y0, x0:x1].reshape(-1, a.shape[2]).mean(0)
    bot = a[y1:y1 + sample_band, x0:x1].reshape(-1, a.shape[2]).mean(0)
    for i, y in enumerate(range(y0, y1)):
        t = i / max(y1 - y0 - 1, 1)
        a[y, x0:x1] = top * (1 - t) + bot * t
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), img.mode)


def feather_mask(size, margin):
    """Rounded-rect soft mask, opaque in the middle and fading over `margin` px."""
    w, h = size
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((margin, margin, w - margin, h - margin), radius=margin * 2, fill=255)
    return m.filter(ImageFilter.GaussianBlur(margin / 2))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGBA")

    # ---- Main version-select panel --------------------------------------
    main_bg = sheet.crop(MAIN_BOX)
    main_bg = erase(main_bg, (18, 8, 70, 32))       # "v3.1" -> drawn live
    main_bg = erase(main_bg, (86, 547, 448, 574))   # recently-used line -> drawn live
    main_bg.save(OUT / "main_bg.png", optimize=True)

    # ---- Product panel, one per active game version ---------------------
    prod = sheet.crop(PRODUCT_BOX)
    up = (round(prod.width * PRODUCT_UPSCALE), round(prod.height * PRODUCT_UPSCALE))

    def finish(img, name):
        img = img.resize(up, Image.LANCZOS).filter(ImageFilter.UnsharpMask(1.2, 60, 2))
        img.save(OUT / name, optimize=True)

    finish(prod, "product_bg_forever.png")

    # Swap the "Forever" logo for the TBC / Midnight logo taken from the main cards.
    # Logo crops are in main-panel coordinates; target is the logo area of the
    # product header (product-panel coordinates).
    # name -> (source box in main panel, target box in product panel)
    logo_swaps = {
        "product_bg_tbc.png": ((508, 180, 728, 302), (312, 44, 488, 142)),
        "product_bg_retail.png": ((512, 362, 718, 474), (300, 48, 498, 140)),
        "product_bg_classic.png": ((914, 180, 1134, 300), (308, 44, 492, 142)),
    }
    main_raw = sheet.crop(MAIN_BOX)
    for name, (src, logo_target) in logo_swaps.items():
        tw, th = logo_target[2] - logo_target[0], logo_target[3] - logo_target[1]
        variant = prod.copy()
        # Darken the old logo area first so its edges don't bleed through the feather
        shade = Image.new("RGBA", (tw, th), (12, 10, 18, 255))
        variant.paste(shade, logo_target[:2], feather_mask((tw, th), 10))
        logo = main_raw.crop(src).resize((tw, th), Image.LANCZOS)
        variant.paste(logo, logo_target[:2], feather_mask((tw, th), 14))
        finish(variant, name)

    # Small standalone logo for the in-game header/toast
    Image.open(ROOT / "master_farmer_gui_assets_second_pass" / "logo_master_farmer.png") \
        .save(OUT / "logo_master_farmer.png", optimize=True)

    for f in sorted(OUT.glob("*.png")):
        print(f"{f.name:28s} {Image.open(f).size}  {f.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
