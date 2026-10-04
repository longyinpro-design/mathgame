extends "res://scripts/market/level_host.gd"
# 齿轮工坊共用宿主：存档事务、撤销、提示与演出生命周期继续复用集市宿主，
# 章专属行为收口在这里：工坊独立往返桥，不消费千灯航图的 Bridge.origin、
# 提醒署上嗒嗒的名字，并在世界之上、按钮之下挂一个常驻的小岚。
# GW02 起的新关卡直接 extends 本文件，不要再逐关复制 _ready()/_process()。
const WorkshopBridge = preload("res://scripts/workshop/workshop_bridge.gd")
const WorkshopCatalog = preload("res://scripts/workshop/chapter_catalog.gd")
const WorkshopProgress = preload("res://scripts/workshop/chapter_progress.gd")
var navigating = false
const Companion = preload("res://scripts/workshop/companion.gd")
const Chime = preload("res://scripts/workshop/chime.gd")
var companion: Node2D
# 音效：报时铃、合鸣、午休铃三套都在运行期合成，见 chime.gd。
var chime_players: Array[AudioStreamPlayer] = []
var chime_cache: Dictionary = {}

func chapter_label() -> String: return "齿轮工坊"
func consumes_origin() -> bool: return false
# 集市现场提醒来自扣扣；工坊的现场提醒来自嗒嗒。
func hint_label() -> String: return "请嗒嗒提醒"
# 小岚的落脚点：默认站在左下角石面上；关卡可覆写成别的落点，Vector2.ZERO 表示本关世界自己画。
func companion_foot() -> Vector2: return Vector2(110,620)
# 有些现场底部只剩一条窄带，关卡可以把她缩小一点站进去。
func companion_scale() -> float: return 1.0

func _ready() -> void:
	origin = WorkshopBridge.origin
	WorkshopBridge.origin = ""
	# Configure once to resolve this scene's identity before applying explicit test paths.
	configure()
	if WorkshopBridge.level_paths.has(level_id): save_path = WorkshopBridge.level_paths[level_id]
	super()
	companion = Companion.new()
	companion.foot = companion_foot()
	companion.scale_factor = companion_scale()
	add_child(companion)
	# 世界先画，小岚压在世界之上；ui 与 overlay 后画，按钮和弹窗仍在她之上。
	move_child(companion,world.get_index()+1)
	# 六路铃够逐拍排铃用：每一拍一声，前一声的尾音还叠着。
	for index in range(6):
		var player = AudioStreamPlayer.new()
		player.volume_db = -9.0
		add_child(player)
		chime_players.append(player)

# ---- 工坊音效（运行期合成，见 chime.gd）----

func chime_play(stream: AudioStreamWAV) -> void:
	# 排铃的定时器可能在这一关被卸载之后才响：不在树上就不播，免得引擎报播放错。
	if stream == null or not is_inside_tree(): return
	for player in chime_players:
		if not player.playing:
			player.stream = stream
			player.play()
			return

func chime_strike(freq: float = 783.99) -> void:
	var key = "strike_%d"%roundi(freq)
	if not chime_cache.has(key): chime_cache[key] = Chime.strike(freq)
	chime_play(chime_cache[key])

func chime_bell() -> void:
	if not chime_cache.has("bell"): chime_cache["bell"] = Chime.bell()
	chime_play(chime_cache["bell"])

func chime_duet() -> void:
	if not chime_cache.has("duet"): chime_cache["duet"] = Chime.duet()
	chime_play(chime_cache["duet"])

func chime_lunch() -> void:
	if not chime_cache.has("lunch"): chime_cache["lunch"] = Chime.lunch()
	chime_play(chime_cache["lunch"])

func chime_stop() -> void:
	for player in chime_players: player.stop()

# 到点再敲：整段午休曲与整圈报时都靠这个排队，不阻塞演出。
func chime_at(delay: float, freq: float) -> void:
	if delay <= 0.0:
		chime_strike(freq); return
	get_tree().create_timer(delay).timeout.connect(chime_strike.bind(freq))

# 午休曲试听：每段按拍数一拍拍敲出来，2/3/4 拍各一个音；整首 12 拍正好一遍。
func chime_tune(segments: Array, per_beat: float = 0.3) -> void:
	chime_stop()
	var at = 0.0
	for length in segments:
		var freq = Chime.note(int(length))
		for beat in range(int(length)):
			chime_at(at,freq)
			at += per_beat

# 报时一圈：从低到高走一遍，收尾 12 盏灯。
func chime_scale(steps: int, per_beat: float = 0.28) -> void:
	chime_stop()
	for index in range(steps):
		chime_at(index*per_beat,587.33*pow(2.0,float(index)/float(maxi(steps,1))))

# Every workshop scene can leave even during dialogue or animation. The pending
# save modal blocks navigation, so only committed state can be left behind.
func refresh() -> void:
	super()
	add_workshop_navigation()

func add_workshop_navigation() -> void:
	if origin != "workshop_hub": return
	add_button("back_hub","返回工坊航图",Rect2(24,98,200,46),go_hub).disabled = modal or navigating

func go_hub() -> void:
	if modal or navigating or origin != "workshop_hub": return
	navigating = true
	chime_stop()
	var result = get_tree().change_scene_to_file(WorkshopCatalog.ISLAND_SCENE)
	if result != OK:
		navigating = false
		message = "暂时无法返回航图，已保存的现场仍保留。"
		refresh()

# A completed level may be replayed before returning to the hub. Persist its
# completion first, otherwise resetting its local save would lose that evidence.
func restart() -> void:
	if origin == "workshop_hub" and state.stage == "complete":
		var progress = WorkshopProgress.new()
		if not WorkshopBridge.progress_path.is_empty(): progress.path = WorkshopBridge.progress_path
		progress.level_paths = WorkshopBridge.level_paths.duplicate()
		var status = progress.load_record()
		if status == "protected":
			show_modal("工坊进度记录无法读取，原文件已保留。\n先返回航图处理记录，再重新体验本关。")
			add_button("close_restart_error","留在现场",Rect2(660,410,226,50),close_modal,true,overlay).grab_focus()
			return
		progress.settle()
		if not progress.error.is_empty():
			show_modal(progress.error + "\n本关通关现场尚未重置。")
			add_button("retry_restart","重试保存并重玩",Rect2(660,410,226,50),restart,true,overlay).grab_focus()
			return
	super()
