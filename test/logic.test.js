const test = require("node:test")
const assert = require("node:assert/strict")

const {
  computeWorkspaceIds,
  computeWindowKey,
  classifyIconValue,
  lookupIconOverride
} = require("../logic.js")

test("computeWorkspaceIds", async (t) => {
  await t.test("defaults to workspaces 1-5 when nothing else is open", () => {
    assert.deepEqual(computeWorkspaceIds([]), [1, 2, 3, 4, 5])
  })

  await t.test("adds occupied workspaces beyond 5, sorted", () => {
    assert.deepEqual(computeWorkspaceIds([9, 7]), [1, 2, 3, 4, 5, 7, 9])
  })

  await t.test("includes workspace 10 but not workspaces past 10", () => {
    assert.deepEqual(computeWorkspaceIds([10, 11]), [1, 2, 3, 4, 5, 10])
  })

  await t.test("ignores workspace 0 and negative ids", () => {
    assert.deepEqual(computeWorkspaceIds([0, -1]), [1, 2, 3, 4, 5])
  })

  await t.test("never duplicates an id already in the default range", () => {
    assert.deepEqual(computeWorkspaceIds([3, 3, 4]), [1, 2, 3, 4, 5])
  })
})

test("computeWindowKey", async (t) => {
  await t.test("prefers the hyprctl class", () => {
    assert.equal(computeWindowKey("firefox", "Firefox", "firefox-appid"), "firefox")
  })

  await t.test("falls back to initialClass when class is empty", () => {
    assert.equal(computeWindowKey("", "Firefox", "firefox-appid"), "Firefox")
  })

  await t.test("falls back to the wayland appId when hyprctl has neither", () => {
    assert.equal(computeWindowKey("", "", "org.wezfurlong.wezterm"), "org.wezfurlong.wezterm")
  })

  await t.test("returns empty string when nothing identifies the window", () => {
    assert.equal(computeWindowKey("", "", ""), "")
  })
})

test("classifyIconValue", async (t) => {
  await t.test("returns null for an empty or blank override", () => {
    assert.equal(classifyIconValue("", () => "irrelevant"), null)
    assert.equal(classifyIconValue("   ", () => "irrelevant"), null)
  })

  await t.test("treats file:// and image:// values as already-resolved images", () => {
    assert.deepEqual(classifyIconValue("file:///tmp/icon.png", () => ""), {
      kind: "image",
      source: "file:///tmp/icon.png"
    })
    assert.deepEqual(classifyIconValue("image://provider/icon", () => ""), {
      kind: "image",
      source: "image://provider/icon"
    })
  })

  await t.test("treats an absolute path as a file image", () => {
    assert.deepEqual(classifyIconValue("/usr/share/icons/foo.png", () => ""), {
      kind: "image",
      source: "file:///usr/share/icons/foo.png"
    })
  })

  await t.test("resolves an icon-theme name through the lookup callback", () => {
    const result = classifyIconValue("firefox", (name) => `themed:${name}`)
    assert.deepEqual(result, { kind: "image", source: "themed:firefox" })
  })

  await t.test("falls back to literal text when the theme lookup finds nothing", () => {
    assert.deepEqual(classifyIconValue("🦊", () => ""), { kind: "text", value: "🦊" })
  })

  await t.test("falls back to literal text when no lookup is provided", () => {
    assert.deepEqual(classifyIconValue("steam", undefined), { kind: "text", value: "steam" })
  })
})

test("lookupIconOverride", async (t) => {
  await t.test("returns empty string when there are no overrides", () => {
    assert.equal(lookupIconOverride(null, "firefox"), "")
  })

  await t.test("matches an exact key", () => {
    assert.equal(lookupIconOverride({ firefox: "🦊" }, "firefox"), "🦊")
  })

  await t.test("falls back to a lowercase key for case-insensitive matching", () => {
    assert.equal(lookupIconOverride({ firefox: "🦊" }, "Firefox"), "🦊")
  })

  await t.test("returns empty string when the key is not present", () => {
    assert.equal(lookupIconOverride({ firefox: "🦊" }, "steam"), "")
  })
})
