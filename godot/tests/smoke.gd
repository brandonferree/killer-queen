extends SceneTree
## Automated smoke test (phases 3-4: berries, ship, military, gates, combat). Run from the repo root:
##   godot_console --headless --path godot -s res://tests/smoke.gd
##   godot_console --path godot -s res://tests/smoke.gd -- shot   (also saves a PNG)
## Exit code is 1 if any check fails.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)


func step(n: int) -> void:
	for i in n:
		await physics_frame


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await step(3)
	var Team = Constants.Team

	# Roster: yellow queen (keyboard), purple queen (pad 0), yellow worker (pad 1).
	var yq = main._spawn_player(Team.YELLOW, true, -1)
	var pq = main._spawn_player(Team.PURPLE, true, 0)
	var yw = main._spawn_player(Team.YELLOW, false, 1)
	main._start_play()
	await step(2)
	check(main.state == main.State.PLAY, "in PLAY state")
	check(main.berries.get_child_count() > 0, "berries spawned: %d nodes" % main.berries.get_child_count())
	check(main.ship_holder.get_child_count() == 3, "ship + 2 targets spawned")
	check(main.lives_labels[Team.YELLOW].text == "Lives: 3", "lives label")

	# --- Berry pickup: drop the worker onto the centre layer-1 bunch.
	var bunch := Constants.to_godot(0.0, -Constants.WINDOW_HEIGHT / 2.0 + Constants.WINDOW_HEIGHT / 9.0 + 20.0)
	yw.position = bunch + Vector2(0, -20)
	yw.velocity = Vector2.ZERO
	await step(10)
	check(yw.has_berry, "worker picked up a berry")
	check(yw.held_berry.visible, "held berry sprite visible")
	yq.position = bunch + Vector2(0, -30)
	await step(10)
	check(not yq.has_berry, "queen cannot pick up berries")

	# --- Deposit in a yellow cell (first cell: x=-2, y=2).
	var R := 12.0
	var cell := Constants.to_godot(-(Constants.WINDOW_WIDTH / 20.0 - 2 * R * 2.1),
			Constants.WINDOW_HEIGHT / 2.0 - Constants.WINDOW_HEIGHT / 7.5 + 2 * R * 2.1)
	yw.position = cell
	yw.velocity = Vector2.ZERO
	await step(10)
	check(not yw.has_berry, "berry deposited")
	check(main.berries.collected[Team.YELLOW] == 1, "yellow collected == 1 (got %d)" % main.berries.collected[Team.YELLOW])

	# --- Economic win: fake the remaining berries.
	Constants.berries_to_win = 2
	yw.has_berry = true
	yw.position = cell + Vector2(0, R * 2.1 * -1)  # next cell (y=1) is above? try both
	yw.velocity = Vector2.ZERO
	await step(10)
	if main.state != main.State.GAME_OVER:
		yw.position = cell + Vector2(0, R * 2.1)
		await step(10)
	check(main.state == main.State.GAME_OVER, "economic game over")
	check(main.hud_label.text == "Economic victory by Yellow", "hud: " + main.hud_label.text)
	Constants.berries_to_win = 6

	# --- Round reset after 3 s.
	await step(int(3.2 * 120))
	check(main.state == main.State.JOIN, "back to JOIN after game over")
	check(main.players.get_child_count() == 3, "roster kept (3 players)")
	check(main.berries.collected[Team.YELLOW] == 0, "berry count reset")

	# --- Ship.
	yw = main._find_player(1)
	main._start_play()
	await step(2)
	var ship = main.ship_holder.get_child(0)
	var ship_x0: float = ship.position.x
	yw.position = ship.position + Vector2(0, -10)
	yw.velocity = Vector2.ZERO
	await step(10)
	check(ship.driver == yw, "worker mounted the ship")
	check(yw.riding_ship == ship, "worker knows it is riding")
	await step(60)
	check(ship.position.x < ship_x0, "ship crawls left for yellow (%.1f -> %.1f)" % [ship_x0, ship.position.x])
	check(absf(yw.position.x - ship.position.x) < 1.0, "rider follows ship")
	# Another worker bumping the occupied ship gets knocked away.
	var pw = main._spawn_player(Team.PURPLE, false, 2)
	pw.position = ship.position + Vector2(34, -2)
	pw.velocity = Vector2.ZERO
	await step(3)
	check(pw.velocity.x > 0.0, "second worker knocked back (vx=%.0f)" % pw.velocity.x)
	# Speed up and win.
	Constants.ship_speed = 20000.0
	await step(20)
	check(main.state == main.State.GAME_OVER and main.hud_label.text == "Ship victory by Yellow", "ship win: " + main.hud_label.text)
	Constants.ship_speed = 30.0
	await step(int(3.2 * 120))
	check(main.state == main.State.JOIN, "reset after ship win")
	check(main.ship_holder.get_child_count() == 3, "fresh ship spawned")

	# --- Military: kill the yellow queen 3 times.
	main._start_play()
	await step(2)
	for i in 3:
		var q = main._find_player(-1)
		check(q != null and q.is_queen, "yellow queen alive before kill %d" % (i + 1))
		main.kill_player(q)
		await step(2)
		check(main._find_player(-1) == null, "queen removed after kill %d" % (i + 1))
		if i < 2:
			check(main.lives_labels[Team.YELLOW].text == "Lives: %d" % (2 - i), "lives label: " + main.lives_labels[Team.YELLOW].text)
			await step(int(2.2 * 120))
			var rq = main._find_player(-1)
			check(rq != null and rq.invincible_time > 0.0, "queen respawned invincible")
			check(main._find_player(-1).is_queen, "respawned as queen")
			main.kill_player(rq)
			await step(2)
			check(main._find_player(-1) == rq, "kill ignored while invincible")
			await step(int(2.1 * 120))
	check(main.state == main.State.GAME_OVER and main.hud_label.text == "Military victory by Purple", "military: " + main.hud_label.text)

	# --- Phase 4: gates and fighters.
	await step(int(3.2 * 120))
	check(main.state == main.State.JOIN and main.players.get_child_count() == 4, "reset with 4 players")
	main._start_play()
	await step(2)
	yq = main._find_player(-1)
	pq = main._find_player(0)
	yw = main._find_player(1)
	pw = main._find_player(2)
	var W := Constants.WINDOW_WIDTH
	var H := Constants.WINDOW_HEIGHT
	var BOTTOM := -H / 2.0
	# Standing spot for a 40 px worker inside the centre gate (on its platform).
	var centre_gate := Constants.to_godot(0.0, BOTTOM + 4.0 * H / 9.0 + 30.0)
	var right_gate := Constants.to_godot(W / 2.0 - W / 3.2, BOTTOM + 2.0 * H / 9.0 + 30.0)
	var far_away := Constants.to_godot(-W / 4.0, BOTTOM + 30.0)
	yw.has_berry = true
	yw.position = centre_gate
	yw.velocity = Vector2.ZERO
	await step(10)
	check(yw.gate_time >= 0.0, "worker with berry starts transforming in a neutral gate")
	await step(int(1.1 * 120))
	check(yw.is_fighter and yw.has_wings, "worker became a fighter")
	check(not yw.has_berry, "berry consumed by the gate")
	check(yw._render_size() == Vector2(60, 60), "fighter uses the winged size")
	check(main.gates.get_child(0).team == -1, "centre gate still neutral")
	# Enemy-owned gate refuses the worker; a queen claims it; leaving cancels.
	var gate = main.gates.get_child(1)
	gate.claim(Team.YELLOW)
	pw.has_berry = true
	pw.position = right_gate
	pw.velocity = Vector2.ZERO
	await step(10)
	check(pw.gate_time < 0.0, "enemy gate ignores the worker")
	pw.position = far_away
	await step(5)
	pq.position = right_gate + Vector2(0, -10)
	pq.velocity = Vector2.ZERO
	await step(5)
	check(gate.team == Team.PURPLE, "purple queen claimed the gate")
	pq.position = far_away + Vector2(200, 0)
	await step(5)
	pw.position = right_gate
	pw.velocity = Vector2.ZERO
	await step(10)
	check(pw.gate_time >= 0.0, "friendly gate starts transforming")
	pw.position = far_away
	await step(5)
	check(pw.gate_time < 0.0 and pw.has_berry and not pw.is_fighter, "leaving the gate cancels")
	pw.has_berry = false

	# --- Phase 4: combat on the floor (x in original coords, y = floor top).
	var floor_worker := BOTTOM + 30.0
	var floor_winged := BOTTOM + 40.0
	yw.position = Constants.to_godot(400.0, floor_winged)
	pw.position = Constants.to_godot(422.0, floor_worker)
	yw.velocity = Vector2.ZERO
	pw.velocity = Vector2.ZERO
	await step(5)
	check(main._find_player(2) == null, "fighter killed the enemy worker")
	check(main._find_player(1) == yw, "fighter survived")
	var w3 = main._spawn_player(Team.YELLOW, false, 3)
	var w4 = main._spawn_player(Team.PURPLE, false, 4)
	w3.position = Constants.to_godot(600.0, floor_worker)
	w4.position = Constants.to_godot(618.0, floor_worker)
	await step(3)
	check(w3.velocity.x < 0.0 and w4.velocity.x > 0.0, "workers knocked apart (%.0f, %.0f)" % [w3.velocity.x, w4.velocity.x])
	check(main._find_player(3) == w3 and main._find_player(4) == w4, "workers both alive")
	# Queens facing each other clash swords: knockback, no death.
	yq.position = Constants.to_godot(800.0, floor_winged)
	pq.position = Constants.to_godot(826.0, floor_winged)
	yq.velocity = Vector2.ZERO
	pq.velocity = Vector2.ZERO
	yq.facing_right = true
	pq.facing_right = false
	await step(3)
	check(yq.velocity.x < 0.0 and pq.velocity.x > 0.0, "queens knocked apart (%.0f, %.0f)" % [yq.velocity.x, pq.velocity.x])
	check(main._find_player(-1) == yq and main._find_player(0) == pq, "both queens alive after clash")
	await step(30)
	# Yellow queen hits the purple queen's back: purple dies.
	yq.position = Constants.to_godot(800.0, floor_winged)
	pq.position = Constants.to_godot(826.0, floor_winged)
	yq.velocity = Vector2.ZERO
	pq.velocity = Vector2.ZERO
	yq.facing_right = true
	pq.facing_right = true
	await step(5)
	check(main._find_player(0) == null, "queen hit from behind dies")
	check(main._find_player(-1) == yq, "attacking queen survives")
	check(main.lives_labels[Team.PURPLE].text == "Lives: 2", "purple lives: " + main.lives_labels[Team.PURPLE].text)
	# A dead fighter comes back as a worker.
	main.kill_player(yw)
	await step(int(2.2 * 120))
	var rw = main._find_player(1)
	check(rw != null and not rw.is_fighter and not rw.has_wings, "fighter respawned as a worker")

	# --- Phase 5: settings menu, persistence, fullscreen toggle.
	var menu = main.settings_menu
	main._handle_menu_input(_key(KEY_ESCAPE))
	await step(2)
	check(menu.is_open and menu.visible, "Escape opens the settings menu")
	check(main.get_tree().paused, "menu pauses the game")
	menu._index = 0  # queen lives
	menu._change(1)
	check(Constants.queen_lives == 4, "queen lives raised to %d" % Constants.queen_lives)
	for i in 20:
		menu._change(1)
	check(Constants.queen_lives == 15, "queen lives clamped at %d" % Constants.queen_lives)
	menu._index = 2  # berries to win
	menu._change(-1)
	check(Constants.berries_to_win == 5, "berries to win lowered to %d" % Constants.berries_to_win)
	main._handle_menu_input(_key(KEY_ESCAPE))
	await step(2)
	check(not menu.is_open and not main.get_tree().paused, "Escape closes the menu and unpauses")
	check(main.lives_labels[Team.YELLOW].text == "Lives: 15", "lives label follows the setting: " + main.lives_labels[Team.YELLOW].text)
	# Saved on close; reset the statics and load them back.
	Constants.queen_lives = 3
	Constants.berries_to_win = 6
	SettingsMenu.load_settings()
	check(Constants.queen_lives == 15 and Constants.berries_to_win == 5,
			"settings round-trip through user://settings.cfg")
	check(not Constants.fullscreen, "fullscreen off by default")
	main._handle_menu_input(_key(KEY_F11))
	check(Constants.fullscreen, "F11 turns fullscreen on")
	main._handle_menu_input(_key(KEY_F11))
	check(not Constants.fullscreen, "F11 turns fullscreen off")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsMenu.CONFIG_PATH))
	Constants.queen_lives = 3
	Constants.berries_to_win = 6

	if OS.get_cmdline_user_args().has("shot"):
		# Put a fighter in frame so the fighter sprite can be eyeballed.
		var shot_fighter = main._spawn_player(Team.PURPLE, false, 5)
		shot_fighter.has_berry = true
		shot_fighter.position = centre_gate
		await step(int(1.3 * 120))
		shot_fighter.position = Constants.to_godot(0.0, floor_winged)
		await step(3)
		await process_frame
		await process_frame
		await _save_shot("user://smoke.png")
		# Second shot with the settings menu up.
		main._handle_menu_input(_key(KEY_ESCAPE))
		await step(2)
		await _save_shot("user://settings.png")
		main._handle_menu_input(_key(KEY_ESCAPE))

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


## Synthesised key press, for the menu/fullscreen shortcuts.
func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _save_shot(path: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved screenshot to ", ProjectSettings.globalize_path(path))
