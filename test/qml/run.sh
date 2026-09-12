#!/usr/bin/env bash
# Runs the QML tests headless against the stand-in Quickshell/Omarchy
# modules in test/qml/stubs, so they need neither a running Hyprland nor an
# Omarchy install.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

runner="$(command -v qmltestrunner || true)"
if [[ -z "$runner" && -x /usr/lib/qt6/bin/qmltestrunner ]]; then
  runner=/usr/lib/qt6/bin/qmltestrunner
fi
if [[ -z "$runner" ]]; then
  echo "qmltestrunner not found - install qt6-declarative or put Qt's bin directory on PATH" >&2
  exit 1
fi

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
exec "$runner" -import "$here/stubs" -input "$here" "$@"
