extends Area2D
## The snail ("ship"). A worker who touches it while it is free becomes its
## driver; it then crawls toward that team's goal post. Any other worker who
## touches an occupied ship is knocked away. Mirrors src/ship.rs.

signal reached_goal(team: int)

const WIDTH := 124.0 / 2.0
const HEIGHT := 67.0 / 2.0
## Distance from the map centre to each goal, in pixels.
const WIN_SPOT := Constants.WINDOW_WIDTH / 2.0 - Constants.WINDOW_WIDTH / 18.0
const WIN_SPOT_WIDTH := 50.0
const SHIP_TEXTURE := preload("res://assets/ship.png")
const TARGET_TEXTURE := preload("res://assets/ship-target.png")

var driver: CharacterBody2D = null
## Constants.Team of the driver, or -1 while free.
var team := -1

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	sprite.scale = Vector2(WIDTH, HEIGHT) / SHIP_TEXTURE.get_size()
	# Sensor covers the whole shell so a worker touching it from any side counts.
	($CollisionShape2D.shape as RectangleShape2D).size = Vector2(WIDTH, HEIGHT)
	collision_layer = 0
	collision_mask = Constants.LAYER_PLAYERS
	body_entered.connect(_on_body_entered)


## Adds the two coloured goal posts as siblings of this ship.
func spawn_targets() -> void:
	for pair in [[-1.0, Constants.Team.YELLOW], [1.0, Constants.Team.PURPLE]]:
		var target := Sprite2D.new()
		target.texture = TARGET_TEXTURE
		target.scale = Vector2.ONE * WIN_SPOT_WIDTH / TARGET_TEXTURE.get_size()
		target.modulate = Constants.TEAM_COLORS[pair[1]]
		target.position = position + Vector2(WIN_SPOT * pair[0], 0.0)
		target.z_index = -1
		get_parent().add_child(target)


func _physics_process(delta: float) -> void:
	if driver == null:
		return
	var direction := -1.0 if team == Constants.Team.YELLOW else 1.0
	position.x += direction * Constants.ship_speed * delta
	driver.position = rider_position()
	if absf(position.x - Constants.WINDOW_WIDTH / 2.0) > WIN_SPOT:
		reached_goal.emit(team)


## Where the driver stands: on top of the shell.
func rider_position() -> Vector2:
	var driver_height: float = driver._render_size().y
	return position + Vector2(0.0, -(driver_height / 2.0 + HEIGHT / 2.0))


func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("pick_up_berry") or body.has_wings or body == driver:
		return
	if driver == null:
		mount(body)
	else:
		body.knock_back(-1.0 if body.position.x < position.x else 1.0)


func mount(worker: CharacterBody2D) -> void:
	driver = worker
	team = worker.team
	worker.riding_ship = self
	worker.position = rider_position()
	sprite.modulate = Constants.TEAM_COLORS[team]


func dismount() -> void:
	if driver != null:
		driver.riding_ship = null
	driver = null
	team = -1
	sprite.modulate = Color.WHITE
