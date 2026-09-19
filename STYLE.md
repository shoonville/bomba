# BOMBA — STYLE.md

The visual specification. Companion to `DESIGN.md`, which defers to this file on anything
visual. Read before touching shaders, materials, UI or viewmodels.

**Reference:** Bomb Rush Cyberfunk for the world, environments, palette and menus. Roboquest
for the first-person viewmodel only — see section 6 for why, and for the rule that keeps the
hybrid coherent.

**Provenance tags.** Every claim below is marked:
- `[measured]` — extracted programmatically from reference screenshots. Trust it.
- `[observed]` — read off the screenshots by eye. Reliable but not sampled.
- `[inferred]` — a judgement about how to apply the reference to this game. Argue with it.

Reference screenshots live in `reference/`. They are for looking at and sampling colour from.
No asset, texture, font or model is ever extracted from them.

---

## 1. Palette

**The reference is a style, not a colour scheme.** These screenshots are here for how the game
is rendered, composed and lit — not for a list of approved colours. The palette is an open
authoring decision. What follows describes how colour *behaves* in the reference, which is the
part worth copying.

Purple is explicitly in scope, and is a candidate for the game's own identity colour. So is
anything else. Nothing below whitelists hues.

### What is structural `[measured]`

Sampled across six reference shots:

- **Each location has one dominant temperature field.** Warm ochre/brick in the sunset and
  monorail shots, cool green/teal in the daytime street, warm sky against cool architecture on
  the rooftop. The field is a composition decision, not a global palette.
- **Saturated pixels cover 13–53% of frame**, varying by location — typically 25–35%. Large
  muted planes (asphalt, concrete, sky) are what make the saturated elements read. This is the
  most commonly missed rule when imitating this look.
- **Value ceiling around 0.85.** Almost nothing reaches full brightness. This is a large part of
  why the reference reads as printed illustration rather than as a lit 3D scene. Clamp emissives
  and bloom accordingly.
- **Saturation of the coloured elements sits at 0.50–0.90.** Confident, not neon.
- **Accents are tiny in area and high in saturation.** Signage, posters, a character's legs, a
  vehicle — under 1% of frame each, and unrestricted in hue. This is where purple, magenta,
  acid green and anything else lives, and it is invisible to area-based measurement.
- **Very little neutral grey.** Desaturated surfaces still carry a hue.

### How to apply it `[inferred]`

Per map or menu screen:

1. Pick a **dominant field** — one temperature, carrying the large surfaces.
2. Pick a **counter** — the complementary temperature, on architecture or sky, for depth.
3. **Accents are free.** Any hue, small area, high saturation, used on signage, props, items,
   VFX and player identification. No restriction.
4. Keep saturated coverage near 25–35% and respect the value ceiling.

Different maps should use different fields. That is how the game gets visual variety without
inventing new rules.

### Player identity colours

`[inferred]` A 2–6 player party game needs six instantly distinguishable player colours that
survive this palette. They should be chosen as an accent set — high saturation, under the value
ceiling, maximally separated in hue — and must stay legible against any map's dominant field.
Design them once, globally, and test them against every map. Purple belongs in this set.

## 2. Shading model

`[observed]` Flat cel shading. One hard step between lit and shadow on most surfaces, occasionally
two. No visible specular highlights on architecture. No gradient falloff.

`[observed]` Cast shadows are hard-edged, single-value, and sit as a distinct silhouette shape
on the ground rather than as a soft darkening. They read as a drawn shape, not as lighting.

`[observed]` Ambient occlusion is essentially absent. Corners and creases are defined by line
work, not by darkening.

`[inferred]` Implementation: stepped `light()` function in the Godot shader, 2 bands with a
sharp threshold, tunable band position. Shadow colour is a **hue shift toward the location's
cool band**, not a darkening toward black — sampled shadows in the reference retain saturation.

---

## 3. Outlines

`[observed]` Two distinct treatments, and conflating them is a mistake:

**In-world line work** is dark, relatively thin, and appears on interior detail — window frames,
panel seams, structural edges — as much as on silhouettes. It reads as ink over the flat colour,
closer to a comic panel than to a toon-shader rim.

**Key-art / character outlines are white**, thick, and sticker-like, offsetting the character
from the background entirely.

`[inferred]` For gameplay, use screen-space depth/normal edge detection for the dark interior
line work. It's cheaper than inverted-hull at 120fps and catches interior edges, which is what
the reference actually shows.

`[inferred]` The white sticker outline is a **character-legibility tool**, not a global style.
Reserve it for cases where a player silhouette must pop against a busy background — which in a
shooter is a real gameplay need, not just decoration. Consider it for enemy players at distance.
This is a decision to test, not to assume.

---

## 4. Signature motif — the marbled swirl

`[observed]` An iridescent oil-slick marble texture appears in the key art background and again
as a sky. Soft, organic, flowing bands in the location's palette.

`[inferred]` Worth stealing deliberately rather than reproducing by accident. Candidate uses:
skyboxes, menu backgrounds, transition wipes, item-award flourishes. Implementable as a
procedural domain-warped noise shader — no texture asset required.

---

## 5. HUD

`[observed]` Minimal to the point of austerity. A single large number and a single bar. Nothing
else on screen during gameplay.

`[observed]` Elements are corner- or edge-anchored and **shaped**, not boxed — the boost meter
is a curved sweeping swash that tapers, not a rectangle with a fill. This is a defining
characteristic and it is what will make a HUD look like this reference rather than like a
default one.

`[observed]` Type is chunky, wide, display-weight, with a hard dark outline. Score numerals in
saturated yellow; the meter in cyan or yellow depending on location palette.

`[inferred]` For a shooter you need more than BRC shows — health, ammo, a hitmarker, a kill
feed. Rules for adding them without breaking the look: keep every element shaped rather than
boxed, keep them at the screen edges, never more than four at once, and let them fade out when
irrelevant. Hitmarkers and damage feedback should be drawn elements — shapes with outlines —
not particle glows.

---

## 6. Viewmodel — the deliberate hybrid

Bomb Rush Cyberfunk is third person and has no first-person viewmodel to copy. Roboquest is the
reference for this one element.

`[observed]` From the Roboquest reference: the weapon occupies roughly the lower-right quarter
of the screen, angled across the frame, large enough to read as a character in its own right.
Hands are visible. The silhouette is chunky and readable at a glance. Outlines match the world's
treatment. A small emissive detail (a screen, an indicator) provides a focal point.

**The rule that keeps the hybrid coherent:** take Roboquest's *framing, scale and proportion*.
Take nothing else. The viewmodel is shaded, outlined and coloured by the Bomb Rush rules in
sections 1–3 — same two-band palette, same value ceiling, same flat stepped shading, same ink
line work. A Roboquest-shaded gun in a Bomb Rush world will look like an import; a
Bomb-Rush-shaded gun framed like Roboquest's will look like it belongs.

`[inferred]` Weapon-specific notes:
- The sniper must read instantly as the sniper when scoped and unscoped. Silhouette differs
  strongly from the AR — long and thin versus compact.
- Scoped view: a drawn scope overlay with outlined edges, not a photographic lens blur.
- The viewmodel is the most-looked-at asset in the game. It gets more modelling attention than
  anything else, including characters.

---

## 7. Menus

Bomb Rush Cyberfunk is the reference here, not the Crash-style menu screen also in `reference/`.

`[observed]` Logo and title treatment: heavy rounded-angular display type, white fill, thick
coloured glow outline, set at an angle rather than square to the frame. Layered over the marbled
swirl.

`[inferred]` Menu language derived from the above and from the HUD rules:
- Shaped panels, angled and tapered, never plain rectangles.
- Type is the primary visual element. Large, wide, confident. Menus are typographic, not iconic.
- Backgrounds use the marbled swirl in the location or mode palette.
- Transitions are aggressive and fast — wipes and slams, not fades. This carries much of the
  energy and is easy to under-budget.
- One accent hue per screen, drawn from whichever band that screen sits in.

`[inferred]` The menus carry a large share of this game's identity, because a party game puts
players in menus constantly — lobby, board UI, item selection, results. Budget real time for
them; they are not a wrapper around the game.

---

## 8. Failure modes

Specific, checkable ways this style goes wrong. Check screenshots against this list:

- **Saturating everything.** Coverage should be roughly 20–30%, not 90%. Flat muted ground is
  load-bearing.
- **Accents spreading into large areas.** Accent hues belong on small, high-saturation elements.
  A wall painted in an accent colour stops being an accent and starts being the field.
- **Blowing the value ceiling.** Full-brightness whites and hot emissives break the illustrated
  quality immediately.
- **Soft shadows or ambient occlusion.** Shadows are drawn shapes with hard edges.
- **Uniform silhouette-only outlines.** The reference has interior line work; silhouette-only
  reads as generic toon shading.
- **Boxed HUD elements.** Rectangles with fills are the default look this style exists to avoid.
- **Photographic post effects.** Lens flare, depth of field, chromatic aberration, motion blur —
  all wrong. Post should be grading, dither and grain only.
- **Grey.** There is very little neutral grey in the reference. Desaturated surfaces still carry
  a hue from the location's band.

---

## 9. Open

- Character art direction — not yet specified. The reference characters are highly stylised with
  strong silhouettes, but this game's characters serve different needs (readable at distance in
  a shooter, recognisable as your own on a board). Needs its own pass.
- Whether the white sticker outline is used on players in gameplay for legibility. Test it.
- Exact type choices. The reference logo type is bespoke; a CC0 or licensed display face needs
  choosing and it will do more work than any other single asset decision.

---

## Reference measurements (appendix added 2026-09-18 by the agent; argue with it)

Ten images in `reference/` (index in `reference/README.md`), each downscaled to 240 px wide and
converted to HSV. "Saturated" = S ≥ 0.45 and V ≥ 0.25. "Grey" = S < 0.12 and 0.2 < V < 0.9.
v99 / v95 = the 99th / 95th percentile of V. Roboquest rows are here only for the viewmodel.

| Image | saturated | grey | v99 | v95 | mean S of saturated | dominant hues |
|---|---|---|---|---|---|---|
| br1 key art | 20 % | 12 % | 1.00 | 0.98 | 0.69 | 60–90° 28 %, 0–30° 21 %, 330–360° 14 % |
| br3 monorail | 32 % | 0 % | 1.00 | 0.99 | 0.55 | 30–60° 52 %, 0–30° 41 %, 150–180° 4 % |
| rooftop | 23 % | 6 % | 1.00 | 1.00 | 0.64 | 0–30° 60 %, 30–60° 30 % |
| street boost | 22 % | 6 % | 0.99 | 0.89 | 0.61 | 30–60° 38 %, 0–30° 28 %, 180–210° 9 % |
| logo / mask | 52 % | 7 % | 1.00 | 1.00 | 0.64 | 150–180° 65 % (flat cyan ground) |
| grind HUD | 47 % | 2 % | 0.99 | 0.84 | 0.58 | 30–60° 68 %, 0–30° 27 % |
| character | 41 % | 1 % | 1.00 | 1.00 | 0.68 | 180–210° 31 %, 30–60° 29 %, 150–180° 17 % |
| Roboquest robot | 52 % | 5 % | 0.98 | 0.91 | 0.70 | 0–30° 78 % |
| Roboquest hub | 54 % | 7 % | 0.91 | 0.76 | 0.59 | 30–60° 47 %, 0–30° 41 % |
| Roboquest combat | 49 % | 1 % | 0.95 | 0.79 | 0.62 | 0–30° 83 % |

`[measured]` What this confirms: BRC's saturated coverage is 20–47 % with this threshold (§1 said
13–53 %), grey is 0–12 %, saturated elements average S 0.55–0.69, and every BRC location is a
warm 0–60° field with a 150–210° teal counter.

`[measured]` What this corrects: **the value ceiling of 0.85 (§1) holds for surfaces, not for
skies.** Cloud highlights reach V 0.97 (br3 `#f8d8af`, character shot `#e0eccb`) and 1–5 % of
pixels in every BRC shot sit above 0.95; the v95 of the busiest shots is 0.84–0.89, which is
where the "ceiling" impression comes from. Proposal: keep the 0.85 ceiling for lit surfaces and
emissives, exempt the sky, and let cloud highlights go to 0.97. The post pass now does exactly
that (depth ≥ sky distance is not clamped).

`[measured]` Sky and cloud tones (upper 40 % of frame, k-means with k = 3):

| Image | cluster 1 | cluster 2 | cluster 3 |
|---|---|---|---|
| br3 monorail (sunset) | `#f8d8af` h34 s0.29 v0.97, 41 % (cloud lit) | `#b48a62` h30 s0.45 v0.71, 38 % (sky/haze) | `#5f674e` h77 s0.24 v0.40, 20 % (cloud shadow: cool olive) |
| character (day) | `#e0eccb` h81 s0.14 v0.93, 47 % (cloud lit) | `#4a786c` h165 s0.38 v0.47, 29 % (sky teal) | `#e8a96a` h30 s0.54 v0.91, 23 % (cloud underside: warm) |
| rooftop (sunset) | `#938e6e` h51 s0.25 v0.58, 52 % | `#f7d5ab` h33 s0.31 v0.97, 27 % (cloud lit) | `#3a4238` h110 s0.15 v0.26, 19 % |

`[observed]` Clouds are flat two-tone shapes with hard edges and a thin dark rim: a lit cream body
and one shadow tone that is cool (olive/teal) at sunset and warm (orange) by day. The sky behind
them is a plain vertical gradient. The arena sky shader (`art/shaders/sky_clouds.gdshader`) is
built to this description, with its tones in `tuning/palette.json`.

`[observed]` Roboquest viewmodel framing, from the three shots: the weapon spans 30–45 % of the
frame width and about 40 % of the height, sits in the lower-right quarter with its top edge near
the vertical centre, points toward the upper-left at 15–30° from horizontal, the arm enters from
the bottom-right corner, and one small emissive (a screen, a lamp) sits on the body. Damage
numerals and spark decals are Roboquest's and are not taken.

`[observed]` BRC HUD type, from the grind shot: numerals in saturated yellow with a thick dark
outline, heavy and italic; labels in italic outlined caps; everything edge-anchored with no boxes.
The feedback burst (street shot) is a spiky cyan shape with a white core and an ink edge.
