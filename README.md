# Better Workspaces

An [Omarchy](https://omarchy.org/) shell plugin that replaces the built-in
`omarchy.workspaces` bar widget with one that also shows a small icon for
every window open on each workspace - so you can see what's actually running
where, not just which workspaces are occupied.

Icons come from your installed applications' own icon (resolved the same way
the Omarchy menu resolves app icons), so new apps get an icon automatically
with no configuration. You can override any app's icon per-window-class if
the automatic match isn't the one you want.

Everything is resolved from Hyprland's own IPC event stream and Quickshell's
built-in desktop-entry/icon-theme lookups - no polling, no shelling out to
external commands - and icon lookups are cached by window class, so repeat
windows of the same app (e.g. two terminals) never repeat the lookup.

<img src="preview.png" alt="Better Workspaces screenshot" width="600">

## Using the icons

- Hover an icon to see that window's title as a tooltip.
- Left-click an icon to focus that exact window.
- Middle-click an icon to close that window.
- Clicking the workspace number or anywhere else in the cell still just
  focuses the workspace, same as before.

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
own. Bind it to a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + ALT + Q", "Better Workspaces settings",
  [[omarchy-shell shell toggle better-workspaces '{"view":"settings"}']])
```

Changes apply as you make them and are written back to your `shell.json`
entry; `Esc` or a click outside closes the view. Values outside the allowed
range are pulled to the nearest one, and anything unusable falls back to the
default.

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
  widget reports it shows. By default it runs the current checkout in a
  throwaway Quickshell instance (real modules, no window, doesn't touch your
  bar); `npm run test:e2e -- --live` asks the widget on your bar instead.
  It briefly switches to a free workspace between 6 and 10 - don't type
  while it runs. Needs `foot` and `jq`.

The widget reports what it's showing as JSON, which is what the end-to-end
tests read:

```bash
omarchy-shell better-workspaces state
```

Before publishing a change, also validate the plugin the way Omarchy does:

```bash
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Workspaces.qml
```

## License

MIT - see [LICENSE](LICENSE).
