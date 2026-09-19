extends RefCounted
# Art-space anchors (1280 x 720). No visible replacement floor is generated.
const FEET_Y = {"treetop":592.0,"camp":592.0,"village":537.0,"mill":515.0,"post":358.0,"heart":520.0}
const POINTS = {
	"treetop":[Vector2(184,565),Vector2(1110,565)],
	"village":[Vector2(126,447),Vector2(824,410)],
	"mill":[Vector2(815,425),Vector2(1045,425),Vector2(937,425),Vector2(625,320)],
	"post":[Vector2(327,321),Vector2(610,334),Vector2(1147,304),Vector2(159,320),Vector2(494,341)],
	"heart":[Vector2(400,445),Vector2(1045,390),Vector2(835,480),Vector2(646,345),Vector2(885,444)]}
const DETAIL_LEVELS = ["FL05","FL06","FL07","FL08","FL09","FL10","FL12","FL14","FL15","FL16"]
static func point(region: String, index: int) -> Vector2:
	return POINTS[region][index]
static func foot(region: String, x: float) -> Vector2:
	return Vector2(clampf(x,90,670 if region == "post" else 1190),FEET_Y[region])
static func party(region: String, level: String = "") -> Dictionary:
	if region == "heart" and level == "FL02":
		return {"hero":Vector2(126,455),"acheng":Vector2(201,486),"mossling":Vector2(175,526),"feather":Vector2(295,590)}
	var start = 180.0 if region == "post" else (340.0 if region == "mill" else (230.0 if region == "heart" else 265.0))
	if region == "post" and level in ["FL08","FL14"]: start = 460
	var feet = {}
	for i in range(4): feet[["hero","acheng","mossling","feather"][i]] = foot(region,start+i*77)
	return feet
static func npc_foot(region: String) -> Vector2:
	return foot(region,670 if region == "post" else (1140 if region != "treetop" else 950))
static func detail_title(id: String) -> String:
	return {"FL05":"育苗机 · 打开检修册","FL06":"育苗机 · 核对试机记录","FL07":"育苗机 · 近看能量槽","FL08":"邮路石碑 · 展开邮袋清单","FL09":"落石路口 · 展开路线图","FL10":"崖边邮站 · 展开送信图","FL12":"守门人 · 俯看棋盘","FL14":"林间石阶 · 查看步数记录","FL15":"吊秤 · 近看晶体盒","FL16":"旧墙边 · 展开围栏草图"}.get(id,"近看机关")
