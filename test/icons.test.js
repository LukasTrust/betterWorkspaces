// Deciding what a window is and which icon stands for it, and the overview's
// search over the same two facts.

const test = require("node:test")
const assert = require("node:assert/strict")

const {
  computeWindowKey,
  classifyIconValue,
  lookupIconOverride,
  steamAppId,
  groupToplevels,
  matchesSearchQuery
} = require("../js/icons.js")

test("computeWindowKey prefers class, then initialClass, then the wayland appId", () => {
  assert.equal(computeWindowKey("firefox", "Firefox", "firefox-appid"), "firefox")
  assert.equal(computeWindowKey("", "Firefox", "firefox-appid"), "Firefox")
  assert.equal(computeWindowKey("", "", "org.wezfurlong.wezterm"), "org.wezfurlong.wezterm")
  assert.equal(computeWindowKey("", "", ""), "")
})

test("matchesSearchQuery matches title or class, case-insensitively", () => {
  assert.equal(matchesSearchQuery("Inbox - Thunderbird", "thunderbird", ""), true)
  assert.equal(matchesSearchQuery("Inbox - Thunderbird", "thunderbird", "  "), true)
  assert.equal(matchesSearchQuery("Inbox - Thunderbird", "thunderbird", "MAIL"), false)
  assert.equal(matchesSearchQuery("Inbox - Thunderbird", "thunderbird", "thunder"), true)
  assert.equal(matchesSearchQuery("Inbox - Thunderbird", "org.mozilla.Thunderbird", "mozilla"), true)
  assert.equal(matchesSearchQuery(null, null, "x"), false)
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
  assert.equal(lookupIconOverride({ firefox: "🦊" }, ""), "")
})

// A window class comes from the app, not from the user, so it can name
// something every object inherits - that must read as "no override", not as
// whatever Object.prototype has under that name.
test("lookupIconOverride ignores inherited members, matching only own keys", () => {
  assert.equal(lookupIconOverride({}, "constructor"), "")
  assert.equal(lookupIconOverride({}, "__proto__"), "")
  assert.equal(lookupIconOverride({}, "hasOwnProperty"), "")
  assert.equal(lookupIconOverride({}, "toString"), "")
  // An override the user really did write under such a name still works.
  assert.equal(lookupIconOverride({ constructor: "🦊" }, "constructor"), "🦊")
})

test("steamAppId pulls the appid out of a Steam window class, else null", () => {
  assert.equal(steamAppId("steam_app_570"), "570")
  assert.equal(steamAppId("STEAM_APP_570"), "570")
  assert.equal(steamAppId("  steam_app_570  "), "570")
  assert.equal(steamAppId("steam_app_0"), "0")
  assert.equal(steamAppId("steam_app_"), null)
  assert.equal(steamAppId("steam_app_570x"), null)
  assert.equal(steamAppId("not_steam_app_570"), null)
  assert.equal(steamAppId("steamapp570"), null)
  assert.equal(steamAppId(""), null)
  assert.equal(steamAppId(null), null)
  assert.equal(steamAppId(undefined), null)
})

test("groupToplevels groups by key, in first-seen order, keeping every window", () => {
  const code1 = { id: "code1" }
  const firefox1 = { id: "firefox1" }
  const code2 = { id: "code2" }
  const keyOf = toplevel => ({ code1: "code", code2: "code", firefox1: "firefox" })[toplevel.id]

  const groups = groupToplevels([code1, firefox1, code2], keyOf)

  assert.deepEqual(groups.map(group => group.key), ["code", "firefox"])
  assert.deepEqual(groups.map(group => group.toplevels), [[code1, code2], [firefox1]])
})

test("groupToplevels groups a window class case-insensitively", () => {
  const lower = { id: "lower" }
  const upper = { id: "upper" }
  const keyOf = toplevel => (toplevel.id === "lower" ? "firefox" : "Firefox")

  const groups = groupToplevels([lower, upper], keyOf)

  assert.equal(groups.length, 1)
  assert.equal(groups[0].key, "firefox")
  assert.deepEqual(groups[0].toplevels, [lower, upper])
})

test("groupToplevels counts a group's windows", () => {
  const windows = [{ id: 1 }, { id: 2 }, { id: 3 }]
  const groups = groupToplevels(windows, () => "code")
  assert.equal(groups.length, 1)
  assert.equal(groups[0].toplevels.length, 3)
})

test("groupToplevels copes with nothing to group and an unusable key", () => {
  assert.deepEqual(groupToplevels([], () => "code"), [])
  assert.deepEqual(groupToplevels([{ id: 1 }], null), [{ key: "", toplevels: [{ id: 1 }] }])
  assert.deepEqual(groupToplevels([{ id: 1 }], () => ""), [{ key: "", toplevels: [{ id: 1 }] }])
})

test("the +N overflow counts groups, not the windows inside them", () => {
  const windows = [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 4 }, { id: 5 }]
  const keyOf = toplevel => (toplevel.id <= 3 ? "code" : "firefox")
  const maxIcons = 1

  const groups = groupToplevels(windows, keyOf)

  assert.equal(groups.length, 2)
  assert.equal(Math.max(0, groups.length - maxIcons), 1)
})
