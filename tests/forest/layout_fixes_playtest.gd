extends SceneTree
# Regression checks for the player-facing layout/maths repairs found by a full
# sit-down playthrough: FL09 counts, FL14 reachable endings, FL16 hit targets and
# caption, FL08 status rows, FL17 buttons, FL05 bet label and the camp button row.
const SCENE = preload("res://game/forest_release.tscn")
const Scenarios = preload("res://tests/forest/scenarios.gd")
const Routes = preload("res://scripts/mechanisms/route_rules.gd")
const Catalog = preload("res://scripts/content/content_catalog.gd")
var game: Control
var checks = 0
var failures = 0
func _initialize() -> void:
    preload("res://tests/forest/window_focus.gd").configure(root)
    call_deferred("run")
func check(ok: bool, label: String) -> void:
    checks += 1
    if ok: print("PASS ",label)
    else: failures += 1; push_error(label)
func click(point: Vector2) -> void:
    if not await preload("res://tests/forest/window_focus.gd").ready(root): quit(1); return
    for pressed in [true,false]:
        var event = InputEventMouseButton.new(); event.position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; root.push_input(event)
    await process_frame
func button(id: String) -> void:
    if not game.buttons.has(id): check(false,"missing "+id); return
    await click(game.buttons[id].get_global_rect().get_center())
    while game.busy: await create_timer(0.005).timeout
func labels_text() -> String:
    var text = ""
    for parent in [game.ui,game.overlay]:
        for node in parent.find_children("*","Label",true,false): text += node.text + "\n"
    return text
func overlap(a: Rect2, b: Rect2) -> Vector2:
    var inter = a.intersection(b)
    return inter.size
func enter(id: String, region: String) -> void:
    game.show_region(region); await process_frame
    await button("object_"+id)
    # The runner restores the foreground on the first click, which cancels a walk by
    # design; a player would simply click the object again, so the test does too.
    if game.page == "region":
        if not game.session.feedback.contains("先停在这里"): push_error("expected visible walk-cancel feedback")
        await button("object_"+id)
        while game.busy: await create_timer(0.005).timeout
    if game.page == "visit": await button("practice")
    check(game.page == "challenge" and game.session.profile.active_run.level_id == id,"actual entrance "+id)

func run() -> void:
    create_timer(100).timeout.connect(func(): push_error("layout repair watchdog"); quit(1))
    game = SCENE.instantiate(); game.story_enabled = false
    game.save_path = "/tmp/pixel-forest-layout-"+str(Time.get_ticks_usec())+"/save.json"
    game.time_scale = 0.02; root.add_child(game); await create_timer(0.25).timeout
    for i in range(1,19):
        if not Scenarios.play(game.session,"FL%02d"%i): check(false,"fixture FL%02d"%i)

    # FL05: the optional bet must name the input it is about.
    await enter("FL05","mill")
    check(labels_text().contains("输入6 →"),"FL05 bet labels the hidden input it asks about")
    await button("module_triple"); await button("module_plus2")
    var bet = game.ui.get_node("prediction")
    bet.text = "8"; bet.text_submitted.emit("8"); await process_frame
    await button("try")
    check(game.session.profile.active_run.outcome == "complete","FL05 still settles with a bet placed")

    # FL09: the blocked count is derived from the real total and never negative.
    await enter("FL09","post")
    await button("guess_1")
    for i in range(4):
        var line: LineEdit = game.ui.get_node("block_predict_"+str(i))
        var guess_value = [8,11,11,8][i]
        line.text = str(guess_value); line.text_submitted.emit(str(guess_value)); await process_frame
    for i in range(4): await button("block_tab_"+str(i))
    var total_paths = Routes.all_paths(game.session.catalog.levels.FL09.params).size()
    for block in range(4):
        await button("block_tab_"+str(block))
        var survives = Routes.survivors(game.session.catalog.levels.FL09.params,block)
        var expected = "这处：挡掉 %d 条，留下 %d 条（共%d条）" % [total_paths-survives,survives,total_paths]
        check(labels_text().contains(expected),"FL09 count line is correct for block %d"%block)
        check(total_paths-survives >= 0,"FL09 blocked count is never negative for block %d"%block)
    # Choose a genuinely optimal position (11 routes survive), then send.
    var best = 0
    for block in range(4):
        if Routes.survivors(game.session.catalog.levels.FL09.params,block) > Routes.survivors(game.session.catalog.levels.FL09.params,best): best = block
    await button("block_tab_"+str(best)); await button("choose_block"); await button("try")
    check(game.session.profile.active_run.outcome == "complete","FL09 still settles after the count fix")

    # FL14: the reachable-endings line honours the 0..10 bound.
    await enter("FL14","post")
    await button("parity_0_2")
    check(labels_text().contains("从 2 再走 4 步，只能走到：2、6、10"),"FL14 reachable line lists only legal endings (from 2)")
    check(labels_text().contains("每步±2，奇偶不变；沿途也不能走出0至10"),"FL14 reachable line still states the parity insight and the bound")
    await button("parity_0_2")
    check(labels_text().contains("从 4 再走 3 步，只能走到：2、6、10"),"FL14 reachable line lists only legal endings (from 4)")
    for i in range(3): await button("parity_0_2")
    for value in [2,2,2,2,1]: await button("parity_1_"+str(value))
    await button("try")
    check(game.session.profile.active_run.outcome == "complete","FL14 still settles after the reachability fix")

    # FL16: the width controls and the commit button must not overlap.
    await enter("FL16","post")
    var more = game.buttons.fence_w_more.get_global_rect()
    var less = game.buttons.fence_w_less.get_global_rect()
    var commit = game.buttons.try.get_global_rect()
    check(overlap(more,commit) == Vector2.ZERO,"FL16 '+ 宽一点' does not overlap '就围这份'")
    check(overlap(less,more) == Vector2.ZERO,"FL16 width buttons do not overlap each other")
    for step in range(4): await button("fence_w_more")
    check(game.session.profile.active_run.state.width == 5,"FL16 four '+' steps reach the widest layout without triggering the commit button")
    check(game.session.profile.active_run.outcome == "active" and not game.session.profile.active_run.state.tested,"FL16 '+' never commits the level")
    # The borrowed-wall caption must stay clear of the intro paragraph at every width.
    var paragraph = Rect2(82,174,1094,38)
    for width in [5,4,3,2,1]:
        while int(game.session.profile.active_run.state.width) > width: await button("fence_w_less")
        var found = null
        for node in game.ui.find_children("*","Label",true,false):
            if node.text == "借来的墙": found = node
        check(found != null,"FL16 borrowed-wall caption exists at width %d"%width)
        if found != null: check(overlap(paragraph,found.get_global_rect()) == Vector2.ZERO,"FL16 caption clear of the intro paragraph at width %d"%width)
    for step in range(5): pass
    while int(game.session.profile.active_run.state.width) < 3: await button("fence_w_more")
    var chosen = -1
    for i in game.session.profile.active_run.state.plans.size():
        if game.session.profile.active_run.state.plans[i][0] == 3: chosen = i
    await button("fence_choose_"+str(chosen))
    await button("try")
    check(game.session.profile.active_run.outcome == "complete","FL16 still settles at the maximum area")

    # FL08 redesigned board: the counts row must stay clear of its neighbours, the
    # filing list must be reachable, and the repair control must fix the card.
    await enter("FL08","post")
    var counts_rect = Rect2(640,530,140,34).merge(Rect2(940,530,140,34))
    var draw_buttons = Rect2(80,497,330,84)
    for node in game.ui.find_children("*","Label",true,false):
        if node.text.begins_with("每层袋应有几条"):
            check(overlap(counts_rect,node.get_global_rect()) == Vector2.ZERO,"FL08 counts row clear of its own label")
            check(overlap(draw_buttons,node.get_global_rect()) == Vector2.ZERO,"FL08 counts label clear of the drawing controls")
    check(not game.ui.has_node("filing_scroll"),"FL08 filing fits without a hidden scroll area")
    var misfiled = -1
    var misfiled_path = ""
    for index in game.session.profile.active_run.state.filing.size():
        var card: Dictionary = game.session.profile.active_run.state.filing[index]
        if card.group != card.path.find("R"): misfiled = index; misfiled_path = card.path
    check(misfiled >= 0 and game.buttons.has("audit_move_"+str(misfiled)),"FL08 misfiled card offers a visible repair control")
    await button("audit_move_"+str(misfiled))
    var repaired = false
    for card in game.session.profile.active_run.state.filing:
        if card.path == misfiled_path and card.group == card.path.find("R"): repaired = true
    check(repaired,"FL08 repair puts the misfiled card in its own bag")

    # FL17: the transfer-card row must not sit under the counterattack button.
    await enter("FL17","heart")
    var cards = Rect2(274,533,214,46).merge(Rect2(776,533,214,46))
    check(game.buttons.has("card_1") and game.buttons.card_1.get_global_rect().position.x >= 274,"FL17 card row starts at its new left edge")
    check(game.buttons.card_3.get_global_rect().end.x <= 1004,"FL17 last card ends before the counterattack button")

    # Camp: the companion line must not overlap the chat button.
    await button("camp")
    var chat = game.buttons.chat.get_global_rect()
    for node in game.ui.find_children("*","Label",true,false):
        if node.text == game.session.feedback and node.text != "":
            check(overlap(chat,node.get_global_rect()) == Vector2.ZERO,"camp feedback line clear of the chat button")
    game.queue_free(); await create_timer(0.2).timeout
    print("FOREST LAYOUT FIXES UI ",checks-failures,"/",checks," PASS"); quit(1 if failures else 0)
