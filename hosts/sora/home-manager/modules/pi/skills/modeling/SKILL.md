---
name: modeling
description: Create, adapt, inspect and validate printable 3D models, STL/3MF files, engraved labels, thread-fit coupons and Bambu Studio projects or print settings. Use for CAD/mesh geometry, FDM printability, dimensional fit, model conversion, plate layout and reusable slicer workflows.
---

# 3D Modeling & Bambu Studio

Keep reusable methods here; keep a project's vehicle/part compatibility, dimensions,
variants, filenames, print results and exact successful preset in its `AGENTS.md`.

## Model and test before committing material

- Preserve the source model unchanged. Keep source, short tests, generators and
  full products distinct. A short rebuilt coupon is not an exact crop of a part.
- Use explicit millimetres. STL has no reliable unit metadata; verify imported
  dimensions. Bambu Studio accepts STL directly; conversion is not required.
- Use separate files for nominal diameter/pitch, male/female, clearance and
  test/full variants. Do not overwrite another variant or add unsolicited sizes.
- Establish the real attachment: threaded, clipped or push-fit. Aftermarket
  listings are evidence to investigate, not proof of physical compatibility.
- Print a small fit coupon before the full part. Known metal bolts/nuts are
  better dimensional references than matching printed pairs. Start by hand;
  never force a fit or treat a test coupon as a safe installed functional part.
- Separate mesh validity, successful slicing, readable physical print and actual
  mechanical fit. Passing one does not prove the others. Vehicle/loaded parts
  also need appropriate heat resistance, strength, retention and clearances.

## Lettering that survives FDM

- Layer height controls Z resolution; nozzle/line width and XY toolpaths limit
  small strokes, dots and gaps. Changing 0.16 to 0.08 mm cannot rescue features
  the slicer omits in XY. Inspect the sliced strokes before blaming layer height.
- Prefer bold/simple glyphs and enough surface area rather than squeezing text
  into a thin rim. Enlarge the body or offer a flat label tab when needed;
  confirm the owner's layout preference instead of assuming minimum material
  matters more than legibility. Do not silently change recessed text to raised.
- For 0.4 mm-nozzle coupons, roughly 5 mm-high bold text, 0.60 mm recesses and
  at least 1.2 mm clear inner/outer borders are a useful tested starting point,
  not universal limits or a readability guarantee. Check actual minimum strokes
  and spacing for the chosen font. A smaller nozzle may help tiny lettering.
- Budget text height AND both clear borders before selecting body diameter.
  Do not claim large lettering while silently scaling it down to fit.
- Curved text needs edge subdivision before warping. Warping can compress inner
  strokes; prevent excessive wrap or overlaps and check decimal points/counters.
- Measure minimum radial clearance along entire polygon/triangle edges, not
  only vertices. Account for the outer wall's faceted inradius. For tabs, check
  the full rectangular border and keep letters out from under taller geometry.
- Engraving must be real subtraction with a remaining solid floor, correct depth
  and connected body. Preview actual exported facets, not just a font mockup.
  A facet render is not a slicer/toolpath preview or a physical print guarantee.
- Print ONE revised coupon before a full batch. Record what actually improved.

## Threads and geometry changes

- Record nominal diameter, pitch, handedness, starts, profile and allowance.
  Diametral allowance is twice radial allowance; specify which is being used.
  Do not apply the same fit allowance to both mating sides accidentally.
- Keep imperial threads exact: diameter in inches × 25.4; pitch = 25.4 / TPI.
  A nearby metric diameter is not an equivalent thread.
- For a helical radial mesh, phase `(z / pitch - theta / (2*pi)) % 1` advances
  in +Z with increasing counterclockwise theta for a right-hand thread.
  Validate the exported helix, not only the analytic formula.
- To replace an existing threaded cavity, fill its old shape completely before
  cutting the new bore; merely enlarging it fails for smaller variants. Preserve
  blind depth, unrelated assembly features, exterior and separate companion parts.
- Boolean operations can retriangulate unchanged surfaces. Different face hashes
  do not prove changed geometry. Compare actual ray intersections or geometric
  differences outside the edit envelope; exact hashes suit untouched files.
- Validate finite/nondegenerate triangles, watertightness, consistent winding,
  connected components, expected topology, positive volume and bounds. Reload
  the serialized STL and check again. For threads, measure actual triangle rays
  across depths/angles for profile, pitch, handedness, entry chamfer and roof.
  Basic profiles and successful meshes are not certified tolerance gauges.
- Reuse the established CAD/native geometry libraries instead of introducing a
  new implementation language or custom boolean engine without a real benefit.

## Slicer settings and successful presets

- Ask for printer, nozzle and filament if unknown. Best template: the owner's
  saved 3MF of a successful single-model print, even if the batch needs 14 models.
  Inspect its actual contents; the filename can be stale or misleading.
- For fine upright functional coupons with a 0.4 mm nozzle, a practical starting
  point is 0.12 mm layers, four walls, five top/bottom layers and 15% gyroid.
  These are not universal structural or full-model settings. Preserve the
  successful first-layer, material, temperatures, bed, brim and other settings.
- Wall loops and shell/infill settings are distinct from layer height, which is
  under Quality. Check actual shell thickness as well as layer count. Supports
  off can suit simple upright coupons, not automatically full complex parts.
- Do not skip required heating/homing for speed. Batch compatible coupons to
  share startup overhead. Estimates are estimates; distinguish model volume,
  sliced filament and startup/purge waste.
- Save reusable projects as 3MF. Open as a PROJECT, not geometry-only, to retain
  settings. Embedded settings are not a separately installed global preset.
  Reimport revised STLs: existing saved projects still contain the old meshes.

## Assemble and verify a Bambu project

1. Inspect the successful 3MF ZIP: model resources/build, object/plate settings,
   printer/process/filament configuration and optional previews/toolpaths.
2. Prefer Bambu Studio's native importer/exporter and arrangement facilities.
   Check the installed CLI's `--help`; flags differ by version. Do not automate
   printing or send a job just to validate a file.
3. Preserve complete successful settings, preferably byte-for-byte, not only a
   handful of visible quality fields. Remove the template's duplicate test model
   when adding the complete suite; verify exact filenames and object counts.
4. Arrange upright at Z=0, within the selected printer's actual usable bed, with
   spacing for brims. Group matched tests together. By-layer printing does not
   need the same head-clearance rules as sequential/by-object printing.
5. Validate resources, relationship targets, build items, plate instances and
   object/part IDs after any ZIP/XML edits. Apply both component and build
   transforms before comparing meshes: native import may center mesh vertices
   and compensate in the component transform. Preserve scale and orientation.
6. Check packaged triangles against source STLs, bed contact, spacing, topology
   and settings; then load AND slice with Bambu Studio. A successful ZIP write
   or zero CLI exit code alone is not sufficient. Inspect the toolpaths before
   printing; no automatic validation establishes physical fit.
7. Never retain stale single-model thumbnails or cached G-code after changing
   geometry/layout. Omit missing previews rather than imply they show the new
   plate. Keep the delivered project editable; generated validation G-code can
   remain outside the source/project outputs unless specifically requested.

### Observed CLI/package traps

- Flatpak uses a separate `/tmp`. Grant access to a temporary output directory
  explicitly with `--filesystem=<absolute-directory>` or use an accessible
  project path. Confirm the file actually exists in the host filesystem.
- On Bambu Studio 02.07.01.62, `--min-save` is a flag, not `--min-save 1`, and
  produced an empty geometry package in the tested export workflow. Do not use
  it as a harmless size optimization; always verify build/object counts.
- CLI export reported `Invalid OpenGL version 3.4` / `Failed to create GLFW window`;
  full export still succeeded without thumbnails once output access was fixed.
  Distinguish failed rendering from failed model export and verify by slicing.
- Bambu's tested relationship reader rejected `ns0:Relationship` XML emitted
  by generic serializers. Keep the relationships namespace as the default
  (unprefixed elements); valid namespace-equivalent XML is not always accepted.
- Missing standalone `machine_full`/`process_full` preset warnings did not block
  slicing a complete embedded configuration. Verify preserved settings and the
  actual result; do not broadly ignore warnings or substitute guessed presets.
