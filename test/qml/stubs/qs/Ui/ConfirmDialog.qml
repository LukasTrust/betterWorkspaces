import QtQuick

// Stand-in for Omarchy's qs.Ui ConfirmDialog. Nothing here needs to look
// right, only behave right: a scrim that cancels, and two plain clickable
// areas standing in for the cancel/confirm buttons.
Item {
  id: root

  property bool opened: false
  property string message: ""
  property string cancelText: "Cancel"
  property string confirmText: "Confirm"
  property int selectedIndex: 1

  signal canceled()
  signal confirmed()

  visible: root.opened

  MouseArea {
    objectName: "confirmScrim"
    anchors.fill: parent
    onClicked: root.canceled()
  }

  Item {
    objectName: "cancelButton"
    x: 10
    y: 10
    width: 80
    height: 30

    MouseArea {
      anchors.fill: parent
      onClicked: root.canceled()
    }
  }

  Item {
    objectName: "confirmButton"
    x: 100
    y: 10
    width: 80
    height: 30

    MouseArea {
      anchors.fill: parent
      onClicked: root.confirmed()
    }
  }
}
