// Keeps the QML test stand-ins (test/qml/stubs, test/qml/helpers/FakeBar.qml)
// honest: every member they expose must exist on the real Quickshell or
// Omarchy type they stand in for, so a QML test can never pass against an
// API that doesn't exist. Members prefixed with "test" are test controls and
// exempt.
//
// Needs Quickshell and Omarchy installed; each check is skipped when its real
// source isn't found (e.g. in CI). Override the locations with QS_QML_DIR and
// OMARCHY_PATH.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const stubsDir = path.join(__dirname, "qml", "stubs")
const helpersDir = path.join(__dirname, "qml", "helpers")
const quickshellDir = process.env.QS_QML_DIR || "/usr/lib/qt6/qml/Quickshell"
const omarchyShellDir = path.join(process.env.OMARCHY_PATH || "/usr/share/omarchy", "shell")

function walk(dir) {
  if (!fs.existsSync(dir)) return []
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name)
    return entry.isDirectory() ? walk(full) : [full]
  })
}

// Property, function and signal names declared anywhere in a QML file,
// including nested QtObjects (e.g. Style.font.body).
function qmlMembers(source) {
  const names = new Set()
  const pattern = /^\s*(?:(?:readonly|required|default)\s+)*property\s+\S+\s+(\w+)|^\s*function\s+(\w+)\s*\(|^\s*signal\s+(\w+)/gm
  for (const match of source.matchAll(pattern)) names.add(match[1] || match[2] || match[3])
  return names
}

function stubMembers(file) {
  return [...qmlMembers(fs.readFileSync(file, "utf8"))].filter(name => !name.startsWith("test"))
}

// Every top-level Component in the Quickshell .qmltypes files, by C++ name.
function loadQmltypes(dir) {
  const components = new Map()
  for (const file of walk(dir).filter(f => f.endsWith(".qmltypes"))) {
    const text = fs.readFileSync(file, "utf8")
    for (const block of text.split(/\n {4}Component \{/).slice(1)) {
      const name = /name: "([^"]+)"/.exec(block)?.[1]
      if (!name) continue
      const exportList = /exports: \[([^\]]*)\]/.exec(block)?.[1] ?? ""
      components.set(name, {
        prototype: /prototype: "([^"]+)"/.exec(block)?.[1],
        exports: [...exportList.matchAll(/"([^" ]+) [\d.]+"/g)].map(match => match[1]),
        members: new Set([...block.matchAll(/(?:Property|Method|Signal) \{\s*name: "([^"]+)"/g)].map(match => match[1]))
      })
    }
  }
  return components
}

// Members of the type QML knows as `exportName` (e.g.
// "Quickshell.Hyprland/HyprlandWorkspace"), including inherited ones.
function exportedMembers(components, exportName) {
  let current = [...components.values()].find(component => component.exports.includes(exportName))
  if (!current) return null
  const members = new Set()
  const seen = new Set()
  while (current && !seen.has(current)) {
    seen.add(current)
    current.members.forEach(member => members.add(member))
    current = components.get(current.prototype)
  }
  return members
}

function assertSubset(stubFile, stubNames, realNames, realLabel) {
  assert.ok(stubNames.length > 0, `parsed no members from ${stubFile}`)
  const missing = stubNames.filter(name => !realNames.has(name))
  assert.deepEqual(missing, [], `${path.relative(__dirname, stubFile)} declares members that ${realLabel} doesn't have`)
}

const qmltypes = loadQmltypes(quickshellDir)

// Quickshell registers these from internal submodules (Quickshell.Hyprland
// re-exports Quickshell.Hyprland._Ipc), so that's the name in .qmltypes.
const quickshellTypes = [
  ["Quickshell/Quickshell.qml", "Quickshell/Quickshell"],
  ["Quickshell/DesktopEntries.qml", "Quickshell/DesktopEntries"],
  ["Quickshell/ObjectModel.qml", "Quickshell/ObjectModel"],
  ["Quickshell/Hyprland/Hyprland.qml", "Quickshell.Hyprland._Ipc/Hyprland"],
  ["Quickshell/Hyprland/HyprlandWorkspace.qml", "Quickshell.Hyprland._Ipc/HyprlandWorkspace"],
  ["Quickshell/Hyprland/HyprlandToplevel.qml", "Quickshell.Hyprland._Ipc/HyprlandToplevel"],
  ["Quickshell/Hyprland/HyprlandMonitor.qml", "Quickshell.Hyprland._Ipc/HyprlandMonitor"],
  ["Quickshell/Wayland/Toplevel.qml", "Quickshell.Wayland._ToplevelManagement/Toplevel"],
  ["Quickshell/Wayland/ScreencopyView.qml", "Quickshell.Wayland._Screencopy/ScreencopyView"],
  ["Quickshell/Io/IpcHandler.qml", "Quickshell.Io/IpcHandler"],
  ["Quickshell/Io/Process.qml", "Quickshell.Io/Process"]
]

// Only a missing Quickshell install is a reason to skip. With Quickshell
// installed, a type that can't be found means this table is out of date,
// and silently skipping would hide exactly the drift this file guards.
const quickshellInstalled = qmltypes.size > 0

for (const [stub, exportName] of quickshellTypes) {
  test(`stub ${stub} only uses members of ${exportName}`, { skip: quickshellInstalled ? false : "Quickshell not installed" }, () => {
    const realMembers = exportedMembers(qmltypes, exportName)
    assert.ok(realMembers, `${exportName} not found in ${quickshellDir} - was it renamed?`)
    const stubFile = path.join(stubsDir, stub)
    assertSubset(stubFile, stubMembers(stubFile), realMembers, exportName)
  })
}

// Stand-ins whose real counterpart is itself a QML file.
const qmlFileTypes = [
  [path.join(stubsDir, "Quickshell/Widgets/IconImage.qml"), path.join(quickshellDir, "Widgets/IconImage.qml")],
  [path.join(stubsDir, "qs/Commons/Style.qml"), path.join(omarchyShellDir, "Commons/Style.qml")],
  [path.join(stubsDir, "qs/Commons/Color.qml"), path.join(omarchyShellDir, "Commons/Color.qml")],
  [path.join(stubsDir, "qs/Commons/Util.qml"), path.join(omarchyShellDir, "Commons/Util.qml")],
  [path.join(stubsDir, "qs/Ui/BarWidget.qml"), path.join(omarchyShellDir, "Ui/BarWidget.qml")],
  [path.join(helpersDir, "FakeBar.qml"), path.join(omarchyShellDir, "Ui/PluginBarApi.qml")],
  [path.join(helpersDir, "FakeShell.qml"), path.join(omarchyShellDir, "services/PluginShellApi.qml")],
  [path.join(stubsDir, "qs/Ui/NumberField.qml"), path.join(omarchyShellDir, "Ui/NumberField.qml")],
  [path.join(stubsDir, "qs/Ui/ToggleSwitch.qml"), path.join(omarchyShellDir, "Ui/ToggleSwitch.qml")],
  [path.join(stubsDir, "qs/Ui/ConfirmDialog.qml"), path.join(omarchyShellDir, "Ui/ConfirmDialog.qml")]
]

for (const [stubFile, realFile] of qmlFileTypes) {
  const label = path.relative(__dirname, stubFile)
  test(`stub ${label} only uses members of ${realFile}`, { skip: fs.existsSync(realFile) ? false : `${realFile} not found` }, () => {
    const realMembers = qmlMembers(fs.readFileSync(realFile, "utf8"))
    assertSubset(stubFile, stubMembers(stubFile), realMembers, realFile)
  })
}

// Stand-ins whose real counterpart is a thin QML wrapper (a handful of
// friendly property names, e.g. FileView's `path`) around a .qmltypes-
// registered type that carries the rest of the API (e.g. `atomicWrites`,
// `setText`) without redeclaring it - so neither source alone lists
// everything a real instance actually offers.
const combinedTypes = [
  [path.join(stubsDir, "Quickshell/Io/FileView.qml"), path.join(quickshellDir, "Io/FileView.qml"), "Quickshell.Io/FileViewInternal"]
]

for (const [stubFile, wrapperFile, exportName] of combinedTypes) {
  const label = path.relative(__dirname, stubFile)
  const skip = !fs.existsSync(wrapperFile) ? `${wrapperFile} not found`
    : !quickshellInstalled ? "Quickshell not installed" : false
  test(`stub ${label} only uses members of ${wrapperFile} or ${exportName}`, { skip }, () => {
    const wrapperMembers = qmlMembers(fs.readFileSync(wrapperFile, "utf8"))
    const baseMembers = exportedMembers(qmltypes, exportName)
    assert.ok(baseMembers, `${exportName} not found in ${quickshellDir} - was it renamed?`)
    const realMembers = new Set([...wrapperMembers, ...baseMembers])
    assertSubset(stubFile, stubMembers(stubFile), realMembers, `${wrapperFile} or ${exportName}`)
  })
}
