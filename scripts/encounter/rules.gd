extends RefCounted
const TOTAL = 14
const DIFFERENCE = 4
static func fresh() -> Dictionary:
	return {"left":7,"attempts":0,"hint":0,"introduced":false,"won":false,"reward":false}
static func result(left: int) -> Dictionary:
	return {"left":left,"right":TOTAL-left,"difference":TOTAL-2*left,"success":TOTAL-2*left == DIFFERENCE}
static func valid(data: Variant) -> bool:
	if not data is Dictionary or not data.has_all(["left","attempts","hint","introduced","won","reward"]): return false
	for entry in [["left",0,14],["attempts",0,1000000],["hint",0,2]]:
		var n = data[entry[0]]
		if not (n is float or n is int) or not is_finite(n) or n != int(n) or n < entry[1] or n > entry[2]: return false
	for key in ["introduced","won","reward"]:
		if not data[key] is bool: return false
	return (not data.won or result(int(data.left)).success) and (not data.reward or data.won)
