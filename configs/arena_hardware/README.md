# Arena Hardware Topology

> **STATUS: UNTESTED / UNVALIDATED DRAFT (2026-05-15).** Files in this directory and the codegen that consumes them (`../../tools/gen_arena_configs.py`) have not been run against real firmware or hardware. Schema may change. Do not rely on the emitted C header for bring-up until validated end-to-end.

Sibling registry to `configs/arenas/` (geometry) and `configs/arena_registry/` (ID assignment). Carries the **controller-side** hardware topology — SPI bus split + per-column CS-GPIO arrays — that the Teensy controller needs but the host-side geometry YAML deliberately omits.

## Why a separate file

- `configs/arenas/G6_<name>.yaml` is host-canonical: rows, cols, orientations, columns-installed, observer angle. The host doesn't care about SPI pins.
- `configs/arena_hardware/<hardware_profile>.yaml` (this directory) is controller-canonical: bus assignment per column, CS GPIO per panel slot. Reflects the as-built arena PCB.
- Geometry YAMLs reference a hardware profile via their `hardware_profile:` field. **One hardware file can serve multiple geometries** — e.g. `G6_2x10` (full install) and `G6_2x8of10` (partial install, cols 0 and 9 absent) both reference `arena_10-10_v1p1r7.yaml` because they run on the same PCB.
- The registry's per-generation Arena ID joins the geometry → hardware lookup.

A single arena geometry may bind to different hardware profiles over PCB revisions; bump the `hardware_profile:` field in the geometry YAML when migrating.

## Schema

Filename convention: `<hardware_profile_id>.yaml` (matches the geometry YAML's `hardware_profile:` field). Examples: `arena_10-10_v1p1r7.yaml`.

```yaml
hardware_profile: arena_10-10_v1p1r7    # filename minus .yaml

spi_buses:
  - bus_id: 0                    # 0 = Teensy SPI, 1 = SPI1, etc.
    name: B0                     # silk-screen / spec label
    cols: [0, 1, 2, 3, 4]        # 0-indexed columns this bus drives
  - bus_id: 1
    name: B1
    cols: [5, 6, 7, 8, 9]

# Teensy silk-label pin numbers (e.g. 0 = D0). Four per column; index = panel_row.
# For the production arena_10-10, the same Teensy GPIOs gate the corresponding
# column on each bus (col 0 ↔ col 5, col 1 ↔ col 6, …) — bus separation
# prevents collision.
cs_gpios_per_column:
  0: [0, 2, 3, 4]
  1: [5, 6, 7, 8]
  # … (one entry per column in the grid)
```

The codegen combines:
- `columns_installed` from the geometry YAML (or all-cols if `null`)
- `num_rows` from the geometry YAML (panels populate rows 0..num_rows-1, using the first `num_rows` entries of each column's `cs_gpios_per_column` list)
- `hardware_profile` from the geometry YAML (this directory's filename)

…to emit one `G6PanelMapEntry` per installed panel. Geometry YAMLs whose `hardware_profile` is `null` (e.g. `G6_3x12of18` — no built 18-col hardware yet) are skipped with a comment in the output header.

## Open issues

- **Partial-row installs** (panel present in row 1 but not row 0 of the same column) are not currently representable in the geometry YAML and not handled by the codegen. Add a `rows_installed` field if/when needed.
- All anticipated G6 hardware uses 2 SPI buses. The schema supports more, but only 2 is exercised today.
