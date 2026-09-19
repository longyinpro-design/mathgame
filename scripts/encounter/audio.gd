extends Node
const PATH = "res://assets/audio/v3/"
const NAMES = ["pickup","place","footstep","awaken","charge","cast","impact","unbalanced","fox","unlock","reward"]
var players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var music: AudioStreamPlayer
var air: AudioStreamPlayer
var enabled = true
var volume = 0.7
var played: Array[String] = []
func _ready() -> void:
	for name in NAMES: streams[name] = load(PATH+name+".wav")
	for i in range(6):
		var player = AudioStreamPlayer.new(); add_child(player); players.append(player)
	music = looping("forest_theme",-13)
	air = looping("forest_air",-8)
	refresh()
func looping(name: String, db: float) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new(); p.stream = load(PATH+name+".wav"); p.volume_db = db
	add_child(p); p.finished.connect(p.play); p.play(); return p
func play_cue(name: String) -> void:
	if not streams.has(name): return
	played.append(name)
	if played.size() > 100: played.pop_front()
	if not enabled or volume <= 0: return
	var player = players[0]
	for p in players:
		if not p.playing: player = p; break
	player.stream = streams[name]; player.volume_db = linear_to_db(volume)-6; player.play()
func set_volume(value: float) -> void:
	volume = clampf(value,0,1); refresh()
func toggle() -> void:
	enabled = not enabled; refresh()
func refresh() -> void:
	var db = linear_to_db(volume) if enabled and volume > 0 else -80.0
	music.volume_db = db-13; air.volume_db = db-8
	for p in players: p.volume_db = db-6
