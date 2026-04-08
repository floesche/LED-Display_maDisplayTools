``# Testing Plan — Session 2026-02-28 Updates

> **Purpose**: Manual verification of all changes from this session before merging maDisplayTools.
> **Web repo**: Already pushed to `main` — all 3 CI checks passed ✅
> **MATLAB repo**: Uncommitted — review/test first, then commit.

---

## Part A: Web YAML Import Fix + Roundtrip

### A1. Web Import Bug Fix (manual, ~3 min)

Open: https://reiserlab.github.io/webDisplayTools/experiment_designer.html

1. **Import the existing multi-condition YAML**:
   - Click "Import YAML"
   - Load `maDisplayTools/examples/g41_experiment_protocol_v1.yaml`
   - **Expected**: All 3 conditions appear in the condition list (not just 1)
   - **Check**: Condition names, pattern filenames, durations, frame rates

2. **Import the roundtrip-generated YAML**:
   - Click "Import YAML"
   - Load `maDisplayTools/tests/web_generated_patterns/test_protocol_v1.yaml`
   - **Expected**: 3 conditions (sine_grating_gs16, square_grating_gs16, square_grating_gs2)
   - **Check**: Pretrial/intertrial/posttrial phases show as included

3. **Round-trip test**:
   - After importing, click "Export YAML" to re-export
   - Compare exported YAML with original — fields and values should match

### A2. CI/CD Pipeline (automated, already done ✅)

The new workflow `validate-protocol-roundtrip.yml` ran and passed:
- 49/49 roundtrip checks ✅
- Generator smoke test (YAML + manifest created) ✅
- All existing CI workflows still pass ✅

To re-run manually: GitHub → Actions → "Validate Protocol YAML Roundtrip" → "Run workflow"

### A3. MATLAB-Side Roundtrip Validation (manual, ~2 min)

In MATLAB:
```matlab
cd('/path/to/maDisplayTools');
addpath('tests');
addpath('experimentExecution');
validate_web_protocol_roundtrip
```
**Expected**: `28/28 tests passed` (already verified, but worth re-running after any edits)

---

## Part B: Mac SD Card Support

### B1. detect_sd_card() Utility (manual, ~2 min)

In MATLAB on Mac:

```matlab
addpath('utils');

% Test 1: No SD card inserted
sd = detect_sd_card('Verbose', true);
% Expected: sd.found = false, sd.candidates lists /Volumes/ contents

% Test 2: Insert SD card named "PATSD"
sd = detect_sd_card('Verbose', true);
% Expected: sd.found = true, sd.path = '/Volumes/PATSD'
% Expected: sd.device shows 'diskN' identifier
% Expected: sd.platform = 'mac'

% Test 3: Custom label
sd = detect_sd_card('Label', 'UNTITLED', 'Verbose', true);
% Expected: Searches for volume named 'UNTITLED' instead
```

### B2. Mac Disk Formatting with Reference Patterns (manual, CAUTION — formats the card!)

**Prerequisites**: Insert an SD card named "PATSD" you're OK with erasing.

```matlab
addpath('tests/fixtures');
addpath('utils');

% Use the full reference pattern set (16 patterns, ~11 MB)
pat_dir = fullfile(pwd, 'patterns', 'reference', 'G41_2x12_cw');
d = dir(fullfile(pat_dir, '*.pat'));
patterns = fullfile(pat_dir, sort({d.name}));
fprintf('Found %d reference patterns\n', length(patterns));

% Detect SD card and deploy with format
sd = detect_sd_card('Verbose', true);
mapping = prepare_sd_card_crossplatform(patterns, sd.path, 'Format', true);

% Inspect result
disp(mapping);
if mapping.success
    fprintf('SUCCESS: %d patterns deployed\n', mapping.num_patterns);
else
    fprintf('FAILED: %s\n', mapping.error);
end
```

**Expected flow**:
1. `✓ SD card validated: PATSD` (Mac volume name validation)
2. `Found 16 reference patterns`
3. Prompts: "Will format diskN as FAT32 with label PATSD. Continue? (y/n)"
4. On "y": runs `diskutil eraseDisk`, waits for remount at `/Volumes/PATSD`
5. 16 patterns staged and copied in order (pat0001.pat–pat0016.pat)
6. macOS `._*` resource fork files cleaned (prevents dirIndex corruption)
7. MANIFEST.bin + MANIFEST.txt created
8. Final dot-file cleanup pass
9. `mapping.success = true`, `mapping.num_patterns = 16`

**If you decline format**: Should print the exact Terminal command for manual formatting.

> **Bug fix (2026-03-01)**: Previous version counted macOS `._pat*.pat` resource fork
> files in verification (found 32 instead of 16). These hidden files also corrupt G4.1
> dirIndex ordering in the lab. Now fixed: dot-files are deleted after copy, and
> verification filters them out.

### B3. Refactored prepare_g41_experiment_sd.m (manual, ~3 min)

```matlab
addpath('tests');
addpath('tests/fixtures');
addpath('utils');
addpath('experimentExecution');

% Test 1: Auto-detection (no SD card)
prepare_g41_experiment_sd
% Expected: Prompts for SD path, falls back to local staging if Enter pressed

% Test 2: With SD card
% Insert card, then run — should auto-detect and use detect_sd_card()
prepare_g41_experiment_sd
% Expected: Finds PATSD, deploys test patterns
```

### B4. Documentation Review (manual, ~2 min)

Review `docs/sd_card_deployment_notes.md` — specifically:
- [ ] "Basic Usage (Mac / Cross-platform)" code example makes sense
- [ ] Platform Support table is accurate
- [ ] Mac troubleshooting entries are helpful
- [ ] Changelog entry for 2026-02-28 is complete

---

## Summary Checklist

| # | Test | Type | Status |
|---|------|------|--------|
| A1 | Web YAML import (multi-condition) | Manual/web | 🔲 |
| A2 | CI/CD roundtrip pipeline | Automated | ✅ Passed |
| A3 | MATLAB roundtrip validation | Manual/MATLAB | ✅ 28/28 (re-run to confirm) |
| B1 | detect_sd_card() on Mac | Manual/MATLAB | ✅ Confirmed working |
| B2 | Mac diskutil formatting (16 ref patterns) | Manual/MATLAB | 🔄 Re-test after dot-file fix |
| B3 | Refactored prepare_g41_experiment_sd | Manual/MATLAB | 🔲 |
| B4 | SD card docs review | Manual/read | 🔲 |

---

## Note for Lisa: Reference Patterns vs Example Patterns

The simple patterns in `examples/` (`pat0001_1row_gs2_sqGrate.pat`, etc.) are basic row gratings that aren't meaningful for lab testing. The reference patterns at `patterns/reference/G41_2x12_cw/` (16 patterns generated by `tests/create_g41_experiment_patterns.m`) are much more comprehensive — they include gratings at multiple spatial frequencies, counter patterns for frame verification, luminance calibration, orientation diagnostics, and web-generated roundtrip patterns.

**Recommended future cleanup:**
- Shift all testing/examples to use `patterns/reference/G41_2x12_cw/` as the standard test set
- Remove or archive the simple `examples/*.pat` files (they don't represent real experimental stimuli)
- Update `SimpleYamlExperimentDemo/` to reference the reference patterns instead

---

## Files Changed (maDisplayTools — not yet committed)

| File | Change |
|------|--------|
| `utils/detect_sd_card.m` | **NEW** — cross-platform SD detection utility |
| `tests/validate_web_protocol_roundtrip.m` | **NEW** — MATLAB roundtrip validation (28 tests) |
| `tests/web_generated_patterns/` | **NEW** — generated YAML + manifest from web tools |
| `tests/fixtures/prepare_sd_card_crossplatform.m` | **MODIFIED** — Mac diskutil formatting + dot-file cleanup + ValidateDriveName |
| `tests/prepare_g41_experiment_sd.m` | **MODIFIED** — refactored to use detect_sd_card() |
| `docs/sd_card_deployment_notes.md` | **MODIFIED** — Mac sections, platform table, troubleshooting |

## Files Changed (webDisplayTools — already pushed ✅)

| File | Change |
|------|--------|
| `experiment_designer.html` | **FIX** — simpleYAMLParse comment-handling + missing braces; version v0.2 |
| `experiment_designer_quickstart.html` | **FIX** — arena dropdown reference (CCW removed) |
| `tests/test-protocol-roundtrip.js` | **NEW** — 49-check CI regression test |
| `tests/generate-roundtrip-protocol.js` | **NEW** — V1 YAML generator + self-verification |
| `docs/protocol-roundtrip-testing.md` | **NEW** — roundtrip testing architecture docs |
| `.github/workflows/validate-protocol-roundtrip.yml` | **NEW** — CI workflow |
