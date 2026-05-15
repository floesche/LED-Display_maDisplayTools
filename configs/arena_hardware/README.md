# Arena Hardware Topology

> **STATUS: UNTESTED / UNVALIDATED DRAFT (2026-05-15).** Files in this directory and the codegen that consumes them (`../../tools/gen_arena_configs.py`) have not been run against real firmware or hardware. Schema may change. Do not rely on the emitted C header for bring-up until validated end-to-end.

Sibling registry to `configs/arenas/` (geometry) and `configs/arena_registry/` (ID assignment). Carries the **controller-side** hardware topology — SPI bus split + per-column CS-GPIO arrays — that the Teensy controller needs but the host-side geometry YAML deliberately omits.

## Why a separate file

- `configs/arenas/G6_<name>.yaml` is host-canonical: rows, cols, orientations, columns-installed, observer angle. The host doesn't care about SPI pins.
- `configs/arena_hardware/G6_<name>.yaml` (this directory) is controller-canonical: bus assignment per column, CS GPIO per panel slot. Reflects the as-built arena PCB.
- The two are keyed on the same `name` (matching `configs/arenas/G6_<name>.yaml`); the registry's per-generation Arena ID joins them.

A single arena may legitimately have multiple hardware variants over time (PCB revs, expanded row count). Keep one hardware YAML per geometry × hardware-rev combo if needed; the codegen picks by filename.

## Schema

```yaml
arena: G6_2x10                  # must match configs/arenas/<name>.yaml
hardware: arena_10-10_v1p1r7    # informational; PCB rev this topology targets

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
- `cols_installed` from the geometry YAML (or all-cols if `null`)
- `num_rows` from the geometry YAML (panels populate rows 0..num_rows-1, using the first `num_rows` entries of each column's `cs_gpios_per_column` list)

…to emit one `G6PanelMapEntry` per installed panel.

## Open issues

- **Partial-row installs** (panel present in row 1 but not row 0 of the same column) are not currently representable in the geometry YAML and not handled by the codegen. Add a `rows_installed` field if/when needed.
- **Hardware that doesn't exist yet** (e.g. `G6_3x12of18` would need a different bus split) has no file in this directory; the codegen skips such arenas with a comment in the output header.
- All anticipated G6 hardware uses 2 SPI buses. The schema supports more, but only 2 is exercised today.
