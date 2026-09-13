extends Area2D
## A gate on the map. Queens claim a gate for their team by flying through it.
## A worker carrying a berry through a gate its team owns (or a neutral one)
## becomes a fighter after standing in it for one second.

signal claimed(gate: Area2D)

const WIDTH := 40.0 * 1.2
const HEIGHT := 40.0 * 1.5
const FRAME_YELLOW := 0
const FRAME_PURPLE := 1
const FRAME_NEUTRAL := 2

## Constants.Team of the owner, or -1 while neutral.
var team := -1
## True for the two start gates used on the join screen.
var is_join_gate := false

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	sprite.scale = Vector2(WIDTH, HEIGHT) / Vector2(32, 32)
	($CollisionShape2D.shape as RectangleShape2D).size = Vector2(WIDTH, HEIGHT)
	set_neutral()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func set_neutral() -> void:
	team = -1
	sprite.frame = FRAME_NEUTRAL


func claim(p_team: int) -> void:
	team = p_team
	sprite.frame = FRAME_YELLOW if team == Constants.Team.YELLOW else FRAME_PURPLE
	claimed.emit(self)


func _on_body_entered(body: Node2D) -> void:
	if not body.has_method("setup"):
		return
	if body.is_queen:
		claim(body.team)
	# A worker carrying a berry starts turning into a fighter, unless the
	# other team owns this gate.
	if team >= 0 and team != body.team:
		return
	if body.has_berry:
		body.start_gate_transform()


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("setup"):
		body.cancel_gate_transform()
