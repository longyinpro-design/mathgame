# v0.3 样板生成提示词

方法：内置 image_gen。生成结果原像素保留；运行时切片由 AtlasTexture 引用，不用本地算法改写图片。

## arena.png

Production game background, 16:9 landscape 1536x864. A beautiful original 2D HD pixel art RPG encounter stage in a mossy enchanted forest ruin at blue-hour, jewel teal, deep indigo, warm amber lanterns. Rich polished pixel clusters, exquisite atmospheric depth, readable uncluttered middle ground, camera side view slightly elevated like a premium 2D JRPG battle stage. The entire lower middle from x10% to95%, y50% to82% is broad walkable weathered stone terrace with subtle circular engraved pattern, not a UI. Ancient large arched sealed doorway stands at x66%, y25% to56% in background, its interior dark turquoise and mysterious, pillars and roots around it. Left side foreground leaves frame a path for hero entry; right side forest canopy. Upper third layered tree silhouettes, hanging lanterns, shafts of cool moonlight. Small golden plants and mushrooms around edges. NO characters, NO creatures, NO UI, NO text, NO digits, NO glowing shield objects. Leave most central floor clear for separately animated hero, huge stone creature and floating energy objects. Dramatic but welcoming children's adventure. Strong silhouette hierarchy, dark foreground corners, brighter central stage. Cohesive artwork ready for a commercial indie game, not a sketch, no mockup borders.

## objects.png

Production sprite atlas for original polished 2D HD pixel art RPG, genuinely transparent RGBA background. EXACTLY four isolated assets in a clean 2 by 2 grid, equal 512x512 cells, total image1024x1024, no borders, no text no numbers no labels. Each sprite centered in its cell with generous 35px clear transparent margin, never overlap. TOP LEFT: full-body large friendly ancient stone guardian, broad mossy boulder body, thick separate rock arms, short legs, small carved face with bright warm amber eyes, teal rune embedded chest, little fern on head, facing slightly LEFT three-quarter, fully visible grounded feet, no ground shadow. TOP RIGHT: ornate hovering energy shield, vertical oval teal glass membrane inside a bronze and weathered stone frame, clear central translucent teal surface, front view, no symbols resembling text, small glowing gold diamond on rim. BOTTOM LEFT: single beautiful large turquoise faceted energy crystal, upright elongated diamond, golden inner heart, crisp light catching facets, no external glow cloud. BOTTOM RIGHT: collectible guardian sigil medal, round antique bronze and mossy stone border around a gold leaf emblem, short teal ribbon, attractive RPG reward icon. Consistent crisp pixel clusters matching high-end indie pixel art, directional warm light from upper-left, deep blue-gray shadows, readable at small size, opaque sprite interiors except the glass shield, fully transparent outside sprites, NO checkerboard background, NO ground plane.

## cast.png

A single full-body transparent-background PNG game sprite of a young male adventurer with short brown hair, teal flowing cape, ochre tunic, navy trousers, brown boots and brown satchel. Facing right, dynamic spell-casting stance, both feet braced, right arm extended forward, left arm balancing behind, cape flowing left. Small turquoise magical orb in extended hand. Beautiful crisp pixel art, expressive face, polished 2D RPG character, 3/4 side view. Isolated cutout with alpha transparency. Only one character. No scenery. Entire body visible, margins around hands and boots.

## victory.png

A single full-body transparent-background PNG game sprite of a young boy adventurer with short brown hair, teal cape, ochre tunic, navy trousers, brown boots and satchel. Facing slightly right, jubilant victory pose with one fist raised overhead, eyes smiling, feet on ground. Cute expressive polished 2D RPG pixel art, crisp detailed pixel clusters, opaque character isolated with alpha transparency. Entire body visible with margins, no scenery, only one character.

## fox-cast.png

A single transparent-background PNG game sprite of a cute orange fox companion with cream muzzle and tail tip, teal scarf, standing on four paws and facing right. Crouched forward, ears alert, scarf waving left, bright golden turquoise magic gathering at its forward paws, excited determined expression. Original polished 2D RPG pixel art character, crisp pixel clusters, full body isolated cutout with real alpha transparency. Entire fox and magic visible with margins. Only one character, no environment.

## 被弃用的动作表

此前生成六姿态主角表与四姿态狐狸表，实测为RGB且棋盘底烘焙在像素中；两次内置提取修订仍未得到alpha。因此这些图未接入运行时。初稿留在 `art/rejected/v3/` 以便追溯；最终改用上述真实RGBA立绘与既有场内精灵。
