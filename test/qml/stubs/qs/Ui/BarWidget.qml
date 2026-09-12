import QtQuick
import qs.Commons

// Mirrors Omarchy's $OMARCHY_PATH/shell/Ui/BarWidget.qml (MIT), the base
// every bar widget extends. Kept behaviourally identical, since the widget
// under test inherits setting(), vertical and barSize from it.
Item {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  function broadcast(method) {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i][method] === "function")
        items[i][method]()
    }
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}
