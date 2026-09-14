// How a Hyprland dispatch names one particular window.

const test = require("node:test")
const assert = require("node:assert/strict")

const {
  windowSelector
} = require("../js/selector.js")

// Quickshell reports an address without the "0x" Hyprland's selector wants.
// A selector missing it matches no window at all - and Hyprland still answers
// "ok", so the move, or the focus, silently does nothing.
test("windowSelector puts back the 0x Quickshell leaves off", () => {
  assert.equal(windowSelector("558b2094a300"), "address:0x558b2094a300")
  assert.equal(windowSelector(" 558b2094a300 "), "address:0x558b2094a300")
})

test("windowSelector leaves an address that already has it alone", () => {
  assert.equal(windowSelector("0x558b2094a300"), "address:0x558b2094a300")
  assert.equal(windowSelector("0X558b2094a300"), "address:0X558b2094a300")
})

test("windowSelector names nothing rather than a broken selector", () => {
  assert.equal(windowSelector(""), "")
  assert.equal(windowSelector(null), "")
  assert.equal(windowSelector(undefined), "")
})
