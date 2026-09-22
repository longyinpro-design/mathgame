extends RefCounted
# 「发现卡」：把玩家在这一关已经做对的动作，命名成一个能带走的方法。
#
# 与 thinking_contract.insight 分开维护。insight 是写给审稿人的设计意图，里面会出现
# 「互斥且穷尽」「不变式」和 C(4,2)=6 这类语言，也带坐标；发现卡的对象是三到四年级的
# 孩子，一律用日常词。两者说的是同一件事，但读的人不同，所以不共用一份文案。
#
# 写新卡时的四条约束（tests 会逐条检查，见 check_discovery_cards）：
#   1. name 是三到六个字、动词开头的短语，孩子看完能照着做；
#   2. explain 不超过 40 字、最多两句，不出现坐标、组合数、± 和英文缩写；
#   3. concept 必须是该关 concept_ids 里真实存在的一项，否则回指会指到空气；
#   4. explain 里出现的每个数字都要能在该关 params 或规则里核对出来。
#      这一条踩过坑：FL04 的合重是 29/35/30（总量 47），11/13/12 只是
#      content_catalog 里 LEGACY_RESULT_PARAMS 的旧档兼容值，写进卡片就是错的。
#
# 一关只命名一个概念。有两个概念的关卡（FL02 的平衡守恒与逆推、FL14 的奇偶与步数）
# 只取最核心的那一个，另一个留到它成为主概念的关卡再命名——一次教一个。
#
# 尚未命名的关卡返回空字典，结算横幅保持旧的 172 高度，不占位置。

# 一关只写一张卡，主概念取该关最核心的那一个。十八关的主概念互不重复，
# 所以每个概念恰好在它第一次出现的那一关被命名——重复出现的概念（平衡守恒、
# 逆推、操作顺序、信息选择、优化）留到各自的首次出场再命名，不在同一关讲两个。
const CARDS = {
	"FL01": {"name":"比一比两边", "concept":"balance_conservation",
		"explain":"吊篮只看两边谁更重。一边重就往下走，一样重就不动。"},
	"FL02": {"name":"倒着走", "concept":"reverse_state",
		"explain":"不知道开头是几，就从最后的8、8、8往回走，每步做相反的事。"},
	"FL03": {"name":"先问是哪一刻", "concept":"temporal_constraints",
		"explain":"两句「一样多」说的不是同一时刻。搬完第一趟看一次，搬完第二趟再看一次。"},
	"FL04": {"name":"一样的换着比", "concept":"equal_substitution",
		"explain":"三架灯每架都称了两次。三条合重加起来再分成两半，就是三架一共多重。"},
	"FL05": {"name":"两条一起看", "concept":"constraint_intersection",
		"explain":"一台机器要同时满足两条记录。只看一条还剩两种装法，两条一起看才只剩一种。"},
	"FL06": {"name":"挑个能分开的", "concept":"information_choice",
		"explain":"只能试一次。挑一个让三台算出不同答案的数：投2或5都会有两台撞上。"},
	"FL07": {"name":"先凑一个新数", "concept":"arithmetic_composition",
		"explain":"两张牌直接相乘到不了24。先把两张合起来，再用新数去乘或加。"},
	"FL08": {"name":"一袋一袋数", "concept":"exhaustive_partition",
		"explain":"按第一次往右的高度分袋子。每袋该装几条是定死的：6、3、1，合起来10条。"},
	"FL09": {"name":"比一比剩几条", "concept":"optimization",
		"explain":"石头只挡住经过它的路。四处各剩下几条，要一处一处比过才知道哪里最好。"},
	"FL10": {"name":"先分两拨", "concept":"joint_constraints",
		"explain":"每封信不是先往右就是先往上。同一拨的两封会撞在同一个路口，所以最多两封。"},
	"FL11": {"name":"留够下一趟的", "concept":"irreversible_resources",
		"explain":"四件货三趟送完，必有一趟装两件。配重用掉就没了，替后面那一趟先留好。"},
	"FL12": {"name":"凑够一组", "concept":"strategy_blocks",
		"explain":"每次能拿1到3颗，就凑够4颗当一组。对手拿几颗，你补到4颗。"},
	"FL13": {"name":"先算最少几趟", "concept":"lower_bound",
		"explain":"一趟只有一个篮子能到顶，最多送两件。三件货至少要两趟。"},
	"FL14": {"name":"只看单双数", "concept":"parity_invariant",
		"explain":"每步加2或减2，只会停在双数上；要停在9，得先把一步换成加1或减1。"},
	"FL15": {"name":"先分成三份", "concept":"decision_tree",
		"explain":"天平每次只有三种结果。把9颗先分成3、3、3，一种结果管一份，两次就够。"},
	"FL16": {"name":"围一围比一比", "concept":"area_perimeter",
		"explain":"篱笆一样长，围出的地不一定一样大。把每种宽都试一遍，3乘6最大。"},
	"FL17": {"name":"先想最后一步", "concept":"reverse_planning",
		"explain":"三枚符石都要用完，最后同时到7。先想好最后一步要的局面，再往回安排前面。"},
	"FL18": {"name":"留够合击的", "concept":"resource_reservation",
		"explain":"试探一次就少一些种子，合击那一步也要花种子。先算好留多少，再决定试几次。"},
}

# 每句最多 40 字：横幅里解释文字排在 940 宽的版面上，22 号字一行放得下 42 个汉字。
# 超过就会折成第二行、压到下面那行回指上。
const EXPLAIN_LIMIT = 40
# 「倒着走」是三个字，也够用；下限定在 3，上限 6——七个字的名字在 320 宽的版面上
# 会挤到解释那一栏去。
const NAME_MIN = 3
const NAME_MAX = 6

static func card(id: String) -> Dictionary:
	return CARDS[id].duplicate(true) if CARDS.has(id) else {}

static func has_card(id: String) -> bool:
	return CARDS.has(id)

# 第 3 行：这一招还在哪儿用过。
# 只有真实数据才写出来，不编造预告。已通关的关卡直接点名；还没走到的，
# 点名最先遇到的那一关——「还会在后面的机关里用到」对三年级等于没说，
# 而关卡名本来就在地图上，不是剧透。一次都没复现过就如实说是第一次。
static func cross_reference(id: String, concept: String, levels: Dictionary, completed: Array) -> String:
	if not CARDS.has(id) or concept.is_empty() or levels.is_empty(): return ""
	var name: String = CARDS[id].name
	var named: Array = []
	var upcoming = ""
	for level_id in levels:
		if level_id == id: continue
		if concept not in levels[level_id].concept_ids: continue
		if level_id in completed: named.append(levels[level_id].title)
		elif upcoming == "": upcoming = levels[level_id].title
	if not named.is_empty():
		return "「%s」还能用在：%s。" % [name, "、".join(named.slice(0,2))]
	if upcoming != "":
		return "「%s」在后面的「%s」还要用到。" % [name, upcoming]
	return "这是你第一次用到它。"

# 校验：把写错的地方指名报出来，而不是返回一个 false。
# 返回空数组表示这份卡片可以用。
# entry 只在测试里传：用来把一份写坏的卡片喂进来，确认拦得住，
# 因为 CARDS 是常量，改不动。
static func check(definition: Dictionary, entry: Dictionary = {}) -> Array:
	var problems: Array = []
	var id: String = definition.get("id","")
	if entry.is_empty():
		if not CARDS.has(id): return problems
		entry = CARDS[id]
	var name: String = entry.get("name","")
	var concept: String = entry.get("concept","")
	var explain: String = entry.get("explain","")
	if name.length() < NAME_MIN or name.length() > NAME_MAX: problems.append("%s 名字要三到六个字，现在是「%s」。" % [id,name])
	if explain.is_empty(): problems.append("%s 缺解释。" % id)
	if explain.length() > EXPLAIN_LIMIT: problems.append("%s 解释 %d 字，超过 %d 字。" % [id,explain.length(),EXPLAIN_LIMIT])
	if concept not in definition.get("concept_ids",[]): problems.append("%s 的主概念「%s」不在这一关的 concept_ids 里。" % [id,concept])
	for banned in ["C(","(1,0)","(0,1)","±","不变量","奇偶","穷尽","下界","组合"]:
		if banned in explain or banned in name: problems.append("%s 出现了给孩子看不该出现的词「%s」。" % [id,banned])
	return problems
