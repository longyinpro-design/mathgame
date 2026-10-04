extends CanvasLayer
# Campaign chrome sits outside a uniformly scaled legacy scene; original input,
# coordinate systems, story code and saves stay owned by the legacy implementation.
const Journey = preload("res://scripts/archipelago/bridge.gd")
const Catalog = preload("res://scripts/archipelago/catalog.gd")
const UIStyle = preload("res://scripts/cargo/skin.gd")
var host: Control
var island = ""
var ui: Control
var note: Label
var back: Button
var next: Button
var retry: Button
var navigating = false
var retry_destination = ""
var original_scale = Vector2.ONE
var original_position = Vector2.ZERO

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	original_scale = host.scale; original_position = host.position
	host.scale = Vector2(0.94,0.94); host.position = Vector2(38,43)
	ui = Control.new(); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(ui)
	var band = ColorRect.new(); band.color = Color("142d34"); band.size = Vector2(1280,40); ui.add_child(band)
	note = UIStyle.text(ui,"数字群岛 · "+Catalog.NAMES[island],Rect2(22,4,640,34),18)
	retry = UIStyle.button(ui,"重试群岛保存",Rect2(644,2,188,36),retry_campaign)
	retry.visible = false
	back = UIStyle.button(ui,"群岛航图 F10",Rect2(846,2,186,36),go_hub)
	next = UIStyle.button(ui,"继续下一段故事",Rect2(1044,2,214,36),go_next,true)

func pending() -> bool:
	if host.get("pending") is Dictionary and not host.get("pending").is_empty(): return true
	var local_session = host.get("session")
	if local_session != null and local_session.get("pending") is Dictionary and not local_session.pending.is_empty(): return true
	var repo = host.get("repository")
	if repo != null and repo.protected: return true
	return false

func ready_to_continue() -> bool:
	if island == "forest":
		var local = host.get("session")
		return local != null and not local.profile.is_empty() and local.profile.story.node in ["end","voyage"]
	var state = host.get("state")
	return state is Dictionary and state.get("stage") == "complete"

func _process(_delta: float) -> void:
	if not is_instance_valid(host) or not is_instance_valid(back): return
	var campaign_pending = Journey.session != null and not Journey.session.pending.is_empty()
	retry.visible = campaign_pending
	retry.disabled = pending() or host.get("modal") == true
	back.disabled = navigating or pending() or host.get("modal") == true or campaign_pending
	next.disabled = back.disabled or not ready_to_continue()

func go_hub() -> void:
	if navigating or pending() or host.get("modal") == true: return
	navigating = true
	if not Journey.hub(get_tree(),island):
		navigating = false; retry_destination = "hub"; note.text = Journey.session.feedback

func go_next() -> void:
	if navigating or pending() or not ready_to_continue(): return
	if not Journey.session.sync_legacy(): retry_destination = "next"; note.text = Journey.session.feedback; return
	var id = Journey.session.story_next()
	if id.is_empty(): go_hub(); return
	navigating = true
	if not Journey.launch(get_tree(),id): navigating = false; retry_destination = "next"; note.text = Journey.session.feedback

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		get_viewport().set_input_as_handled(); go_hub()


func retry_campaign() -> void:
	if pending() or host.get("modal")==true or Journey.session==null: return
	if Journey.session.retry():
		note.text="群岛记录已保存，可以继续故事或返回航图。"
		var destination=retry_destination;retry_destination=""
		if destination=="hub":go_hub()
		elif destination=="next":go_next()
	else: note.text=Journey.session.feedback
