"""Inspect source images and build a local catalog. Never modifies image pixels."""

import hashlib
import html
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
RECORD = ROOT / "art/生成记录-v1.json"

INFO = {
    "style-master-v1": ("统一风格基准", "视觉参考", None,
                         "风格参考板，包含角色、环境、机关、界面与配色。"),
    "world-map-v1": ("数字群岛世界地图", "不透明背景母版", None,
                      "六座主题岛屿与中央营地；实际关卡节点由引擎叠加。"),
    "explorer-sprites-v1": ("主角初版 · 已替代", "保留过程参考", [4, 3],
                             "RGB 中烘焙了棋盘底，不能当透明精灵使用；使用 v2 继续整备。"),
    "explorer-sprites-v2": ("主角四方向姿态", "RGBA 源图 · 待校准", [4, 3],
                             "真实 alpha；需检查部分透明边缘、残留光晕和脚底锚点，不能直接等分三行。"),
    "companions-npcs-v1": ("狐狸伙伴与六岛居民", "不透明部件母版", [4, 3],
                            "狐狸方向按实际图为正面、右、背面、左；需透明化及逐项命名。"),
    "mechanisms-props-v1": ("数学机关与探索道具", "不透明部件母版", [6, 4],
                             "24 个部件；天平拆分为支座、横梁和托盘。数字槽保持空白。需按实际轮廓切片。"),
    "terrain-textures-v1": ("六主题地表纹理", "地表样本母版", [4, 6],
                             "24 个地表样本；尚未验证重复拼缝，也未补齐自动地形边角。"),
    "ui-kit-v1": ("对话、按钮与功能图标", "UI 母版 · 待切片", None,
                   "面板、六种按钮状态、八个功能图标与三种关卡节点。需定义九宫格与焦点状态。"),
    "effects-rewards-v1": ("机关特效与探索奖励", "分镜母版 · 待校准", [4, 4],
                            "三组特效分镜和四个奖励图案；深蓝底为源图背景，帧中心与连续性尚未验收。"),
    "chapter-rooms-v1": ("六章机关房间", "房间背景母版", [3, 2],
                          "中央区域用于放置数学棋盘，边缘装饰对应六个主题。"),
}


def main():
    record = json.loads(RECORD.read_text())
    assets = []
    for item in record["assets"]:
        path = ROOT / item["path"]
        prompt_path = ROOT / item["prompt"]
        assert path.is_file() and prompt_path.is_file()
        title, status, grid, note = INFO[item["id"]]
        with Image.open(path) as image:
            image.load()
            width, height = image.size
            alpha = None
            if "A" in image.getbands():
                histogram = image.getchannel("A").histogram()
                alpha = {"minimum": min(i for i, count in enumerate(histogram) if count),
                         "maximum": max(i for i, count in enumerate(histogram) if count),
                         "fully_transparent_pixels": histogram[0],
                         "fully_opaque_pixels": histogram[255],
                         "partially_transparent_pixels": sum(histogram[1:255])}
            local_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            original = Path(item["source"])
            copy_match = (local_hash == hashlib.sha256(original.read_bytes()).hexdigest()
                          if original.is_file() else None)
            if original.is_file():
                assert copy_match
            assets.append({**item, "title": title, "status": status,
                           "active": item["id"] != "explorer-sprites-v1",
                           "width": width, "height": height, "mode": image.mode,
                           "alpha": alpha, "nominal_grid_columns_rows": grid,
                           "dimensions_divisible_by_nominal_grid": (
                               width % grid[0] == 0 and height % grid[1] == 0 if grid else None),
                           "sha256": local_hash, "copy_matches_generated_original": copy_match,
                           "runtime_ready": False, "qa_note": note})
    result = {"date": "2026-09-08", "generator": record["generator"],
              "total_files": len(assets), "active_visual_categories": sum(a["active"] for a in assets),
              "scope": "Source art pack v1. No Godot import, runtime slicing or complete animation QA.",
              "command": "python3 art/build_catalog.py", "assets": assets}
    (ROOT / "art/素材清单-v1.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")

    cards = []
    for a in assets:
        if not a["active"]:
            continue
        image_url = "../" + a["path"]
        prompt_url = "../" + a["prompt"]
        alpha_label = "真实 alpha" if a["alpha"] and a["alpha"]["fully_transparent_pixels"] else "不透明源图"
        cards.append(f'''<article class="card">
          <a class="picture" href="{html.escape(image_url)}" target="_blank" rel="noopener">
            <img src="{html.escape(image_url)}" alt="{html.escape(a['title'])}" loading="lazy">
          </a>
          <div class="card-copy"><div class="eyebrow">{html.escape(a['status'])}</div>
          <h2>{html.escape(a['title'])}</h2><p>{html.escape(a['qa_note'])}</p>
          <div class="meta">{a['width']} × {a['height']} · {a['mode']} · {alpha_label}</div>
          <a href="{html.escape(image_url)}" target="_blank" rel="noopener">查看原图 ↗</a>
          <a href="{html.escape(prompt_url)}" target="_blank" rel="noopener">生成提示词 ↗</a></div></article>''')
    page = '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>数字群岛 · 统一美术母版 v1</title>
<style>
:root{color-scheme:light;--ink:#223247;--paper:#f6efdf;--teal:#326b70;--line:#d7cab2}
*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif;line-height:1.7}
main{max-width:1360px;margin:0 auto;padding:48px 30px 60px}header{border-bottom:1px solid var(--line);padding-bottom:28px;margin-bottom:28px}
.eyebrow{font-size:12px;font-weight:700;letter-spacing:.13em;color:var(--teal)}h1{font-size:clamp(32px,5vw,54px);letter-spacing:-.04em;line-height:1.2;margin:10px 0 18px}header p{max-width:880px;margin:0 0 18px}
.facts{display:flex;gap:10px;flex-wrap:wrap}.facts span{border:1px solid var(--line);padding:5px 12px;border-radius:4px;font-size:13px;background:#fff8e9}
.toolbar{display:flex;align-items:center;gap:10px;margin:18px 0 26px;flex-wrap:wrap}.toolbar label{font-size:13px;cursor:pointer}input{accent-color:var(--teal)}
.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}.card{overflow:hidden;border:1px solid var(--line);background:#fffaf0;border-radius:9px}.picture{display:flex;align-items:center;justify-content:center;height:400px;background:#f3e4c0;overflow:hidden}.picture img{width:100%;height:100%;object-fit:contain}.card-copy{padding:21px 23px 24px}h2{font-size:21px;margin:6px 0 9px}.card p{font-size:14px;margin:0 0 10px}.meta{font-size:12px;color:#646c70;margin-bottom:15px}.card a:not(.picture){font-size:13px;margin-right:17px;color:var(--teal);text-underline-offset:4px}
.notice{margin:28px 0;padding:20px 24px;background:#e8e4d8;border-left:4px solid #c2a367;font-size:14px}.notice strong{display:block;margin-bottom:4px}footer{font-size:13px;color:#596465;margin-top:30px}footer a{color:var(--teal);margin-right:18px}
body.dark-matte .picture{background:#223247}body.white-matte .picture{background:#fff}
@media(max-width:760px){main{padding:28px 16px}.grid{grid-template-columns:1fr}.picture{height:auto;min-height:240px}.picture img{height:auto;max-height:520px}.card-copy{padding:18px}.toolbar{align-items:flex-start}}
</style></head><body><main>
<header><div class="eyebrow">PIXEL MATH · ART DIRECTION / 2026.09.08</div>
<h1>数字群岛，开始成形。</h1>
<p>浅奥数学解谜冒险的首套统一美术母版。苔藓遗迹、黄铜机关、青绿能量与羊皮纸界面，共用同一张风格参考，由内置 imagegen 分批生成。</p>
<div class="facts"><span>6 个主题章节</span><span>18 关数学规则已验算</span><span>9 类当前母版</span><span>最终引擎：Godot</span></div></header>
<div class="notice"><strong>本轮交付状态：策划与源图包 v1</strong>当前图片用于确定统一视觉和继续制作。主角修订版有真实透明通道；其余多数图仍带底色。切片、逐帧锚点、透明边缘与地形拼缝需在 Godot 素材整备阶段继续验证。原始图片未被本预览页面改写。</div>
<div class="toolbar"><span>查看透明图的底色：</span>
<label><input type="radio" name="matte" value="paper" checked> 羊皮纸</label>
<label><input type="radio" name="matte" value="white"> 纯白</label>
<label><input type="radio" name="matte" value="dark"> 深蓝</label></div>
<section class="grid">''' + "\n".join(cards) + '''</section>
<footer><a href="../docs/策划案-v1.md">完整策划案</a><a href="../docs/美术资源规范-v1.md">美术与 Godot 规格</a><a href="素材清单-v1.json">文件清单与实际检查</a><a href="../docs/首章关卡-v1.json">18 关规则</a><a href="../docs/关卡验算-v1.json">数学验算结果</a></footer>
</main><script>document.querySelectorAll('input[name="matte"]').forEach(input=>input.addEventListener('change',()=>{document.body.classList.remove('dark-matte','white-matte');if(input.value!=='paper')document.body.classList.add(input.value+'-matte')}));</script></body></html>'''
    (ROOT / "art/素材预览.html").write_text(page)
    print(json.dumps({"total_files": len(assets), "active_categories": sum(a["active"] for a in assets),
                      "copied_originals_verified": sum(a["copy_matches_generated_original"] is True for a in assets),
                      "with_alpha": [a["id"] for a in assets if a["alpha"]],
                      "non_integral_nominal_grids": [a["id"] for a in assets
                                                     if a["dimensions_divisible_by_nominal_grid"] is False]},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
