extends CanvasLayer
class_name SettingsMenu
## Pause / settings menu. Replaces the egui window from src/settings.rs with
## something a fight stick can drive: Up/Down picks a row, Left/Right changes
## the value, the jump/accept button activates it, Start or Escape closes.
##
## Values live on Constants (static vars) and are saved to user://settings.cfg.

signal closed(berries_changed: bool)

const CONFIG_PATH := "user://settings.cfg"
const FONT := preload("res://assets/fonts/FiraSans-Bold.ttf")
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.08

const ROWS := [
	{"id": "queen_lives", "label": "Queen lives", "min": 1.0, "max": 15.0, "step": 1.0},
	{"id": "ship_speed", "label": "Ship speed", "min": 10.0, "max": 200.0, "step": 5.0},
	{"id": "berries_to_win", "label": "Berries to win", "min": 1.0, "max": 18.0, "step": 1.0},
	{"id": "fullscreen", "label": "Fullscreen"},
	{"id": "resume", "label": "Resume"},
	{"id": "quit", "label": "Quit game"},
]

var is_open := false
var _index := 0
var _labels: Array[Label] = []
var _berries_changed := false
var _repeat_dir := 0
var _repeat_time := 0.0


func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	set_process(false)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -360.0
	box.offset_right = 360.0
	box.offset_top = -220.0
	box.offset_bottom = 220.0
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	box.add_child(_make_label("SETTINGS", 48))
	for row in ROWS:
		var l := _make_label("", 36)
		box.add_child(l)
		_labels.append(l)
	box.add_child(_make_label(
		"Up/Down: pick    Left/Right: change    Start / Esc: close", 24))


func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- Open / close ---------------------------------------------------------

func open() -> void:
	if is_open:
		return
	is_open = true
	_berries_changed = false
	_index = 0
	visible = true
	set_process(true)
	get_tree().paused = true
	_refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	set_process(false)
	get_tree().paused = false
	save_settings()
	closed.emit(_berries_changed)


# --- Input ----------------------------------------------------------------

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_up"):
		_move(-1)
	elif Input.is_action_just_pressed("ui_down"):
		_move(1)
	if Input.is_action_just_pressed("ui_accept"):
		_activate()
		return

	var dir := 0
	if Input.is_action_pressed("ui_right"):
		dir = 1
	elif Input.is_action_pressed("ui_left"):
		dir = -1
	if dir != _repeat_dir:
		_repeat_dir = dir
		_repeat_time = REPEAT_DELAY
		if dir != 0:
			_change(dir)
	elif dir != 0:
		_repeat_time -= delta
		if _repeat_time <= 0.0:
			_repeat_time = REPEAT_RATE
			_change(dir)


func _move(step: int) -> void:
	_index = wrapi(_index + step, 0, ROWS.size())
	_refresh()


func _change(dir: int) -> void:
	var row: Dictionary = ROWS[_index]
	match row.id:
		"fullscreen":
			_set_fullscreen(not Constants.fullscreen)
		"resume", "quit":
			return
		_:
			var v: float = clampf(_get_value(row.id) + dir * row.step, row.min, row.max)
			_set_value(row.id, v)
	_refresh()


func _activate() -> void:
	match ROWS[_index].id:
		"fullscreen":
			_set_fullscreen(not Constants.fullscreen)
			_refresh()
		"resume":
			close()
		"quit":
			save_settings()
			get_tree().quit()


# --- Values ---------------------------------------------------------------

func _get_value(id: String) -> float:
	match id:
		"queen_lives":
			return float(Constants.queen_lives)
		"ship_speed":
			return Constants.ship_speed
		"berries_to_win":
			return float(Constants.berries_to_win)
	return 0.0


func _set_value(id: String, v: float) -> void:
	match id:
		"queen_lives":
			Constants.queen_lives = int(v)
		"ship_speed":
			Constants.ship_speed = v
		"berries_to_win":
			if int(v) != Constants.berries_to_win:
				Constants.berries_to_win = int(v)
				_berries_changed = true


func _value_text(row: Dictionary) -> String:
	match row.id:
		"fullscreen":
			return "On" if Constants.fullscreen else "Off"
		"resume", "quit":
			return ""
	return str(int(_get_value(row.id)))


func _refresh() -> void:
	for i in ROWS.size():
		var row: Dictionary = ROWS[i]
		var value := _value_text(row)
		var text: String = row.label
		if not value.is_empty():
			text = "%s:  %s" % [row.label, ("<  %s  >" % value) if i == _index else value]
		_labels[i].text = ("> %s" % text) if i == _index else text
		_labels[i].modulate = Color.WHITE if i == _index else Color(0.7, 0.7, 0.7)


# --- Fullscreen and persistence -------------------------------------------

static func _set_fullscreen(on: bool) -> void:
	Constants.fullscreen = on
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on
			else DisplayServer.WINDOW_MODE_WINDOWED)


static func toggle_fullscreen() -> void:
	_set_fullscreen(not Constants.fullscreen)


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	Constants.queen_lives = int(cfg.get_value("game", "queen_lives", Constants.queen_lives))
	Constants.ship_speed = float(cfg.get_value("game", "ship_speed", Constants.ship_speed))
	Constants.berries_to_win = int(cfg.get_value("game", "berries_to_win", Constants.berries_to_win))
	_set_fullscreen(bool(cfg.get_value("display", "fullscreen", false)))


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "queen_lives", Constants.queen_lives)
	cfg.set_value("game", "ship_speed", Constants.ship_speed)
	cfg.set_value("game", "berries_to_win", Constants.berries_to_win)
	cfg.set_value("display", "fullscreen", Constants.fullscreen)
	cfg.save(CONFIG_PATH)
