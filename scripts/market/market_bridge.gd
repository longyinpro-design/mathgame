extends RefCounted
# One-way note between market samples: which sample sent the player through the door.
# Samples stay independent scenes, so the hand-off is a plain id instead of a script cycle.
static var origin = ""
