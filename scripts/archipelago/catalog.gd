extends RefCounted
# Authored content identity; no mutable player state.
const ISLANDS = ["forest","market","workshop","geometry","fractions","observatory"]
const PREFIXES = {"forest":"FL","market":"MK","workshop":"GW","geometry":"GV","fractions":"FW","observatory":"SO"}
const NAMES = {"forest":"森林来信","market":"千灯集市","workshop":"齿轮工坊","geometry":"几何山谷","fractions":"分数水庭","observatory":"星穹观测台"}
const COLORS = {"forest":Color("588c64"),"market":Color("bf8f42"),"workshop":Color("708b91"),"geometry":Color("ad9173"),"fractions":Color("4faaaa"),"observatory":Color("7578b8")}
const ForestCatalog = preload("res://scripts/content/content_catalog.gd")
const MarketCatalog = preload("res://scripts/market/chapter_catalog.gd")
const WorkshopCatalog = preload("res://scripts/workshop/chapter_catalog.gd")
static var definitions: Dictionary = {}
static var rule_instances: Dictionary = {}
static var forest_content: RefCounted
const NEW = ["geometry","fractions","observatory"]
const PARTNERS = {"acheng":"阿橙","mossling":"苔团","feather":"折羽","koukou":"扣扣","tata":"嗒嗒","lingjiao":"棱角","shuimo":"水沫","xinglu":"星鹭"}
const JOIN_AFTER = {"mossling":"FL02","feather":"FL08","koukou":"MK04","tata":"GW04","lingjiao":"GV04","shuimo":"FW04","xinglu":"SO04"}

static func island_for(id: String) -> String:
	for island in ISLANDS:
		if id.begins_with(PREFIXES[island]): return island
	return ""

static func ids(island: String = "") -> Array:
	var result: Array = []
	for place in ISLANDS:
		if not island.is_empty() and island != place: continue
		for index in range(1,19): result.append(PREFIXES[place]+"%02d"%index)
	return result

static func exists(id: String) -> bool:
	var island = island_for(id)
	return not island.is_empty() and id.length()==4 and id.substr(2).is_valid_int() and int(id.substr(2)) in range(1,19) and id == PREFIXES[island]+"%02d"%int(id.substr(2))
static func is_new(id: String) -> bool: return island_for(id) in NEW
static func is_side(id: String) -> bool: return int(id.substr(2)) in [13,14,15,16]
static func mains(island: String) -> Array:
	return ids(island).filter(func(id): return not is_side(id))

static func definition(id: String) -> Dictionary:
	if not definitions.has(id):
		var loaded = load_definition(id)
		if not loaded.is_empty(): definitions[id] = loaded
	return definitions.get(id,{}).duplicate(true)

static func load_definition(id: String) -> Dictionary:
	if not exists(id): return {}
	var island = island_for(id)
	if island in NEW:
		var path = "res://scripts/%s/catalog.gd"%island
		if not ResourceLoader.exists(path): return {}
		return load(path).definition(id)
	if island == "forest":
		if forest_content == null: forest_content = ForestCatalog.new()
		var source = forest_content.definition(id)
		return {"id":id,"island":island,"title":source.title,"goal":source.get("goal",source.title),"act":mini(6,1+int(id.substr(2))/3),"side":is_side(id),
			"prerequisites":source.prerequisites_all,"concept_ids":source.concept_ids,"reward":{"id":source.reward.id,"experience":source.reward.journey_exp,"keepsake":"森林手记 · "+source.title},
			"scene":"res://game/forest_release.tscn"}
	var source = MarketCatalog.LEVELS[id] if island == "market" else WorkshopCatalog.LEVELS[id]
	return {"id":id,"island":island,"title":source.title,"goal":source.goal,"act":source.act,"side":is_side(id),"prerequisites":[] if source.after.is_empty() else [source.after],
		"concept_ids":["equivalence" if island == "market" else "temporal_planning"],"reward":{"id":"archipelago-"+id,"experience":20 if int(id.substr(2)) >= 17 else 10,"keepsake":NAMES[island]+" · "+source.title},"scene":source.scene}

static func rules_for(id: String) -> RefCounted:
	if not is_new(id): return null
	var path = "res://scripts/%s/rules.gd"%island_for(id)
	if not rule_instances.has(id) and ResourceLoader.exists(path): rule_instances[id] = load(path).new(definition(id))
	return rule_instances.get(id)

static func all_main_done(island: String, completed: Array) -> bool:
	for id in mains(island):
		if id not in completed: return false
	return true

static func island_open(island: String, completed: Array) -> bool:
	var index = ISLANDS.find(island)
	return index == 0 or (index > 0 and all_main_done(ISLANDS[index-1],completed))

static func available(id: String, completed: Array) -> bool:
	if not exists(id): return false
	if id in completed: return true
	var d = definition(id)
	if d.is_empty() or not island_open(d.island,completed): return false
	for prerequisite in d.prerequisites:
		if prerequisite not in completed: return false
	return true

static func next_main(completed: Array) -> String:
	for island in ISLANDS:
		for id in mains(island):
			if id not in completed and available(id,completed): return id
	return ""

static func roster_for(completed: Array) -> Array:
	var found: Array = ["acheng"]
	for partner in JOIN_AFTER:
		if JOIN_AFTER[partner] in completed: found.append(partner)
	return found
