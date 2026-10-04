extends RefCounted
# 齿轮工坊的章节进度。航图补记；完成后直接重玩也先补记，避免重置现场抹去证据。
# 完成证据来自关卡自己的存档——枢纽回到航图时读取每一关的 stage，看到 complete 才补记，
# 因此关卡被跳过、被改坏或写坏了章节档都不会凭空多出灯火。
const Repository = preload("res://scripts/persistence/save_repository.gd")
const Numbers = preload("res://scripts/content/content_catalog.gd")
const Catalog = preload("res://scripts/workshop/chapter_catalog.gd")

var path = "user://profiles/workshop-chapter-v1/save-v1.json"
var repository = Repository.new()
var error = ""
var record = {"chapter": "workshop-v1", "completed": []}
# 检查与试玩可以把某一关的证据文件指到别处；默认仍读玩家自己的关卡存档。
var level_paths: Dictionary = {}

static func fresh() -> Dictionary:
	return {"chapter": "workshop-v1", "completed": []}

# 编号必须是本岛认得的关卡，且不重复；顺序由写入时按目录整理，读取时不假设。
static func validate(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or value.get("chapter") != "workshop-v1": return false
	var done = value.get("completed")
	if not done is Array: return false
	for id in done:
		if not id is String or not Catalog.exists(id) or done.count(id) > 1: return false
	return true

# 读写之前必须把仓库绑到本记录的落点上，否则它会用默认路径去碰别岛的手记。
func bind() -> void:
	repository.path = path

func load_record() -> String:
	error = ""
	bind()
	record = fresh()
	var read = repository.read_profile(validate)
	if read.status == "loaded": record = read.profile
	return read.status

func level_path(id: String) -> String: return level_paths.get(id, Catalog.save_path(id))

func level_finished(id: String) -> bool:
	var target = level_path(id)
	if not FileAccess.file_exists(target): return false
	var file = FileAccess.open(target, FileAccess.READ)
	if file == null: return false
	var parsed = Numbers.normalize_numbers(JSON.parse_string(file.get_buffer(file.get_length()).get_string_from_utf8()))
	file.close()
	# 只有当前版本的合法通关现场才算证据；单独写 stage=complete 不能点亮关卡。
	if not parsed is Dictionary or parsed.get("stage") != "complete": return false
	var rules = load("res://scripts/workshop/%s_rules.gd" % id.to_lower())
	return rules != null and rules.validate(parsed)

# 返回 true 表示这一趟确实补上了新的完成记录并已落盘。写入失败时内存保持不变。
func settle() -> bool:
	bind()
	var ids: Array = []
	for id in Catalog.order():
		if record.completed.has(id) or level_finished(id): ids.append(id)
	if ids == record.completed:
		error = ""
		return false
	var candidate = {"chapter": "workshop-v1", "completed": ids}
	if not repository.write_profile(candidate, validate):
		error = repository.error
		return false
	error = ""
	record = candidate
	return true

func completed() -> Array: return record.completed
func is_done(id: String) -> bool: return record.completed.has(id)
func is_open(id: String) -> bool: return Catalog.available(id, record.completed)
