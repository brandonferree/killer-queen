extends CharacterBody2D
## One player (worker or queen). Movement mirrors src/player.rs from the Rust
## version: impulse-based acceleration with linear friction, hard velocity
## clamps, a single jump for workers and repeatable wing flaps for the queen.
##
## Input comes straight from a device id so several gamepads can play at once
## without per-player InputMap actions. Device -1 means the keyboard.

## Emitted when this player's hitbox starts touching another player. Main
## resolves who dies or gets knocked back (src/player.rs players_attack).
signal contact(me: CharacterBody2D, other: CharacterBody2D)

const SPRITESHEETS := {
	Constants.Team.YELLOW: {
		"worker": preload("res://assets/spritesheets/workerYellow.png"),
		"queen": preload("res://assets/spritesheets/queenYellow.png"),
		"fighter": preload("res://assets/spritesheets/fighterYellow.png"),
	},
	Constants.Team.PURPLE: {
		"worker": preload("res://assets/spritesheets/workerPurple.png"),
		"queen": preload("res://assets/spritesheets/queenPurple.png"),
		"fighter": preload("res://assets/spritesheets/fighterPurple.png"),
	},
}

const WORKER_SIZE := Vector2(40, 40)
const WINGED_SIZE := Vector2(60, 60)
## Seconds a berry-carrying worker must stand in a friendly gate (src/gates.rs).
const GATE_TIME := 1.0
## The contact hitbox is the collider grown by this much on every side, so two
## bodies resting against each other still overlap.
const HITBOX_MARGIN := 3.0

# --- Tuning (px, px/s, px/s^2). Impulses are divided by mass like the
# original Rapier bodies, so these numbers match src/player.rs. ---
@export_group("Movement")
@export var max_velocity_x := 600.0
@export var min_velocity_x := 40.0   # below this, releasing the stick stops you
@export var movement_impulse_ground := 180.0
@export var movement_impulse_air := 115.0
@export var friction_ground := 0.5
@export var friction_air := 0.3
@export_group("Vertical")
@export var gravity := 1850.0        # tuned by feel; original used Rapier gravity x15
@export var dive_gravity_scale := 3.0
@export var max_fall_speed := 400.0
@export var max_dive_speed := 1200.0
@export var max_rise_speed := 600.0
@export var jump_impulse := 46.0
@export var fly_impulse := 73.0
@export_group("Sprite")
@export var anim_frame_ms := 70
@export_group("Respawn")
@export var invincibility_duration := 2.0
@export var blink_interval := 0.1

# --- Identity, set by whoever spawns the player. ---
var team: Constants.Team = Constants.Team.YELLOW
var is_queen := false
## A worker that carried a berry through a friendly gate: flies and fights
## like the queen but its deaths do not count, and it respawns as a worker.
var is_fighter := false
var device := -1
var has_wings: bool:
	get: return is_queen or is_fighter

# --- State ---
var facing_right := false
## True while the dive input is held (queens and fighters only).
var is_diving := false
## Seconds spent transforming inside a gate, or -1 when not transforming.
var gate_time := -1.0
## Workers carry at most one berry; shown as a small sprite beside them.
var has_berry := false:
	set(value):
		has_berry = value
		if is_node_ready():
			held_berry.visible = value
## The ship this worker is driving, or null.
var riding_ship: Area2D = null
## Seconds of spawn protection left; the sprite blinks while positive.
var invincible_time := 0.0
var _blink_time := 0.0
var _jump_was_down := false
var _anim_frames: Array[int] = []
var _anim_index := 0
var _anim_time := 0.0
var _frames: Array[AtlasTexture] = []
## Pixel size of one cropped sprite tile; the sprite is scaled from this.
var _crop := Vector2.ONE

# Sprite tile layout of the 50x50 sheets: 2x2 tiles of 25x25 with padding.
const TILE := 25.0
const FRAME_STAND := 0
const FRAMES_WALK: Array[int] = [1, 0]
const FRAMES_FLY: Array[int] = [2, 0]
const FRAMES_DIVE: Array[int] = [3]

# Collider is narrower than the rendered sprite, as in the original.
const COLLIDER_WIDTH_MULTIPLIER := 0.4

@onready var sprite: Sprite2D = $Sprite2D
@onready var collider: CollisionShape2D = $CollisionShape2D
@onready var held_berry: Sprite2D = $HeldBerry
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/CollisionShape2D

## Mass follows the original collider (metres, density 1).
var mass: float:
	get:
		var s := _render_size()
		return (s.x * COLLIDER_WIDTH_MULTIPLIER / 100.0) * (s.y / 100.0)


func setup(p_team: Constants.Team, p_is_queen: bool, p_device: int,
		start_invincible := false) -> void:
	team = p_team
	is_queen = p_is_queen
	device = p_device
	facing_right = team == Constants.Team.PURPLE
	if start_invincible:
		invincible_time = invincibility_duration


func _ready() -> void:
	_build_frames()
	collider.shape = RectangleShape2D.new()
	hitbox_shape.shape = RectangleShape2D.new()
	_apply_size()
	collision_layer = Constants.LAYER_PLAYERS
	collision_mask = Constants.LAYER_WORLD | Constants.LAYER_PLAYERS
	held_berry.visible = has_berry
	_set_frame(FRAME_STAND)
	hitbox.body_entered.connect(_on_hitbox_body_entered)


## Called by a berry sensor. Returns true if this player took the berry.
func pick_up_berry() -> bool:
	if has_wings or has_berry or riding_ship != null:
		return false
	has_berry = true
	return true


## Horizontal shove, e.g. from bumping into an occupied ship. direction is -1/+1.
func knock_back(direction: float) -> void:
	velocity.x += direction * fly_impulse / mass


## Half width/height of the physics collider, used by the combat rules.
func half_extents() -> Vector2:
	var s := _render_size()
	return Vector2(s.x * COLLIDER_WIDTH_MULTIPLIER, s.y) / 2.0


# --- Gate transformation (src/gates.rs) ------------------------------------

## Called by a gate when a berry-carrying worker enters it.
func start_gate_transform() -> void:
	if gate_time < 0.0 and has_berry and not has_wings:
		gate_time = 0.0


## Called by a gate when a player leaves it before the transformation finishes.
func cancel_gate_transform() -> void:
	if gate_time < 0.0:
		return
	gate_time = -1.0
	sprite.scale = _render_size() / _crop
	sprite.position.y = 0.0


func _tick_gate_transform(delta: float) -> void:
	if gate_time < 0.0:
		return
	gate_time += delta
	if gate_time >= GATE_TIME:
		_become_fighter()
		return
	# Grow the sprite towards the winged size, keeping the feet on the ground.
	var size := WORKER_SIZE.lerp(WINGED_SIZE, gate_time / GATE_TIME)
	sprite.scale = size / _crop
	sprite.position.y = -(size.y - WORKER_SIZE.y) / 2.0


func _become_fighter() -> void:
	gate_time = -1.0
	is_fighter = true
	has_berry = false
	# The collider grows around the centre, so lift it to keep the feet down.
	position.y -= (WINGED_SIZE.y - WORKER_SIZE.y) / 2.0
	sprite.position.y = 0.0
	_build_frames()
	_apply_size()
	_anim_frames = []
	_set_frame(FRAME_STAND)


func _render_size() -> Vector2:
	return WINGED_SIZE if has_wings else WORKER_SIZE


## Sizes the physics collider and the contact hitbox for the current role.
func _apply_size() -> void:
	var size := _render_size()
	(collider.shape as RectangleShape2D).size = Vector2(size.x * COLLIDER_WIDTH_MULTIPLIER, size.y)
	(hitbox_shape.shape as RectangleShape2D).size = (
		Vector2(size.x * COLLIDER_WIDTH_MULTIPLIER, size.y) + Vector2.ONE * 2.0 * HITBOX_MARGIN)


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body != self and body is CharacterBody2D and body.has_method("setup"):
		contact.emit(self, body)


func _build_frames() -> void:
	var role := "queen" if is_queen else ("fighter" if is_fighter else "worker")
	var sheet: Texture2D = SPRITESHEETS[team][role]
	var pad := Vector2(2, 3) if has_wings else Vector2(2, 5)
	_frames.clear()
	for i in 4:
		var col := i % 2
		var row := i / 2
		var tex := AtlasTexture.new()
		tex.atlas = sheet
		tex.region = Rect2(col * TILE + pad.x, row * TILE + pad.y, TILE - 2 * pad.x, TILE - 2 * pad.y)
		_frames.append(tex)
	# Stretch the cropped tile to the render size, like the original custom_size.
	_crop = Vector2(TILE - 2 * pad.x, TILE - 2 * pad.y)
	sprite.scale = _render_size() / _crop


func _set_frame(index: int) -> void:
	sprite.texture = _frames[index]


func _physics_process(delta: float) -> void:
	_update_invincibility(delta)
	_tick_gate_transform(delta)
	var move := _read_move_axis()
	var jump_down := _read_jump()
	var jump_just_pressed := jump_down and not _jump_was_down
	_jump_was_down = jump_down

	if riding_ship != null:
		# The ship carries us; jumping hops off (src/ship.rs jump_off_ship).
		if jump_just_pressed:
			riding_ship.dismount()
			velocity = Vector2(0.0, -jump_impulse / mass)
		else:
			position = riding_ship.rider_position()
			velocity = Vector2.ZERO
			_update_animation(delta, true, false)
			return
		jump_just_pressed = false

	var dive := has_wings and _read_dive()
	is_diving = dive
	var on_ground := is_on_floor()
	var m := mass

	# Horizontal movement (src/player.rs movement + friction systems).
	if move != 0.0 and not (dive and on_ground):
		facing_right = move > 0.0
		var impulse := movement_impulse_ground if on_ground else movement_impulse_air
		velocity.x += move * impulse / m * delta
	elif absf(velocity.x) < min_velocity_x:
		velocity.x = 0.0
	velocity.x = clampf(velocity.x, -max_velocity_x, max_velocity_x)
	var friction := friction_ground if on_ground else friction_air
	velocity.x -= velocity.x * friction / m * delta

	# Vertical: gravity, jump / fly, dive, clamps.
	if not on_ground:
		velocity.y += gravity * (dive_gravity_scale if dive else 1.0) * delta
	if has_wings:
		if jump_just_pressed and not dive:
			velocity.y -= fly_impulse / m
	elif jump_just_pressed and on_ground:
		velocity.y -= jump_impulse / m
	var max_down := max_dive_speed if dive else max_fall_speed
	var max_up := max_rise_speed if has_wings else INF
	velocity.y = clampf(velocity.y, -max_up, max_down)

	move_and_slide()
	_wrap_around_screen()
	_update_animation(delta, on_ground, dive)


func _wrap_around_screen() -> void:
	var w := Constants.WINDOW_WIDTH
	var h := Constants.WINDOW_HEIGHT
	if position.x > w:
		position.x -= w
	elif position.x < 0.0:
		position.x += w
	if position.y > h:
		position.y -= h
	elif position.y < 0.0:
		position.y += h


func _update_invincibility(delta: float) -> void:
	if invincible_time <= 0.0:
		return
	invincible_time -= delta
	_blink_time += delta
	if invincible_time <= 0.0:
		visible = true
	elif _blink_time >= blink_interval:
		_blink_time = 0.0
		visible = not visible


func _update_animation(delta: float, on_ground: bool, dive: bool) -> void:
	sprite.flip_h = facing_right
	held_berry.position.x = absf(held_berry.position.x) * (1.0 if facing_right else -1.0)
	var running := absf(velocity.x) >= 10.0
	var wanted: Array[int]
	if dive:
		wanted = FRAMES_DIVE
	elif not on_ground:
		wanted = FRAMES_FLY
	elif running:
		wanted = FRAMES_WALK
	else:
		wanted = []
	if wanted != _anim_frames:
		_anim_frames = wanted
		_anim_index = 0
		_anim_time = 0.0
		_set_frame(wanted[0] if not wanted.is_empty() else FRAME_STAND)
		return
	if wanted.is_empty():
		return
	_anim_time += delta
	if _anim_time >= anim_frame_ms / 1000.0:
		_anim_time = 0.0
		_anim_index = (_anim_index + 1) % wanted.size()
		_set_frame(wanted[_anim_index])


# --- Raw input per device -------------------------------------------------

func _read_move_axis() -> float:
	if device < 0:
		return Input.get_axis("ui_left", "ui_right")
	var axis := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	if absf(axis) < 0.5:
		axis = 0.0
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
		axis = -1.0
	elif Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
		axis = 1.0
	return axis


func _read_jump() -> bool:
	if device < 0:
		return Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP)
	return Input.is_joy_button_pressed(device, JOY_BUTTON_A)


func _read_dive() -> bool:
	if device < 0:
		return Input.is_key_pressed(KEY_DOWN)
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
		return true
	return Input.get_joy_axis(device, JOY_AXIS_LEFT_Y) > 0.9
