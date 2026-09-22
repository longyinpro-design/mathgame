extends SceneTree
# 版面宽度尺：把「文案实际有多宽」量出来，而不是按每个汉字 ≈ 一格字号去估。
#
# 这些棋盘用 Label 画文案，Label 开了 autowrap，而框高一律只够一行——
# 一旦量出来的宽度超过框宽，文字会折行并被裁掉，而且只有实机截图看得出来。
# 所以改完文案先用这里量一遍：把 (文案, 框宽) 填进 CASES 再跑。
#
#   godot --headless --path . --script tools/measure_labels.gd
const UIStyle = preload("res://scripts/cargo/skin.gd")

# 每行：(标签, 文案, 框宽, 请求字号)
const CASES = [
	["FL04 总量提问","先算总量：三次合称一共多少格？",470,20],
	["FL04 总重提问","每架灯都被称了两次。一套灯架的总重是：",470,20],
	["FL05 押注提示","押一注（必填）：写下算出的输出，再启动。",520,19],
	["FL14 判因表头","8、9、10 各为什么？",240,20],
	["FL14 代价提问","把一步 +2 换成 −2，终点会少：",400,20],
	["FL14 判因 能走到","能走到",114,20],
	["FL14 判因 奇偶拦住","奇偶拦住",114,20],
	["FL14 判因 五步凑不出","五步凑不出",114,20],
	["FL15 提交前说明","九颗里有且只有一颗更重。称完之后，每一种结果都要指向唯一一颗——先自己排好，再来核对。",1100,20],
	["FL15 次数提问","一次天平最多 3 种结果。九颗至少要称几次才够？",600,20],
	["FL16 押注提问","先押一注：最大多少格？",290,19],
	["FL16 代价提问","宽多 1 格，长会少：",250,19],
	["FL16 押注结果","你押 20 格，五种宽度里最大 18 格——押得准！",636,18],
]
# 按钮字号在 skin.gd 里是固定的 20px；按钮宽度至少要 = 文案宽 + 内容边距。
const BUTTON_FONT = 20
const BUTTON_MARGIN = 12

func _initialize() -> void:
	var font: FontFile = UIStyle.face()
	var failures = 0
	for case in CASES:
		var label: String = case[0]; var value: String = case[1]; var width: int = case[2]
		var size_px: int = UIStyle.text_size(int(case[3]))
		var measured: float = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
		var ratio: float = measured/float(width)
		var ok: bool = measured <= width
		if not ok: failures += 1
		print("%s %-18s 实测 %6.1fpx / 框宽 %4dpx (渲染 %dpx, 占 %3.0f%%)  %s"%["OK " if ok else "溢出",label,measured,width,size_px,ratio*100,value])
	print("BUTTONS 字号 %dpx，4 字约需 %dpx、5 字约需 %dpx" % [BUTTON_FONT,
		int(font.get_string_size("奇偶拦住",HORIZONTAL_ALIGNMENT_LEFT,-1,BUTTON_FONT).x)+BUTTON_MARGIN,
		int(font.get_string_size("五步凑不出",HORIZONTAL_ALIGNMENT_LEFT,-1,BUTTON_FONT).x)+BUTTON_MARGIN])
	print("LABEL WIDTHS %d/%d 在框内" % [CASES.size()-failures,CASES.size()])
	quit(1 if failures else 0)
