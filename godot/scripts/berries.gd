extends Node2D
## Berries, flowers and hive cells: the economic win condition. Mirrors
## src/berries.rs. Berries on flowers are frozen bodies that only act as
## pickup sensors; berries dropped by a dead worker fall and bounce.

signal team_won(team: int, condition: String)

const RADIUS := 12.0
const BERRY_TEXTURE := preload("res://assets/berry.png")
const CELL_TEXTURE := preload("res://assets/berry-cell.png")
const FLOWER_TEXTURE := preload("res://assets/flower.png")

const W := Constants.WINDOW_WIDTH
const H := Constants.WINDOW_HEIGHT
const BOTTOM := -H / 2.0
const TOP := H / 2.0
const RIGHT := W / 2.0
const PH := Constants.PLATFORM_HEIGHT

# Berry bunch centres in original coordinates.
const BUNCH_POSITIONS := [
	[RIGHT - W / 5.0, BOTTOM + PH],                     # layer 0
	[-(RIGHT - W / 5.0), BOTTOM + PH],
	[0.0, BOTTOM + H / 9.0 + PH],                       # layer 1
	[0.0, BOTTOM + 2.0 * H / 9.0 + PH],                 # layer 2
	[RIGHT - W / 7.0, BOTTOM + 2.0 * H / 9.0 + PH],
	[-(RIGHT - W / 7.0), BOTTOM + 2.0 * H / 9.0 + PH],
	[W / 10.0, BOTTOM + 3.0 * H / 9.0 + PH],            # layer 3
	[-W / 10.0, BOTTOM + 3.0 * H / 9.0 + PH],
]

# Berry offsets (in radii) inside a bunch.
const BUNCH_OFFSETS := [
	[-2.0, 0.0], [0.0, 0.0], [2.0, 0.0],
	[-1.0, 1.5], [1.0, 1.5],
	[0.0, 3.0],
]

var collected := {Constants.Team.YELLOW: 0, Constants.Team.PURPLE: 0}


## Removes everything and lays out fresh flowers and empty hive cells.
func respawn() -> void:
	clear()
	for team in collected:
		collected[team] = 0
	for b in BUNCH_POSITIONS:
		_spawn_bunch(b[0], b[1])
	for team in [Constants.Team.YELLOW, Constants.Team.PURPLE]:
		var sign := -1.0 if team == Constants.Team.YELLOW else 1.0
		var placed := 0
		for x in range(-2, 100):
			for y in [2, 1, 0]:
				_spawn_cell(
					(W / 20.0 + x * RADIUS * 2.1) * sign,
					TOP - H / 7.5 + y * RADIUS * 2.1,
					team)
				placed += 1
				if placed >= Constants.berries_to_win:
					break
			if placed >= Constants.berries_to_win:
				break


func clear() -> void:
	for c in get_children():
		c.free()


# --- Berries ----------------------------------------------------------------

func _spawn_bunch(x: float, y: float) -> void:
	var flower := Sprite2D.new()
	flower.texture = FLOWER_TEXTURE
	flower.scale = Vector2(RADIUS * 8.0, RADIUS * 7.0 / 4.0) / FLOWER_TEXTURE.get_size()
	flower.position = Constants.to_godot(x, y - (11.0 / 8.0) * RADIUS)
	flower.z_index = -2
	add_child(flower)
	for o in BUNCH_OFFSETS:
		var berry := _make_berry(Constants.to_godot(x + o[0] * RADIUS, y + o[1] * RADIUS))
		berry.freeze = true
		berry.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		add_child(berry)


## Drops a loose, bouncing berry (e.g. where a worker carrying one died).
func spawn_dropped(pos: Vector2) -> void:
	# Deferred so it is safe to call from a collision callback (phase 4 combat).
	add_child.call_deferred(_make_berry(pos))


func _make_berry(pos: Vector2) -> RigidBody2D:
	var berry := RigidBody2D.new()
	berry.position = pos
	berry.collision_layer = Constants.LAYER_BERRIES
	berry.collision_mask = Constants.LAYER_WORLD
	var material := PhysicsMaterial.new()
	material.bounce = 0.7
	berry.physics_material_override = material
	berry.add_child(_circle_shape())

	var sprite := Sprite2D.new()
	sprite.texture = BERRY_TEXTURE
	sprite.scale = Vector2.ONE * RADIUS * 2.0 / BERRY_TEXTURE.get_size()
	sprite.z_index = -5
	berry.add_child(sprite)

	# Sensor that hands the berry to a worker who touches it.
	var pickup := Area2D.new()
	pickup.collision_layer = 0
	pickup.collision_mask = Constants.LAYER_PLAYERS
	pickup.add_child(_circle_shape())
	pickup.body_entered.connect(_on_berry_touched.bind(berry))
	berry.add_child(pickup)
	return berry


func _circle_shape() -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	return shape


func _on_berry_touched(body: Node2D, berry: RigidBody2D) -> void:
	if berry.is_queued_for_deletion():
		return
	if body.has_method("pick_up_berry") and body.pick_up_berry():
		berry.queue_free()


# --- Hive cells -------------------------------------------------------------

func _spawn_cell(x: float, y: float, team: int) -> void:
	var cell := Area2D.new()
	cell.position = Constants.to_godot(x, y)
	cell.collision_layer = 0
	cell.collision_mask = Constants.LAYER_PLAYERS
	cell.set_meta("team", team)
	cell.set_meta("filled", false)
	cell.add_child(_circle_shape())

	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = CELL_TEXTURE
	sprite.scale = Vector2.ONE * RADIUS / CELL_TEXTURE.get_size()
	sprite.modulate = Constants.TEAM_COLORS[team]
	cell.add_child(sprite)

	cell.body_entered.connect(_on_cell_entered.bind(cell))
	add_child(cell)


func _on_cell_entered(body: Node2D, cell: Area2D) -> void:
	if cell.get_meta("filled"):
		return
	if not body.has_method("pick_up_berry") or body.has_wings or not body.has_berry:
		return
	var team: int = cell.get_meta("team")
	if body.team != team:
		return
	body.has_berry = false
	cell.set_meta("filled", true)
	var sprite: Sprite2D = cell.get_node("Sprite2D")
	sprite.texture = BERRY_TEXTURE
	sprite.scale = Vector2.ONE * RADIUS * 2.0 / BERRY_TEXTURE.get_size()
	sprite.modulate = Color.WHITE
	collected[team] += 1
	if collected[team] >= Constants.berries_to_win:
		team_won.emit(team, "Economic")
