# Killer Queen (Godot 4)

Godot 4.7 port of the couch game. Open `godot/` in the Godot editor, or use the
command line below (`godot` = `%LOCALAPPDATA%\Microsoft\WinGet\Links\godot_console.exe`).

## Controls

- **Join screen:** LB joins Yellow, RB joins Purple (keyboard `1` / `2`).
  First player on a team is the queen. Select/Back (`Backspace`) leaves.
  Both queens fly through their start gate to begin.
- **In game:** D-pad/stick to move, jump button to jump (queens and fighters
  hold it to fly), down while airborne to dive.
- **Start** (keyboard `Esc`) opens the settings menu; **F11** or **Alt+Enter**
  toggles fullscreen.

## Settings menu

Up/Down picks a row, Left/Right changes the value, the jump button activates
Fullscreen / Resume / Quit. Queen lives, ship speed and berries to win match
the sliders from the original Rust build; everything is saved to
`user://settings.cfg` (`%APPDATA%\Godot\app_userdata\Killer Queen\`).

## Commands

Run the game:

```bash
godot --path godot
```

Run the smoke test (exit code 1 on failure; add `-- shot` without `--headless`
to also save a screenshot to `user://smoke.png`):

```bash
godot --headless --path godot -s res://tests/smoke.gd
```

Export the Windows build to `godot/build/KillerQueen.exe` (needs the export
templates, installed once from the editor's *Editor → Manage Export Templates*):

```bash
godot --headless --path godot --export-release "Windows Desktop"
```

The exe is self-contained (the game data is embedded), so it can be copied to
the TV laptop on its own.
