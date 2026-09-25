extends RefCounted
# 齿轮工坊 18 关的目录：编号、幕次、场景、底景、存档路径、前置与一句话目标。
# 场景（kit）与底景取自原章节稿的「六幕与场景路线」与 art/workshop-art-v2/README.md：
# dock=错拍码头、assembly=双层装配间、corridor=旧报时廊、rooftop=屋顶修理街、engine=总机船坞。
# 这里是关卡身份的唯一来源：关卡自己的存档路径从 save_path() 取，未建的关卡由 built() 判成待制作。
# 幕次与路线取自 docs/production/workshop_chapter_olympiad.md 的「路线与难度节奏」：
# 主线 GW01→02→03→04→05→06→07→08→09→10→11→12→17→18，GW13～16 为可选支线。
const MAIN = ["GW01","GW02","GW03","GW04","GW05","GW06","GW07","GW08","GW09","GW10","GW11","GW12","GW17","GW18"]
const SIDE = ["GW13","GW14","GW15","GW16"]
const ACTS = {1:"错拍码头 · 找回货单",2:"两班之间",3:"装配间的拍子",4:"旧报时廊",5:"屋顶修理街",6:"总机船坞"}
const LEVELS = {
	"GW01": {"title":"被蒸汽抹去的货单","act":1,"kit":"dock","scene":"res://game/workshop_gw01.tscn",
		"save":"user://profiles/workshop-gw01-3/save-v1.json","after":"",
		"goal":"从三轮各 8 根倒推出甲、乙、丙的起始货单"},
	"GW02": {"title":"留样之后，还缺多少","act":1,"kit":"assembly","scene":"res://game/workshop_gw02.tscn",
		"save":"user://profiles/workshop-gw02-1/save-v1.json","after":"GW01",
		"goal":"补回两种留样，给 8 片铜料选模具，安装数恰好 27"},
	"GW03": {"title":"相遇了，还不能交接","act":2,"kit":"dock","scene":"res://game/workshop_gw03.tscn",
		"save":"user://profiles/workshop-gw03-1/save-v1.json","after":"GW02",
		"goal":"找吊台、小车与放行灯第一次同时成立的时刻"},
	"GW04": {"title":"两班船，都要赶上","act":2,"kit":"dock","scene":"res://game/workshop_gw04.tscn",
		"save":"user://profiles/workshop-gw04-1/save-v1.json","after":"GW03",
		"goal":"调整吊台起点，让两班船都在第 16 拍前接到货"},
	"GW05": {"title":"七拍能做完吗","act":3,"kit":"assembly","scene":"res://game/workshop_gw05.tscn",
		"save":"user://profiles/workshop-gw05-1/save-v1.json","after":"GW04",
		"goal":"排两条工序带，七拍内做完三件工具"},
	"GW06": {"title":"产量一样，工时不同","act":3,"kit":"assembly","scene":"res://game/workshop_gw06.tscn",
		"save":"user://profiles/workshop-gw06-1/save-v1.json","after":"GW05",
		"goal":"选炉次少、换模也少的产量组合，八拍内做出 31 枚扣环"},
	"GW07": {"title":"检修前，先留好位置","act":3,"kit":"assembly","scene":"res://game/workshop_gw07.tscn",
		"save":"user://profiles/workshop-gw07-1/save-v1.json","after":"GW06",
		"goal":"检修前留好暂存位，第 11 拍完成全部四件"},
	"GW08": {"title":"两张旧单，锁定一块槽板","act":4,"kit":"corridor","scene":"res://game/workshop_gw08.tscn",
		"save":"user://profiles/workshop-gw08-1/save-v1.json","after":"GW07",
		"goal":"用两张旧记录锁定一块槽板的槽数"},
	"GW09": {"title":"既不漏灯，也不错站","act":4,"kit":"corridor","scene":"res://game/workshop_gw09.tscn",
		"save":"user://profiles/workshop-gw09-1/save-v1.json","after":"GW08",
		"goal":"找既不漏灯、第 3 站又停在 9 号灯的步长"},
	"GW10": {"title":"最急的那单，为什么不能先开","act":4,"kit":"rooftop","scene":"res://game/workshop_gw10.tscn",
		"save":"user://profiles/workshop-gw10-1/save-v1.json","after":"GW09",
		"goal":"把到料时间算进去，排出一张全不逾期的顺序"},
	"GW11": {"title":"两张船票，倒排到同一张台","act":5,"kit":"dock","scene":"res://game/workshop_gw11.tscn",
		"save":"user://profiles/workshop-gw11-1/save-v1.json","after":"GW10",
		"goal":"两张船票倒排到同一张装配台"},
	"GW12": {"title":"两班合起来，槽数才找得到","act":5,"kit":"rooftop","scene":"res://game/workshop_gw12.tscn",
		"save":"user://profiles/workshop-gw12-1/save-v1.json","after":"GW11",
		"goal":"先看两班总账，再还原每班交了多少满托"},
	"GW13": {"title":"两只鸟，到底叫了几次","act":2,"kit":"corridor","scene":"res://game/workshop_gw13.tscn",
		"save":"user://profiles/workshop-gw13-1/save-v1.json","after":"GW04","side":true,
		"goal":"数清有几个时刻听到叫声，其中几个只有一只鸟"},
	"GW14": {"title":"第三张记录才有用","act":4,"kit":"rooftop","scene":"res://game/workshop_gw14.tscn",
		"save":"user://profiles/workshop-gw14-1/save-v1.json","after":"GW08","side":true,
		"goal":"用第三张记录排除前两张留下的候选"},
	"GW15": {"title":"最早的一次观察","act":4,"kit":"corridor","scene":"res://game/workshop_gw15.tscn",
		"save":"user://profiles/workshop-gw15-1/save-v1.json","after":"GW09","side":true,
		"goal":"选最早的一次观察，一次分清三种周期"},
	"GW16": {"title":"找全四种午休曲","act":5,"kit":"rooftop","scene":"res://game/workshop_gw16.tscn",
		"save":"user://profiles/workshop-gw16-1/save-v1.json","after":"GW12","side":true,
		"goal":"找全四种互不相同的午休铃句"},
	"GW17": {"title":"巡轨兽 · 空出第一拍","short":"巡轨兽","act":6,"kit":"engine","scene":"res://game/workshop_gw17.tscn",
		"save":"user://profiles/workshop-gw17-1/save-v1.json","after":"GW12",
		"goal":"给四辆车排出唯一一张完整时刻表"},
	"GW18": {"title":"百臂总机 · 两种船期，一套准备","short":"百臂总机","act":6,"kit":"engine","scene":"res://game/workshop_gw18.tscn",
		"save":"user://profiles/workshop-gw18-1/save-v1.json","after":"GW17",
		"goal":"一套计划同时应付早晚两班，第 10 拍开船"},
}
# 航图顺序：主线十四关在前，第三行是四条支线与两位首领。
const ALL = ["GW01","GW02","GW03","GW04","GW05","GW06","GW07","GW08","GW09","GW10","GW11","GW12",
	"GW13","GW14","GW15","GW16","GW17","GW18"]
const ISLAND_SCENE = "res://game/workshop_island.tscn"

static func exists(id: String) -> bool: return LEVELS.has(id)
static func title(id: String) -> String: return LEVELS[id].title
# 卡片只放得下两行标题，首领关的副题留在提示与目标里。
static func card_title(id: String) -> String: return LEVELS[id].get("short", LEVELS[id].title)
static func goal(id: String) -> String: return LEVELS[id].goal
static func scene(id: String) -> String: return LEVELS[id].scene
static func save_path(id: String) -> String: return LEVELS[id].save
static func is_side(id: String) -> bool: return LEVELS[id].get("side", false)
static func act(id: String) -> int: return LEVELS[id].act
static func act_name(id: String) -> String: return ACTS[LEVELS[id].act]
static func kit(id: String) -> String: return LEVELS[id].kit

# 关卡还没有场景文件时，航图把它标成待制作，而不是给玩家一个空房间。
static func built(id: String) -> bool: return ResourceLoader.exists(LEVELS[id].scene)

static func order() -> Array: return ALL.duplicate()
static func main_pending(completed: Array) -> Array:
	var missing: Array = []
	for id in MAIN:
		if not completed.has(id): missing.append(id)
	return missing

# 支线不挡主线：前置只决定它什么时候开门。
static func opens_after(id: String) -> String: return LEVELS[id].after

static func next_main(completed: Array) -> String:
	for id in MAIN:
		if not completed.has(id): return id
	return ""

static func available(id: String, completed: Array) -> bool:
	var gate = opens_after(id)
	return gate.is_empty() or completed.has(gate)
