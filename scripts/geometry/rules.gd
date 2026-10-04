extends RefCounted
const Numbers=preload("res://scripts/content/content_catalog.gd")
var definition: Dictionary
var p: Dictionary
var kind: String
func _init(d: Dictionary):
	definition = Numbers.normalize_numbers(d); p = definition.params; kind = definition.mechanism
func integer(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) == floor(float(v))
func exact(v: Variant, keys: Array) -> bool:
	if not v is Dictionary or v.size() != keys.size(): return false
	for k in keys:
		if not v.has(k): return false
	return true
func fresh() -> Dictionary:
	var s = {"pieces": [], "cells": [], "cut": false, "proofs": []}
	if is_tile():
		for shape in p.shapes: s.pieces.append({"x": -1, "y": -1, "r": 0, "f": 0})
	elif kind == "symmetry": s.cells = p.seeds.duplicate(true)
	return s
func is_tile() -> bool: return kind in ["mosaic", "mirror_boss"]
func shapes(s: Dictionary) -> Array:
	return p.cut_shapes if s.cut else p.get("shapes", [])
func target(s: Dictionary) -> Array:
	if kind == "mirror_boss": return p.targets[mini(s.proofs.size(), 1)]
	return p.get("target", [])
func transformed(shape: Array, r: int, f: int) -> Array:
	var out: Array = []; var mx = 100; var my = 100
	for c in shape:
		var x = int(c[0]); var y = int(c[1])
		if f == 1: x = -x
		for i in range(r):
			var old = x; x = -y; y = old
		out.append([x,y]); mx = mini(mx,x); my = mini(my,y)
	for c in out: c[0] -= mx; c[1] -= my
	return out
func occupied(s: Dictionary) -> Array:
	var result: Array = []
	for i in range(s.pieces.size()):
		var q = s.pieces[i]
		if q.x < 0: continue
		for c in transformed(shapes(s)[i], int(q.r), int(q.f)): result.append([c[0]+q.x,c[1]+q.y])
	return result
func cell_list(v: Variant) -> bool:
	if not v is Array or v.size() > p.w*p.h: return false
	var seen: Array = []
	for c in v:
		if not c is Array or c.size()!=2 or not integer(c[0]) or not integer(c[1]): return false
		if c[0]<0 or c[0]>=p.w or c[1]<0 or c[1]>=p.h or c in seen: return false
		seen.append(c)
	return true
func same(a: Array,b: Array) -> bool:
	if a.size()!=b.size(): return false
	for c in a:
		if not c in b: return false
	return true
func validate(s: Variant) -> bool:
	s=Numbers.normalize_numbers(s)
	if not exact(s,["pieces","cells","cut","proofs"]): return false
	if not s.cut is bool or not s.pieces is Array or not s.proofs is Array or not cell_list(s.cells): return false
	if s.cut and not p.has("cut_shapes"): return false
	if s.proofs.size() > (2 if kind=="mirror_boss" else 1 if kind=="architect_boss" else 0): return false
	if kind=="mirror_boss" and s.proofs.size()==2:
		if s.pieces!=s.proofs[1]:return false
	if is_tile():
		if not s.cells.is_empty() or s.pieces.size()!=shapes(s).size(): return false
		for q in s.pieces:
			if not exact(q,["x","y","r","f"]): return false
			for k in q:
				if not integer(q[k]): return false
			if q.r<0 or q.r>3 or q.f<0 or q.f>1: return false
			if q.x == -1 and q.y == -1: continue
			if q.x<0 or q.y<0: return false
		var cells = occupied(s)
		if not cell_list(cells): return false
		for c in cells:
			if not c in target(s): return false
	else:
		if not s.pieces.is_empty() or s.cut: return false
		for c in p.get("seeds",[]):
			if not c in s.cells: return false
		for c in p.get("blocked",[]):
			if c in s.cells: return false
		if kind=="architect_boss" and s.proofs.size()==1 and rock(s.proofs[0]) in s.cells: return false
	for i in range(s.proofs.size()):
		if kind == "mirror_boss":
			var proof = {"pieces":s.proofs[i],"cells":[],"cut":false,"proofs":[]}
			# Validate each pose directly against its own shield, never trust a claimed seal.
			if not proof.pieces is Array or proof.pieces.size()!=p.shapes.size(): return false
			for q in proof.pieces:
				if not exact(q,["x","y","r","f"]): return false
				for k in q:
					if not integer(q[k]): return false
				if q.x<0 or q.y<0 or q.r<0 or q.r>3 or q.f<0 or q.f>1: return false
			if not same(occupied(proof),p.targets[i]): return false
		elif kind=="architect_boss":
			if not cell_list(s.proofs[i]) or not garden_ok(s.proofs[i],6,14,1): return false
	return true
func apply(s: Dictionary, a: Dictionary) -> Dictionary:
	s=Numbers.normalize_numbers(s);a=Numbers.normalize_numbers(a)
	if not validate(s) or not a.has("type") or not a.type is String: return {}
	var n = s.duplicate(true)
	if a.type == "seal":
		if not exact(a,["type"]): return {}
		if kind=="mirror_boss" and n.proofs.size()<2 and same(occupied(n),target(n)):
			n.proofs.append(n.pieces.duplicate(true))
			if n.proofs.size()<2:
				for q in n.pieces: q.x=-1; q.y=-1; q.r=0; q.f=0
		elif kind=="architect_boss" and n.proofs.is_empty() and garden_ok(n.cells,6,14,1):
			n.proofs.append(n.cells.duplicate(true)); n.cells=[]
		else: return {}
	elif a.type == "cut":
		if not exact(a,["type"]) or n.cut or not p.has("cut_shapes"): return {}
		for q in n.pieces:
			if q.x!=-1: return {}
		n.cut=true; n.pieces=[]
		for shape in p.cut_shapes: n.pieces.append({"x":-1,"y":-1,"r":0,"f":0})
	elif a.type == "toggle":
		if is_tile() or not exact(a,["type","x","y"]) or not integer(a.x) or not integer(a.y): return {}
		var c = [a.x,a.y]
		if c in n.cells: n.cells.erase(c)
		else: n.cells.append(c)
	elif a.type in ["place","rotate","flip","lift"]:
		if not is_tile() or (kind=="mirror_boss" and n.proofs.size()==2): return {}
		if not exact(a,["type","piece","x","y"] if a.type=="place" else ["type","piece"]): return {}
		if not integer(a.piece) or a.piece<0 or a.piece>=n.pieces.size(): return {}
		var q = n.pieces[int(a.piece)]
		if a.type=="place":
			if not integer(a.x) or not integer(a.y): return {}
			q.x=a.x; q.y=a.y
		elif a.type=="rotate": q.r=(int(q.r)+1)%4
		elif a.type=="flip": q.f=1-int(q.f)
		else: q.x=-1; q.y=-1
	else: return {}
	return n if validate(n) else {}
func perimeter(cells: Array) -> int:
	var count=0
	for c in cells:
		for d in [[1,0],[-1,0],[0,1],[0,-1]]:
			if not [c[0]+d[0],c[1]+d[1]] in cells: count+=1
	return count
func components(cells: Array) -> int:
	var remaining = cells.duplicate(true); var count=0
	while not remaining.is_empty():
		count+=1; var queue=[remaining.pop_back()]
		while not queue.is_empty():
			var c = queue.pop_back()
			for d in [[1,0],[-1,0],[0,1],[0,-1]]:
				var z=[c[0]+d[0],c[1]+d[1]]
				if z in remaining: remaining.erase(z); queue.append(z)
	return count
func garden_ok(cells: Array, area: int, edge: int, groups: int) -> bool:
	if cells.size()!=area or perimeter(cells)!=edge or components(cells)!=groups: return false
	for c in p.get("required",[]):
		if not c in cells: return false
	return true
func rock(proof: Array) -> Array:
	for c in [[0,0],[3,0],[0,3],[3,3]]:
		if not c in proof: return c
	return [1,1]
func solved(s: Dictionary) -> bool:
	s=Numbers.normalize_numbers(s)
	if not validate(s): return false
	if kind=="mirror_boss": return s.proofs.size()==2
	if kind=="architect_boss": return s.proofs.size()==1 and garden_ok(s.cells,6,10,1)
	if kind=="mosaic": return same(occupied(s),target(s)) and (s.cut if p.has("cut_shapes") else true)
	if kind=="garden": return garden_ok(s.cells,int(p.area),int(p.perimeter),int(p.get("components",1)))
	if s.cells.size()!=p.area: return false
	for c in s.cells:
		var images: Array=[]
		match p.mode:
			"vertical": images=[[p.w-1-c[0],c[1]]]
			"both": images=[[p.w-1-c[0],c[1]],[c[0],p.h-1-c[1]]]
			"diagonal": images=[[c[1],c[0]]]
			"half": images=[[p.w-1-c[0],p.h-1-c[1]]]
		for z in images:
			if not z in s.cells: return false
	return true
func feedback(s: Dictionary) -> String:
	if not validate(s): return "棋盘状态不合法。"
	if solved(s): return "几何条件全部成立，山谷道路重新相连。"
	if is_tile():
		if kind=="mirror_boss": return "已封印%d/2面石盾；完整覆盖后按封印。" % s.proofs.size()
		if p.has("cut_shapes") and not s.cut: return "先把长梁收回，再沿刻痕切开；面积必须保持不变。"
		return "已铺%d/%d格；石块必须全部覆盖亮格，无缝也不重叠。" % [occupied(s).size(),target(s).size()]
	if kind=="symmetry":
		if s.cells.size()!=p.area:return "已有%d格，目标恰好%d格；还要保持全部对称伙伴。"%[s.cells.size(),p.area]
		for c in s.cells:
			var images: Array=[]
			match p.mode:
				"vertical":images=[[p.w-1-c[0],c[1]]]
				"both":images=[[p.w-1-c[0],c[1]],[c[0],p.h-1-c[1]]]
				"diagonal":images=[[c[1],c[0]]]
				"half":images=[[p.w-1-c[0],p.h-1-c[1]]]
			for z in images:
				if not z in s.cells:return "第%d列、第%d行的花还缺少对称伙伴；总格数对了也要检查位置。"%[c[0]+1,c[1]+1]
	var edge=10 if kind=="architect_boss" and s.proofs.size()==1 else int(p.perimeter)
	if s.cells.size()!=p.area:return "面积是%d格，需要%d格。"%[s.cells.size(),p.area]
	if perimeter(s.cells)!=edge:return "面积正确；外露边是%d条，需要%d条。移动一格，观察共用边怎样变化。"%[perimeter(s.cells),edge]
	if components(s.cells)!=p.get("components",1):return "面积与周长正确；现在有%d片，目标是%d片。角碰角不算相连。"%[components(s.cells),p.get("components",1)]
	for c in p.get("required",[]):
		if not c in s.cells:return "第%d列、第%d行的金色苗尚未种回。"%[c[0]+1,c[1]+1]
	return "地基条件成立，按封印／推进，让守护者落石。"

func hint(s: Dictionary, tier: int) -> String:
	return feedback(s)+"\n"+definition.hints[clampi(tier-1,0,3)]
