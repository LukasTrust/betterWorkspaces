#!/usr/bin/env bash
# Undoes install-bindings.sh: removes the keybinding block it appended to
# ~/.config/hypr/bindings.lua, and - with --purge - this plugin's saved
# setups too.
#
# `omarchy plugin remove` deletes the plugin directory and its shell.json
# entry and nothing else, so anything written outside the plugin directory
# outlives it: the bindings here, and ~/.config/omarchy/better-workspaces.
# That is what this cleans up. Run it before removing the plugin, or after -
# neither ordering matters, nothing here reads the plugin itself.
#
# Only ever removes what install-bindings.sh wrote, recognised by the marker
# comment it leaves behind. A binding you added by hand is left alone and
# reported, because there is no marker to tell it apart from any other line
# you wrote yourself.
set -euo pipefail

bindings_file="${HOME}/.config/hypr/bindings.lua"
setups_dir="${HOME}/.config/omarchy/better-workspaces"
marker="-- Better Workspaces: added by install-bindings.sh."

purge=0
case ${1:-} in
  "") ;;
  --purge) purge=1 ;;
  -h | --help)
    echo "Usage: $0 [--purge]"
    echo
    echo "  (no flag)  remove the keybindings install-bindings.sh added"
    echo "  --purge    also delete saved setups in $setups_dir"
    exit 0
    ;;
  *)
    echo "unknown option: $1 (try --help)" >&2
    exit 2
    ;;
esac

# ---- the keybindings --------------------------------------------------------

if [[ ! -f "$bindings_file" ]]; then
  echo "No $bindings_file found - nothing to remove." >&2
else
  # Walks the file and drops each marker comment together with the o.bind
  # calls underneath it, stopping at the first line that isn't one - so a
  # block is removed exactly as far as install-bindings.sh wrote it, and
  # anything you appended after it survives. Blank lines are buffered rather
  # than printed immediately, so the blank line the installer put *before*
  # its marker goes with the block instead of piling up.
  removed_count=$(awk -v marker="$marker" '
    function flush_blanks(   i) {
      for (i = 1; i <= nblank; i++) print blanks[i]
      nblank = 0
    }
    BEGIN { state = 0; nblank = 0; removed = 0 }
    state == 0 && /^[[:space:]]*$/ { blanks[++nblank] = $0; next }
    state == 0 && $0 == marker { nblank = 0; state = 1; next }
    # Inside a block: another o.bind starts a binding, anything else ends it.
    # The line that ended it still has to go through the blank-buffering
    # above, or two adjacent blocks leave two blank lines behind where the
    # file had one.
    state == 1 {
      if ($0 ~ /^o\.bind\(/) { removed++; state = 2; next }
      state = 0
      if ($0 ~ /^[[:space:]]*$/) { blanks[++nblank] = $0; next }
    }
    # Inside one o.bind call, until its closing "]])".
    state == 2 {
      if ($0 ~ /\]\][[:space:]]*\)[[:space:]]*$/) state = 1
      next
    }
    { flush_blanks(); print }
    END { flush_blanks(); print removed > "/dev/stderr" }
  ' "$bindings_file" 2>&1 >"${bindings_file}.tmp.$$")

  if [[ "$removed_count" -eq 0 ]]; then
    rm -f "${bindings_file}.tmp.$$"
    echo "No bindings from install-bindings.sh found in $bindings_file." >&2
  else
    backup="${bindings_file}.bak.$(date +%s)"
    cp "$bindings_file" "$backup"
    echo "Backed up bindings.lua to $backup" >&2
    mv "${bindings_file}.tmp.$$" "$bindings_file"
    echo "Removed $removed_count binding(s) from $bindings_file - Hyprland picks up the change on save." >&2
  fi

  # Anything still naming this plugin was written by hand (or by an older
  # version that didn't leave a marker), so it's reported rather than
  # guessed at.
  leftovers="$(grep -n "better-workspaces" "$bindings_file" || true)"
  if [[ -n "$leftovers" ]]; then
    echo >&2
    echo "These lines still mention this plugin and were left alone - remove them by hand if you want them gone:" >&2
    sed 's/^/  /' <<<"$leftovers" >&2
  fi
fi

# ---- the saved setups -------------------------------------------------------

if [[ ! -d "$setups_dir" ]]; then
  exit 0
fi

if (( purge )); then
  rm -rf "$setups_dir"
  echo >&2
  echo "Deleted $setups_dir." >&2
else
  echo >&2
  echo "Saved setups are still in $setups_dir - 'omarchy plugin remove' doesn't" >&2
  echo "touch them, so reinstalling picks them back up. Delete them with: $0 --purge" >&2
fi
