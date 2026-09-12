// Pure logic pulled out of Workspaces.qml so it can run under plain Node in
// tests, with no Quickshell/Hyprland runtime available. Anything that needs
// Quickshell singletons (Quickshell.iconPath, DesktopEntries, Hyprland) stays
// in the QML file and is passed in here as plain data or a callback.

function computeWorkspaceIds(existingIds) {
  var ids = [1, 2, 3, 4, 5]

  for (var i = 0; i < existingIds.length; i++) {
    var id = existingIds[i]
    if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
  }

  ids.sort(function(left, right) { return left - right })
  return ids
}

// Hyprland's own "class" (from hyprctl) is preferred over the wlr-toplevel
// appId: some XWayland apps report an empty wayland appId while hyprctl
// still reports a class, and this is what icon overrides are keyed by.
function computeWindowKey(ipcClass, ipcInitialClass, waylandAppId) {
  var key = String(ipcClass || ipcInitialClass || "")
  if (key.length === 0 && waylandAppId) key = String(waylandAppId || "")
  return key
}

// Turns a raw icon value (a user override or a DesktopEntry.icon) into
// either a themed/file image source, or - if it doesn't resolve to an
// icon-theme entry - plain text. This lets a user override with either an
// icon-theme name or a literal glyph/emoji in shell.json.
//
// iconPathLookup(name) resolves a themed icon name to a source URL (or "" if
// unresolved) - in the real widget this is Quickshell.iconPath.
function classifyIconValue(value, iconPathLookup) {
  var text = String(value || "").trim()
  if (text.length === 0) return null
  if (text.indexOf("file://") === 0 || text.indexOf("image://") === 0)
    return { kind: "image", source: text }
  if (text.charAt(0) === "/")
    return { kind: "image", source: "file://" + text }
  var themed = iconPathLookup ? String(iconPathLookup(text) || "") : ""
  if (themed.length > 0) return { kind: "image", source: themed }
  return { kind: "text", value: text }
}

function lookupIconOverride(overrides, key, appHint, title) {
  if (!overrides) return ""

  var titleStr = String(title || "")
  var keyStr = String(key || "")
  var hintStr = String(appHint || "")

  // 1. Check title-based override rules first (explicit title patterns)
  var overrideKeys = Object.keys(overrides)
  for (var i = 0; i < overrideKeys.length; i++) {
    var k = overrideKeys[i]
    if (k.toLowerCase().indexOf("title:") === 0) {
      var pattern = k.slice(6).trim().toLowerCase()
      if (pattern.length > 0 && titleStr.toLowerCase().indexOf(pattern) !== -1) {
        return String(overrides[k] || "")
      }
    } else if (k.length > 2 && k.charAt(0) === "/" && k.lastIndexOf("/") > 0) {
      var lastSlash = k.lastIndexOf("/")
      var regexBody = k.slice(1, lastSlash)
      var regexFlags = k.slice(lastSlash + 1)
      try {
        var re = new RegExp(regexBody, regexFlags)
        if (re.test(titleStr)) {
          return String(overrides[k] || "")
        }
      } catch (e) {}
    }
  }

  // 2. Check app hint override (e.g. "discord": "omarchy-discord")
  if (hintStr.length > 0) {
    if (overrides[hintStr] !== undefined) return String(overrides[hintStr])
    if (overrides[hintStr.toLowerCase()] !== undefined) return String(overrides[hintStr.toLowerCase()])
  }

  // 3. Check window class/key override (e.g. "Google-chrome" or "code")
  if (keyStr.length > 0) {
    if (overrides[keyStr] !== undefined) return String(overrides[keyStr])
    if (overrides[keyStr.toLowerCase()] !== undefined) return String(overrides[keyStr.toLowerCase()])
  }

  return ""
}

function isBrowserClass(className) {
  var c = String(className || "").toLowerCase()
  return /^(google-chrome|chromium|brave-browser|microsoft-edge|opera|vivaldi|helium)/i.test(c)
}

function extractDomain(initialTitle) {
  var text = String(initialTitle || "").trim()
  if (text.length === 0) return ""

  // Chrome --app initialTitle is usually "domain.tld_/path" or "sub.domain.tld_/"
  // Or sometimes "https://domain.tld/..."
  var m = text.match(/^(?:https?:\/\/)?([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})(?:[_/].*)?$/i)
  return m ? m[1].toLowerCase() : ""
}

function extractAppHintFromDomain(domain) {
  var d = String(domain || "").toLowerCase().trim()
  if (d.length === 0) return ""

  // Strip common service subdomains (app., web., mobile., portal., 3., www.)
  d = d.replace(/^(?:www|app|web|mobile|portal|\d+)\./, "")

  // Take the primary domain name part before the TLD (e.g. "discord" from "discord.com")
  var parts = d.split(".")
  if (parts.length >= 2) {
    // If it's something like "discord.com", return "discord"
    return parts[0]
  }
  return d
}

function extractAppHintFromTitle(title) {
  var t = String(title || "").trim()
  if (t.length === 0) return ""

  // Strip leading notification count like "(1) ", "(99+) ", unread markers like "• ", "● ", "* ", etc.
  var clean = t.replace(/^(?:(?:\(\d+\+?\)|[•●*!#])\s*)+/, "").trim()

  if (/^discord(\s*[|\-–—:]|\s*$)/i.test(clean)) return "discord"
  if (/^notion(\s*[|\-–—:]|\s*$)|[-–—:]\s*notion$/i.test(clean)) return "notion"
  if (/^whatsapp(\s*[|\-–—:]|\s*$)/i.test(clean)) return "whatsapp"
  if (/^basecamp(\s*[|\-–—:]|\s*$)|[-–—:]\s*basecamp$/i.test(clean)) return "basecamp"
  if (/^slack(\s*[|\-–—:]|\s*$)/i.test(clean)) return "slack"
  if (/^telegram(\s*[|\-–—:]|\s*$)/i.test(clean)) return "telegram"
  if (/^spotify(\s*[|\-–—:]|\s*$)|[-–—:]\s*spotify/i.test(clean)) return "spotify"

  return ""
}

function isRegularBrowserTitle(title, className) {
  var t = String(title || "").trim()
  // Normal browser windows typically end with " - Google Chrome", " - Chromium", " - Brave", etc.
  return / - (?:Google Chrome|Chromium|Brave|Microsoft Edge|Vivaldi|Opera)$/i.test(t)
}

function detectWebApp(ipcClass, initialTitle, title) {
  var isBrowser = isBrowserClass(ipcClass)
  if (!isBrowser) {
    return { isWebApp: false, hint: "", domain: "" }
  }

  var domain = extractDomain(initialTitle)
  var domainHint = extractAppHintFromDomain(domain)
  var titleHint = extractAppHintFromTitle(title)
  var regularBrowser = isRegularBrowserTitle(title, ipcClass)

  // If initialTitle had a domain, it's definitely a web app (Chrome --app format)
  if (domain.length > 0) {
    var hint = domainHint || titleHint || domain
    return { isWebApp: true, hint: hint, domain: domain }
  }

  // If title indicates a known web app and does NOT end with browser suffix:
  if (!regularBrowser && titleHint.length > 0) {
    return { isWebApp: true, hint: titleHint, domain: "" }
  }

  return { isWebApp: false, hint: "", domain: "" }
}

function execMatchesInitialTitle(execString, initialTitle, domain) {
  var exec = String(execString || "").toLowerCase()
  var dom = String(domain || "").toLowerCase()
  if (dom.length > 0 && exec.indexOf(dom) !== -1) return true

  var init = String(initialTitle || "").toLowerCase()
  if (init.length > 0 && exec.indexOf(init) !== -1) return true

  return false
}

function computeCacheKey(key, title, initialTitle, appHint, isWebApp) {
  var k = String(key || "").toLowerCase()
  if (isWebApp && appHint) {
    return "webapp:" + k + ":" + String(appHint).toLowerCase()
  }
  return "class:" + k
}

// Node's CommonJS module loader defines `module`; QML's JS engine never
// does, so this is a no-op when the file is imported as a QML library.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    computeWorkspaceIds: computeWorkspaceIds,
    computeWindowKey: computeWindowKey,
    classifyIconValue: classifyIconValue,
    lookupIconOverride: lookupIconOverride,
    isBrowserClass: isBrowserClass,
    extractDomain: extractDomain,
    extractAppHintFromDomain: extractAppHintFromDomain,
    extractAppHintFromTitle: extractAppHintFromTitle,
    isRegularBrowserTitle: isRegularBrowserTitle,
    detectWebApp: detectWebApp,
    execMatchesInitialTitle: execMatchesInitialTitle,
    computeCacheKey: computeCacheKey
  }
}
