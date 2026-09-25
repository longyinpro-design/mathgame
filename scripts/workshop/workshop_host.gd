extends "res://scripts/market/level_host.gd"
# 齿轮工坊共用宿主：存档事务、撤销、提示与演出生命周期继续复用集市宿主，
# 只把章专属的几处收口在这里——章节名换成工坊、不消费千灯航图的 Bridge.origin、
# 提醒署上嗒嗒的名字，并在世界之上、按钮之下挂一个常驻的小岚。
# GW02 起的新关卡直接 extends 本文件，不要再逐关复制 _ready()/_process()。
const Companion = preload("res://scripts/workshop/companion.gd")
var companion: Node2D

func chapter_label() -> String: return "齿轮工坊"
func consumes_origin() -> bool: return false
# 集市现场提醒来自扣扣；工坊的现场提醒来自嗒嗒。
func hint_label() -> String: return "请嗒嗒提醒"
# 小岚的落脚点：默认站在左下角石面上；关卡可覆写成别的落点，Vector2.ZERO 表示本关世界自己画。
func companion_foot() -> Vector2: return Vector2(110,620)
# 有些现场底部只剩一条窄带，关卡可以把她缩小一点站进去。
func companion_scale() -> float: return 1.0

func _ready() -> void:
	super()
	companion = Companion.new()
	companion.foot = companion_foot()
	companion.scale_factor = companion_scale()
	add_child(companion)
	# 世界先画，小岚压在世界之上；ui 与 overlay 后画，按钮和弹窗仍在她之上。
	move_child(companion,world.get_index()+1)
