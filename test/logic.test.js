const test = require("node:test")
const assert = require("node:assert/strict")

const {
  computeWorkspaceIds,
  computeWindowKey,
  classifyIconValue,
  lookupIconOverride,
  isBrowserClass,
  extractDomain,
  extractAppHintFromDomain,
  extractAppHintFromTitle,
  isRegularBrowserTitle,
  detectWebApp,
  execMatchesInitialTitle,
  computeCacheKey
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

test("lookupIconOverride matches class, appHint, title prefixes, and regexes", () => {
  const overrides = {
    "firefox": "🦊",
    "discord": "omarchy-discord",
    "title:custom": "🌟",
    "/notion.*wiki/i": "📖"
  }

  // Exact & case-insensitive class match
  assert.equal(lookupIconOverride(overrides, "firefox"), "🦊")
  assert.equal(lookupIconOverride(overrides, "Firefox"), "🦊")

  // App hint match
  assert.equal(lookupIconOverride(overrides, "Google-chrome", "discord", "Discord | #general"), "omarchy-discord")

  // Title prefix match
  assert.equal(lookupIconOverride(overrides, "Google-chrome", "", "My Custom Project"), "🌟")

  // Regex match
  assert.equal(lookupIconOverride(overrides, "Google-chrome", "notion", "Notion Team Wiki"), "📖")

  // Unmatched
  assert.equal(lookupIconOverride(overrides, "steam"), "")
  assert.equal(lookupIconOverride(null, "firefox"), "")
})

test("isBrowserClass identifies common browsers", () => {
  assert.equal(isBrowserClass("Google-chrome"), true)
  assert.equal(isBrowserClass("google-chrome-stable"), true)
  assert.equal(isBrowserClass("chromium"), true)
  assert.equal(isBrowserClass("brave-browser"), true)
  assert.equal(isBrowserClass("code"), false)
  assert.equal(isBrowserClass("com.mitchellh.ghostty"), false)
})

test("extractDomain extracts domain from Chrome --app initialTitle", () => {
  assert.equal(extractDomain("discord.com_/channels/@me"), "discord.com")
  assert.equal(extractDomain("app.notion.com_/"), "app.notion.com")
  assert.equal(extractDomain("3.basecamp.com_/1234"), "3.basecamp.com")
  assert.equal(extractDomain("portal.elitelab.ai_/dashboard"), "portal.elitelab.ai")
  assert.equal(extractDomain("https://discord.com/channels/@me"), "discord.com")
  assert.equal(extractDomain("Untitled - Google Chrome"), "")
  assert.equal(extractDomain(""), "")
})

test("extractAppHintFromDomain extracts base service name", () => {
  assert.equal(extractAppHintFromDomain("discord.com"), "discord")
  assert.equal(extractAppHintFromDomain("app.notion.com"), "notion")
  assert.equal(extractAppHintFromDomain("3.basecamp.com"), "basecamp")
  assert.equal(extractAppHintFromDomain("web.whatsapp.com"), "whatsapp")
  assert.equal(extractAppHintFromDomain("portal.elitelab.ai"), "elitelab")
})

test("extractAppHintFromTitle detects apps from window titles", () => {
  assert.equal(extractAppHintFromTitle("Discord | #general | Server"), "discord")
  assert.equal(extractAppHintFromTitle("(1) Discord | Friends"), "discord")
  assert.equal(extractAppHintFromTitle("• Discord | Amigos"), "discord")
  assert.equal(extractAppHintFromTitle("(99+) • Discord | Servidor"), "discord")
  assert.equal(extractAppHintFromTitle("Discord - Bate-papo em grupo repleto de diversão e jogos"), "discord")
  assert.equal(extractAppHintFromTitle("Tasks - Notion"), "notion")
  assert.equal(extractAppHintFromTitle("(2) WhatsApp"), "whatsapp")
  assert.equal(extractAppHintFromTitle("Project - Basecamp"), "basecamp")
  assert.equal(extractAppHintFromTitle("Random Web Page"), "")
})

test("detectWebApp distinguishes web apps from normal browser browsing", () => {
  // Standalone Discord web app window
  const discordApp = detectWebApp("Google-chrome", "discord.com_/channels/@me", "Discord | #general")
  assert.equal(discordApp.isWebApp, true)
  assert.equal(discordApp.hint, "discord")

  // Standalone Notion web app window
  const notionApp = detectWebApp("Google-chrome", "app.notion.com_/", "Tasks - Notion")
  assert.equal(notionApp.isWebApp, true)
  assert.equal(notionApp.hint, "notion")

  // Regular browser tab
  const regularTab = detectWebApp("Google-chrome", "Untitled - Google Chrome", "diffusiongemma-kv-profiling - Google Chrome")
  assert.equal(regularTab.isWebApp, false)

  // Non-browser window
  const vscode = detectWebApp("code", "Visual Studio Code", "file.js - Visual Studio Code")
  assert.equal(vscode.isWebApp, false)
})

test("execMatchesInitialTitle matches desktop file Exec with webapp domain", () => {
  assert.equal(
    execMatchesInitialTitle("omarchy-launch-webapp https://discord.com/channels/@me", "discord.com_/channels/@me", "discord.com"),
    true
  )
  assert.equal(
    execMatchesInitialTitle("omarchy-launch-webapp https://3.basecamp.com/", "3.basecamp.com_/", "basecamp.com"),
    true
  )
  assert.equal(
    execMatchesInitialTitle("code --unity-launch", "discord.com_/", "discord.com"),
    false
  )
})

test("computeCacheKey separates web apps from regular browser windows", () => {
  assert.equal(computeCacheKey("Google-chrome", "Discord", "discord.com_/", "discord", true), "webapp:google-chrome:discord")
  assert.equal(computeCacheKey("Google-chrome", "Page - Google Chrome", "", "", false), "class:google-chrome")
  assert.equal(computeCacheKey("code", "main.rs - VSCode", "", "", false), "class:code")
})

