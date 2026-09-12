# Better Workspaces

An [Omarchy](https://omarchy.org/) shell plugin that replaces the built-in
`omarchy.workspaces` bar widget with one that also shows a small icon for
every window open on each workspace - so you can see what's actually running
where, not just which workspaces are occupied.

Icons come from your installed applications' own icon (resolved the same way
the Omarchy menu resolves app icons), so new apps get an icon automatically
with no configuration. Proton-run games in your Steam library get their own
icon too (`gameIcons`, resolved straight from the window class - no extra
process, no polling) - this covers games launched from Steam itself as well
as other launchers like Heroic, as long as Proton is doing the running and
the game is also in your Steam library. It doesn't cover native Linux game
binaries: Steam only tags the window class for Proton games, so a native
build (e.g. Valheim) shows the generic icon like any other unrecognized app,
unless you override it. You can override any app's icon per-window-class if
the automatic match isn't the one you want.

Everything is resolved from Hyprland's own IPC event stream and Quickshell's
built-in desktop-entry/icon-theme lookups - no polling, no shelling out to
external commands - and icon lookups are cached by window class, so repeat
windows of the same app (e.g. two terminals) never repeat the lookup.

<img src="preview.png" alt="Better Workspaces screenshot" width="600">

## Using the icons

- Hover an icon to see that window's title as a tooltip.
- Left-click an icon to focus that exact window, switching workspace if it is
  on another one.
- Middle-click an icon to close that window.
- Clicking the workspace number or anywhere else in the cell still just
  focuses the workspace, same as before.

With `groupApps` on, windows of the same app share one icon with a count
badge once there are 2 or more. Hovering lists every window's title; left-
click focuses the group's most recently focused window, and each further
click steps to the next one. Middle-click closes the currently focused (or
last-focused) window in the group. `maxIcons` and the `+N` overflow then
count apps, not windows.

## The overview

Every workspace as a card, laid out to fill the screen, each showing its
wallpaper with its windows drawn where they really sit on it. That is the
whole view - the cards are large enough to recognise a window in, so there is
nothing else to page through. A card is the shape of the screen its workspace
is on, and every window carries its app icon in the corner, so a black
terminal is still obviously a terminal.

### Opening it

Three ways, none of which touches your Hyprland bindings:

- **Click the workspace you are already on** in the bar. Clicking any other
  workspace still just switches to it, as before. This is the one that needs
  no setup; `overviewEnabled` turns it back into a plain switch.
- **A key of your own**, added to `~/.config/hypr/bindings.lua`. `SUPER + Q`
  is free in a stock Omarchy:

  ```lua
  o.bind("SUPER + Q", "Workspace overview",
    [[omarchy-shell shell toggle better-workspaces '{}']])
  ```

- **A touchpad gesture**, in `~/.config/hypr/input.lua` - for example a
  three-finger swipe up:

  ```lua
  hl.gesture({ fingers = 3, direction = "up", action = function()
    hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell toggle better-workspaces '{}'"))
  end })
  ```

It opens on the monitor Hyprland says has focus. The same command closes it
again, as do `Esc` and a click past the cards.

### Using it

- **Click a window** to go straight to it - the right workspace and the right
  window in one - and the overview closes behind you.
- **Click anywhere else on a card** to go to that workspace; the overview
  closes too.
- **Drag a window onto another card** to move it there. The focus stays where
  it is, so you can keep rearranging. Dropping it back where it came from
  does nothing.
- **Drag a window onto the `+` card** to move it to a new workspace. `+`
  always offers the one after the highest you have: a strip of 1-5 offers 6,
  and one that already reaches 8 offers 9. The number under the card says
  which one you are about to get.
- **Drag the number under a card** onto another card to reorder workspaces.
  Hyprland can't renumber a workspace, so this moves the windows instead:
  dropping 5 onto 2 leaves 5's windows on 2, 2's on 3, and so on. Nothing is
  renamed. The number is the handle rather than the card itself because a
  busy workspace leaves no empty spot on its card to grab.
- **Arrow keys or `hjkl`** walk the cards, **Enter** opens the selected one
  (or makes the new one, on `+`), **Esc** closes.
- **The gear in the top-right corner** opens the settings over the cards.
  They stay on screen, previews and all, because most of the settings change
  what the overview shows - `Esc` there goes back to them rather than closing
  everything.

### Previews

Window previews come from the compositor's screencopy protocol, and only
while the overview is actually open - closing it tears every capture down.
Only the workspace you are on keeps updating; every other card takes a single
frame and then stops. A window the compositor won't hand a frame for shows
its app icon on a plain surface instead.

Where a window sits comes from its `hyprctl clients` entry, which Hyprland
can deliver later than the window itself, so the overview asks Hyprland for
fresh geometry as it opens. That is a single request on the way in, not a
poll.

## Install

```bash
omarchy plugin add https://github.com/LukasTrust/betterWorkspaces.git --enable
```

## Manual / dev install

```bash
ln -s /path/to/betterWorkspaces ~/.config/omarchy/plugins/better-workspaces
omarchy plugin enable better-workspaces --section left
```

Omarchy's plugin watcher doesn't follow symlinks, so edits in the checkout
aren't hot-reloaded. Re-creating the link (`ln -sfn "$PWD"
~/.config/omarchy/plugins/better-workspaces`) triggers Omarchy's plugin
reload, but that doesn't reliably pick up the new code; `omarchy restart
shell` always does. To check a change without touching your bar, use the
tests below - they always run the current checkout.

## Remove

```bash
omarchy plugin disable better-workspaces   # keep it installed, just hide it
omarchy plugin remove better-workspaces    # uninstall entirely
```

Removing it restores the stock `omarchy.workspaces` widget; no other files or
settings are left behind beyond this widget's entry in `shell.json`.

## Configuration

### The edit view

Every setting except the per-app `icons` overrides has a small editor of its
own. The gear in the overview's top-right corner opens it, or bind it to a
key of its own in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + ALT + Q", "Better Workspaces settings",
  [[omarchy-shell shell toggle better-workspaces '{"view":"settings"}']])
```

Changes apply as you make them and are written back to your `shell.json`
entry. Values outside the allowed range are pulled to the nearest one, and
anything unusable falls back to the default.

`Esc`, or a click outside the card, closes the editor - or, when you got
there through the overview's gear, steps back to the overview so you can see
what your change did.

### shell.json

The per-app `icons` overrides are only editable here. Everything is
configured inline in `~/.config/omarchy/shell.json`, on this widget's layout
entry:

```jsonc
{
  "id": "better-workspaces",
  "maxIcons": 5,           // icons shown per workspace before "+N" overflow
  "iconSize": 14,          // icon size in px
  "minWorkspaces": 5,      // workspaces shown even while empty, counted from 1
  "hideEmpty": false,      // show only workspaces with windows in them
  "groupApps": false,      // one icon per app, with a count badge, instead of one per window
  "gameIcons": true,       // use a Proton game's own icon instead of the generic fallback
  "overviewEnabled": true, // clicking the workspace you are on opens the overview
  "icons": {
    // Override the icon for a window class/appId. Value can be either an
    // icon-theme name or a literal glyph/emoji.
    "firefox": "🦊",
    "code": "󰨞",
    "steam": ""
  }
}
```

Window class/appId matching is case-insensitive. To find a window's class,
run `hyprctl clients` and look at its `class` field.

A workspace above `minWorkspaces` is shown while Hyprland knows about it,
which is as long as it has windows or you are on it. With `hideEmpty` on,
`minWorkspaces` is ignored and the bar shows only the workspaces that have
windows in them, plus the one you are on - so the strip grows and shrinks as
you work.

## Testing

Three levels, from fast and isolated to real:

```bash
npm test            # logic.js unit tests + coverage gate, stand-in API check
npm run test:qml    # widget behaviour, headless, against stand-in modules
npm run test:e2e    # real windows on your live Hyprland session
```

- **`npm test`** runs the pure logic in `logic.js` under plain Node, with a
  coverage gate. It also checks that every member of the QML test
  stand-ins exists on the real Quickshell/Omarchy type, so a QML test can't
  pass against an API that doesn't exist (skipped where Quickshell isn't
  installed, e.g. in CI).
- **`npm run test:qml`** loads `Workspaces.qml` in `qmltestrunner` against
  the stand-ins in `test/qml/stubs`, so it needs neither Hyprland nor
  Omarchy. Needs `qmltestrunner` (Arch: `qt6-declarative`).
- **`npm run test:e2e`** opens real `foot` windows and checks what the
  widget reports it shows, and that the requests the overview sends really do
  move windows between workspaces on a running Hyprland. By default it runs
  the current checkout in a throwaway Quickshell instance (real modules, no
  window, doesn't touch your bar); `npm run test:e2e -- --live` asks the
  widget on your bar instead. It briefly switches to free workspaces between
  6 and 10 - don't type while it runs. Needs `foot` and `jq`.

The widget reports what it's showing as JSON, which is what the end-to-end
tests read:

```bash
omarchy-shell better-workspaces state
```

Before publishing a change, also validate the plugin the way Omarchy does:

```bash
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" *.qml
```

## License

MIT - see [LICENSE](LICENSE).
