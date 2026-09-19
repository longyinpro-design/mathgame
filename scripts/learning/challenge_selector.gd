extends RefCounted
# The tutorial scaffold and exercise recommendations were removed from the game.
# support_for still fills the frozen run field so existing saves stay readable.
static func support_for(_profile: Dictionary, _definition: Dictionary, _catalog: RefCounted = null) -> Dictionary:
	return {"show_scaffold":false,"offer_transfer":false,"variant_id":"base"}
