# Flight 2048

**Play 2048 while you ride a flight path in WoW Forever.**

Flight 2048 is a World of Warcraft add-on for the WoW Forever client. When you take a flight path, a 2048 window opens in the classic WoW dialog style. It closes again when you land, and your game is saved for your next flight.


![Flight 2048 in game](flight2048.png)

## Features

- **Opens when your flight starts.** Take any flight path and the game window appears. When you land it closes and prints your score in chat.
- **Your game carries over between flights.** The board, score and best score are saved per account. If you `/reload` mid-flight, the window comes back.
- **Classic 2048 rules.** A 4×4 board. Each move adds a new tile: a 2 (90% of the time) or a 4. A tile can merge only once per move. Reaching 2048 shows a "You Win!" screen with a *Keep Playing* option, and a *Game Over* screen appears when no moves are left.
- **Classic WoW look.** The window uses the old dialog box border, the gold title header, the red close button and the standard buttons. You can drag it around, and Escape closes it.
- **Tiles are colored by item quality.** See [Tile colors](#tile-colors).
- **Flight status line.** Shows where you're flying and how long you've been in the air, for example *Flying to Stormwind – 1:23*.
- **Small animations.** Merged tiles bump and new tiles pop in. Your score shows a floating "+N" when you gain points.

## Installation

1. Download the latest release, or click **Code → Download ZIP** on this page.
2. Copy the `Flight2048` folder into your WoW Forever client's `Interface\AddOns\` folder.
3. Make sure the folder layout looks like this:
   ```
   Interface\AddOns\Flight2048\Flight2048.toc
   Interface\AddOns\Flight2048\Flight2048.lua
   ```
   The folder **must** be named `Flight2048`, the same name as the `.toc` file, or the game won't load it. A GitHub ZIP unpacks to `Flight2048-Forever-main\Flight2048\`, so copy the inner `Flight2048` folder.
4. Restart the game, or `/reload` if you're already logged in. Check that **Flight 2048** is enabled in the AddOns list on the character select screen.

## Controls

| Input | Action |
|---|---|
| Arrow keys or `W` `A` `S` `D` | Slide the tiles |
| Click and drag on the board | Slide the tiles in the direction you dragged (a swipe) |
| Drag the window border | Move the window |
| `Esc` | Close the window |

While you're flying, the keys work wherever your mouse is, since you can't move your character anyway. On the ground, they only work while your mouse is over the window, so they never stop you from walking.

## Slash commands

`/f2048` and `/flight2048` are the same command.

| Command | What it does |
|---|---|
| `/f2048` | Show or hide the game window |
| `/f2048 new` | Start a new game |
| `/f2048 auto` | Turn opening when a flight starts on or off (default: **on**) |
| `/f2048 close` | Turn closing when you land on or off (default: **on**) |
| `/f2048 reset` | Move the window back to the center of the screen |
| `/f2048 help` | List the commands in chat |

## Tile colors

Tiles use WoW's item quality colors, so you can tell your progress at a glance.

| Tile | Color |
|---|---|
| 2 | Poor (gray) |
| 4 | Common (white) |
| 8 | Uncommon (green) |
| 16 | Rare (blue) |
| 32 | Epic (purple) |
| 64 | Legendary (orange) |
| 128 | Artifact (light gold) |
| 256 | Heirloom (light blue) |
| 512 | Red |
| 1024 | Gold |
| 2048 and above | Pale gold |

## How it's built

Flight 2048 is plain Lua against the WoW UI API. It has **no build step and no libraries**: the two files in `Flight2048/` are exactly what the game loads.

```
Flight2048/
├── Flight2048.toc   # Add-on manifest: interface version, title, saved variables
└── Flight2048.lua   # Everything else: game logic, UI, flight detection, commands
```

### Target client

WoW Forever reports **interface version `16001`** and uses the modern (Midnight-era, 12.x) UI API, not the old 1.12 Classic one. The add-on relies on modern API pieces such as `BackdropTemplate`, `C_Timer`, `SetColorTexture`, the Scale/Alpha/Translation animations and `SOUNDKIT`. Classic Era add-on code (`this`, `arg1`, Lua 5.0) would not work here.

### Code layout

`Flight2048.lua` is organized top to bottom into these sections:

1. **Constants.** Board size (4), tile size (68 px), gap (8 px), the win tile (2048), the repo URL, and the tile color table.
2. **Game logic.** These are pure functions that work on a 4×4 table of numbers, where `0` means an empty cell.
   - `NewBoard`, `SpawnTile`, `CanMove` and `HasTile` create and check the board.
   - `LineCoords(dir, i)` returns the four cells of row or column `i`, ordered from the edge the tiles slide toward. This lets one routine handle all four directions.
   - `Slide(board, dir)` gathers the non-empty tiles in each line, merges equal pairs from the leading edge (each tile merges once), and writes the line back. It returns whether anything moved, the points gained, and which cells merged (used for animations).
3. **UI helpers and rendering.** The window keeps 16 fixed cell frames. `UpdateCell` restyles a cell for its value (border, background, text color and font size), and `Render` redraws the whole board and both scores. Tiles don't slide on screen. The "pop" and "bump" effects come from Scale animations on the cell frames.
4. **Game flow.** `NewGame`, `DoMove` and `CheckEndStates` handle the win screen, the game-over screen and the best score.
5. **Frame construction.** `BuildFrame` creates the whole window once at load time. That includes the dialog backdrop and header, the score boxes, the board, the win/game-over overlay, the status line, the buttons and the branding footer. It also sets up keyboard and mouse input and adds the window to `UISpecialFrames` so Escape closes it.
6. **Flight detection.** See below.
7. **Init and events.** On `ADDON_LOADED` the add-on fills in the saved settings, builds the frame and loads the saved board.
8. **Slash commands.**

### Flight detection

The add-on checks `UnitOnTaxi("player")` and reacts when the answer changes:

- **Events.** `PLAYER_CONTROL_LOST`, `PLAYER_CONTROL_GAINED`, `TAXIMAP_CLOSED` and `PLAYER_ENTERING_WORLD` each trigger a check right away, then again 0.5 s and 1.5 s later. The client doesn't always report the taxi state at the exact moment the event fires.
- **Backup check.** A `C_Timer` ticker also checks once per second, in case an event is missed.
- **Destination.** A `hooksecurefunc` on `TakeTaxiNode` records the name of the node you picked (the part before the comma, such as "Stormwind") for the status line.

A change to "on taxi" calls `OnFlightStart`, which starts the timer, begins a new game if the old one is over, and shows the window. A change back calls `OnFlightEnd`, which hides the window and prints your score.

### Keyboard handling

The window uses `EnableKeyboard(true)` with an `OnKeyDown` handler. For each key it calls `SetPropagateKeyboardInput(not handled)`. Keys the game uses (movement keys while flying, or while the mouse is over the window) are consumed, and every other key, including Escape and your keybinds, passes through to the game as normal. The propagation call is skipped during combat lockdown, where it isn't allowed.

### Saved data

Saved per account in `WTF\Account\<ACCOUNT>\SavedVariables\Flight2048.lua` as `Flight2048DB`:

| Key | Meaning |
|---|---|
| `board` | The current 4×4 board |
| `score` | Current score |
| `best` | Best score |
| `won` | Whether you already reached 2048 in this game (so the win screen shows only once) |
| `autoOpen` | Open when a flight starts |
| `autoClose` | Close when you land |

To wipe everything, log out and delete that file.

## Troubleshooting

- **The add-on doesn't show in the AddOns list.** Check that the folder is named `Flight2048` and holds the `.toc` directly, not in another subfolder. If the list says it's *out of date*, tick **Load out of date AddOns**.
- **The window didn't open on a flight.** Run `/f2048 auto` and check that chat says *on*. You can always open it by hand with `/f2048`.
- **A Lua error appears.** Please [open an issue](https://github.com/chase-hunter/Flight2048-Forever/issues) and paste the full error text. Enabling Lua errors (`/console scriptErrors 1`) will show it.

## Contributing

Issues and pull requests are welcome. There is nothing to build: edit `Flight2048/Flight2048.lua`, copy the folder into your `AddOns` folder, and `/reload` in game to test. Please keep the classic WoW UI style and keep the add-on free of outside libraries.

---

[github.com/chase-hunter/Flight2048-Forever](https://github.com/chase-hunter/Flight2048-Forever)
