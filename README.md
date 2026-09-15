# Better Workspaces

An [Omarchy](https://omarchy.org/) shell plugin that replaces the built-in
`omarchy.workspaces` bar widget: each workspace shows a small icon per open
window, plus a full-screen overview to drag windows between workspaces and
save/restore whole workspace setups.

<img src="preview.png" alt="Better Workspaces screenshot" width="600">

## Install

```bash
omarchy plugin add https://github.com/LukasTrust/betterWorkspaces.git --enable
```

That's it - clicking the workspace you're already on opens the overview,
no further setup needed. If you want key shortcuts too, add these to
`~/.config/hypr/bindings.lua` (check `omarchy menu keybindings --print` first
for conflicts):

```lua
o.bind("SUPER + Q", "Workspace overview",
  [[omarchy-shell shell toggle better-workspaces '{}']])
o.bind("SUPER + SHIFT + Q", "Save current workspace",
  [[omarchy-shell shell toggle better-workspaces '{"view":"save"}']])
o.bind("SUPER + SHIFT + ALT + Q", "Better Workspaces settings",
  [[omarchy-shell shell toggle better-workspaces '{"view":"settings"}']])
```

A three-finger swipe up works too, via `~/.config/hypr/input.lua`:

```lua
hl.gesture({ fingers = 3, direction = "up", action = function()
  hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell toggle better-workspaces '{}'"))
end })
```

## The bar icons

New apps get an icon automatically, resolved the same way the Omarchy menu
does. Web apps (`omarchy webapp install`, Firefox/Chromium PWAs) get the
launcher's icon instead of a generic browser icon; games started from Steam,
Heroic or Lutris get their own icon (`gameIcons`). Override any app's icon
per-window-class in `shell.json` (see [Configuration](#configuration)).

- **Hover** an icon for that window's title. **Left-click** focuses it,
  switching workspace if needed. **Middle-click** closes it.
- With `groupApps` on, windows of the same app share one icon with a count
  badge; left-click cycles through them, middle-click closes the current one.

## The overview

Every workspace as a card filling the screen, windows drawn where they
really sit, each with its app icon. Opens by clicking the workspace you're
on, your own key, or the gesture above; closes with `Esc`, a click past the
cards, or the same key/gesture again.

<img src="screenshots/screenshot-overview.png" alt="Better Workspaces overview" width="700">

- **Click a window** to jump to it. **Middle-click** closes it.
- **Drag a window** onto another card to move it there, or onto `+` for a
  new workspace. **Drag the number under a card** onto another to swap their
  windows (Hyprland can't renumber a workspace, so this moves windows
  instead).
- **Arrow keys / `hjkl`** navigate, **Enter** opens, **`/`** searches by
  title or app (dims non-matches), **Esc** steps back or closes.
- **The gear** (top-right) opens settings; **the save icon** (top-left of
  each card) saves that workspace as a reusable setup.

### Saved setups

A strip along the bottom of the overview once you've saved at least one.

- **Click** a chip to open it on the active workspace; **drag** it onto a
  card (or `+`) to open it there instead.
- If the target workspace already has windows, `setupTargetMode` decides:
  `add` (default) opens alongside them, `replace` closes them first (a
  normal close request, not a kill).
- **×** deletes a chip; the other corner button assigns which workspace it
  should open on at boot.

Reopening a setup replays each window's own launch command and rebuilds its
tiled layout on a best-effort basis (exact only on an empty workspace).

## Configuration

Most settings are in Omarchy's **Setup > Plugins**, or the overview's gear
icon. Per-app icon overrides are only editable directly in
`~/.config/omarchy/shell.json`, on this widget's entry:

```jsonc
{
  "id": "better-workspaces",
  "maxIcons": 5,           // icons shown per workspace before "+N" overflow
  "iconSize": 14,          // icon size in px
  "minWorkspaces": 5,      // workspaces shown even while empty, counted from 1
  "hideEmpty": false,      // show only workspaces with windows in them
  "groupApps": false,      // one icon per app instead of one per window
  "gameIcons": true,       // a game's own icon instead of the generic fallback
  "overviewEnabled": true, // clicking the workspace you are on opens the overview
  "setupTargetMode": "add",     // "add" or "replace" when opening a setup on a busy workspace
  "focusAfterSetupDrop": true,  // switch to the target workspace after dropping a setup
  "icons": {
    // Window class/appId (case-insensitive, see `hyprctl clients`) -> an
    // icon-theme name or a literal glyph/emoji.
    "firefox": "🦊",
    "code": "󰨞",
    "steam": ""
  }
}
```

<img src="screenshots/screenshot-settings.png" alt="Better Workspaces settings" width="500">

## Remove

```bash
omarchy plugin remove better-workspaces
```

Two things live outside the plugin directory and survive removal on purpose:
saved setups (`~/.config/omarchy/better-workspaces/`, kept for a future
reinstall - delete by hand if you don't want that) and any keybindings you
added (remove those lines from `~/.config/hypr/bindings.lua`).

## Development

```bash
ln -s /path/to/betterWorkspaces ~/.config/omarchy/plugins/better-workspaces
omarchy plugin enable better-workspaces --section left
```

`omarchy restart shell` picks up code changes (the plugin watcher doesn't
follow symlinks reliably).

QML holds everything that needs a live Quickshell/Hyprland/window; `js/`
holds pure, dependency-free decision logic that's unit-testable under plain
Node - see the header comment in each `js/*.js` file for what it owns.

```bash
npm test            # js/ unit tests + coverage gate, stand-in API check
npm run test:qml    # widget behaviour, headless, against stand-in modules
npm run test:e2e    # real windows on your live Hyprland session (needs foot, jq)
```

Before publishing a change:

```bash
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" qml/*.qml
```

## License

MIT - see [LICENSE](LICENSE).
