# Lab Test Plan — 2026-03-02 (Quick)

> **Time budget**: ~15 min total
> **Goal**: Confirm Mac → SD card → G4.1 controller works end-to-end after dot-file fix

---

## Prerequisites (before going to lab)

```matlab
cd('/Users/reiserm/Documents/GitHub/maDisplayTools');
addpath('tests'); addpath('tests/fixtures'); addpath('utils');
```

Insert SD card named **PATSD** into Mac.

---

## Step 1: Automated test suite (~3 min)

```matlab
results = test_sd_card_deployment('UseRealSD', true, 'Format', true);
```

**Pass criteria**: All tests pass, `mapping.num_patterns = 16`, no dot-file warnings.

If it fails → check `results.details` for which test. Most likely: SD card not named PATSD, or not mounted.

---

## Step 2: Visual SD card check (~1 min)

In Terminal:
```bash
ls -la /Volumes/PATSD/patterns/
```

**Check**:
- [x] 16 files: `pat0001.pat` – `pat0016.pat`
- [x] NO `._pat*.pat` files (dot-file fix working)
- [x] `MANIFEST.bin` and `MANIFEST.txt` in root

---

## Step 3: Controller test (~5 min)

1. Eject SD card from Mac, insert into G4.1 controller
2. Power on controller, connect via MATLAB:

```matlab
addpath('controller');
ctrl = PanelsController;
ctrl.open();

% Test pattern 1 (should be first grating)
ctrl.setPatternID(1);
ctrl.startDisplay(2);   % Mode 2 = open loop
pause(2);
ctrl.stopDisplay();

% Test pattern 8 (mid-range — should be different pattern)
ctrl.setPatternID(8);
ctrl.startDisplay(2);
pause(2);
ctrl.stopDisplay();

% Test pattern 16 (last — should be last pattern)
ctrl.setPatternID(16);
ctrl.startDisplay(2);
pause(2);
ctrl.stopDisplay();

ctrl.close();
```

**Pass criteria**: Each pattern ID shows a DIFFERENT pattern on the arena. If ID 1 and ID 2 show the same thing, dirIndex is corrupted (format and retry).

---

## Step 4: Cross-reference with MANIFEST (~1 min)

```matlab
type('/Volumes/PATSD/MANIFEST.txt')
```

Confirm the mapping matches what you see on the arena (e.g., pat0001 = first grating type, pat0016 = last pattern type).

---

## If anything fails

1. Re-format manually: `diskutil eraseDisk FAT32 PATSD MBRFormat diskN` (find diskN via `diskutil list external`)
2. Re-run Step 1
3. If still failing, check `docs/sd_card_deployment_notes.md` troubleshooting section

---

## Done?

✅ Mac cross-platform SD card workflow is validated for lab use.
