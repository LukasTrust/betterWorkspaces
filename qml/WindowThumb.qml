import QtQuick
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons

// One window as the overview draws it: the window's own contents where the
// compositor will hand them over, its app icon on a plain surface where it
// won't.
//
// Screencopy is deliberately short-lived. `capturing` is only true while the
// overview is actually open, so nothing is being copied off the screen in the
// background, and only the workspace you are looking at is `live` - the other
// cards take a single frame each and then stop. A window the compositor never
// hands a frame for (it may be occluded, or the protocol may be unavailable)
// leaves `hasContent` false, which is what shows the icon instead.
Item {
  id: root

  // A Quickshell.Hyprland HyprlandToplevel.
  property var toplevel: null
  // The resolved icon for the fallback, as IconResolver hands it over:
  // { kind: "image", source } or { kind: "text", value }.
  property var icon: null
  // Whether the overview is open at all. False tears the capture down.
  property bool capturing: false
  // True keeps the preview updating, false takes one frame and stops.
  property bool live: false
  property bool hovered: false
  property real radius: Style.cornerRadius

  readonly property var captureSource: root.toplevel ? root.toplevel.wayland : null
  readonly property bool showingContents: capture.item !== null && capture.item.hasContent

  // Rounded like every other surface in the overview, which means clipping:
  // a screencopy view paints its own texture and knows nothing about the
  // shape it sits in.
  Rectangle {
    id: surface
    objectName: "thumbSurface"
    anchors.fill: parent
    radius: root.radius
    clip: true
    color: Color.menu.background
    // A window has to be tellable apart from the card behind it even when
    // its own contents are near-black - a terminal, most of all - so the
    // outline is a real one, not a hairline.
    border.width: Math.max(1, Style.space(root.hovered ? 3 : 2))
    border.color: root.hovered ? Color.bar.active : Color.menu.border

    // Only built while the overview is open, so the capture is torn down
    // with it rather than left running behind the bar.
    Loader {
      id: capture
      objectName: "thumbCapture"
      anchors.fill: parent
      anchors.margins: surface.border.width
      active: root.capturing && root.captureSource !== null
      visible: root.showingContents
      sourceComponent: captureComponent
    }

    Component {
      id: captureComponent

      ScreencopyView {
        id: screencopy
        objectName: "thumbScreencopy"
        captureSource: root.captureSource
        paintCursor: false

        // A card that isn't the workspace you are on needs exactly one
        // frame. captureFrame() is the obvious way to ask for it and the
        // wrong one: the capture context is negotiated with the compositor
        // after the view is built, so the call is answered with "no
        // recording context is ready" and no frame ever arrives. Starting
        // live and stopping on the first frame asks the same thing along the
        // path that waits for the context, and leaves the compositor alone
        // from then on just the same.
        live: root.live || !screencopy.hasContent
      }
    }

    // What a window looks like before (or instead of) its first frame: its
    // own app icon, centred, at a size that suits the space it has.
    Item {
      objectName: "thumbFallback"
      anchors.centerIn: parent
      visible: !root.showingContents
      readonly property int size: Math.max(Style.space(16), Math.min(surface.width, surface.height) * 0.4)
      width: size
      height: size

      IconImage {
        objectName: "thumbFallbackImage"
        anchors.fill: parent
        implicitSize: parent.size
        asynchronous: true
        visible: root.icon !== null && root.icon.kind === "image"
        source: root.icon !== null && root.icon.kind === "image" ? root.icon.source : ""
      }

      Text {
        objectName: "thumbFallbackText"
        anchors.centerIn: parent
        textFormat: Text.PlainText
        visible: root.icon !== null && root.icon.kind === "text"
        text: root.icon !== null && root.icon.kind === "text" ? root.icon.value : ""
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: parent.size
      }
    }

    // The app's icon in the corner, over the preview. A screenshot of a
    // window doesn't always say which app it is - an empty terminal is a
    // black rectangle, a blank editor nearly one - and at card size the
    // window's own title bar is far too small to read.
    Rectangle {
      id: badge
      objectName: "thumbBadge"
      visible: root.showingContents && badge.size >= Style.space(14)
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.margins: Math.max(Style.space(3), surface.border.width + Style.space(2))
      readonly property int size: Math.round(Math.min(surface.width, surface.height) * 0.22)
      width: badge.size
      height: badge.size
      radius: Style.cornerRadius > 0 ? Math.max(2, Style.cornerRadius / 2) : 0
      color: Color.menu.background
      opacity: 0.92

      IconImage {
        objectName: "thumbBadgeImage"
        anchors.fill: parent
        anchors.margins: Math.max(1, Math.round(badge.size * 0.12))
        implicitSize: badge.size
        asynchronous: true
        visible: root.icon !== null && root.icon.kind === "image"
        source: root.icon !== null && root.icon.kind === "image" ? root.icon.source : ""
      }

      Text {
        objectName: "thumbBadgeText"
        anchors.centerIn: parent
        textFormat: Text.PlainText
        visible: root.icon !== null && root.icon.kind === "text"
        text: root.icon !== null && root.icon.kind === "text" ? root.icon.value : ""
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Math.max(6, Math.round(badge.size * 0.7))
      }
    }
  }
}
