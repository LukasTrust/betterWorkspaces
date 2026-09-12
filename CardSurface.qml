import QtQuick
import qs.Commons

// One workspace card: the wallpaper it sits on, whatever is placed inside it,
// and its number underneath. The "+" card uses the same shape with `empty`
// set, so the two never drift apart.
//
// The card is the caller's `width`/`height`; the caption is drawn below that,
// in the room the grid layout reserved for it, so a long-running title or a
// two-digit number can't eat into the preview.
Item {
  id: root

  // Everything a card can say about itself, in one place so the three
  // borders (focused, selected, drop target) can't each pick their own.
  property bool focused: false
  property bool selected: false
  property bool highlighted: false
  property bool empty: false

  property string wallpaper: ""
  property string caption: ""
  property int captionHeight: Style.space(30)

  // Children land inside the card, not next to the caption.
  default property alias content: surface.data
  // The caption doubles as the card's handle: once windows cover the whole
  // card there is no empty spot left to grab it by, so the caller puts the
  // reorder drag here.
  property alias captionArea: captionRow

  // No implicit size: the card is placed by the grid, which hands it an
  // explicit width and height. Deriving one from `surface`, which in turn
  // fills this item, is a binding loop.

  Rectangle {
    id: surface
    objectName: "cardSurfaceBody"
    anchors.fill: parent
    radius: Style.cornerRadius
    clip: true
    color: Color.menu.background
    border.width: Math.max(1, Style.space(root.selected || root.highlighted ? 3 : 2))
    border.color: root.highlighted ? Color.menu.selectedText : (root.selected || root.focused ? Color.bar.active : Color.menu.border)

    // The wallpaper the workspace actually sits on. Read straight off the
    // symlink Omarchy keeps pointing at the current background - no process,
    // and no cache, so a theme change is picked up the next time the overview
    // opens. Declared first so everything else draws over it.
    Image {
      objectName: "cardWallpaper"
      anchors.fill: parent
      anchors.margins: surface.border.width
      visible: !root.empty && root.wallpaper.length > 0
      source: root.wallpaper
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      opacity: root.focused ? 0.6 : 0.4
    }
  }

  Item {
    id: captionRow
    anchors.top: surface.bottom
    anchors.left: surface.left
    anchors.right: surface.right
    height: root.captionHeight

    Text {
      objectName: "cardCaption"
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.caption
      color: root.focused || root.selected ? Color.bar.active : Color.menu.text
      opacity: root.focused || root.selected ? 1 : 0.7
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: root.focused
    }
  }
}
