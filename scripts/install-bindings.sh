#!/usr/bin/env bash
# Adds the three keybindings this plugin's README shows as examples to
# ~/.config/hypr/bindings.lua - SUPER+Q (overview), SUPER+SHIFT+Q (save the
# current workspace), and SUPER+SHIFT+ALT+Q (this plugin's own settings).
#
# Not run by `omarchy plugin add` - Omarchy's installer deliberately never
# runs plugin code or install hooks, so this is opt-in: run it yourself,
# once, after installing the plugin. It never overwrites a key that already
# does something else; SUPER+Q is the one binding the overview actually
# needs, so a conflict there aborts before anything is written at all,
# rather than leaving you with only the other two.
set -euo pipefail

bindings_file="${HOME}/.config/hypr/bindings.lua"
toggle="omarchy-shell shell toggle better-workspaces"

# key | description | command
overview_binding="SUPER + Q|Workspace overview|${toggle} '{}'"
save_binding="SUPER + SHIFT + Q|Save current workspace|${toggle} '{\"view\":\"save\"}'"
settings_binding="SUPER + SHIFT + ALT + Q|Better Workspaces settings|${toggle} '{\"view\":\"settings\"}'"

if ! command -v omarchy >/dev/null 2>&1; then
  echo "omarchy command not found - this only works on an Omarchy install." >&2
  exit 1
fi

if [[ ! -f "$bindings_file" ]]; then
  echo "No $bindings_file found - nothing to edit." >&2
  exit 1
fi

# Omarchy's own keybindings listing merges its default binds with every
# override in bindings.lua, in whatever format Hyprland itself resolved -
# the one source that's actually authoritative, so this asks it rather than
# re-parsing bindings.lua (and every default binding file behind it) by hand.
listing="$(omarchy menu keybindings --print)"

# "SUPER + SHIFT + ALT + Q" (how bindings.lua writes a combo) and
# "SUPER SHIFT ALT + Q" (how the listing prints it) name the same combo -
# reduce both to a sorted, space-separated, upper-case token set so they
# compare equal regardless of which separator was used or what order the
# modifiers came in.
normalize() {
  tr '+' ' ' <<<"$1" | tr '[:lower:]' '[:upper:]' | tr -s '[:space:]' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ *$//'
}

# Prints "bound|<description>" for a key the listing already resolves to
# something, or "free|" for one it doesn't.
#
# Whether the key is taken and what it's taken by are two separate answers,
# not one: a binding is allowed to carry no description at all, and reading
# "no description" as "no binding" would report an occupied key as free and
# then quietly shadow it. Only the first field decides whether a key can be
# written to; the description is for the message and the already-set-up
# check.
binding_state_for() {
  local norm_key
  norm_key="$(normalize "$1")"
  local line combo desc
  while IFS= read -r line; do
    [[ "$line" == *"→"* ]] || continue
    combo="${line%%→*}"
    desc="${line#*→}"
    combo="$(sed 's/[[:space:]]*$//' <<<"$combo")"
    desc="$(sed 's/^[[:space:]]*//' <<<"$desc")"
    if [[ "$(normalize "$combo")" == "$norm_key" ]]; then
      printf 'bound|%s\n' "$desc"
      return 0
    fi
  done <<<"$listing"
  printf 'free|\n'
  return 0
}

# How to name a binding in a message when it has no description of its own.
describe() {
  [[ -n "$1" ]] && echo "\"$1\"" || echo "a binding with no description"
}

# Checks one candidate against the listing and reports what it found.
# Echoes the candidate back out (for the caller to collect) only when it's
# free to add.
check_binding() {
  local entry="$1" key description state bound existing
  IFS='|' read -r key description _ <<<"$entry"
  state="$(binding_state_for "$key")"
  bound="${state%%|*}"
  existing="${state#*|}"

  if [[ "$bound" == "free" ]]; then
    echo "  $key -> free, will add \"$description\"" >&2
    echo "$entry"
  elif [[ "$existing" == "$description" ]]; then
    echo "  $key -> already set up" >&2
  else
    echo "  $key -> already bound to $(describe "$existing"), skipping" >&2
  fi
}

echo "Checking keybindings against \`omarchy menu keybindings --print\`..." >&2

overview_state="$(binding_state_for "SUPER + Q")"
overview_bound="${overview_state%%|*}"
overview_existing="${overview_state#*|}"
if [[ "$overview_bound" == "bound" && "$overview_existing" != "Workspace overview" ]]; then
  echo "  SUPER + Q -> already bound to $(describe "$overview_existing")" >&2
  echo "SUPER + Q is the overview's own key and is already taken - aborting without changing anything." >&2
  echo "Pick a free key yourself and add it as shown in the README, under \"Opening it\"." >&2
  exit 1
fi

to_add=()
for entry in "$overview_binding" "$save_binding" "$settings_binding"; do
  result="$(check_binding "$entry")"
  [[ -n "$result" ]] && to_add+=("$result")
done

if [[ ${#to_add[@]} -eq 0 ]]; then
  echo "Nothing to add - every binding is already set up." >&2
  exit 0
fi

backup="${bindings_file}.bak.$(date +%s)"
cp "$bindings_file" "$backup"
echo "Backed up bindings.lua to $backup" >&2

{
  echo ""
  echo "-- Better Workspaces: added by install-bindings.sh."
  for entry in "${to_add[@]}"; do
    IFS='|' read -r key description command <<<"$entry"
    printf 'o.bind("%s", "%s",\n  [[%s]])\n' "$key" "$description" "$command"
  done
} >> "$bindings_file"

echo "Added ${#to_add[@]} binding(s) to $bindings_file - Hyprland picks up the change on save." >&2
