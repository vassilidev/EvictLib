---
name: EvictLib
description: On-device iCloud Photos cleaner. Biggest wins first, one tap to act, native iOS.
colors:
  delete-red: "#FF3B30"
  keep-green: "#34C759"
  favorite-pink: "#FF2D55"
  accent-blue: "#007AFF"
  kind-video: "#FF2D55"
  kind-photo: "#007AFF"
  kind-live: "#FFCC00"
  kind-screenshot: "#34C759"
  kind-burst: "#FF9500"
  tile-indigo: "#5856D6"
  tile-gray: "#8E8E93"
  grouped-background: "#F2F2F7"
  grouped-surface: "#FFFFFF"
  label: "#000000"
  secondary-label: "#3C3C4399"
  media-canvas: "#000000"
  badge-scrim: "#00000080"
typography:
  size-figure:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "34px"
    fontWeight: 700
    lineHeight: "41px"
    fontFeature: "tnum"
  control-glyph:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "22px"
    fontWeight: 600
  headline:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: "22px"
  body:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: "22px"
  value:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: "20px"
    fontFeature: "tnum"
  detail:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: "20px"
  legend:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: "18px"
  fact-label:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: "13px"
  badge:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: "13px"
    fontFeature: "tnum"
rounded:
  tile: "8px"
  card: "24px"
  hud: "28px"
  capsule: "9999px"
spacing:
  gutter: "2px"
  xs: "6px"
  sm: "8px"
  md: "10px"
  lg: "14px"
  xl: "16px"
  edge: "20px"
components:
  action-bar-delete:
    backgroundColor: "{colors.delete-red}"
    textColor: "{colors.grouped-surface}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
    height: "56px"
  action-bar-default:
    backgroundColor: "{colors.accent-blue}"
    textColor: "{colors.grouped-surface}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
    height: "56px"
  swipe-hud:
    textColor: "{colors.grouped-surface}"
    typography: "{typography.size-figure}"
    rounded: "{rounded.hud}"
    padding: "14px 20px"
  swipe-control-button:
    typography: "{typography.control-glyph}"
    rounded: "{rounded.capsule}"
    width: "66px"
    height: "56px"
  marked-pill:
    typography: "{typography.value}"
    rounded: "{rounded.capsule}"
    padding: "11px 16px"
  delete-pill:
    backgroundColor: "{colors.delete-red}"
    typography: "{typography.value}"
    rounded: "{rounded.capsule}"
    padding: "11px 16px"
  recommendation-tile:
    textColor: "{colors.grouped-surface}"
    rounded: "{rounded.tile}"
    size: "32px"
  cell-badge:
    backgroundColor: "{colors.badge-scrim}"
    textColor: "{colors.grouped-surface}"
    typography: "{typography.badge}"
    rounded: "{rounded.capsule}"
    padding: "3px 6px"
---

# Design System: EvictLib

## Overview

**Creative North Star: "The Photos Companion"**

EvictLib reads as a part of iOS that Apple forgot to ship: Settings-style grouped lists for deciding where space goes, and a Photos-style media viewer for deciding item by item. Every surface is built from system components, system colors, and SF Pro, so it follows light and dark mode, Dynamic Type, and Liquid Glass without custom theming. Personality lives in the details: tabular byte counts, tinted glass at the moment of commitment, a single haptic when a swipe crosses its threshold.

The organizing idea is weight. The largest number on any screen is a size in bytes (Large Title bold, tabular figures), and every action states what it saves. Color is functional, never decorative: hues encode either a decision (red delete, green keep, pink favorite) or a media type (the storage bar's per-kind colors), and the two vocabularies are kept consistent wherever they appear.

Two canvases coexist. The Clean tab and its sheets are grouped lists on the system grouped background, first-class in light and dark. The Swipe tab and the video player are always dark: a black canvas under full-bleed media, with all controls floating on glass.

**Key Characteristics:**
- System components, system colors, SF Pro with Dynamic Type; no custom fonts or brand palette.
- Bytes first: the size figure is the largest type on screen, always tabular.
- Floating glass for controls over content (iOS 26 Liquid Glass, ultra-thin material before it).
- Color encodes decisions and media types only.
- Media surfaces are always dark; everything else follows the system appearance.

## Colors

All colors are iOS system colors resolved by appearance; hex values are the light-mode resolutions, and dark mode uses the system's dark variants automatically.

### Primary
- **Delete Red** (delete-red): the destructive decision. Swipe Delete glyph, left edge glow, Delete pill and Action Bar tint whenever the pending action deletes.
- **Keep Green** (keep-green): the Keep glyph and right edge glow in Swipe.
- **Favorite Pink** (favorite-pink): the Favorite glyph and top edge glow in Swipe.
- **Accent Blue** (accent-blue): the system accent (no custom AccentColor asset). Tints the Action Bar for non-destructive actions (convert, compress), selection checkmarks, tab selection.

### Secondary
- **Media type colors**: videos (kind-video, system pink), photos (kind-photo, system blue), Live Photos (kind-live, system yellow), screenshots (kind-screenshot, system green), bursts (kind-burst, system orange). Used in the storage bar segments and legend dots, and echoed by the matching recommendation tiles (Bursts orange, Live Photos yellow).
- **Tile Indigo / Tile Gray**: recommendation icon tiles with no media-type meaning (Similar Photos indigo, Finish Previous Cleanup gray).

### Neutral
- **Grouped Background / Grouped Surface**: system grouped background and secondary grouped background for the Clean tab list.
- **Label / Secondary Label**: primary text, and every secondary line (descriptions, legend sizes, savings figures in rows, fact labels).
- **Media Canvas**: pure black behind full-bleed media in Swipe and the player.
- **Badge Scrim** (black at 50%): capsule behind white badges drawn on thumbnails.

### Named Rules
**The Two Vocabularies Rule.** A hue means either a decision (red delete, green keep, pink favorite, accent for non-destructive) or a media type, and keeps that meaning everywhere it appears. A new color needs a new meaning.

**The Red Means Delete Rule.** Red appears only where the next tap removes items. The Action Bar turns red only when its pending actions include deletions; otherwise it carries the accent.

## Typography

**Display Font:** SF Pro (system font, Dynamic Type text styles)
**Body Font:** SF Pro
**Label/Mono Font:** none; numerals use `monospacedDigit()` instead of a mono face.

**Character:** One family, weights doing the work. Bold Large Title for bytes, semibold for values and actions, regular for descriptions. All sizes are Dynamic Type styles, so values listed are the Large (default) size.

### Hierarchy
- **Size figure** (Large Title bold, tabular): library total on Home, current item size in the Swipe HUD. Shrinks to 60% before truncating.
- **Control glyph** (Title 2 semibold): SF Symbols in the Swipe control bar.
- **Headline** (Headline semibold): Action Bar verb ("Delete 12 Items"), section-level labels in sheets.
- **Body** (Body): row titles.
- **Value** (Subheadline semibold, tabular): savings in rows, fact values, marked count.
- **Detail** (Subheadline): one-line row descriptions, summary subtitle.
- **Legend** (Footnote): storage legend entries.
- **Fact label** (Caption 2 semibold, uppercase, secondary): TYPE and DATE labels over their values in the Swipe HUD.
- **Badge** (Caption 2 semibold or bold, tabular, white): thumbnail size and duration badges.

### Named Rules
**The Tabular Bytes Rule.** Every byte count, item count, and duration uses tabular figures, and counters that change animate with numeric content transitions.

**The Dynamic Type Rule.** Only system text styles; at accessibility sizes, horizontal fact rows stack vertically instead of truncating.

## Layout

The Clean tab is the Heavy Wall: a 4-column mosaic of the 12 heaviest unprotected items (2pt gutter, size badge on each) starting under the toolbar, fading into the grouped background over its last 84pt; the summary card overlaps that fade by 84pt so its glass always sits over photos; then a "Recommendations" group of Settings-style rows (32pt icon tile, 14pt gap, title over a one-line description, savings trailing, chevron) on the secondary grouped surface with 20pt corners. Tapping the wall opens Largest Items. Grids of thumbnails use adaptive columns with a 110pt minimum and a 2pt gutter, edge to edge like Photos. Bottom action controls float above content in a safe-area inset with 20pt side margins.

The Swipe tab is a full-screen stack: media ignores safe areas and fills the screen; a glass HUD sits 8pt below the status bar with 16pt side margins; the control bar floats 14pt above the tab bar. Spacing steps are small and repeated: 2, 6, 8, 10, 14, 16, 20pt.

## Elevation & Depth

Depth comes from material, not shadow. Controls that float over content use `glassBackground` (Liquid Glass `regular`, `interactive` for tappable shapes, on iOS 26; `ultraThinMaterial`, or the tint at 80% opacity, before). Adjacent glass shapes are wrapped in a `GlassGroup` so they blend and morph together. Grouped lists rely on the system's tonal layering. The only shadows are a small soft drop (black 35-40%, 2pt radius, 1pt y) under white glyphs on thumbnails, for legibility over arbitrary photos.

### Named Rules
**The Glass Floats Rule.** Glass is reserved for controls floating over content (HUD, control bar, Action Bar, play button). Content itself (rows, cards, thumbnails) never wears glass, with one exception: the Home summary card, and only where it floats over the Heavy Wall's photos.

**The Tinted Commit Rule.** Glass is neutral by default; it takes a tint (red at 75-85%, or the accent) only on the button that commits an action.

## Shapes

Continuous corners throughout. Recommendation icon tiles use 8pt continuous corners with a gradient of their color; progress cards 16pt; the Swipe HUD 28pt continuous. Every floating button is a capsule or a circle (56pt round export button, 76pt round play button). The storage bar is a 12pt capsule split by 2pt gaps, each segment at least 3pt wide.

## Components

### Buttons
- **Action Bar:** a full-width 56pt glass capsule stating verb, count, and savings ("Delete 12 Items / Saves 1.2 GB"). Tinted red for deletions, accent otherwise; untinted with secondary text when nothing is selected. Optional 56pt glass circle beside it (export originals).
- **Press feedback (PressStyle):** controls on glass scale to 0.92 and dim to 80% while pressed (snappy, 0.18s); disabled at 35% opacity.
- **Swipe control bar:** one glass capsule, 6pt padding, four 66x56pt glyph buttons: Delete (red), Undo (secondary), Favorite (pink), Keep (green).

### Cards / Containers
- **Storage summary:** a 24pt glass card floating over the Heavy Wall: the library total (size figure, numeric transition), items and freed so far, the per-type storage bar, and a legend with colored dots.
- **Progress card:** 300pt max width, regular material, 16pt corners, centered over a 20% black dim.

### Navigation
- System `TabView` (Clean, Swipe) and `NavigationStack` with Large Titles; History in the toolbar opens a sheet. Settings forms open as sheets with medium and large detents.

### Swipe HUD (signature)
A glass rounded rectangle (28pt) at the top: the size figure at left, TYPE and DATE facts at right. Below it, trailing, a GlassGroup of the marked pill (trash symbol, count and total, opens the review sheet) and a red-tinted Delete pill. The media card follows the finger with rotation (width/22 degrees, anchored at the bottom); a gradient glow in the decision color rises from the edge it travels toward, with its symbol; one medium impact haptic when the 110pt threshold is crossed; the item flies off on a spring (response 0.32, damping 0.85). Reduce Motion replaces rotation and fly-off with a 0.2s crossfade. Every gesture also exists as a button and an accessibility action.

### Asset Cell (signature)
A square thumbnail with one job per corner: top-leading play badge (duration or LIVE, 44pt hit area), top-trailing status glyph (yellow star for best, white heart for favorite, white stack for album), bottom-leading size badge, bottom-trailing selection circle (white on blue when selected). Selection darkens the thumbnail with a 28% black overlay. Long press shows facts and a large preview.

## Do's and Don'ts

### Do:
- **Do** use system colors, system text styles, and SF Symbols only, so light, dark, and Dynamic Type come free.
- **Do** lead every screen and every action with bytes, in tabular figures.
- **Do** keep the Swipe canvas and video player dark regardless of system appearance, like Photos.
- **Do** float controls over media on glass via `glassBackground`, grouped with `GlassGroup` when adjacent.
- **Do** give every gesture a button and an accessibility action.

### Don't:
- **Don't** use red for anything that does not delete.
- **Don't** reuse a media-type color or a decision color for a different meaning.
- **Don't** put glass on content (the Home summary card over the wall is the only exception), or tint glass that does not commit an action.
- **Don't** add custom fonts, a custom accent, or a brand palette.
