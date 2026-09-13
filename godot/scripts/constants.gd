class_name Constants
## Shared layout constants. The original Bevy game used a y-up world centred on
## the screen; Godot uses y-down with the origin at the top-left, so everything
## goes through [method to_godot].

const WINDOW_WIDTH := 1920.0
const WINDOW_HEIGHT := 1016.0
const PLATFORM_HEIGHT := 20.0

enum Team { YELLOW, PURPLE }

const TEAM_COLORS := {
	Team.YELLOW: Color(1.0, 0.773, 0.0),
	Team.PURPLE: Color(0.435, 0.0, 1.0),
}
const TEAM_NAMES := {
	Team.YELLOW: "Yellow",
	Team.PURPLE: "Purple",
}

# --- Match settings (src/settings.rs defaults). Phase 5 adds a menu for these. ---
static var queen_lives := 3
static var ship_speed := 30.0
static var berries_to_win := 6
static var fullscreen := false

# --- Keyboard "devices". Gamepads use their own non-negative device ids. ---
const KEYBOARD_ARROWS := -1  ## arrows + Space/Up + Down
const KEYBOARD_WASD := -2    ## A/D + W/F + S

# --- Collision layers (bit masks). Platforms use the default layer 1. ---
const LAYER_WORLD := 1
const LAYER_PLAYERS := 2
const LAYER_BERRIES := 4


## Convert a position from the original game's coordinate system
## (origin at screen centre, y up) to Godot's (origin top-left, y down).
static func to_godot(x: float, y: float) -> Vector2:
	return Vector2(WINDOW_WIDTH / 2.0 + x, WINDOW_HEIGHT / 2.0 - y)


static func other_team(team: int) -> int:
	return Team.PURPLE if team == Team.YELLOW else Team.YELLOW
