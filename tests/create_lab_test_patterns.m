%% create_lab_test_patterns.m — DEPRECATED
%
% This script has been superseded by create_g41_experiment_patterns.m,
% which generates a unified set of 16 patterns including orientation
% diagnostics and web roundtrip validation patterns.
%
% Use instead:
%   create_g41_experiment_patterns   % Generate all 16 patterns
%   prepare_g41_experiment_sd        % Deploy to SD card

error('DEPRECATED: Use create_g41_experiment_patterns.m instead.');

%% Original code below (kept for reference) ================================

%% Setup
cd(project_root());
clear classes;
addpath(genpath('.'));

rows = 32;   % 2 panel rows × 16 pixels
cols = 192;  % 12 panel cols × 16 pixels
num_frames = 16;
wavelength = 32;  % Grating wavelength in pixels

save_dir = fullfile(pwd, 'tests', 'lab_test_patterns');
if ~exist(save_dir, 'dir')
    mkdir(save_dir);
end

% Auto-detect webDisplayTools as sibling repo (works on Mac + Windows)
repo_root = project_root();
parent_dir = fileparts(repo_root);
web_tools_dir = fullfile(parent_dir, 'webDisplayTools');
if ~exist(fullfile(web_tools_dir, 'js', 'pat-encoder.js'), 'file')
    error(['Cannot find webDisplayTools repo.\n' ...
           'Expected at: %s\n' ...
           'Make sure webDisplayTools is cloned next to maDisplayTools.'], ...
           web_tools_dir);
end

fprintf('=== Lab Test Pattern Generator ===\n\n');

%% Pattern 1: MATLAB GS2 vertical grating
fprintf('Pattern 1: MATLAB GS2 vertical grating\n');
Pats = zeros(rows, cols, num_frames, 1, 'uint8');
for f = 1:num_frames
    shift = f - 1;
    for c = 1:cols
        phase = mod(c - 1 + shift, wavelength);
        if phase < wavelength / 2
            Pats(:, c, f, 1) = 1;
        end
    end
end
stretch = ones(num_frames, 1, 'uint8');
maDisplayTools.generate_pattern_from_array(Pats, save_dir, 'pat01_matlab_gs2_grating', 2, stretch);
fprintf('  Created: pat01_matlab_gs2_grating\n');

%% Pattern 2: MATLAB GS16 vertical grating
fprintf('Pattern 2: MATLAB GS16 vertical grating\n');
Pats16 = zeros(rows, cols, num_frames, 1, 'uint8');
for f = 1:num_frames
    shift = f - 1;
    for c = 1:cols
        phase = mod(c - 1 + shift, wavelength);
        if phase < wavelength / 2
            Pats16(:, c, f, 1) = 15;
        end
    end
end
maDisplayTools.generate_pattern_from_array(Pats16, save_dir, 'pat02_matlab_gs16_grating', 16, stretch);
fprintf('  Created: pat02_matlab_gs16_grating\n');

%% Pattern 6: MATLAB GS16 multi-frame digits (for Mode 3)
fprintf('Pattern 6: MATLAB GS16 multi-frame digits\n');
% Each frame displays a different digit (1-16) using 8x8 font
digit_bitmaps = define_digit_bitmaps();
Pats_digits16 = zeros(rows, cols, num_frames, 1, 'uint8');
for f = 1:num_frames
    frame = zeros(rows, cols, 'uint8');
    % Display frame number centered on each panel column
    d1 = floor((f - 1) / 10);  % Tens digit
    d2 = mod(f - 1, 10);       % Ones digit
    % Place digits at center of arena
    start_col = 80;  % Roughly center of 192-wide arena
    if f >= 10
        frame = place_digit(frame, digit_bitmaps(:,:,d1+1), 4, start_col);
        frame = place_digit(frame, digit_bitmaps(:,:,d2+1), 4, start_col + 12);
    else
        frame = place_digit(frame, digit_bitmaps(:,:,d2+1), 4, start_col + 6);
    end
    % Scale to GS16 (bitmap is 0/1, multiply by 15 for max brightness)
    Pats_digits16(:,:,f,1) = frame * 15;
end
maDisplayTools.generate_pattern_from_array(Pats_digits16, save_dir, 'pat06_matlab_gs16_digits', 16, stretch);
fprintf('  Created: pat06_matlab_gs16_digits\n');

%% Pattern 7: MATLAB GS2 multi-frame digits (for Mode 3 GS2 test)
fprintf('Pattern 7: MATLAB GS2 multi-frame digits\n');
Pats_digits2 = zeros(rows, cols, num_frames, 1, 'uint8');
for f = 1:num_frames
    frame = zeros(rows, cols, 'uint8');
    d1 = floor((f - 1) / 10);
    d2 = mod(f - 1, 10);
    start_col = 80;
    if f >= 10
        frame = place_digit(frame, digit_bitmaps(:,:,d1+1), 4, start_col);
        frame = place_digit(frame, digit_bitmaps(:,:,d2+1), 4, start_col + 12);
    else
        frame = place_digit(frame, digit_bitmaps(:,:,d2+1), 4, start_col + 6);
    end
    Pats_digits2(:,:,f,1) = frame;  % Already 0/1
end
maDisplayTools.generate_pattern_from_array(Pats_digits2, save_dir, 'pat07_matlab_gs2_digits', 2, stretch);
fprintf('  Created: pat07_matlab_gs2_digits\n');

%% Pattern 8: Top-ON / Bottom-OFF (vertical orientation diagnostic)
% Top half of arena (rows 1-16) is fully ON, bottom half (rows 17-32) is OFF.
% Single frame — if you see the bright half on the physical bottom, display is
% upside down.
fprintf('Pattern 8: MATLAB GS2 top-ON / bottom-OFF\n');
Pats_topbot = zeros(rows, cols, 1, 1, 'uint8');
Pats_topbot(1:rows/2, :, 1, 1) = 1;   % top half ON
stretch1 = uint8(1);
maDisplayTools.generate_pattern_from_array(Pats_topbot, save_dir, 'pat08_matlab_gs2_top_on', 2, stretch1);
fprintf('  Created: pat08_matlab_gs2_top_on\n');

%% Pattern 9: Left-ON / Right-OFF (horizontal orientation diagnostic)
% Left half of arena (cols 1-96) is fully ON, right half (cols 97-192) is OFF.
% Single frame — if you see the bright half on the physical right, display is
% mirrored.
fprintf('Pattern 9: MATLAB GS2 left-ON / right-OFF\n');
Pats_leftright = zeros(rows, cols, 1, 1, 'uint8');
Pats_leftright(:, 1:cols/2, 1, 1) = 1;  % left half ON
maDisplayTools.generate_pattern_from_array(Pats_leftright, save_dir, 'pat09_matlab_gs2_left_on', 2, stretch1);
fprintf('  Created: pat09_matlab_gs2_left_on\n');

%% Patterns 3, 4, 5, 8: Web-generated patterns via Node.js
fprintf('\nGenerating web patterns via Node.js...\n');
web_gen_script = fullfile(pwd, 'tests', 'generate_lab_web_patterns.js');
write_web_generator_script(web_gen_script, save_dir, web_tools_dir, wavelength, num_frames, rows, cols);

[status, output] = system(sprintf('node "%s"', web_gen_script));

if status ~= 0
    fprintf('  ERROR generating web patterns:\n%s\n', output);
    fprintf('  You may need to generate web patterns manually.\n');
else
    fprintf('%s', output);
end

%% List all generated patterns
fprintf('\n=== Generated Patterns ===\n');
pat_files = dir(fullfile(save_dir, '*.pat'));
for i = 1:length(pat_files)
    fprintf('  %d. %s (%d bytes)\n', i, pat_files(i).name, pat_files(i).bytes);
end

fprintf('\n=== Next Steps ===\n');
fprintf('1. Run diagnose_web_patterns.m to verify patterns\n');
fprintf('2. Deploy to SD card:\n');
fprintf('   pat_files = sort_lab_patterns(''%s'');\n', save_dir);
fprintf('   mapping = prepare_sd_card(pat_files, ''D'', ''Format'', true);\n');


%% Helper functions

function bitmaps = define_digit_bitmaps()
    % Define 8x8 digit bitmaps (0-9)
    bitmaps = zeros(8, 8, 10, 'uint8');

    bitmaps(:,:,1) = [  % 0
        0 0 1 1 1 1 0 0; 0 1 1 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 1 1 0 0 1 1 0
        0 1 1 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 0 1 1 1 1 0 0];
    bitmaps(:,:,2) = [  % 1
        0 0 0 1 1 0 0 0; 0 0 1 1 1 0 0 0; 0 1 1 1 1 0 0 0; 0 0 0 1 1 0 0 0
        0 0 0 1 1 0 0 0; 0 0 0 1 1 0 0 0; 0 0 0 1 1 0 0 0; 0 1 1 1 1 1 1 0];
    bitmaps(:,:,3) = [  % 2
        0 0 1 1 1 1 0 0; 0 1 1 0 0 1 1 0; 0 0 0 0 0 1 1 0; 0 0 0 0 1 1 0 0
        0 0 0 1 1 0 0 0; 0 0 1 1 0 0 0 0; 0 1 1 0 0 0 0 0; 0 1 1 1 1 1 1 0];
    bitmaps(:,:,4) = [  % 3
        0 0 1 1 1 1 0 0; 0 1 1 0 0 1 1 0; 0 0 0 0 0 1 1 0; 0 0 0 1 1 1 0 0
        0 0 0 0 0 1 1 0; 0 0 0 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 0 1 1 1 1 0 0];
    bitmaps(:,:,5) = [  % 4
        0 0 0 0 1 1 0 0; 0 0 0 1 1 1 0 0; 0 0 1 1 1 1 0 0; 0 1 1 0 1 1 0 0
        0 1 1 1 1 1 1 0; 0 0 0 0 1 1 0 0; 0 0 0 0 1 1 0 0; 0 0 0 0 1 1 0 0];
    bitmaps(:,:,6) = [  % 5
        0 1 1 1 1 1 1 0; 0 1 1 0 0 0 0 0; 0 1 1 0 0 0 0 0; 0 1 1 1 1 1 0 0
        0 0 0 0 0 1 1 0; 0 0 0 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 0 1 1 1 1 0 0];
    bitmaps(:,:,7) = [  % 6
        0 0 1 1 1 1 0 0; 0 1 1 0 0 0 0 0; 0 1 1 0 0 0 0 0; 0 1 1 1 1 1 0 0
        0 1 1 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 0 1 1 1 1 0 0];
    bitmaps(:,:,8) = [  % 7
        0 1 1 1 1 1 1 0; 0 0 0 0 0 1 1 0; 0 0 0 0 1 1 0 0; 0 0 0 0 1 1 0 0
        0 0 0 1 1 0 0 0; 0 0 0 1 1 0 0 0; 0 0 0 1 1 0 0 0; 0 0 0 1 1 0 0 0];
    bitmaps(:,:,9) = [  % 8
        0 0 1 1 1 1 0 0; 0 1 1 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 0 1 1 1 1 0 0
        0 1 1 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 0 1 1 1 1 0 0];
    bitmaps(:,:,10) = [ % 9
        0 0 1 1 1 1 0 0; 0 1 1 0 0 1 1 0; 0 1 1 0 0 1 1 0; 0 0 1 1 1 1 1 0
        0 0 0 0 0 1 1 0; 0 0 0 0 0 1 1 0; 0 0 0 0 1 1 0 0; 0 0 1 1 1 0 0 0];
end

function frame = place_digit(frame, bitmap, start_row, start_col)
    % Place an 8x8 digit bitmap into the frame at (start_row, start_col)
    [bh, bw] = size(bitmap);
    [fh, fw] = size(frame);
    for r = 1:bh
        for c = 1:bw
            fr = start_row + r - 1;
            fc = start_col + c - 1;
            if fr >= 1 && fr <= fh && fc >= 1 && fc <= fw
                frame(fr, fc) = bitmap(r, c);
            end
        end
    end
end

function write_web_generator_script(script_path, out_dir, web_dir, wavelength, num_frames, rows, cols)
    % Write a Node.js script that generates web patterns using PatEncoder
    % Uses absolute paths for require() so the script works regardless of cwd.
    fid = fopen(script_path, 'w');

    % Normalize to forward slashes for JS (works on both platforms)
    web_dir_js = strrep(web_dir, '\', '/');
    out_dir_js = strrep(out_dir, '\', '/');

    fprintf(fid, '#!/usr/bin/env node\n');
    fprintf(fid, '/**\n');
    fprintf(fid, ' * Generate web-encoded lab test patterns (3, 4, 5)\n');
    fprintf(fid, ' * Auto-generated by create_lab_test_patterns.m\n');
    fprintf(fid, ' */\n\n');

    fprintf(fid, 'const fs = require(''fs'');\n');
    fprintf(fid, 'const path = require(''path'');\n');
    fprintf(fid, 'const PatEncoder = require(''%s/js/pat-encoder.js'');\n', web_dir_js);
    fprintf(fid, 'const { getArenaId, getGenerationId } = require(''%s/js/arena-configs.js'');\n\n', web_dir_js);

    fprintf(fid, 'const outDir = ''%s'';\n', strrep(out_dir_js, '''', '\\'''));
    fprintf(fid, 'const wavelength = %d;\n', wavelength);
    fprintf(fid, 'const numFrames = %d;\n', num_frames);
    fprintf(fid, 'const pixelRows = %d;\n', rows);
    fprintf(fid, 'const pixelCols = %d;\n\n', cols);

    % Square grating generator
    fprintf(fid, 'function squareGrating(pixelRows, pixelCols, period, shift, maxVal) {\n');
    fprintf(fid, '    const frame = new Uint8Array(pixelRows * pixelCols);\n');
    fprintf(fid, '    for (let r = 0; r < pixelRows; r++) {\n');
    fprintf(fid, '        for (let c = 0; c < pixelCols; c++) {\n');
    fprintf(fid, '            const phase = ((c + shift) %% period + period) %% period;\n');
    fprintf(fid, '            frame[r * pixelCols + c] = phase < period / 2 ? maxVal : 0;\n');
    fprintf(fid, '        }\n');
    fprintf(fid, '    }\n');
    fprintf(fid, '    return frame;\n');
    fprintf(fid, '}\n\n');

    % Sine grating generator
    fprintf(fid, 'function sineGrating(pixelRows, pixelCols, period, shift, maxVal) {\n');
    fprintf(fid, '    const frame = new Uint8Array(pixelRows * pixelCols);\n');
    fprintf(fid, '    for (let r = 0; r < pixelRows; r++) {\n');
    fprintf(fid, '        for (let c = 0; c < pixelCols; c++) {\n');
    fprintf(fid, '            const phase = 2 * Math.PI * (c + shift) / period;\n');
    fprintf(fid, '            frame[r * pixelCols + c] = Math.round((Math.sin(phase) + 1) / 2 * maxVal);\n');
    fprintf(fid, '        }\n');
    fprintf(fid, '    }\n');
    fprintf(fid, '    return frame;\n');
    fprintf(fid, '}\n\n');

    % Generate pattern helper
    fprintf(fid, 'function savePattern(filename, generation, configName, gs, genFunc) {\n');
    fprintf(fid, '    const isGS16 = gs === 16;\n');
    fprintf(fid, '    const maxVal = isGS16 ? 15 : 1;\n');
    fprintf(fid, '    const frames = [];\n');
    fprintf(fid, '    for (let f = 0; f < numFrames; f++) {\n');
    fprintf(fid, '        frames.push(genFunc(pixelRows, pixelCols, wavelength, f, maxVal));\n');
    fprintf(fid, '    }\n');
    fprintf(fid, '    const patternData = {\n');
    fprintf(fid, '        generation, gs_val: gs, numFrames,\n');
    fprintf(fid, '        rowCount: pixelRows / 16, colCount: pixelCols / 16,\n');
    fprintf(fid, '        pixelRows, pixelCols, frames,\n');
    fprintf(fid, '        stretchValues: new Array(numFrames).fill(1),\n');
    fprintf(fid, '        generation_id: getGenerationId(generation),\n');
    fprintf(fid, '        arena_id: getArenaId(generation, configName) || 0,\n');
    fprintf(fid, '        observer_id: 0\n');
    fprintf(fid, '    };\n');
    fprintf(fid, '    const buffer = PatEncoder.encode(patternData);\n');
    fprintf(fid, '    fs.writeFileSync(path.join(outDir, filename), Buffer.from(buffer));\n');
    fprintf(fid, '    console.log(''  Created: '' + filename + '' ('' + buffer.byteLength + '' bytes)'');\n');
    fprintf(fid, '}\n\n');

    % Generate patterns
    fprintf(fid, '// Pattern 3: Web GS2 vertical grating (CW)\n');
    fprintf(fid, 'savePattern(''pat03_web_gs2_grating.pat'', ''G4.1'', ''G41_2x12_cw'', 2, squareGrating);\n\n');

    fprintf(fid, '// Pattern 4: Web GS16 vertical grating (CW)\n');
    fprintf(fid, 'savePattern(''pat04_web_gs16_grating.pat'', ''G4.1'', ''G41_2x12_cw'', 16, squareGrating);\n\n');

    fprintf(fid, '// Pattern 5: Web GS16 sine grating (CW — for Mode 3 smooth motion)\n');
    fprintf(fid, 'savePattern(''pat05_web_gs16_sine.pat'', ''G4.1'', ''G41_2x12_cw'', 16, sineGrating);\n');

    fclose(fid);
end
