---
title: iOS WebKit emoji in canvas fillText breaks measured and aligned layout
date: 2026-07-02
last_updated: 2026-07-02
category: ui-bugs
module: html5-canvas-rendering
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Matchup line rendered off-center on iPhone while perfectly centered in desktop Chromium"
  - "Right-/left-aligned emoji strings overlapped into garbled text on iPhone (team names painted on top of each other)"
  - "Right-aligned scoreboard string ending in a flag emoji overflowed its anchor and clipped off the canvas edge on mobile"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags: [canvas, filltext, measuretext, emoji, ios, webkit, mobile-rendering, text-align]
---

# iOS WebKit emoji in canvas fillText breaks measured and aligned layout

## Problem

Flag emoji inside `canvas.fillText()` strings caused visible layout corruption on iOS — team names collapsed on top of each other and scoreboard text clipped off the canvas edge — while the same code rendered perfectly on desktop Chromium. Every iOS browser (including Chrome on iPhone) runs on WebKit, so no mobile user could see a correct layout.

## Symptoms

- Title screen matchup line rendered off-center on iPhone while perfectly centered in desktop Chromium.
- After the first fix attempt, both team names painted on top of each other, producing a single garbled string like "🇯🇲JABAHAMAS🇧🇸" — visible only on real iPhone hardware.
- After the second attempt, the words rendered correctly but the flag emoji floated detached from the team names, with a gap that varied by device.
- Scoreboard HUD right-aligned score string `"0  BAH 🇧🇸"` overflowed its anchor point and was clipped at the canvas right edge on iOS.

## What Didn't Work

**Baseline — centering one emoji-containing string.** The original code centered `'🇯🇲 JAMAICA  vs  BAHAMAS 🇧🇸'` as a single string with `textAlign:'center'`. WebKit centers on the *measured* width, which diverges from the *painted* width for emoji, so the whole line drifted off-center on iPhone.

**Failed fix A (commit 346baee) — split into right/left anchored substrings**

The idea was to center "vs" at `CX`, then anchor the left team name with `textAlign:'right'` at `CX-26` and the right team name with `textAlign:'left'` at `CX+26`:

```js
// broken
ctx.textAlign = 'right';
ctx.fillText('🇯🇲 JAMAICA', CX - 26, 240);
ctx.textAlign = 'center';
ctx.fillText('vs', CX, 240);
ctx.textAlign = 'left';
ctx.fillText('BAHAMAS 🇧🇸', CX + 26, 240);
```

This failed because `textAlign:'right'` positions the string so its *right edge* is at the anchor — computed as `anchor - measureText(string).width`. On iOS WebKit, `measureText` returns a width for emoji-containing strings that diverges significantly from the actual painted glyph width, so the painted string starts in the wrong place. Both team names collapsed inward and painted nearly on top of each other.

**Failed fix B (commit 310cf19) — center pure ASCII text, offset emoji by measured half-width**

```js
// broken
ctx.textAlign = 'center';
ctx.fillText('JAMAICA  vs  BAHAMAS', CX, 240);
const half = ctx.measureText('JAMAICA  vs  BAHAMAS').width / 2;
ctx.fillText('🇯🇲', CX - half - offset, 240);  // center-anchored emoji
ctx.fillText('🇧🇸', CX + half + offset, 240);
```

The ASCII text rendered correctly everywhere. But a center-anchored emoji still shifts by its own measured-vs-painted delta: `textAlign:'center'` paints at `anchor - measuredWidth/2`, and if the measured width is wrong, so is the paint position. iOS flag glyphs also paint larger than their measured box. The flags appeared correct on desktop but floated detached from the names on iPhone.

## Solution

Draw flags as canvas geometry (shapes, not glyphs). All measured and aligned text is pure ASCII. Geometry coordinates are deterministic across every platform because they involve no font metrics at all.

**Flag helpers** (`drawJamFlag` / `drawBahFlag` in `index.html`):

```js
// canvas-drawn flags — emoji metrics differ per platform, geometry doesn't
function drawJamFlag(x, y, w, h) { // gold saltire, green top/bottom, black hoist/fly
  ctx.fillStyle = '#009B3A'; ctx.fillRect(x, y, w, h);
  ctx.fillStyle = '#000';
  ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + w * 0.42, y + h / 2); ctx.lineTo(x, y + h); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.moveTo(x + w, y); ctx.lineTo(x + w * 0.58, y + h / 2); ctx.lineTo(x + w, y + h); ctx.closePath(); ctx.fill();
  ctx.strokeStyle = '#FFD700'; ctx.lineWidth = 2.5;
  ctx.beginPath();
  ctx.moveTo(x, y); ctx.lineTo(x + w, y + h);
  ctx.moveTo(x + w, y); ctx.lineTo(x, y + h);
  ctx.stroke();
}
function drawBahFlag(x, y, w, h) { // aqua-gold-aqua bands, black hoist triangle
  ctx.fillStyle = '#00778B'; ctx.fillRect(x, y, w, h);
  ctx.fillStyle = '#FAD44D'; ctx.fillRect(x, y + h / 3, w, h / 3);
  ctx.fillStyle = '#000';
  ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + w * 0.45, y + h / 2); ctx.lineTo(x, y + h); ctx.closePath(); ctx.fill();
}
```

**Title matchup block** — ASCII text centered, flags placed by measuring the ASCII half-width and adding a fixed pixel gap (commit f6bbcf1):

```js
// matchup: centered ASCII text + canvas-drawn flags (identical on every platform)
const matchup = 'JAMAICA  vs  BAHAMAS';
ctx.fillText(matchup, CX, 240);
const half = ctx.measureText(matchup).width / 2;
const fw = 27, fh = 17;
drawJamFlag(CX - half - 9 - fw, 240 - fh / 2, fw, fh);
drawBahFlag(CX + half + 9, 240 - fh / 2, fw, fh);
```

`measureText` is called only on the pure-ASCII string. The flag geometry is then placed at a fixed pixel offset from the measured text edge — no emoji metrics involved.

**HUD scoreboard block** — flags at fixed margins, ASCII score text anchored inside them (commit a1b6958):

```js
// scores: drawn flags + ASCII text (emoji inside aligned strings clips on mobile)
const FW = 30, FH = 19, FY = 42 - FH / 2;
drawJamFlag(48, FY, FW, FH);
drawBahFlag(W - 48 - FW, FY, FW, FH);
ctx.textAlign = 'left';
ctx.fillText(TEAMS[0].abbr + '  ' + scores[0], 48 + FW + 10, 42);
ctx.textAlign = 'right';
ctx.fillText(scores[1] + '  ' + TEAMS[1].abbr, W - 48 - FW - 10, 42);
```

The right-aligned score string no longer contains emoji, so `textAlign:'right'` anchors at a predictable position on every platform.

## Why This Works

`measureText` and glyph painting go through different code paths for color-emoji fonts. On iOS WebKit the mismatch between measured width and actual painted width for flag emoji is large enough to break any layout arithmetic that depends on it — centering, right/left anchoring, or computing offsets from `measureText` results. Because every iOS browser (Safari, Chrome, Firefox) uses WebKit under the hood, the failure affects all mobile users regardless of browser. Desktop Blink (Chromium) has a much smaller mismatch that does not visibly break layouts at typical font sizes, so desktop testing cannot reproduce the mobile failures.

Canvas geometry (rectangles, paths, strokes) uses no font metrics. Coordinates passed to `fillRect`, `moveTo`, and `lineTo` are screen pixels, identical across all rendering engines. Positioning geometry relative to `measureText` of a pure-ASCII string is safe because ASCII glyph metrics are consistent across platforms.

## Prevention

1. **No emoji inside measured or aligned canvas text.** Never pass a string containing emoji to `fillText` when its position depends on `measureText`, `textAlign:'right'`, or `textAlign:'left'`. The measured width is unreliable for emoji on iOS WebKit.

2. **Use canvas geometry for layout-critical icons.** If a flag, symbol, or decorative element must align precisely with text or sit at a predictable screen coordinate, draw it with `fillRect` / `beginPath` / `moveTo` / `lineTo` / `fill` / `stroke`. Geometry is platform-independent; emoji glyphs are not. Reuse `drawJamFlag`/`drawBahFlag` in `index.html` as the pattern.

3. **Decorative emoji in centered banner text is acceptable.** A 🔥 inside a `textAlign:'center'` banner line with nothing anchored relative to it drifts by only a few pixels — invisible at typical banner sizes. The rule applies to layout arithmetic, not to all emoji everywhere.

4. **Verify on a real iOS device before shipping any canvas text change.** Desktop Chromium cannot reproduce iOS WebKit emoji metric failures — all three failures in this project were caught only by real iPhone screenshots. "Chrome on iPhone" is WebKit, so one iOS device covers all iOS browsers.

5. **When in doubt, measure only ASCII.** If a displayed string mixes ASCII and emoji, split the rendering: `fillText` the ASCII portion and separately position any graphic element using coordinates derived solely from `measureText` of the ASCII portion.

## Related Issues

- **346baee** — Failed fix A: split right/left anchored strings with emoji; names collapsed on iPhone.
- **310cf19** — Failed fix B: pure-ASCII names + emoji offset by measured half-width; flags floated detached on mobile.
- **f6bbcf1** — Final fix for title matchup: ASCII `fillText` + `drawJamFlag`/`drawBahFlag` geometry.
- **a1b6958** — Final fix for HUD scoreboard: removed emoji from right-aligned score string, placed flag geometry at fixed margin.
- Project memory note: `no-emoji-in-measured-canvas-text` (auto memory [claude])
