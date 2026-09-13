extends Node2D
## Builds the platform layout in code, mirroring src/platforms.rs from the Rust
## version. Coordinates in the tables below are in the original game's system
## (centre origin, y up) and converted with Constants.to_godot.

const GROUND_TEXTURE := preload("res://assets/ground.png")

const W := Constants.WINDOW_WIDTH
const H := Constants.WINDOW_HEIGHT
const BOTTOM := -H / 2.0
const TOP := H / 2.0
const RIGHT := W / 2.0
const PH := Constants.PLATFORM_HEIGHT

# (x, y, width) for the right half; mirrored for the left half.
const MIRRORED_PLATFORMS := [
	[0.0, BOTTOM, W],                                     # floor
	[RIGHT - W / 24.0, BOTTOM + H / 9.0, W / 12.0],       # layer 1
	[RIGHT - W / 5.0, BOTTOM + H / 9.0, W / 30.0],
	[RIGHT - W / 7.0, BOTTOM + 2.0 * H / 9.0, W / 25.0],  # layer 2
	[RIGHT - W / 3.2, BOTTOM + 2.0 * H / 9.0, W / 20.0],
	[RIGHT - W / 40.0, BOTTOM + 3.0 * H / 9.0, W / 20.0], # layer 3
	[W / 10.0, BOTTOM + 3.0 * H / 9.0, W / 20.0],
	[RIGHT - W / 5.0, BOTTOM + 4.0 * H / 9.0, W / 5.0],   # layer 4
	[RIGHT - W / 40.0, BOTTOM + 5.0 * H / 9.0, W / 20.0], # layer 5
	[W / 10.0, BOTTOM + 5.0 * H / 9.0, W / 20.0],
	[RIGHT - W / 5.0, BOTTOM + 5.0 * H / 9.0, W / 15.0],
	[RIGHT - W / 8.0, BOTTOM + 6.0 * H / 9.0, W / 25.0],  # layer 6
	[RIGHT - W / 3.2, BOTTOM + 6.0 * H / 9.0, W / 25.0],
	[RIGHT - W / 40.0, BOTTOM + 7.0 * H / 9.0, W / 20.0], # layer 7
	[W / 20.0, BOTTOM + 7.0 * H / 9.0, W / 10.0],
	[RIGHT - W / 5.0, BOTTOM + 7.0 * H / 9.0, W / 15.0],
	[RIGHT - W / 3.2, BOTTOM + 8.0 * H / 9.0, W / 25.0],  # layer 8
	[0.0, TOP, W],                                        # ceiling
]

# (y, width) centred platforms.
const CENTER_PLATFORMS := [
	[BOTTOM + H / 9.0, W / 4.0],
	[BOTTOM + 2.0 * H / 9.0, W / 20.0],
	[BOTTOM + 4.0 * H / 9.0, W / 20.0],
]


func _ready() -> void:
	for sign in [1.0, -1.0]:
		for p in MIRRORED_PLATFORMS:
			add_platform(p[0] * sign, p[1], p[2], PH, true)
	for p in CENTER_PLATFORMS:
		add_platform(0.0, p[0], p[1], PH, true)
	# Vertical divider between the two hives at the top of the map.
	add_platform(0.0, BOTTOM + 8.0 * H / 9.0, PH, 2.0 * H / 9.0, false)
	# Outer walls on the upper part of the map (no wrapping there).
	for sign in [-1.0, 1.0]:
		add_platform(RIGHT * sign, BOTTOM + 7.0 * H / 9.0, PH, 4.0 * H / 9.0, false)


## Adds a solid platform. x/y are in the original game's coordinates.
func add_platform(x: float, y: float, width: float, height: float, is_floor: bool,
		color := Color.WHITE) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = Constants.to_godot(x, y)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, height)
	shape.shape = rect
	body.add_child(shape)

	var sprite := Sprite2D.new()
	sprite.texture = GROUND_TEXTURE
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.modulate = color
	# Tile the 12x12 ground texture along the platform's long axis only.
	var tex := GROUND_TEXTURE.get_size()
	if is_floor:
		sprite.region_rect = Rect2(0, 0, width, tex.y)
		sprite.scale = Vector2(1.0, height / tex.y)
	else:
		sprite.region_rect = Rect2(0, 0, tex.x, height)
		sprite.scale = Vector2(width / tex.x, 1.0)
	sprite.z_index = -10
	body.add_child(sprite)

	add_child(body)
	return body
