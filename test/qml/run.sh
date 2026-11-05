#!/usr/bin/env bash
# Runs the QML tests headless against the stand-in Quickshell/Omarchy
# modules in test/qml/stubs, so they need neither a running Hyprland nor an
# Omarchy install.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

runner="$(command -v qmltestrunner || true)"
if [[ -z "$runner" && -x /usr/lib/qt6/bin/qmltestrunner ]]; then
  runner=/usr/lib/qt6/bin/qmltestrunner
fi
if [[ -z "$runner" ]]; then
  echo "qmltestrunner not found - install qt6-declarative or put Qt's bin directory on PATH" >&2
  exit 1
fi

# Qt 6.12 added a `Color` singleton to QtQuick, and under qmltestrunner it
# wins over the stub `qs.Commons` Color whatever the import order - so every
# `Color.bar`/`Color.menu` read in a test came back undefined. Quickshell
# resolves `qs.*` itself, so the real shell is unaffected. The tests run on a
# copy with `import QtQuick` pinned to 6.11, from before that singleton,
# rather than renaming anything in the plugin itself.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/test"
cp -r "$repo/qml" "$repo/js" "$work/"
cp -r "$here" "$work/test/qml"
find "$work" -name '*.qml' -exec sed -i 's/^import QtQuick$/import QtQuick 6.11/' {} +

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
"$runner" -import "$work/test/qml/stubs" -input "$work/test/qml" "$@"
