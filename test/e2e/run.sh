#!/usr/bin/env bash
# End-to-end check on the live Hyprland session: opens real windows and
# asserts on what the widget reports it is showing via its `state` IPC call.
#
#   test/e2e/run.sh          runs the current checkout in a throwaway
#                            Quickshell instance (real Quickshell, Hyprland
#                            and Omarchy modules; no window, own IPC socket)
#   test/e2e/run.sh --live   asks the widget on your actual bar instead
#
# BW_E2E_SETTINGS='{"maxIcons":2}' passes widget settings (default mode).
#
# Needs an Omarchy session, foot and jq. It briefly switches to a free
# workspace to open its test windows there, switches back afterwards and
# closes everything it opened. Don't type while it runs.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
readonly here repo
readonly PREFIX="bw-e2e"
readonly TIMEOUT_S=${E2E_TIMEOUT:-10}

mode=isolated
case ${1:-} in
  "") ;;
  --live) mode=live ;;
  *)
    echo "usage: $0 [--live]" >&2
    exit 2
    ;;
esac

passed=0
failed=0
pids=()
original_ws=""
ws=""
ws2=""
probe_dir=""
probe_pid=""
boot_probe_dir=""
boot_probe_pid=""
boot_home=""
boot_xdg_runtime=""

ok() {
  passed=$((passed + 1))
  printf '  ok    %s\n' "$1"
}

not_ok() {
  failed=$((failed + 1))
  printf '  FAIL  %s\n' "$1"
  [[ -z ${2:-} ]] || printf '        %s\n' "$2"
}

require() {
  command -v "$1" >/dev/null || {
    echo "missing dependency: $1" >&2
    exit 2
  }
}

focus_workspace() {
  hyprctl dispatch "hl.dsp.focus({ workspace = \"$1\" })" >/dev/null
}

open_window() {
  foot --app-id="$1" --title="$1" sleep infinity >/dev/null 2>&1 &
  pids+=("$!")
}

close_window() {
  kill "$1" 2>/dev/null || true
}

cleanup() {
  for pid in "${pids[@]}"; do
    close_window "$pid"
  done
  [[ -z $original_ws ]] || focus_workspace "$original_ws"
  if [[ -n $probe_pid ]]; then
    kill "$probe_pid" 2>/dev/null || true
    wait "$probe_pid" 2>/dev/null || true
  fi
  [[ -z $probe_dir ]] || rm -rf "$probe_dir"
  if [[ -n $boot_probe_pid ]]; then
    kill "$boot_probe_pid" 2>/dev/null || true
    wait "$boot_probe_pid" 2>/dev/null || true
  fi
  [[ -z $boot_probe_dir ]] || rm -rf "$boot_probe_dir"
  [[ -z $boot_home ]] || rm -rf "$boot_home"
  [[ -z $boot_xdg_runtime ]] || rm -rf "$boot_xdg_runtime"
}
trap cleanup EXIT

start_probe() {
  probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/bw-e2e.XXXXXX")
  ln -s "$OMARCHY_PATH/shell/Commons" "$probe_dir/Commons"
  ln -s "$OMARCHY_PATH/shell/Ui" "$probe_dir/Ui"
  ln -s "$repo" "$probe_dir/plugin"
  cp "$here/probe.qml" "$probe_dir/shell.qml"

  qs -p "$probe_dir" >"$probe_dir/log.txt" 2>&1 &
  probe_pid=$!

  local deadline=$((SECONDS + TIMEOUT_S))
  until qs ipc -p "$probe_dir" show 2>/dev/null | grep -q "target better-workspaces"; do
    if ((SECONDS >= deadline)) || ! kill -0 "$probe_pid" 2>/dev/null; then
      echo "the widget didn't come up in the probe instance:" >&2
      sed 's/\x1b\[[0-9;]*m//g' "$probe_dir/log.txt" >&2
      exit 2
    fi
    sleep 0.2
  done
}

# The boot service (Plugin.Service, `boot_probe.qml`) in its own probe,
# entirely separate from the widget one above: its own directory and IPC
# socket, and - critically - its own HOME and XDG_RUNTIME_DIR, so it never
# reads or writes the real user's setups.json or boot guard. It has no IPC
# target of its own to wait on (nothing to summon, it just runs), so
# readiness is whatever it actually does - the caller polls for that.
start_boot_probe() { # <window class the seeded setup opens> <boot workspace id>
  boot_home=$(mktemp -d "${TMPDIR:-/tmp}/bw-e2e-boot-home.XXXXXX")
  boot_xdg_runtime=$(mktemp -d "${TMPDIR:-/tmp}/bw-e2e-boot-runtime.XXXXXX")
  boot_probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/bw-e2e-boot.XXXXXX")
  ln -s "$repo" "$boot_probe_dir/plugin"
  cp "$here/boot_probe.qml" "$boot_probe_dir/shell.qml"

  mkdir -p "$boot_home/.config/omarchy/better-workspaces"
  cat >"$boot_home/.config/omarchy/better-workspaces/setups.json" <<EOF
{
  "schemaVersion": 1,
  "setups": {
    "E2EBoot": {
      "windows": [{
        "recipe": { "type": "argv", "argv": ["foot", "--app-id=$1", "--title=$1", "sleep", "infinity"] },
        "class": "$1",
        "floating": false,
        "fullscreen": false,
        "rect": { "x": 0, "y": 0, "width": 1, "height": 1 }
      }],
      "bootWorkspace": $2
    }
  }
}
EOF

  HOME="$boot_home" BW_E2E_BOOT_RUNTIME_DIR="$boot_xdg_runtime/better-workspaces" qs -p "$boot_probe_dir" \
    >"$boot_probe_dir/log-$(date +%s%N).txt" 2>&1 &
  boot_probe_pid=$!
}

stop_boot_probe() {
  [[ -z $boot_probe_pid ]] || {
    kill "$boot_probe_pid" 2>/dev/null || true
    wait "$boot_probe_pid" 2>/dev/null || true
    boot_probe_pid=""
  }
}

state() {
  if [[ $mode == live ]]; then
    omarchy-shell better-workspaces state
  else
    qs ipc -p "$probe_dir" call better-workspaces state
  fi
}

# expect <description> <jq filter>
# Re-reads the widget's state until the filter is true or the timeout
# passes: windows map and the bar updates asynchronously. $ws is available
# to the filter as the test workspace id.
expect() {
  local description=$1 filter=$2 current=""
  local deadline=$((SECONDS + TIMEOUT_S))
  while :; do
    current=$(state 2>&1 || true)
    if jq -e --argjson ws "$ws" "$filter" <<<"$current" >/dev/null 2>&1; then
      ok "$description"
      return
    fi
    ((SECONDS < deadline)) || break
    sleep 0.2
  done
  not_ok "$description" "state of workspace $ws: $(jq -c --argjson ws "$ws" '.workspaces[] | select(.id == $ws)' <<<"$current" 2>/dev/null || echo "$current")"
}

# Hyprland window addresses on the test workspace, normalized for comparison.
real_addresses() {
  hyprctl clients -j | jq -c --argjson ws "$ws" '[.[] | select(.workspace.id == $ws) | .address | ltrimstr("0x")] | sort'
}

: "${OMARCHY_PATH:?OMARCHY_PATH is not set - run this inside an Omarchy session}"
for dependency in hyprctl foot jq; do
  require "$dependency"
done

if [[ $mode == live ]]; then
  require omarchy-shell
  if ! state 2>/dev/null | jq -e '.workspaces' >/dev/null 2>&1; then
    echo "the widget on your bar isn't answering - is the plugin on the bar, and has the shell loaded this version? (omarchy restart shell)" >&2
    exit 2
  fi
else
  require qs
  start_probe
fi

# Above the always-shown workspaces, a workspace is only listed while it
# exists, so a free one there also proves the widget follows workspaces
# coming and going.
existing=$(hyprctl workspaces -j | jq -c '[.[].id]')
for candidate in 10 9 8 7 6; do
  jq -e --argjson id "$candidate" 'index($id) == null' <<<"$existing" >/dev/null || continue
  if [[ -z $ws ]]; then
    ws=$candidate
  elif [[ -z $ws2 ]]; then
    # A second free workspace, for the reorder check at the end. Not fatal
    # if there isn't one - that check is skipped instead.
    ws2=$candidate
  fi
done
[[ -n $ws ]] || {
  echo "no free workspace between 6 and 10 to test on" >&2
  exit 2
}

original_ws=$(hyprctl activeworkspace -j | jq '.id')
echo "Testing ($mode) on workspace $ws, returning to $original_ws afterwards"

expect "free workspace $ws isn't listed yet" '[.workspaces[].id] | index($ws) == null'

focus_workspace "$ws"
open_window "$PREFIX-a"
open_window "$PREFIX-a"
open_window "$PREFIX-b"

expect "workspace $ws is listed once it has windows" 'any(.workspaces[]; .id == $ws)'
expect "workspace $ws is marked focused" '.workspaces[] | select(.id == $ws) | .focused'
expect "workspace $ws counts its 3 windows" '.workspaces[] | select(.id == $ws) | .occupied and .windows == 3'
expect "one icon per window, up to maxIcons, rest as +N" \
  '.settings.maxIcons as $max | .workspaces[] | select(.id == $ws) | (.icons | length) == ([3, $max] | min) and .overflow == ([0, 3 - $max] | max)'
expect "every icon belongs to a test window" '.workspaces[] | select(.id == $ws) | all(.icons[]; .key | startswith("bw-e2e-"))'

addresses=$(real_addresses)
expect "icons point at the real Hyprland windows" \
  "(.settings.maxIcons < 3) or ([.workspaces[] | select(.id == \$ws) | .icons[].address | ltrimstr(\"0x\")] | sort == $addresses)"

close_window "${pids[2]}"
expect "closing a window removes its icon" \
  '.workspaces[] | select(.id == $ws) | .windows == 2 and all(.icons[]; .key == "bw-e2e-a")'

focus_workspace "$original_ws"
expect "workspace $ws loses focus when switching away" '.workspaces[] | select(.id == $ws) | .focused | not'

for pid in "${pids[@]}"; do
  close_window "$pid"
done
pids=()
expect "workspace $ws disappears once empty again" '[.workspaces[].id] | index($ws) == null'

# ---- reordering two workspaces ---------------------------------------------
#
# Dragging one workspace card onto another can't be driven from a shell
# script, but what it ends up asking Hyprland for can: these two dispatches
# are exactly what the overview sends for that drag, with the addresses of
# real windows filled in. Nothing below the running compositor can tell you
# whether this dispatcher form really moves a window that was never focused,
# and leaves the focus alone while doing it - which is the whole point of
# checking it here.
address_of() {
  hyprctl clients -j | jq -r --arg class "$1" 'first(.[] | select(.class == $class) | .address) // ""'
}

# The address as the plugin actually has it: Quickshell reports it without
# the "0x" that Hyprland's `address:` selector needs. That difference is
# invisible from inside the plugin - Hyprland answers "ok" to a selector
# that matches nothing and quietly does nothing - so it can only be caught
# here, against a real compositor.
widget_address_of() {
  state | jq -r --arg class "$1" 'first(.workspaces[].icons[] | select(.key == $class) | .address) // ""'
}

move_request() { # <address as quickshell reports it> <workspace>
  printf 'hl.dsp.window.move({ workspace = "%s", window = "address:0x%s", follow = false })' "$2" "${1#0x}"
}

# A window lands on whichever workspace is focused when it maps, not when it
# was launched, so each one has to be there before switching away again.
wait_for_window() {
  local deadline=$((SECONDS + TIMEOUT_S))
  until [[ -n $(address_of "$1") ]]; do
    ((SECONDS < deadline)) || return 1
    sleep 0.2
  done
}

if [[ -z $ws2 ]]; then
  echo "  skip  reordering: needs a second free workspace between 6 and 10"
else
  focus_workspace "$ws"
  open_window "$PREFIX-swap-a"
  wait_for_window "$PREFIX-swap-a" || not_ok "reorder window a opened" "it never appeared"
  focus_workspace "$ws2"
  open_window "$PREFIX-swap-b"
  wait_for_window "$PREFIX-swap-b" || not_ok "reorder window b opened" "it never appeared"
  focus_workspace "$original_ws"

  expect "both reorder workspaces have their window" \
    "(.workspaces[] | select(.id == \$ws) | any(.icons[]; .key == \"$PREFIX-swap-a\"))
     and (.workspaces[] | select(.id == $ws2) | any(.icons[]; .key == \"$PREFIX-swap-b\"))"

  swap_a=$(widget_address_of "$PREFIX-swap-a")
  swap_b=$(widget_address_of "$PREFIX-swap-b")
  if [[ -z $swap_a || -z $swap_b ]]; then
    not_ok "reordering swaps the two workspaces' windows" "the widget didn't report the test windows"
  else
    # First the trap: the address exactly as the plugin holds it. Hyprland
    # accepts this and moves nothing, so a plugin that forgets the "0x"
    # looks like it works and doesn't.
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"$ws2\", window = \"address:${swap_a#0x}\", follow = false })" >/dev/null
    sleep 0.5
    expect "an address without the 0x prefix moves nothing" \
      "(.workspaces[] | select(.id == \$ws) | any(.icons[]; .key == \"$PREFIX-swap-a\"))"

    # Focusing a window by address has to take you to the workspace it is
    # on. The wlr activate request Quickshell also offers does not - it marks
    # the window active and leaves the focused workspace alone - and no test
    # below a real compositor can tell the two apart.
    focus_request() { printf 'hl.dsp.focus({ window = "address:0x%s" })' "${1#0x}"; }
    hyprctl dispatch "$(focus_request "$swap_a")" >/dev/null
    sleep 0.5
    if [[ $(hyprctl activeworkspace -j | jq '.id') == "$ws" ]]; then
      ok "focusing a window by address switches to its workspace"
    else
      not_ok "focusing a window by address switches to its workspace" \
        "still on workspace $(hyprctl activeworkspace -j | jq '.id'), wanted $ws"
    fi
    focus_workspace "$original_ws"

    hyprctl dispatch "$(move_request "$swap_b" "$ws")" >/dev/null
    hyprctl dispatch "$(move_request "$swap_a" "$ws2")" >/dev/null

    expect "reordering swaps the two workspaces' windows" \
      "(.workspaces[] | select(.id == \$ws) | any(.icons[]; .key == \"$PREFIX-swap-b\"))
       and (.workspaces[] | select(.id == $ws2) | any(.icons[]; .key == \"$PREFIX-swap-a\"))"
    expect "reordering leaves nothing behind on either workspace" \
      "(.workspaces[] | select(.id == \$ws) | .windows == 1)
       and (.workspaces[] | select(.id == $ws2) | .windows == 1)"
  fi

  for pid in "${pids[@]}"; do
    close_window "$pid"
  done
  pids=()
fi

# ---- the boot service -------------------------------------------------------
#
# Only meaningful against an isolated probe: it needs its own throwaway
# HOME/XDG_RUNTIME_DIR (see start_boot_probe), which only makes sense for a
# probe process this script owns - the live shell already has its own real
# guard file from whenever Hyprland actually started, and touching that here
# would be indistinguishable from a bug in the real thing.
if [[ $mode == live ]]; then
  echo "  skip  boot service: only meaningful against an isolated probe, not the live shell"
else
  boot_ws=""
  boot_existing=$(hyprctl workspaces -j | jq -c '[.[].id]')
  for candidate in 10 9 8 7 6; do
    [[ $candidate != "$ws" && $candidate != "${ws2:-}" ]] || continue
    jq -e --argjson id "$candidate" 'index($id) == null' <<<"$boot_existing" >/dev/null || continue
    boot_ws=$candidate
    break
  done

  if [[ -z $boot_ws ]]; then
    echo "  skip  boot service: no free workspace between 6 and 10 left to test on"
  else
    boot_class="$PREFIX-boot"
    start_boot_probe "$boot_class" "$boot_ws"

    boot_deadline=$((SECONDS + TIMEOUT_S))
    until [[ -n $(address_of "$boot_class") ]]; do
      if ((SECONDS >= boot_deadline)); then
        not_ok "boot service opens the assigned setup" \
          "window never appeared; log: $(sed 's/\x1b\[[0-9;]*m//g' "$boot_probe_dir"/log-*.txt 2>/dev/null | tail -5)"
        break
      fi
      sleep 0.2
    done

    if [[ -n $(address_of "$boot_class") ]]; then
      boot_opened_ws=$(hyprctl clients -j | jq -r --arg class "$boot_class" '.[] | select(.class == $class) | .workspace.id')
      if [[ $boot_opened_ws == "$boot_ws" ]]; then
        ok "boot service opens the assigned setup on its workspace"
      else
        not_ok "boot service opens the assigned setup on its workspace" \
          "opened on $boot_opened_ws, wanted $boot_ws"
      fi
    fi

    if [[ -f "$boot_xdg_runtime/better-workspaces/boot-guard" ]]; then
      ok "boot service writes the guard file"
    else
      not_ok "boot service writes the guard file" "not found under $boot_xdg_runtime/better-workspaces"
    fi

    stop_boot_probe

    # A restart in the same Hyprland session (e.g. `omarchy restart shell`)
    # reuses the same HOME/guard directory here, so the guard the run above
    # wrote is still there - the whole point of it.
    HOME="$boot_home" BW_E2E_BOOT_RUNTIME_DIR="$boot_xdg_runtime/better-workspaces" qs -p "$boot_probe_dir" \
      >"$boot_probe_dir/log-$(date +%s%N).txt" 2>&1 &
    boot_probe_pid=$!
    sleep 2
    boot_count=$(hyprctl clients -j | jq --arg class "$boot_class" '[.[] | select(.class == $class)] | length')
    if [[ $boot_count == "1" ]]; then
      ok "a second run in the same session does not reopen it"
    else
      not_ok "a second run in the same session does not reopen it" \
        "found $boot_count window(s) of class $boot_class, wanted 1"
    fi
    stop_boot_probe

    hyprctl clients -j | jq -r --arg class "$boot_class" '.[] | select(.class == $class) | .pid' |
      while read -r boot_pid; do close_window "$boot_pid"; done
  fi
fi

echo
echo "$passed passed, $failed failed"
((failed == 0))
