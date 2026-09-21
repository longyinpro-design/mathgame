extends RefCounted
# 千灯集市 18 关的目录：编号、幕次、场景、kit-v1 底景、存档路径、前置与一句话目标。
# 这里是关卡身份的唯一来源；关卡自己的存档路径也从这里取，枢纽才能观察完成状态。
const MAIN = ["MK01","MK02","MK03","MK04","MK05","MK06","MK07","MK08","MK09","MK10","MK11","MK12","MK17","MK18"]
const SIDE = ["MK13","MK14","MK15","MK16"]
const ACTS = {1:"两种杯子的争吵",2:"扣扣没有偷东西",3:"每家都还缺一点",4:"没有人收到的回信",5:"公平不只是一样多",6:"今夜，灯往海上走"}
const LEVELS = {
	"MK01": {"title":"找回杯子的刻度","act":1,"kit":"harbor","scene":"res://game/market_mk01.tscn",
		"save":"user://profiles/market-mk01-2/save-v2.json","after":"",
		"goal":"比较两张混合装法的差量，推断蓝白杯各自的容量"},
	"MK02": {"title":"回礼要留下一段线","act":1,"kit":"nursery","scene":"res://game/market_mk02.tscn",
		"save":"user://profiles/market-mk02-1/save-v1.json","after":"MK01",
		"goal":"整组兑换，交足 5 根灯芯又留下 2 卷捆货绳"},
	"MK03": {"title":"封箱里的重量","act":2,"kit":"nursery","scene":"res://game/market_mk03.tscn",
		"save":"user://profiles/market-mk03-1/save-v1.json","after":"MK02",
		"goal":"叠合两份称量、消去相同组，给红蓝箱挂上真实重量"},
	"MK04": {"title":"不可能兑现的收据","act":2,"kit":"nursery","scene":"res://game/market_mk04.tscn",
		"save":"user://profiles/market-mk04-1/save-v1.json","after":"MK03",
		"goal":"沿两条原约实换一遍，指出转抄收据错在哪"},
	"MK05": {"title":"四张被雨打湿的货签","act":3,"kit":"street","scene":"res://game/market_mk05.tscn",
		"save":"user://profiles/market-mk05-1/save-v1.json","after":"MK04",
		"goal":"用留下的线索把四箱货配回四个去处"},
	"MK06": {"title":"十根灯芯怎么凑","act":3,"kit":"street","scene":"res://game/market_mk06.tscn",
		"save":"user://profiles/market-mk06-1/save-v1.json","after":"MK05",
		"goal":"19 张筹票恰好买满 10 根灯芯"},
	"MK07": {"title":"先别把东西平均分","act":3,"kit":"street","scene":"res://game/market_mk07.tscn",
		"save":"user://profiles/market-mk07-1/save-v1.json","after":"MK06",
		"goal":"让四位居民都拿到用得上的那一件"},
	"MK08": {"title":"多出来的三瓶油","act":4,"kit":"street","scene":"res://game/market_mk08.tscn",
		"save":"user://profiles/market-mk08-1/save-v1.json","after":"MK07",
		"goal":"对齐单位，撤下重复副本、补回漏掉的单号"},
	"MK09": {"title":"不必两个人就换成","act":4,"kit":"street","scene":"res://game/market_mk09.tscn",
		"save":"user://profiles/market-mk09-1/save-v1.json","after":"MK08",
		"goal":"牵起交换线，让五摊一次换完且各自满意"},
	"MK10": {"title":"无论回哪封信","act":4,"kit":"dock","scene":"res://game/market_mk10.tscn",
		"save":"user://profiles/market-mk10-1/save-v1.json","after":"MK09",
		"goal":"选一条能同时覆盖两种订单箱数的船"},
	"MK11": {"title":"砝码也能站在货物旁","act":5,"kit":"oil","scene":"res://game/market_mk11.tscn",
		"save":"user://profiles/market-mk11-1/save-v1.json","after":"MK10",
		"goal":"用 1、3、9 三枚砝码称出恰好 7 单位灯油"},
	"MK12": {"title":"不一样多，也都够用","act":5,"kit":"oil","scene":"res://game/market_mk12.tscn",
		"save":"user://profiles/market-mk12-1/save-v1.json","after":"MK11",
		"goal":"按三处各自的需要分封油，一壶不剩"},
	"MK13": {"title":"扣扣的旧围巾","act":2,"kit":"nursery","scene":"res://game/market_mk13.tscn",
		"save":"user://profiles/market-mk13-1/save-v1.json","after":"MK04","side":true,
		"goal":"整包摊满对折样边尺的 11 格，且对折两头齐"},
	"MK14": {"title":"三枚砝码的小摊","act":5,"kit":"oil","scene":"res://game/market_mk14.tscn",
		"save":"user://profiles/market-mk14-1/save-v1.json","after":"MK11","side":true,
		"goal":"只许挪一枚砝码，把 4、7、13 三单依次配平"},
	"MK15": {"title":"不会越换越多的铜果","act":4,"kit":"street","scene":"res://game/market_mk15.tscn",
		"save":"user://profiles/market-mk15-1/save-v1.json","after":"MK09","side":true,
		"goal":"实演一个闭环，回到 12 颗铜果"},
	"MK16": {"title":"给森林寄回一份礼物","act":5,"kit":"dock","scene":"res://game/market_mk16.tscn",
		"save":"user://profiles/market-mk16-1/save-v1.json","after":"MK12","side":true,
		"goal":"挑 3 样纪念物，带上绿叶章和信纸"},
	"MK17": {"title":"铜鹭巡守 · 三次验货","short":"铜鹭巡守","act":6,"kit":"dock","scene":"res://game/market_mk17.tscn",
		"save":"user://profiles/market-mk17-1/save-v1.json","after":"MK12",
		"goal":"三次验货：用有限的重新封装通过三个码头的装载约定"},
	"MK18": {"title":"万签守约兽 · 让每一盏灯都有回信","short":"万签守约兽","act":6,"kit":"dock","scene":"res://game/market_mk18.tscn",
		"save":"user://profiles/market-mk18-1/save-v1.json","after":"MK17",
		"goal":"让每一盏灯都有回信：一次联合采购，按实际更正回执完成三街交付"},
}
# 航图上的顺序：18 关按编号排，主线十二关占前两行，第三行是四条支线与两场首领。
const ALL = ["MK01","MK02","MK03","MK04","MK05","MK06","MK07","MK08","MK09","MK10","MK11","MK12",
	"MK13","MK14","MK15","MK16","MK17","MK18"]
const ISLAND_SCENE = "res://game/market_island.tscn"

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
