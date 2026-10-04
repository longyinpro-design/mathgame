extends RefCounted
# 工坊独立的往返上下文；不消费集市来源，也不接触森林进度。
static var origin = ""
# 默认留空；独立测试可以显式传递临时路径，跨场景时仍不碰玩家存档。
static var progress_path = ""
static var level_paths: Dictionary = {}
