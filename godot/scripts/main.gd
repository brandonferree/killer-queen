extends Node2D
## Game manager: join screen, player roster, game states and round reset.
## Mirrors src/join.rs, src/gates.rs (setup) and the state handling in
## src/main.rs of the Rust version.
##
## Join: LB joins Yellow, RB joins Purple. The keyboard counts as two players:
## 1 / 2 join with the arrow keys, 3 / 4 join with WASD, so two people can play
## without a gamepad. The first player on a team is its queen. Select/Back
## (keyboard: Backspace, or Delete for the WASD player) leaves during the join
## screen. Both queens fly through their start gate to begin the match.

enum State { JOIN, PLAY, GAME_OVER }

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const GATE_SCENE := preload("res://scenes/gate.tscn")
const SHIP_SCENE := preload("res://scenes/ship.tscn")
const TEMP_PLATFORM_COLOR := Color.BLACK
const NEXT_GAME_DELAY := 3.0
const RESPAWN_DELAY := 2.0

const W := Constants.WINDOW_WIDTH
const H := Constants.WINDOW_HEIGHT
const BOTTOM := -H / 2.0
const TOP := H / 2.0
const RIGHT := W / 2.0
const PH := Constants.PLATFORM_HEIGHT
const GATE_H := 60.0

# Regular gates (x, y) in original coordinates.
const GATE_POSITIONS := [
	[0.0, BOTTOM + 4.0 * H / 9.0 + GATE_H / 2.0],
	[RIGHT - W / 3.2, BOTTOM + 2.0 * H / 9.0 + GATE_H / 2.0],
	[-(RIGHT - W / 3.2), BOTTOM + 2.0 * H / 9.0 + GATE_H / 2.0],
	[RIGHT - W / 5.0, BOTTOM + 7.0 * H / 9.0 + GATE_H / 2.0],
	[-(RIGHT - W / 5.0), BOTTOM + 7.0 * H / 9.0 + GATE_H / 2.0],
]

@onready var level: Node2D = $Level
@onready var players: Node2D = $Players
@onready var gates: Node2D = $Gates
@onready var berries: Node2D = $Berries
@onready var ship_holder: Node2D = $ShipHolder
@onready var settings_menu: CanvasLayer = $SettingsMenu
@onready var hud_label: Label = $HUD/Label
@onready var lives_labels := {
	Constants.Team.YELLOW: $HUD/YellowLives as Label,
	Constants.Team.PURPLE: $HUD/PurpleLives as Label,
}

var state := State.JOIN
var queen_deaths := {Constants.Team.YELLOW: 0, Constants.Team.PURPLE: 0}
var _temp_platforms: Array[StaticBody2D] = []
var _join_gates: Array[Area2D] = []
var _next_game_timer := 0.0
## Dead players waiting to respawn: {team, is_queen, device, time_left}.
var _pending_spawns: Array[Dictionary] = []


func _ready() -> void:
	SettingsMenu.load_settings()
	settings_menu.closed.connect(_on_settings_closed)
	berries.team_won.connect(end_game)
	for team in lives_labels:
		lives_labels[team].add_theme_color_override("font_color", Constants.TEAM_COLORS[team])
	_enter_join()


## Berries only need replacing when the target count changed; the lives labels
## always follow the setting.
func _on_settings_closed(berries_changed: bool) -> void:
	if berries_changed and state != State.PLAY:
		berries.respawn()
	_update_lives()


# --- State transitions ----------------------------------------------------

func _enter_join() -> void:
	state = State.JOIN
	for team in queen_deaths:
		queen_deaths[team] = 0
	_update_lives()
	berries.respawn()
	_spawn_ship()
	_spawn_gates()
	for sign in [-1.0, 1.0]:
		# Thin black platforms that seal the hive exits until the match starts.
		_temp_platforms.append(level.add_platform(
			sign * (RIGHT - W / 40.0 - W / 10.0 + W / 60.0),
			BOTTOM + 7.0 * H / 9.0,
			(RIGHT - W / 20.0) - (RIGHT - W / 5.0 + W / 30.0),
			PH / 4.0, true, TEMP_PLATFORM_COLOR))
		_temp_platforms.append(level.add_platform(
			sign * ((W / 10.0) + (RIGHT - W / 5.0 - W / 30.0)) / 2.0,
			BOTTOM + 7.0 * H / 9.0,
			(RIGHT - W / 5.0 - W / 30.0) - W / 10.0,
			PH / 4.0, true, TEMP_PLATFORM_COLOR))
		var gate := _spawn_gate((RIGHT - W / 3.2) * sign, BOTTOM + 8.0 * H / 9.0 + GATE_H / 2.0)
		gate.is_join_gate = true
		gate.claimed.connect(_on_join_gate_claimed)
		_join_gates.append(gate)
	_update_hud()


func _on_join_gate_claimed(_gate: Area2D) -> void:
	if state != State.JOIN:
		return
	for g in _join_gates:
		if g.team < 0:
			return
	_start_play()


func _start_play() -> void:
	for p in _temp_platforms:
		p.queue_free()
	_temp_platforms.clear()
	for g in _join_gates:
		g.queue_free()
	_join_gates.clear()
	state = State.PLAY
	_update_hud()


## Ends the match. condition is "Economic", "Ship" or "Military".
func end_game(team: int, condition: String) -> void:
	if state != State.PLAY:
		return
	state = State.GAME_OVER
	_next_game_timer = NEXT_GAME_DELAY
	hud_label.text = "%s victory by %s" % [condition, Constants.TEAM_NAMES[team]]
	hud_label.add_theme_color_override("font_color", Constants.TEAM_COLORS[team])
	hud_label.visible = true


func _process(delta: float) -> void:
	_tick_pending_spawns(delta)
	if state == State.GAME_OVER:
		_next_game_timer -= delta
		if _next_game_timer <= 0.0:
			_reset_round()


func _reset_round() -> void:
	# Everyone keeps their team and role but respawns at the hive.
	var roster: Array = []
	for p in players.get_children():
		roster.append([p.team, p.is_queen, p.device])
		p.free()
	for s in _pending_spawns:
		roster.append([s.team, s.is_queen, s.device])
	_pending_spawns.clear()
	for g in gates.get_children():
		g.free()
	for s in ship_holder.get_children():
		s.free()
	for r in roster:
		_spawn_player(r[0], r[1], r[2])
	_enter_join()


# --- Deaths and respawns (src/player.rs players_attack / spawn_players) ----

## Both players' hitboxes report the same touch, so contacts already handled
## this physics frame are remembered here, keyed by their instance ids.
var _handled_contacts := {}
var _handled_contacts_frame := -1


func _on_player_contact(a: CharacterBody2D, b: CharacterBody2D) -> void:
	if state != State.PLAY or a.team == b.team:
		return
	var frame := Engine.get_physics_frames()
	if frame != _handled_contacts_frame:
		_handled_contacts_frame = frame
		_handled_contacts.clear()
	var key := "%d:%d" % [mini(a.get_instance_id(), b.get_instance_id()),
			maxi(a.get_instance_id(), b.get_instance_id())]
	if _handled_contacts.has(key):
		return
	_handled_contacts[key] = true
	_resolve_contact(a, b)


## Combat rules from src/player.rs players_attack:
## - a winged player (queen or fighter) touching an enemy worker kills it;
## - two workers bumping sideways knock each other back;
## - two winged players: the one on top kills the one below; side on, whoever
##   is facing the other's back kills them, otherwise (swords clash, backs
##   touch, or someone is diving) both are knocked back.
func _resolve_contact(a: CharacterBody2D, b: CharacterBody2D) -> void:
	var left: CharacterBody2D = a if a.position.x < b.position.x else b
	var right: CharacterBody2D = b if left == a else a
	var half_a: Vector2 = a.half_extents()
	var half_b: Vector2 = b.half_extents()
	var diff: Vector2 = (a.position - b.position).abs()
	var one_on_top: bool = (diff.y - (half_a.y + half_b.y)) > (diff.x - (half_a.x + half_b.x))
	var victim: CharacterBody2D = null
	if a.has_wings and b.has_wings:
		if one_on_top:
			victim = b if a.position.y < b.position.y else a
		elif left.is_diving or right.is_diving:
			_knock_apart(left, right)
		elif left.facing_right and right.facing_right:
			victim = right
		elif not left.facing_right and not right.facing_right:
			victim = left
		else:
			_knock_apart(left, right)
	elif a.has_wings:
		victim = b
	elif b.has_wings:
		victim = a
	elif not one_on_top:
		_knock_apart(left, right)
	if victim != null:
		kill_player(victim)


func _knock_apart(left: CharacterBody2D, right: CharacterBody2D) -> void:
	left.knock_back(-1.0)
	right.knock_back(1.0)


## Kills a player: drops their berry, frees the ship, counts queen deaths and
## checks the military win. Fighters respawn as workers.
func kill_player(p: CharacterBody2D) -> void:
	if p.invincible_time > 0.0 or p.is_queued_for_deletion():
		return
	if p.has_berry:
		berries.spawn_dropped(p.position)
	if p.riding_ship != null:
		p.riding_ship.dismount()
	if p.is_queen:
		queen_deaths[p.team] += 1
		_update_lives()
	_pending_spawns.append({
		"team": p.team, "is_queen": p.is_queen, "device": p.device,
		"time_left": RESPAWN_DELAY,
	})
	p.device = -999
	p.queue_free()
	if p.is_queen and queen_deaths[p.team] >= Constants.queen_lives:
		end_game(Constants.other_team(p.team), "Military")


func _tick_pending_spawns(delta: float) -> void:
	var i := 0
	while i < _pending_spawns.size():
		var s := _pending_spawns[i]
		s.time_left -= delta
		if s.time_left <= 0.0:
			_pending_spawns.remove_at(i)
			_spawn_player(s.team, s.is_queen, s.device, true)
		else:
			i += 1


# --- Ship -----------------------------------------------------------------

func _spawn_ship() -> void:
	var ship := SHIP_SCENE.instantiate()
	ship.position = Constants.to_godot(0.0, BOTTOM + H / 36.0)
	ship_holder.add_child(ship)
	ship.spawn_targets()
	ship.reached_goal.connect(end_game.bind("Ship"))


# --- Gates ----------------------------------------------------------------

func _spawn_gates() -> void:
	for g in GATE_POSITIONS:
		_spawn_gate(g[0], g[1])


func _spawn_gate(x: float, y: float) -> Area2D:
	var gate := GATE_SCENE.instantiate()
	gate.position = Constants.to_godot(x, y)
	gates.add_child(gate)
	return gate


# --- Joining and leaving --------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _handle_menu_input(event):
		return
	if settings_menu.is_open:
		return
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				_join(event.device, Constants.Team.YELLOW)
			JOY_BUTTON_RIGHT_SHOULDER:
				_join(event.device, Constants.Team.PURPLE)
			JOY_BUTTON_BACK:
				_leave(event.device)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_join(Constants.KEYBOARD_ARROWS, Constants.Team.YELLOW)
			KEY_2:
				_join(Constants.KEYBOARD_ARROWS, Constants.Team.PURPLE)
			KEY_3:
				_join(Constants.KEYBOARD_WASD, Constants.Team.YELLOW)
			KEY_4:
				_join(Constants.KEYBOARD_WASD, Constants.Team.PURPLE)
			KEY_BACKSPACE:
				_leave(Constants.KEYBOARD_ARROWS)
			KEY_DELETE:
				_leave(Constants.KEYBOARD_WASD)


## Start (keyboard: Escape) opens the settings menu; F11 / Alt+Enter toggles
## fullscreen from anywhere. Returns true when the event was consumed.
func _handle_menu_input(event: InputEvent) -> bool:
	var open_menu := false
	if event is InputEventJoypadButton and event.pressed:
		open_menu = event.button_index == JOY_BUTTON_START
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			SettingsMenu.toggle_fullscreen()
			SettingsMenu.save_settings()
			return true
		open_menu = event.keycode == KEY_ESCAPE
	if not open_menu:
		return false
	if settings_menu.is_open:
		settings_menu.close()
	else:
		settings_menu.open()
	return true


func _join(device: int, team: int) -> void:
	if _find_player(device) != null or _is_respawning(device):
		return
	var is_queen := _find_queen(team) == null and not _queen_respawning(team)
	_spawn_player(team, is_queen, device)
	_update_hud()


func _is_respawning(device: int) -> bool:
	for s in _pending_spawns:
		if s.device == device:
			return true
	return false


func _queen_respawning(team: int) -> bool:
	for s in _pending_spawns:
		if s.is_queen and s.team == team:
			return true
	return false


func _leave(device: int) -> void:
	if state != State.JOIN:
		return
	var p := _find_player(device)
	if p == null:
		return
	if p.is_queen:
		for g in _join_gates:
			if g.team == p.team:
				g.set_neutral()
	p.queue_free()
	p.device = -999  # so _find_player ignores it until freed
	_update_hud()


func _find_player(device: int) -> CharacterBody2D:
	for p in players.get_children():
		if p.device == device:
			return p
	return null


func _find_queen(team: int) -> CharacterBody2D:
	for p in players.get_children():
		if p.is_queen and p.team == team and p.device != -999:
			return p
	return null


func _spawn_player(team: int, is_queen: bool, device: int,
		start_invincible := false) -> CharacterBody2D:
	var p := PLAYER_SCENE.instantiate()
	p.setup(team, is_queen, device, start_invincible)
	var x := -W / 20.0 if team == Constants.Team.YELLOW else W / 20.0
	p.position = Constants.to_godot(x, TOP - H / 9.0)
	p.contact.connect(_on_player_contact)
	players.add_child(p)
	return p


# --- HUD ------------------------------------------------------------------

func _update_hud() -> void:
	match state:
		State.JOIN:
			var lines := ["LB: join Yellow    RB: join Purple    Select: leave",
					"Keyboard: 1 / 2 to join with arrows, 3 / 4 to join with WASD"]
			var missing: Array[String] = []
			for team in [Constants.Team.YELLOW, Constants.Team.PURPLE]:
				if _find_queen(team) == null:
					missing.append(Constants.TEAM_NAMES[team])
			if missing.is_empty():
				lines.append("Both queens: fly through your start gate to begin")
			else:
				lines.append("Waiting for a %s queen" % " and ".join(missing))
			hud_label.text = "\n".join(lines)
			hud_label.remove_theme_color_override("font_color")
			hud_label.visible = true
		State.PLAY:
			hud_label.visible = false


func _update_lives() -> void:
	for team in lives_labels:
		lives_labels[team].text = "Lives: %d" % (Constants.queen_lives - queen_deaths[team])
