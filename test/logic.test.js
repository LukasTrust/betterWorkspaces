const test = require("node:test")
const assert = require("node:assert/strict")

const {
  computeWorkspaceIds,
  computeWindowKey,
  classifyIconValue,
  lookupIconOverride
} = require("../logic.js")

test("computeWorkspaceIds always shows 1-5, plus occupied workspaces up to 10", () => {
  assert.deepEqual(computeWorkspaceIds([]), [1, 2, 3, 4, 5])
  assert.deepEqual(computeWorkspaceIds([9, 7, 3]), [1, 2, 3, 4, 5, 7, 9])
  assert.deepEqual(computeWorkspaceIds([0, -1, 10, 11]), [1, 2, 3, 4, 5, 10])
})

test("computeWindowKey prefers class, then initialClass, then the wayland appId", () => {
  assert.equal(computeWindowKey("firefox", "Firefox", "firefox-appid"), "firefox")
  assert.equal(computeWindowKey("", "Firefox", "firefox-appid"), "Firefox")
  assert.equal(computeWindowKey("", "", "org.wezfurlong.wezterm"), "org.wezfurlong.wezterm")
  assert.equal(computeWindowKey("", "", ""), "")
})

test("classifyIconValue resolves images, else falls back to literal text", () => {
  const unresolvable = () => ""

  assert.equal(classifyIconValue("   ", unresolvable), null)
  assert.deepEqual(classifyIconValue("file:///tmp/icon.png", unresolvable), {
    kind: "image",
    source: "file:///tmp/icon.png"
  })
  assert.deepEqual(classifyIconValue("/usr/share/icons/foo.png", unresolvable), {
    kind: "image",
    source: "file:///usr/share/icons/foo.png"
  })
  assert.deepEqual(classifyIconValue("firefox", name => `themed:${name}`), {
    kind: "image",
    source: "themed:firefox"
  })
  assert.deepEqual(classifyIconValue("🦊", unresolvable), { kind: "text", value: "🦊" })
})

test("lookupIconOverride matches a key exactly, then case-insensitively", () => {
  assert.equal(lookupIconOverride({ firefox: "🦊" }, "firefox"), "🦊")
  assert.equal(lookupIconOverride({ firefox: "🦊" }, "Firefox"), "🦊")
  assert.equal(lookupIconOverride({ firefox: "🦊" }, "steam"), "")
  assert.equal(lookupIconOverride(null, "firefox"), "")
})
