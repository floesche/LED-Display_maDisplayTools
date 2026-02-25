%% create_g41_experiment_patterns.m — Generate G4.1 experiment pattern set
%
% Creates 16 patterns for G4.1 lab testing and experiments:
%
%   Gratings (vertical bars, horizontal motion):
%     1.  sq_grating_30deg_gs2        — 30° square grating, GS2, 16 frames
%     2.  sq_grating_30deg_gs16       — 30° square grating, GS16, 16 frames
%     3.  sq_grating_60deg_gs2        — 60° square grating, GS2, 32 frames
%     4.  sq_grating_60deg_gs16       — 60° square grating, GS16, 32 frames
%     5.  sine_grating_30deg_gs16     — 30° sine grating, GS16, 16 frames
%     6.  sine_grating_60deg_gs16     — 60° sine grating, GS16, 32 frames
%     7.  sine_grating_30deg_fine_gs16 — 30° sine, 1/4px step, GS16, 64 frames
%     8.  sine_grating_60deg_fine_gs16 — 60° sine, 1/4px step, GS16, 128 frames
%
%   Counters (large 4-digit display, 0000-1000):
%     9.  counter_0000_1000_gs2       — Alternating inversion, 1001 frames
%     10. counter_0000_1000_gs16      — Brightness ramp, 1001 frames
%
%   Luminance levels (calibration/diagnostic):
%     11. luminance_levels_gs2        — All-off then all-on, 2 frames
%     12. luminance_levels_gs16       — All pixels at level 0..15, 16 frames
%
%   Orientation diagnostics:
%     13. top_on_gs2                  — Top half ON, bottom half OFF, 1 frame
%     14. left_on_gs2                 — Left half ON, right half OFF, 1 frame
%
%   Web-generated (roundtrip validation):
%     15. web_sq_grating_30deg_gs16   — 30° square grating via web encoder
%     16. web_sine_grating_30deg_gs16 — 30° sine grating via web encoder
%
% Target arena: G41_2x12_cw (32 rows x 192 cols, 24 panels, 360°)
%
% After running, deploy to SD card:
%   pat_dir = fullfile(pwd, 'patterns', 'reference', 'G41_2x12_cw');
%   pat_files = dir(fullfile(pat_dir, '*.pat'));
%   pat_paths = sort(fullfile(pat_dir, {pat_files.name}));
%   mapping = prepare_sd_card(pat_paths, 'D', 'Format', true);

%% Setup
cd(project_root());
clear classes;
addpath(genpath('.'));

rows = 32;   % 2 panel rows x 16 pixels
cols = 192;  % 12 panel cols x 16 pixels

arena_config = load_arena_config('configs/arenas/G41_2x12_cw.yaml');

save_dir = fullfile(pwd, 'patterns', 'reference', 'G41_2x12_cw');
if ~exist(save_dir, 'dir')
    mkdir(save_dir);
end

% Clean existing files to avoid save_pattern collision errors
existing = dir(fullfile(save_dir, '*.pat'));
if ~isempty(existing)
    fprintf('Cleaning %d existing .pat files in %s\n', length(existing), save_dir);
    delete(fullfile(save_dir, '*.pat'));
end

fprintf('=== G4.1 Experiment Pattern Generator ===\n');
fprintf('Arena: G41_2x12_cw (%d x %d pixels)\n', rows, cols);
fprintf('Output: %s\n\n', save_dir);

pattern_count = 0;

%% --- GRATINGS ---

%% Pattern 1: Square grating 30°, GS2
fprintf('Pattern 1: sq_grating_30deg_gs2\n');
wavelength = 16;  % 30° / 1.875°/px = 16 px
nf = wavelength;
Pats = zeros(rows, cols, nf, 1, 'uint8');
for f = 1:nf
    for c = 1:cols
        phase = mod(c - 1 + (f - 1), wavelength);
        if phase < wavelength / 2
            Pats(:, c, f, 1) = 1;
        end
    end
end
param = make_param(2, nf, arena_config);
save_pattern(Pats, param, save_dir, 'pat01_sq_grating_30deg_gs2');
pattern_count = pattern_count + 1;
fprintf('  OK: %d frames\n', nf);

%% Pattern 2: Square grating 30°, GS16
fprintf('Pattern 2: sq_grating_30deg_gs16\n');
Pats16 = zeros(rows, cols, nf, 1, 'uint8');
for f = 1:nf
    for c = 1:cols
        phase = mod(c - 1 + (f - 1), wavelength);
        if phase < wavelength / 2
            Pats16(:, c, f, 1) = 15;
        end
    end
end
param = make_param(16, nf, arena_config);
save_pattern(Pats16, param, save_dir, 'pat02_sq_grating_30deg_gs16');
pattern_count = pattern_count + 1;
fprintf('  OK: %d frames\n', nf);

%% Pattern 3: Square grating 60°, GS2
fprintf('Pattern 3: sq_grating_60deg_gs2\n');
wavelength = 32;  % 60° / 1.875°/px = 32 px
nf = wavelength;
Pats = zeros(rows, cols, nf, 1, 'uint8');
for f = 1:nf
    for c = 1:cols
        phase = mod(c - 1 + (f - 1), wavelength);
        if phase < wavelength / 2
            Pats(:, c, f, 1) = 1;
        end
    end
end
param = make_param(2, nf, arena_config);
save_pattern(Pats, param, save_dir, 'pat03_sq_grating_60deg_gs2');
pattern_count = pattern_count + 1;
fprintf('  OK: %d frames\n', nf);

%% Pattern 4: Square grating 60°, GS16
fprintf('Pattern 4: sq_grating_60deg_gs16\n');
Pats16 = zeros(rows, cols, nf, 1, 'uint8');
for f = 1:nf
    for c = 1:cols
        phase = mod(c - 1 + (f - 1), wavelength);
        if phase < wavelength / 2
            Pats16(:, c, f, 1) = 15;
        end
    end
end
param = make_param(16, nf, arena_config);
save_pattern(Pats16, param, save_dir, 'pat04_sq_grating_60deg_gs16');
pattern_count = pattern_count + 1;
fprintf('  OK: %d frames\n', nf);

%% Pattern 5: Sine grating 30°, GS16
fprintf('Pattern 5: sine_grating_30deg_gs16\n');
wavelength = 16;
nf = wavelength;
Pats = zeros(rows, cols, nf, 1, 'uint8');
for f = 1:nf
    for c = 1:cols
        phase = 2 * pi * (c - 1 + (f - 1)) / wavelength;
        Pats(:, c, f, 1) = round((sin(phase) + 1) / 2 * 15);
    end
end
param = make_param(16, nf, arena_config);
save_pattern(Pats, param, save_dir, 'pat05_sine_grating_30deg_gs16');
pattern_count = pattern_count + 1;
fprintf('  OK: %d frames\n', nf);

%% Pattern 6: Sine grating 60°, GS16
fprintf('Pattern 6: sine_grating_60deg_gs16\n');
wavelength = 32;
nf = wavelength;
Pats = zeros(rows, cols, nf, 1, 'uint8');
for f = 1:nf
    for c = 1:cols
        phase = 2 * pi * (c - 1 + (f - 1)) / wavelength;
        Pats(:, c, f, 1) = round((sin(phase) + 1) / 2 * 15);
    end
end
param = make_param(16, nf, arena_config);
save_pattern(Pats, param, save_dir, 'pat06_sine_grating_60deg_gs16');
pattern_count = pattern_count + 1;
fprintf('  OK: %d frames\n', nf);

%% Pattern 7: Sine grating 30° fine (1/4 px step), GS16
fprintf('Pattern 7: sine_grating_30deg_fine_gs16\n');
wavelength = 16;
nf = wavelength * 4;  % 64 frames
Pats = zeros(rows, cols, nf, 1, 'uint8');
for f = 1:nf
    shift = (f - 1) / 4;  % 1/4 pixel per frame
    for c = 1:cols
        phase = 2 * pi * (c - 1 + shift) / wavelength;
        Pats(:, c, f, 1) = round((sin(phase) + 1) / 2 * 15);
    end
end
param = make_param(16, nf, arena_config);
save_pattern(Pats, param, save_dir, 'pat07_sine_grating_30deg_fine_gs16');
pattern_count = pattern_count + 1;
fprintf('  OK: %d frames\n', nf);

%% Pattern 8: Sine grating 60° fine (1/4 px step), GS16
fprintf('Pattern 8: sine_grating_60deg_fine_gs16\n');
wavelength = 32;
nf = wavelength * 4;  % 128 frames
Pats = zeros(rows, cols, nf, 1, 'uint8');
for f = 1:nf
    shift = (f - 1) / 4;  % 1/4 pixel per frame
    for c = 1:cols
        phase = 2 * pi * (c - 1 + shift) / wavelength;
        Pats(:, c, f, 1) = round((sin(phase) + 1) / 2 * 15);
    end
end
param = make_param(16, nf, arena_config);
save_pattern(Pats, param, save_dir, 'pat08_sine_grating_60deg_fine_gs16');
pattern_count = pattern_count + 1;
fprintf('  OK: %d frames\n', nf);

%% --- COUNTERS ---

large_digits = define_large_digit_bitmaps();

%% Pattern 9: Counter 0000-1000, GS2 (alternating inversion)
fprintf('Pattern 9: counter_0000_1000_gs2\n');
nf = 1001;
Pats = zeros(rows, cols, nf, 1, 'uint8');
for f = 1:nf
    number = f - 1;  % 0 to 1000
    digit_frame = render_number_frame(number, large_digits, rows, cols);

    if mod(f - 1, 2) == 0
        % Even frames: normal polarity (digits ON, bg OFF)
        Pats(:,:,f,1) = digit_frame;
    else
        % Odd frames: inverted (digits OFF, bg ON)
        Pats(:,:,f,1) = 1 - digit_frame;
    end

    if mod(f, 200) == 0
        fprintf('  ... frame %d/%d\n', f, nf);
    end
end
param = make_param(2, nf, arena_config);
save_pattern(Pats, param, save_dir, 'pat09_counter_0000_1000_gs2');
pattern_count = pattern_count + 1;
fprintf('  OK: %d frames\n', nf);

%% Pattern 10: Counter 0000-1000, GS16 (background ramp, digits flip at midpoint)
%  Background ramps 0→15 over 16 steps, repeating every 16 frames.
%  Digits are binary: bright (15) for steps 0-7, dark (0) for steps 8-15.
fprintf('Pattern 10: counter_0000_1000_gs16\n');
nf = 1001;
Pats = zeros(rows, cols, nf, 1, 'uint8');
for f = 1:nf
    number = f - 1;  % 0 to 1000
    digit_frame = render_number_frame(number, large_digits, rows, cols);

    % Background level: ramp 0→15 repeating every 16 frames
    bg = uint8(mod(f - 1, 16));  % 0,1,2,...,15,0,1,...

    % Digits: bright while bg is dark (0-7), dark while bg is bright (8-15)
    if bg < 8
        fg = uint8(15);
    else
        fg = uint8(0);
    end

    gs_frame = zeros(rows, cols, 'uint8');
    gs_frame(digit_frame == 0) = bg;
    gs_frame(digit_frame == 1) = fg;
    Pats(:,:,f,1) = gs_frame;

    if mod(f, 200) == 0
        fprintf('  ... frame %d/%d\n', f, nf);
    end
end
param = make_param(16, nf, arena_config);
save_pattern(Pats, param, save_dir, 'pat10_counter_0000_1000_gs16');
pattern_count = pattern_count + 1;
fprintf('  OK: %d frames\n', nf);

%% --- LUMINANCE LEVELS ---

%% Pattern 11: Luminance levels GS2
fprintf('Pattern 11: luminance_levels_gs2\n');
Pats = zeros(rows, cols, 2, 1, 'uint8');
Pats(:,:,1,1) = 0;  % All off
Pats(:,:,2,1) = 1;  % All on
param = make_param(2, 2, arena_config);
save_pattern(Pats, param, save_dir, 'pat11_luminance_levels_gs2');
pattern_count = pattern_count + 1;
fprintf('  OK: 2 frames\n');

%% Pattern 12: Luminance levels GS16
fprintf('Pattern 12: luminance_levels_gs16\n');
Pats = zeros(rows, cols, 16, 1, 'uint8');
for f = 1:16
    Pats(:,:,f,1) = f - 1;  % Level 0 through 15
end
param = make_param(16, 16, arena_config);
save_pattern(Pats, param, save_dir, 'pat12_luminance_levels_gs16');
pattern_count = pattern_count + 1;
fprintf('  OK: 16 frames\n');

%% --- ORIENTATION DIAGNOSTICS ---

%% Pattern 13: Top-ON / Bottom-OFF
% Top half of arena (rows 1-16) fully ON, bottom half OFF.
% If bright half appears at the physical bottom, display is upside down.
fprintf('Pattern 13: top_on_gs2\n');
Pats = zeros(rows, cols, 1, 1, 'uint8');
Pats(1:rows/2, :, 1, 1) = 1;
param = make_param(2, 1, arena_config);
save_pattern(Pats, param, save_dir, 'pat13_top_on_gs2');
pattern_count = pattern_count + 1;
fprintf('  OK: 1 frame\n');

%% Pattern 14: Left-ON / Right-OFF
% Left half of arena (cols 1-96) fully ON, right half OFF.
% If bright half appears on the physical right, display is mirrored.
fprintf('Pattern 14: left_on_gs2\n');
Pats = zeros(rows, cols, 1, 1, 'uint8');
Pats(:, 1:cols/2, 1, 1) = 1;
param = make_param(2, 1, arena_config);
save_pattern(Pats, param, save_dir, 'pat14_left_on_gs2');
pattern_count = pattern_count + 1;
fprintf('  OK: 1 frame\n');

%% --- WEB-GENERATED PATTERNS (roundtrip validation) ---

% Auto-detect webDisplayTools as sibling repo
parent_dir = fileparts(project_root());
web_tools_dir = fullfile(parent_dir, 'webDisplayTools');
if exist(fullfile(web_tools_dir, 'js', 'pat-encoder.js'), 'file')
    fprintf('\nGenerating web patterns via Node.js...\n');
    web_gen_script = fullfile(save_dir, 'generate_web_patterns.js');
    write_web_generator_script(web_gen_script, save_dir, web_tools_dir, rows, cols);

    [status, output] = system(sprintf('node "%s"', web_gen_script));

    if status ~= 0
        fprintf('  WARNING: Web pattern generation failed:\n%s\n', output);
        fprintf('  Patterns 15-16 not created. MATLAB patterns 1-14 are unaffected.\n');
    else
        fprintf('%s', output);
        pattern_count = pattern_count + 2;
    end

    % Clean up generated script
    delete(web_gen_script);
else
    fprintf('\nSkipping web patterns: webDisplayTools not found at %s\n', web_tools_dir);
    fprintf('  Clone it as a sibling to maDisplayTools to enable web roundtrip.\n');
end

%% Summary
fprintf('\n=== Generated %d Patterns ===\n', pattern_count);
pat_files = dir(fullfile(save_dir, '*.pat'));
total_bytes = 0;
for i = 1:length(pat_files)
    fprintf('  %2d. %-50s %8d bytes\n', i, pat_files(i).name, pat_files(i).bytes);
    total_bytes = total_bytes + pat_files(i).bytes;
end
fprintf('  Total: %.2f MB\n', total_bytes / 1e6);

fprintf('\n=== Next Steps ===\n');
fprintf('Run prepare_g41_experiment_sd.m to deploy to SD card.\n');

%% =========================================================================
%% Helper Functions
%% =========================================================================

function param = make_param(gs_val, num_frames, arena_config)
    % Build a param struct for save_pattern()
    param.gs_val = gs_val;
    param.stretch = ones(num_frames, 1);
    param.generation = 'G4.1';
    param.arena_config = arena_config;
end

function frame = render_number_frame(number, digit_bitmaps, rows, cols)
    % Render a 4-digit number centered on a rows x cols frame
    %   number: 0-9999
    %   digit_bitmaps: 28x20x10 uint8 array from define_large_digit_bitmaps()
    %   Returns: uint8 frame (rows x cols) with 0/1 values

    frame = zeros(rows, cols, 'uint8');

    d = [floor(number/1000), mod(floor(number/100),10), ...
         mod(floor(number/10),10), mod(number,10)];

    digit_w = 20;
    digit_h = 28;
    spacing = 2;
    block_w = 4 * digit_w + 3 * spacing;  % 86 pixels
    start_col = floor((cols - block_w) / 2) + 1;  % 54
    start_row = floor((rows - digit_h) / 2) + 1;  % 3

    for i = 1:4
        c = start_col + (i-1) * (digit_w + spacing);
        bm = digit_bitmaps(:,:,d(i)+1);
        r1 = start_row;
        r2 = start_row + digit_h - 1;
        c1 = c;
        c2 = c + digit_w - 1;
        % Clip to frame bounds
        if r2 <= rows && c2 <= cols
            frame(r1:r2, c1:c2) = bm;
        end
    end

    % Flip vertically: pattern row 1 is display bottom in G4/G4.1 format
    frame = flipud(frame);
end

function bitmaps = define_large_digit_bitmaps()
    % 28x20 pixel 7-segment-style digit bitmaps for digits 0-9.
    %
    % Segment layout (3px thick strokes):
    %   A (top):         rows 1-3,   cols 1-20
    %   B (upper-left):  rows 2-14,  cols 1-3
    %   C (upper-right): rows 2-14,  cols 18-20
    %   D (middle):      rows 13-15, cols 1-20
    %   E (lower-left):  rows 14-27, cols 1-3
    %   F (lower-right): rows 14-27, cols 18-20
    %   G (bottom):      rows 26-28, cols 1-20
    %
    % Standard 7-segment digit-to-segment mapping:
    %   0: ABCEFG    1: CF      2: ACDEG    3: ACDFG
    %   4: BCDF      5: ABDFG   6: ABDEFG   7: ACF
    %   8: ABCDEFG   9: ABCDFG

    bitmaps = zeros(28, 20, 10, 'uint8');

    % Segment definitions: {name, row_range, col_range}
    seg.A = {1:3,   1:20};   % top horizontal
    seg.B = {2:14,  1:3};    % upper-left vertical
    seg.C = {2:14,  18:20};  % upper-right vertical
    seg.D = {13:15, 1:20};   % middle horizontal
    seg.E = {14:27, 1:3};    % lower-left vertical
    seg.F = {14:27, 18:20};  % lower-right vertical
    seg.G = {26:28, 1:20};   % bottom horizontal

    % Digit-to-segment mapping
    digit_segs = {
        'ABCEFG',   % 0
        'CF',       % 1
        'ACDEG',    % 2
        'ACDFG',    % 3
        'BCDF',     % 4
        'ABDFG',    % 5
        'ABDEFG',   % 6
        'ACF',      % 7
        'ABCDEFG',  % 8
        'ABCDFG',   % 9
    };

    for d = 1:10
        bm = zeros(28, 20, 'uint8');
        active = digit_segs{d};
        for s = 1:length(active)
            seg_name = active(s);
            ranges = seg.(seg_name);
            bm(ranges{1}, ranges{2}) = 1;
        end
        bitmaps(:,:,d) = bm;
    end
end

function write_web_generator_script(script_path, out_dir, web_dir, px_rows, px_cols)
    % Write a Node.js script that generates web-encoded patterns matching
    % MATLAB patterns 2 and 5 (30° square and sine gratings, GS16).
    % Uses absolute paths for require() so it works on any platform.

    web_dir_js = strrep(web_dir, '\', '/');
    out_dir_js = strrep(out_dir, '\', '/');

    wavelength = 16;  % 30° at 1.875°/px
    num_frames = wavelength;

    fid = fopen(script_path, 'w');

    fprintf(fid, '#!/usr/bin/env node\n');
    fprintf(fid, '// Auto-generated by create_g41_experiment_patterns.m\n');
    fprintf(fid, '// Web-encoded equivalents of MATLAB patterns 2 and 5\n\n');

    fprintf(fid, 'const fs = require(''fs'');\n');
    fprintf(fid, 'const path = require(''path'');\n');
    fprintf(fid, 'const PatEncoder = require(''%s/js/pat-encoder.js'');\n', web_dir_js);
    fprintf(fid, 'const { getArenaId, getGenerationId } = require(''%s/js/arena-configs.js'');\n\n', web_dir_js);

    fprintf(fid, 'const outDir = ''%s'';\n', strrep(out_dir_js, '''', '\\'''));
    fprintf(fid, 'const wavelength = %d;\n', wavelength);
    fprintf(fid, 'const numFrames = %d;\n', num_frames);
    fprintf(fid, 'const pixelRows = %d;\n', px_rows);
    fprintf(fid, 'const pixelCols = %d;\n\n', px_cols);

    % Square grating generator
    fprintf(fid, 'function squareGrating(rows, cols, period, shift) {\n');
    fprintf(fid, '    const frame = new Uint8Array(rows * cols);\n');
    fprintf(fid, '    for (let r = 0; r < rows; r++)\n');
    fprintf(fid, '        for (let c = 0; c < cols; c++)\n');
    fprintf(fid, '            frame[r * cols + c] = ((c + shift) %% period + period) %% period < period / 2 ? 15 : 0;\n');
    fprintf(fid, '    return frame;\n');
    fprintf(fid, '}\n\n');

    % Sine grating generator
    fprintf(fid, 'function sineGrating(rows, cols, period, shift) {\n');
    fprintf(fid, '    const frame = new Uint8Array(rows * cols);\n');
    fprintf(fid, '    for (let r = 0; r < rows; r++)\n');
    fprintf(fid, '        for (let c = 0; c < cols; c++)\n');
    fprintf(fid, '            frame[r * cols + c] = Math.round((Math.sin(2 * Math.PI * (c + shift) / period) + 1) / 2 * 15);\n');
    fprintf(fid, '    return frame;\n');
    fprintf(fid, '}\n\n');

    % Save helper
    fprintf(fid, 'function savePattern(filename, genFunc) {\n');
    fprintf(fid, '    const frames = [];\n');
    fprintf(fid, '    for (let f = 0; f < numFrames; f++)\n');
    fprintf(fid, '        frames.push(genFunc(pixelRows, pixelCols, wavelength, f));\n');
    fprintf(fid, '    const buf = PatEncoder.encode({\n');
    fprintf(fid, '        generation: ''G4.1'', gs_val: 16, numFrames,\n');
    fprintf(fid, '        rowCount: pixelRows / 16, colCount: pixelCols / 16,\n');
    fprintf(fid, '        pixelRows, pixelCols, frames,\n');
    fprintf(fid, '        stretchValues: new Array(numFrames).fill(1),\n');
    fprintf(fid, '        generation_id: getGenerationId(''G4.1''),\n');
    fprintf(fid, '        arena_id: getArenaId(''G4.1'', ''G41_2x12_cw'') || 0,\n');
    fprintf(fid, '        observer_id: 0\n');
    fprintf(fid, '    });\n');
    fprintf(fid, '    fs.writeFileSync(path.join(outDir, filename), Buffer.from(buf));\n');
    fprintf(fid, '    console.log(''  Created: '' + filename + '' ('' + buf.byteLength + '' bytes)'');\n');
    fprintf(fid, '}\n\n');

    fprintf(fid, 'savePattern(''pat15_web_sq_grating_30deg_gs16.pat'', squareGrating);\n');
    fprintf(fid, 'savePattern(''pat16_web_sine_grating_30deg_gs16.pat'', sineGrating);\n');

    fclose(fid);
end
