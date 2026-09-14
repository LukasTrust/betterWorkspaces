import QtQuick

// Stand-in for Omarchy's qs.Ui TextField - itself a thin wrapper around Qt
// Quick Controls' own TextField, which has no local .qmltypes for a script
// to check inherited members (text, accepted, ...) against. This stub isn't
// part of the automatic stub/API check the others get for that reason; its
// surface here is deliberately just what SaveSetupView.qml actually uses.
// A test drives it by setting `text` directly and calling `accepted()`,
// exactly as a real one reacts to typing and pressing Enter.
Item {
  id: root

  property string text: ""
  property string placeholderText: ""
  property color foreground: "#ffffff"
  property color accent: "#88aaff"

  signal accepted()

  implicitWidth: 200
  implicitHeight: 30
}
