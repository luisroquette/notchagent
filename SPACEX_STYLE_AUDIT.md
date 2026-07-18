# SpaceX visual-system audit

Source: `https://www.spacex.com/`, inspected from the rendered desktop and mobile page plus the CSS served by the official domain on 2026-07-17.

This document extracts reusable design principles. It does not authorize use of SpaceX trademarks, logos, copy, photography or video.

## 1. Typography

The current official site does **not** use Brandon Grotesque.

- Body: `D-DIN, Arial, Verdana, sans-serif`.
- Display: `D-DIN-Bold`.
- Telemetry/countdowns: `Roboto Mono`.
- Body baseline: 16/24–26 pt.
- Desktop hero: 60/54 pt, tracking `-1px`, uppercase.
- Secondary desktop headings: 48/48 pt, tracking near `0.02em`, uppercase.
- Mobile headings: 36/36–48 pt depending on template.
- Navigation: 13 pt, 700, line-height 94%, tracking `0.09em`, uppercase.
- Button label: D-DIN 12 pt, uppercase, line-height 100%.

## 2. Color

- Canvas: pure black `#000000`.
- Primary ink: `rgba(240,240,250,1)` — `#F0F0FA`, not pure white.
- Secondary ink: 80%, 70%, 60% and 50% variants of the same cool white.
- Borders: 35% cool white; subtle dividers use 15–25%.
- Scrim: black at 50% or 80%.
- The official Home has no persistent blue brand accent. Color comes primarily from media.

## 3. Composition

- Each main narrative block is a full-viewport scene.
- Media is edge-to-edge with `object-fit: cover`.
- A transparent-to-black bottom gradient starts around 50% and reaches black at 100%.
- Desktop content is anchored 15% from the bottom and 60–100 pt from the left.
- Mobile content is anchored 5% from the bottom and 16 pt from both sides.
- Maximum desktop content width is approximately 520–720 pt.
- Navigation overlays the media instead of occupying a separate surface.
- Hierarchy is created by scale and position, not card elevation.

## 4. Shape and controls

- Primary CTA: 48 pt content height plus border, 1 pt cool-white/35%, 4 pt radius.
- CTA background: black/50%; hover transitions to cool white with black label.
- Transition curve: `cubic-bezier(0.19,1,0.22,1)`, 400–500 ms.
- Compact status/dropdown: 31 pt height, 4 pt radius, 1 pt white/25% border.
- Large rounded cards, glass pills and floating capsules are not part of the core language.

## 5. Motion

- Heading reveal: vertical translation from 220%, 750 ms, ease-in-out.
- Subheading reveal: vertical translation from 80%, 750 ms, 500 ms delay.
- CTA reveal: vertical translation from 300%, 750 ms, 1 s delay.
- Motion is sequential and directional, never springy.
- Media itself provides ambient motion; interface chrome stays restrained.

## 6. Responsive behavior

- Main navigation collapses below 1280 pt.
- Mobile navigation becomes a black full-screen vertical menu.
- Narrative layout changes below 961 pt.
- Desktop left/bottom anchors collapse to 16 pt horizontal and 5% bottom.
- Content remains large; the layout reflows instead of shrinking everything proportionally.

## 7. AgentMeter translation

Apply:

- Pure-black scene, cool-white ink and media-like procedural atmosphere.
- D-DIN/D-DIN Bold/Roboto Mono hierarchy already bundled.
- 4 pt functional radii and hairline borders.
- One dominant mission scene; telemetry embedded in that scene.
- Borderless top controls with 44 pt hit areas.
- Bottom navigation with a hairline and underline state, not filled pills.
- Staged vertical entrance motion with Reduce Motion support.

Preserve:

- AgentMeter name, orbit mark and signal blue.
- Apple navigation, accessibility and touch-target behavior.
- Provider semantic colors and truthful source/confidence labels.

Avoid:

- SpaceX logo, wordmark, media, spacecraft silhouettes or marketing copy.
- A presentation that could be mistaken for an official SpaceX product.
- Decorative telemetry without real data.
