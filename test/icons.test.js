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

// ---- web apps -------------------------------------------------------------

const {
  parseWebAppClass,
  urlsInExec,
  findWebAppEntry,
  parseProcEnviron,
  lutrisSlug,
  heroicIconPaths,
  gameHintsFromEnv,
  execReferences,
  resolveGameHints
} = require("../js/icons.js")

test("parseWebAppClass reads the site out of any Chromium-family --app class", () => {
  assert.deepEqual(parseWebAppClass("chrome-app.hey.com__-Default"), { host: "app.hey.com", path: "" })
  assert.deepEqual(parseWebAppClass("brave-discord.com__app-Default"), { host: "discord.com", path: "app" })
  assert.deepEqual(parseWebAppClass("msedge-www.example.org__a_b-Profile 1"), { host: "example.org", path: "a_b" })
  assert.deepEqual(parseWebAppClass("helium-my-site.io__my-page-Default"), { host: "my-site.io", path: "my-page" })
  assert.deepEqual(parseWebAppClass("  Chromium-Web.WhatsApp.com__-Default "), { host: "web.whatsapp.com", path: "" })
})

test("parseWebAppClass leaves ordinary and installed-PWA classes alone", () => {
  assert.equal(parseWebAppClass("chrome-nngceckbapebfimnlniiiahkandclblb-Default"), null)
  assert.equal(parseWebAppClass("google-chrome"), null)
  assert.equal(parseWebAppClass("org.gnome.Nautilus"), null)
  assert.equal(parseWebAppClass("FFPWA-01HXYZ"), null)
  assert.equal(parseWebAppClass(""), null)
  assert.equal(parseWebAppClass(null), null)
})

test("urlsInExec finds every http(s) URL in an Exec line, normalized", () => {
  assert.deepEqual(urlsInExec('omarchy-launch-webapp "https://app.hey.com"'), [{ host: "app.hey.com", path: "" }])
  assert.deepEqual(urlsInExec("chromium --app=https://www.Discord.com:443/app/?x=1#y"), [{ host: "discord.com", path: "app" }])
  assert.deepEqual(urlsInExec("x http://a.com/one/two/ https://b.com"), [
    { host: "a.com", path: "one_two" },
    { host: "b.com", path: "" }
  ])
  assert.deepEqual(urlsInExec("foot"), [])
  assert.deepEqual(urlsInExec(undefined), [])
})

test("findWebAppEntry prefers same host and path, then same host, and needs an icon", () => {
  const hey = { id: "HEY", icon: "hey", execString: 'omarchy-launch-webapp "https://app.hey.com"' }
  const discordRoot = { id: "D1", icon: "d1", execString: "omarchy-launch-webapp https://discord.com" }
  const discordApp = { id: "D2", icon: "d2", execString: "omarchy-launch-webapp https://discord.com/app" }
  const noIcon = { id: "X", icon: "", execString: "omarchy-launch-webapp https://x.com" }
  const entries = [null, noIcon, hey, discordRoot, discordApp, { id: "foot", icon: "foot", execString: "foot" }]

  assert.equal(findWebAppEntry(entries, parseWebAppClass("chrome-app.hey.com__-Default")), hey)
  assert.equal(findWebAppEntry(entries, parseWebAppClass("chrome-discord.com__app-Default")), discordApp)
  assert.equal(findWebAppEntry(entries, parseWebAppClass("chrome-discord.com__channels-Default")), discordRoot)
  assert.equal(findWebAppEntry(entries, parseWebAppClass("chrome-x.com__-Default")), null)
  assert.equal(findWebAppEntry(entries, parseWebAppClass("chrome-unknown.net__-Default")), null)
  assert.equal(findWebAppEntry(entries, null), null)
  assert.equal(findWebAppEntry(null, { host: "app.hey.com", path: "" }), null)
})

// ---- games started by a launcher --------------------------------------------

const NUL = String.fromCharCode(0)

test("parseProcEnviron splits NAME=value pairs, keeping the first of a repeat", () => {
  const env = parseProcEnviron(["A=1", "B=x=y", "", "=bad", "noequals", "A=2", "constructor=c", ""].join(NUL))
  assert.deepEqual({ ...env }, { A: "1", B: "x=y", constructor: "c" })
  assert.equal(Object.getPrototypeOf(env), null)
  assert.deepEqual({ ...parseProcEnviron("") }, {})
  assert.deepEqual({ ...parseProcEnviron(null) }, {})
})

test("lutrisSlug matches Lutris's Django-style slugs", () => {
  assert.equal(lutrisSlug("Hearts of Iron IV"), "hearts-of-iron-iv")
  assert.equal(lutrisSlug("Baldur's Gate: Enhanced Edition"), "baldurs-gate-enhanced-edition")
  assert.equal(lutrisSlug("  Pokémon -- Red  "), "pokemon-red")
  assert.equal(lutrisSlug(null), "")
})

test("heroicIconPaths covers native and Flatpak config dirs, and refuses unsafe names", () => {
  const paths = heroicIconPaths("CrabEA", "/home/u", "")
  assert.equal(paths[0], "/home/u/.config/heroic/icons/CrabEA.png")
  assert.ok(paths.includes("/home/u/.config/heroic/icons/CrabEA.jpg"))
  assert.ok(paths.includes("/home/u/.var/app/com.heroicgameslauncher.hgl/config/heroic/icons/CrabEA.webp"))
  assert.equal(heroicIconPaths("CrabEA", "/home/u", "/cfg")[0], "/cfg/heroic/icons/CrabEA.png")
  assert.deepEqual(heroicIconPaths("../evil", "/home/u", ""), [])
  assert.deepEqual(heroicIconPaths("a/b", "/home/u", ""), [])
  assert.deepEqual(heroicIconPaths("", "/home/u", ""), [])
  assert.deepEqual(heroicIconPaths("CrabEA", "", ""), [])
})

test("gameHintsFromEnv reads Steam, Heroic and Lutris launch environments", () => {
  assert.deepEqual(gameHintsFromEnv(parseProcEnviron(["PATH=/bin", "SteamAppId=0", ""].join(NUL)), "/h", ""), [])
  assert.deepEqual(gameHintsFromEnv({ SteamAppId: "0", STEAM_COMPAT_APP_ID: "892970" }, "/h", ""), [
    { kind: "themed", name: "steam_icon_892970" }
  ])
  assert.deepEqual(gameHintsFromEnv({ SteamGameId: "570", STEAM_COMPAT_APP_ID: "1" }, "/h", ""), [
    { kind: "themed", name: "steam_icon_570" }
  ])

  const heroic = gameHintsFromEnv({ HEROIC_APP_NAME: " CrabEA " }, "/h", "")
  assert.deepEqual(heroic[0], { kind: "exec", token: "CrabEA" })
  assert.equal(heroic[1].kind, "file")
  assert.equal(heroic[1].paths[0], "/h/.config/heroic/icons/CrabEA.png")
  // No home directory: still matchable through a desktop shortcut.
  assert.deepEqual(gameHintsFromEnv({ HEROIC_APP_NAME: "CrabEA" }, "", ""), [{ kind: "exec", token: "CrabEA" }])

  assert.deepEqual(gameHintsFromEnv({ GAME_NAME: "Hearts of Iron IV" }, "/h", ""), [
    { kind: "name", name: "Hearts of Iron IV" },
    { kind: "themed", name: "lutris_hearts-of-iron-iv" }
  ])
  assert.deepEqual(gameHintsFromEnv({ GAME_NAME: "!!!" }, "/h", ""), [{ kind: "name", name: "!!!" }])
  assert.deepEqual(gameHintsFromEnv(null, "/h", ""), [])
})

test("execReferences matches an id only as a whole token", () => {
  assert.equal(execReferences("xdg-open heroic://launch/legendary/CrabEA", "CrabEA"), true)
  assert.equal(execReferences("xdg-open heroic://launch?appName=CrabEA&runner=legendary", "CrabEA"), true)
  assert.equal(execReferences("CrabEA", "CrabEA"), true)
  assert.equal(execReferences("heroic://launch/legendary/CrabEAX CrabEA2", "CrabEA"), false)
  assert.equal(execReferences("foo", ""), false)
  assert.equal(execReferences(null, "x"), false)
})

test("resolveGameHints tries hints in order and only ever returns an image", () => {
  const themed = name => ({ steam_icon_570: "themed:steam_icon_570", heroic_shortcut: "themed:heroic_shortcut" })[name] || ""
  const entries = [
    null,
    { name: "No Icon", icon: "", execString: "heroic://launch/legendary/CrabEA" },
    { name: "Glyph", icon: "🎮", execString: "heroic://launch/legendary/Glyphy" },
    { name: "Satisfactory", icon: "heroic_shortcut", execString: "xdg-open heroic://launch/legendary/CrabEA" },
    { name: "Hearts of Iron IV", icon: "/icons/hoi4.png", execString: "lutris lutris:rungameid/3" }
  ]
  const existing = new Set(["/h/.config/heroic/icons/CrabEA.jpg"])
  const lookup = { themed, entries, fileExists: path => existing.has(path) }

  assert.deepEqual(resolveGameHints([{ kind: "themed", name: "steam_icon_1" }, { kind: "themed", name: "steam_icon_570" }], lookup), {
    kind: "image",
    source: "themed:steam_icon_570"
  })
  assert.deepEqual(resolveGameHints(gameHintsFromEnv({ HEROIC_APP_NAME: "CrabEA" }, "/h", ""), lookup), {
    kind: "image",
    source: "themed:heroic_shortcut"
  })
  assert.deepEqual(resolveGameHints(gameHintsFromEnv({ HEROIC_APP_NAME: "CrabEA" }, "/h", ""), { ...lookup, entries: null }), {
    kind: "image",
    source: "file:///h/.config/heroic/icons/CrabEA.jpg"
  })
  assert.deepEqual(resolveGameHints([{ kind: "name", name: "hearts of iron iv" }], lookup), {
    kind: "image",
    source: "file:///icons/hoi4.png"
  })
  // A desktop entry whose icon is only text is no game icon.
  assert.equal(resolveGameHints([{ kind: "exec", token: "Glyphy" }], lookup), null)
  assert.equal(resolveGameHints(gameHintsFromEnv({ HEROIC_APP_NAME: "Other" }, "/h", ""), lookup), null)
  assert.equal(resolveGameHints(null, lookup), null)
})
