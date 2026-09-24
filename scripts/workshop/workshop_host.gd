extends "res://scripts/market/level_host.gd"
# 齿轮工坊共用宿主：存档事务、撤销、提示与演出生命周期继续复用集市宿主，
# 只把章专属的两处收口在这里——章节名换成工坊，且不消费千灯航图的 Bridge.origin。
# GW02 起的新关卡直接 extends 本文件，不要再逐关复制 _ready()/_process()。
func chapter_label() -> String: return "齿轮工坊"
func consumes_origin() -> bool: return false
