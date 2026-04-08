# Arena & Rig Configuration — Audit & Consolidation Plan

**Date:** 2026-02-26 (updated from 2026-01-25 original audit)
**Author:** Michael Reiser
**Status:** Proposal for discussion

---

## Background

With recent G4.1/G6 tool consolidation, arena and rig configurations are now standardized in YAML files under `configs/`. However, the same information (arena dimensions, generation specs, controller IPs) still appears in multiple places across the codebase. This document maps where configuration data lives, identifies redundancies, and proposes a consolidation strategy.

### Progress Since Original Audit (Jan 25)

Several issues from the original audit have been resolved:
- `get_generation_specs.m` created as shared function (was recommendation #3)
- `load_arena_config.m` and `load_rig_config.m` now call `get_generation_specs()` (was recommendation #4)
- G6 tools parameterized via arena config (was recommendation #6)
- `maDisplayTools.m` updated to accept generation parameter (was recommendation #7)

Remaining issues are addressed in this updated plan.

---

## Current Architecture

### Config Files (Single Sources of Truth)

| Location | Contents | Notes |
|----------|----------|-------|
| `configs/arenas/*.yaml` (10 files) | Arena layout: generation, rows, cols, column_order, angle_offset | One file per physical arena configuration |
| `configs/rigs/*.yaml` (6 files) | Controller IP/port, plugin settings, arena reference (file path) | One file per lab rig. Arena is a reference, not duplicated |
| `configs/arena_registry/generations.yaml` | Panel hardware specs per generation (panel_size, led_type, panel_width_mm) | Shared by MATLAB and web tools |
| `configs/arena_registry/index.yaml` | Arena ID assignments per generation | For pattern header metadata |

### Config Loading Chain

```
get_generation_specs(gen)     → panel hardware specs (pixels, physical dimensions)
         |
load_arena_config(path)       → arena YAML + computed derived properties
         |
load_rig_config(path)         → rig YAML + resolved arena + controller info
         |
ProtocolParser                → experiment YAML → resolved rig → arena → controller
         |
CommandExecutor               → executes trial commands (pattern_ID, mode, duration only)
```

This chain is clean — each layer adds information, and `CommandExecutor` at the bottom only needs trial-level parameters. The issues are in how information enters this chain.

---

## Identified Redundancies

### 1. Protocol YAML Inlines Arena Dimensions (HIGH)

Current V1 protocol YAMLs embed arena info directly:

```yaml
# In g41_experiment_protocol_v1.yaml
arena_info:
  num_rows: 2
  num_cols: 12
  generation: "G4.1"
```

These values duplicate `configs/arenas/G41_2x12_cw.yaml`. If the arena config changes, the protocol silently becomes stale.

V2 protocol format solves this by referencing a rig file instead:

```yaml
rig: "../configs/rigs/test_rig_1.yaml"
```

The rig references the arena config, so there's a single chain with no duplication.

### 2. Controller IP Specified Twice (MEDIUM)

`run_protocol(yamlPath, arenaIP)` requires the controller IP as a function argument, even though V2 rig configs already contain `controller.host`. This means the IP is specified in two places: the rig YAML and the function call.

Standalone test scripts (e.g., `test_mode3.m`) reasonably hardcode IPs — they aren't protocol-driven. But the experiment pipeline should resolve IP from the rig config by default.

### 3. Generation Specs: Code vs YAML (MEDIUM)

`get_generation_specs.m` returns panel specs (pixels_per_panel, panel_width_mm, pin layout, etc.) via a hardcoded switch statement. The same basic specs exist in `generations.yaml`. The two are maintained in parallel — neither reads from the other.

Risk: If someone updates one but not the other, specs diverge silently.

### 4. Derived Property Computation Duplicated (LOW)

Both `load_arena_config.m` and `load_rig_config.m` independently compute the same derived properties (total_pixels, inner_radius, azimuth_coverage). Both call `get_generation_specs()` so the source data is consistent. The duplication is in computation code, not data — low risk but unnecessary.

### 5. Pattern Header Arena Metadata (LOW — intentional)

V2 pattern file headers store `generation_id` and `arena_id`. This duplicates arena config info but is intentional: patterns need to be self-describing for validation when loaded without config context. No change needed.

---

## Proposed Consolidation

### Phase 1: Standardize on V2 Protocols + Rig-Based IP Resolution

**What changes:**
- Rewrite existing protocol YAMLs as V2 format (replace inline `arena_info` with `rig:` reference)
- Remove V1 parsing from ProtocolParser (no backward compatibility needed — all V1 files are development artifacts)
- Make controller IP optional in `run_protocol()` — resolve from rig config by default, accept explicit IP as override

**Files affected:**
- `examples/g41_experiment_protocol_v1.yaml` → rewrite as V2, rename
- `experimentExecution/ProtocolParser.m` → remove V1 parsing path
- `experimentExecution/run_protocol.m` → make `arenaIP` optional
- `experimentExecution/ProtocolRunner.m` → pass controller IP from rig config
- `examples/experimentTemplate.yaml` → update to V2 format

**Result:** `run_protocol('examples/g41_experiment_protocol.yaml')` works with no extra arguments. The rig config provides the arena and controller IP. Explicit IP override still available for ad-hoc testing.

### Phase 2: Unify Generation Specs

**What changes:**
- Extend `generations.yaml` to include all mechanical specs currently hardcoded in MATLAB (pin layout, depth, etc.)
- Refactor `get_generation_specs.m` to read from YAML as primary source
- Add validation test ensuring YAML and MATLAB agree

**Files affected:**
- `configs/arena_registry/generations.yaml` → add missing fields
- `utils/get_generation_specs.m` → read from YAML

**Result:** Single source of truth for all panel generation specifications. MATLAB reads from YAML instead of maintaining parallel hardcoded values.

### Phase 3: Extract Shared Derived Property Computation

**What changes:**
- Extract `compute_arena_derived()` helper function
- Both `load_arena_config.m` and `load_rig_config.m` call it instead of inline computation

**Files affected:**
- New: `utils/compute_arena_derived.m`
- `utils/load_arena_config.m` → call helper
- `utils/load_rig_config.m` → call helper

**Result:** Derived property logic maintained in one place.

---

## Priority & Effort

| Phase | Priority | Effort | Dependencies |
|-------|----------|--------|--------------|
| Phase 1: V2 protocols + IP resolution | High | 1 session | None |
| Phase 2: Generation specs unification | Medium | 1-2 sessions | None |
| Phase 3: Derived property helper | Low | 1 session | Phase 2 |

Phase 1 can proceed immediately. Phase 2 is independent. Phase 3 is cleanup.

---

## Questions

1. **Vestigial `pattern` field in CommandExecutor**: The `required_fields` list (line 120) includes `pattern` but `getPatternID` is commented out. Safe to remove, or is it used for logging?

2. **Rig config flow**: Currently the controller IP flows from rig config through ProtocolRunner to PanelsController. Is this working for your experiments, or should CommandExecutor accept a rig config directly?
