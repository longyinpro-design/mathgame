#!/usr/bin/env python3
"""Slice the approved v1 master sheets into transparent runtime UI/FX pieces.

Sources stay untouched; outputs are new RGBA files under assets/runtime/forest/
with a manifest recording SHA-256, sizes and source regions. Numbers and text
are still rendered by the engine — these slices carry no baked characters.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT_UI = ROOT/"assets/runtime/forest/ui"
OUT_FX = ROOT/"assets/runtime/forest/fx"

def decontaminate(image: Image.Image, bg: tuple[int, int, int], tol: float = 34.0, soft: float = 70.0) -> Image.Image:
    """Key out a flat background with soft alpha and edge decontamination."""
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, a = pixels[x, y]
            distance = ((r-bg[0])**2+(g-bg[1])**2+(b-bg[2])**2)**0.5
            if distance <= tol:
                pixels[x, y] = (r, g, b, 0)
            elif distance < soft:
                alpha = (distance-tol)/(soft-tol)
                # Unmix the background contribution so edges keep their own colour.
                keep = max(alpha, 0.05)
                clean = tuple(max(0, min(255, round((c-(1-keep)*bgc)/keep))) for c, bgc in zip((r, g, b), bg))
                pixels[x, y] = (clean[0], clean[1], clean[2], round(alpha*255))
    return rgba

def trim(image: Image.Image, box: tuple[int, int, int, int], inset: int = 2) -> Image.Image:
    left, top, right, bottom = box
    return image.crop((left+inset, top+inset, right-inset, bottom-inset))

def save(image: Image.Image, path: Path) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return {
        "path": str(path.relative_to(ROOT)),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "size": list(image.size),
        "mode": image.mode,
    }

def main() -> int:
    entries: dict[str, list] = {"ui": [], "fx": []}
    kit = Image.open(ROOT/"assets/source/ui-kit-v1.png").convert("RGB")
    cream = kit.getpixel((10, 10))
    ui_cuts = {
        "panel-paper": (60, 50, 919, 320),      # Parchment with brass corners (nine-patch)
        "panel-tall": (962, 48, 1196, 588),     # Vertical parchment
        "button-teal": (65, 356, 325, 468),     # Normal
        "button-teal-bright": (355, 355, 613, 468),   # Hover
        "button-teal-dark": (644, 356, 906, 468),     # Pressed
        "button-gold": (65, 478, 325, 591),     # Primary
        "button-gold-bright": (355, 478, 616, 591),   # Primary hover
        "button-gray": (644, 478, 906, 591),    # Disabled
    }
    for name, box in ui_cuts.items():
        piece = decontaminate(trim(kit, box), cream)
        entries["ui"].append(save(piece, OUT_UI/(name+".png")))
        if name.startswith("button-"):
            # Buttons render as small as 32px tall; pre-scale so nine-patch margins fit.
            small = piece.resize((round(piece.width*0.4), round(piece.height*0.4)), Image.LANCZOS)
            entries["ui"].append(save(small, OUT_UI/(name+"-small.png")))

    fx = Image.open(ROOT/"assets/source/effects-rewards-v1.png").convert("RGB")
    navy = fx.getpixel((8, 8))
    fx_cuts = {
        "crystal-idle": (108, 150, 232, 312),   # Crystal on stone base
        "crystal-lit": (408, 150, 532, 312),    # Crystal with glow ticks
        "spark": (128, 452, 216, 532),          # Single gold sparkle
        "burst": (660, 420, 880, 596),          # Gold sparkle ring
        "reward-burst": (652, 660, 890, 906),   # Firework spray
    }
    for name, box in fx_cuts.items():
        piece = decontaminate(trim(fx, box), navy, tol=26.0, soft=58.0)
        entries["fx"].append(save(piece, OUT_FX/(name+".png")))

    manifest = {
        "version": "forest-ui-v6",
        "sources": [
            {"path": "assets/source/ui-kit-v1.png", "background": list(cream), "used": True},
            {"path": "assets/source/effects-rewards-v1.png", "background": list(navy), "used": True},
        ],
        "engine_numeric_overlay": True,
        "pixel_edits": "none on sources; slices chroma-keyed with edge decontamination",
        "outputs": entries,
    }
    (ROOT/"art/forest_ui_v6.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n")

    # Contact sheet for human QA.
    sheet = Image.new("RGBA", (1560, 560), (40, 52, 44, 255))
    x = 16
    for entry in entries["ui"]:
        piece = Image.open(ROOT/entry["path"])
        sheet.alpha_composite(piece.resize((piece.width//2, piece.height//2)), (x, 16)); x += piece.width//2+14
    x = 16
    for entry in entries["fx"]:
        piece = Image.open(ROOT/entry["path"])
        sheet.alpha_composite(piece, (x, 330)); x += piece.width+14
    sheet.convert("RGB").save(ROOT/".scratch/v07-ui-contact-sheet.png")
    print(json.dumps({name: len(items) for name, items in entries.items()}))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
