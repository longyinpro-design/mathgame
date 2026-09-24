#!/usr/bin/env python3
"""切出齿轮工坊 GW02–GW07 共用的运行时 AtlasTexture，并写清单。

来源是 workshop-art-v1 的两张机关/道具母版与嗒嗒姿态母版，像素原样不动，
只登记 region；数量、时间格、刻度、指针与状态一律由引擎绘制，不进切片。
区域用固定表而不是自动找边界：母版换一版时，清单里每一块都能逐像素复核。
"""
from pathlib import Path
import hashlib
import json
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = {
    "harbor": "assets/source/workshop/harbor-props-source-v1.png",
    "mechanisms": "assets/source/workshop/mechanisms-source-v1.png",
    "dada": "assets/source/workshop/dada-poses-source-v1.png",
}
# id: (source, region[x,y,w,h], 用途)
SPRITES = [
    ("tray",     "harbor",     (64, 195, 584, 251),   "空槽盘壳：托盘、交付架"),
    ("spindle",  "harbor",     (769, 122, 125, 311),  "单根灯轴：一切计数物的实体"),
    ("box",      "harbor",     (1097, 98, 366, 352),  "维修盒：留样盒与封存箱"),
    ("lift",     "harbor",     (59, 567, 492, 360),   "升降平台：吊台"),
    ("cart",     "harbor",     (605, 715, 508, 217),  "空货车：小车"),
    ("bell",     "harbor",     (1168, 549, 281, 374), "开船铃：放行灯与报时铃"),
    ("press",    "mechanisms", (92, 41, 453, 452),    "压机：压制/钻孔工位"),
    ("ingot",    "mechanisms", (657, 335, 273, 142),  "铜锭：待加工料"),
    ("plate",    "mechanisms", (1068, 343, 376, 134), "铜板：铜料片与模具底"),
    ("dial",     "mechanisms", (42, 560, 511, 368),   "双空表盘：抛光机与冷却机"),
    ("lever",    "mechanisms", (625, 560, 356, 368),  "启动杆：开工与换模"),
    ("rack",     "mechanisms", (1036, 634, 469, 294), "单批暂存架：暂存位与炉架"),
    ("dada_idle",   "dada", (68, 78, 416, 534),   "嗒嗒待机"),
    ("dada_hold",   "dada", (613, 83, 430, 529),  "嗒嗒夹拍/抱料"),
    ("dada_brace",  "dada", (1174, 91, 392, 521), "嗒嗒忍住加速"),
    ("dada_invite", "dada", (1643, 77, 476, 535), "嗒嗒邀请休息"),
]
OUT_DIR = ROOT / "assets/runtime/workshop/kit-v1"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sizes = {}
    for key, rel in SOURCE.items():
        path = ROOT / rel
        with Image.open(path) as image:
            sizes[key] = image.size
    manifest = {"schema_version": 1, "source_mode": "AtlasTexture regions; source pixels unchanged",
                "sources": {k: {"path": v, "size": list(sizes[k]), "sha256": digest(ROOT / v)}
                            for k, v in SOURCE.items()},
                "sprites": []}
    for sprite_id, key, region, purpose in SPRITES:
        x, y, w, h = region
        width, height = sizes[key]
        assert x >= 0 and y >= 0 and x + w <= width and y + h <= height, (sprite_id, region)
        atlas = OUT_DIR / (sprite_id + ".tres")
        atlas.write_text(
            '[gd_resource type="AtlasTexture" load_steps=2 format=3]\n'
            '[ext_resource type="Texture2D" path="res://%s" id="1"]\n'
            '[resource]\n'
            'atlas = ExtResource("1")\n'
            'region = Rect2(%d, %d, %d, %d)\n'
            'filter_clip = true\n' % (SOURCE[key], x, y, w, h))
        manifest["sprites"].append({"id": sprite_id, "source": SOURCE[key], "region": list(region),
                                    "anchor_px": [x + w / 2, y + h], "purpose": purpose,
                                    "atlas": str(atlas.relative_to(ROOT))})
    manifest["sprites"] = sorted(manifest["sprites"], key=lambda s: s["id"])
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print("wrote", len(manifest["sprites"]), "atlases to", OUT_DIR.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
