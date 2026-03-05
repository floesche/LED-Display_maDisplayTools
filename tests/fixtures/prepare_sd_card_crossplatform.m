function mapping = prepare_sd_card_crossplatform(pattern_paths, sd_location, options)
% PREPARE_SD_CARD_CROSSPLATFORM Cross-platform version of prepare_sd_card
%
%   mapping = prepare_sd_card_crossplatform(pattern_paths, sd_location)
%   mapping = prepare_sd_card_crossplatform(pattern_paths, sd_location, 'Format', true)
%   mapping = prepare_sd_card_crossplatform(pattern_paths, sd_location, 'UsePatternFolder', false)
%   mapping = prepare_sd_card_crossplatform(pattern_paths, sd_location, 'StagingDir', '/path/to/staging')
%
%   Cross-platform wrapper that works on Windows, Mac, and Linux.
%   Handles both drive letters (Windows) and absolute paths (Mac/Linux).
%
%   INPUTS:
%       pattern_paths - Cell array of full paths to pattern files (in desired order)
%       sd_location   - SD card location:
%                       Windows: Drive letter (e.g., 'E' or 'E:')
%                       Mac/Linux: Absolute path (e.g., '/Volumes/SD_CARD' or '/tmp/fake_sd')
%       options       - Name-value pairs:
%           'Format' (false)          - Format SD card before copying
%                                       Windows: format X: /FS:FAT32 /V:PATSD /Q /Y
%                                       Mac: diskutil eraseDisk FAT32 PATSD MBRFormat diskN
%                                       (prompts for confirmation on Mac before erasing)
%           'UsePatternFolder' (true) - Copy patterns to /patterns subfolder
%           'StagingDir' ('')         - Custom staging directory (default: tempdir/sd_staging)
%           'ValidateDriveName' (true)- Require SD card named PATSD (Windows only)
%
%   OUTPUTS:
%       mapping - Struct with same fields as prepare_sd_card.m
%
%   EXAMPLES:
%       % Windows (real SD card)
%       mapping = prepare_sd_card_crossplatform(patterns, 'E');
%       mapping = prepare_sd_card_crossplatform(patterns, 'E', 'Format', true);
%       
%       % Mac (real SD card)
%       mapping = prepare_sd_card_crossplatform(patterns, '/Volumes/SD_CARD');
%       
%       % Mac (testing with fake folder)
%       mapping = prepare_sd_card_crossplatform(patterns, '/tmp/fake_sd_card');
%       
%       % Linux
%       mapping = prepare_sd_card_crossplatform(patterns, '/media/user/SD_CARD');
%
%   TESTING ON MAC:
%       % Create fake SD card folder
%       fake_sd = '/tmp/fake_sd_card';
%       if isfolder(fake_sd), rmdir(fake_sd, 's'); end
%       mkdir(fake_sd);
%       
%       % Deploy to fake SD card
%       patterns = {'pattern1.pat', 'pattern2.pat'};
%       result = prepare_sd_card_crossplatform(patterns, fake_sd);
%       
%       % Check contents
%       dir(fullfile(fake_sd, 'patterns'))
%       type(fullfile(fake_sd, 'MANIFEST.txt'))
%
%   NOTES:
%       - Pattern IDs are determined by position in pattern_paths array
%       - Same file can appear multiple times with different IDs
%       - Lowercase filenames: pat0001.pat, pat0002.pat, etc.
%       - MANIFEST files written AFTER patterns for correct FAT32 dirIndex
%       - Format option: Windows (auto), Mac (with confirmation prompt)
%       - ValidateDriveName: checks 'PATSD' on both Windows (vol) and Mac (mount path)
%       - On Mac, formatting clears the FAT table, ensuring reliable dirIndex order
%       - macOS dot-files (._*) are automatically cleaned from FAT32 volumes
%         (AppleDouble resource forks corrupt G4.1 controller dirIndex ordering)
%
%   See also: prepare_sd_card, deploy_experiments_to_sd

    arguments
        pattern_paths cell
        sd_location char
        options.Format (1,1) logical = false
        options.UsePatternFolder (1,1) logical = true
        options.StagingDir char = ''
        options.ValidateDriveName (1,1) logical = true
    end

    %% Initialize mapping struct
    mapping = struct();
    mapping.success = false;
    mapping.error = '';
    mapping.timestamp = '';
    mapping.timestamp_unix = uint32(0);
    mapping.sd_drive = '';
    mapping.num_patterns = 0;
    mapping.patterns = {};
    mapping.log_file = '';
    mapping.staging_dir = '';
    mapping.target_dir = '';

    %% Set staging directory
    if isempty(options.StagingDir)
        staging_dir = fullfile(tempdir, 'sd_staging');
    else
        staging_dir = options.StagingDir;
    end
    mapping.staging_dir = staging_dir;
    
    %% Detect platform and location type
    is_windows = ispc;
    
    % Check if sd_location looks like a Windows drive letter
    is_drive_letter = (length(sd_location) <= 2 && ...
                      ((length(sd_location) == 1 && isletter(sd_location)) || ...
                       (length(sd_location) == 2 && sd_location(2) == ':')));
    
    %% Normalize location to sd_root path
    if is_drive_letter
        if ~is_windows
            % Non-Windows platform but given a drive letter - error
            mapping.error = 'Drive letters (e.g., ''E:'') are only valid on Windows. On Mac/Linux, provide full path (e.g., ''/Volumes/SD_CARD'')';
            return;
        end
        
        % Windows drive letter - normalize
        sd_drive = upper(strrep(sd_location, ':', ''));
        if length(sd_drive) ~= 1 || ~isletter(sd_drive)
            mapping.error = 'sd_location must be a single letter (e.g., ''E'') or full path';
            return;
        end
        mapping.sd_drive = sd_drive;
        sd_root = [sd_drive, ':'];
    else
        % Absolute path (Mac/Linux or Windows path)
        sd_root = sd_location;
        mapping.sd_drive = sd_location;  % Store full path for non-Windows
    end
    
    %% Check location exists
    if ~isfolder(sd_root)
        mapping.error = sprintf('SD card location not found: %s', sd_root);
        return;
    end
    
    %% Validate SD card name
    if is_windows && is_drive_letter && options.ValidateDriveName
        try
            [~, vol_name] = system(['vol ' sd_drive ':']);
            if ~contains(vol_name, 'PATSD')
                mapping.error = sprintf('SD card is not named PATSD. Found: %s\nUse ''ValidateDriveName'', false to skip this check.', strtrim(vol_name));
                return;
            end
            fprintf('✓ SD card validated: PATSD\n');
        catch ME
            mapping.error = sprintf('Could not validate SD card name: %s', ME.message);
            return;
        end
    elseif ismac && ~is_drive_letter && options.ValidateDriveName
        % Mac: volume name is the last component of the mount path
        [~, vol_name] = fileparts(sd_root);  % /Volumes/PATSD → 'PATSD'
        if ~strcmpi(vol_name, 'PATSD')
            mapping.error = sprintf('SD card is not named PATSD (found: "%s" at %s).\nRename in Disk Utility, or use ''ValidateDriveName'', false to skip.', vol_name, sd_root);
            return;
        end
        fprintf('✓ SD card validated: PATSD\n');
    end
    
    %% Validate pattern count
    num_patterns = length(pattern_paths);
    if num_patterns == 0
        mapping.error = 'pattern_paths is empty';
        return;
    end
    if num_patterns > 9999
        mapping.error = sprintf('Maximum 9999 patterns supported (got %d)', num_patterns);
        return;
    end
    mapping.num_patterns = num_patterns;
    
    %% Validate all pattern files exist
    for i = 1:num_patterns
        if ~isfile(pattern_paths{i})
            mapping.error = sprintf('Pattern file not found: %s', pattern_paths{i});
            return;
        end
    end
    
    %% Generate timestamps
    now_dt = datetime('now');
    timestamp = uint32(floor(posixtime(now_dt)));
    timestamp_str = datestr(now_dt, 'yyyy-mm-ddTHH:MM:SS');
    timestamp_filename = datestr(now_dt, 'yyyymmdd_HHMMSS');
    
    mapping.timestamp = timestamp_str;
    mapping.timestamp_unix = timestamp;
    
    %% Create staging directory
    fprintf('Creating staging directory: %s\n', staging_dir);
    
    try
        if isfolder(staging_dir)
            rmdir(staging_dir, 's');
        end
        mkdir(staging_dir);
        mkdir(fullfile(staging_dir, 'patterns'));
    catch ME
        mapping.error = sprintf('Failed to create staging directory: %s', ME.message);
        return;
    end
    
    %% Copy and rename patterns to staging
    fprintf('Staging %d patterns...\n', num_patterns);
    
    mapping.patterns = cell(num_patterns, 1);
    
    for i = 1:num_patterns
        old_path = pattern_paths{i};
        new_name = sprintf('pat%04d.pat', i);  % Lowercase to match boss's version
        new_path = fullfile(staging_dir, 'patterns', new_name);
        
        try
            copyfile(old_path, new_path);
        catch ME
            mapping.error = sprintf('Failed to copy pattern %s: %s', old_path, ME.message);
            return;
        end
        
        mapping.patterns{i} = struct('new_name', new_name, 'original_path', old_path);
        fprintf('  %s <- %s\n', new_name, old_path);
    end
    
    %% Create MANIFEST.bin (binary) in staging
    bin_path = fullfile(staging_dir, 'MANIFEST.bin');
    try
        fid = fopen(bin_path, 'wb');
        if fid == -1
            error('Could not open file');
        end
        fwrite(fid, uint16(num_patterns), 'uint16');  % 2 bytes: pattern count
        fwrite(fid, timestamp, 'uint32');              % 4 bytes: unix timestamp
        fclose(fid);
    catch ME
        mapping.error = sprintf('Failed to create MANIFEST.bin: %s', ME.message);
        return;
    end
    fprintf('Created MANIFEST.bin (count=%d, timestamp=%d)\n', num_patterns, timestamp);
    
    %% Create MANIFEST.txt (human-readable) in staging
    txt_path = fullfile(staging_dir, 'MANIFEST.txt');
    try
        fid = fopen(txt_path, 'w');
        if fid == -1
            error('Could not open file');
        end
        
        fprintf(fid, 'Timestamp: %s\r\n', timestamp_str);
        fprintf(fid, 'SD Location: %s\r\n', sd_root);
        fprintf(fid, 'Pattern Count: %d\r\n', num_patterns);
        fprintf(fid, '\r\n');
        fprintf(fid, 'Mapping:\r\n');
        
        for i = 1:num_patterns
            fprintf(fid, '%s <- %s\r\n', mapping.patterns{i}.new_name, mapping.patterns{i}.original_path);
        end
        
        fclose(fid);
    catch ME
        mapping.error = sprintf('Failed to create MANIFEST.txt: %s', ME.message);
        return;
    end
    fprintf('Created MANIFEST.txt\n');
    
    %% Save local log copy
    try
        this_file = mfilename('fullpath');
        [this_dir, ~, ~] = fileparts(this_file);
        repo_root = fileparts(this_dir);  % Go up one level
        logs_dir = fullfile(repo_root, 'logs');
        
        if ~isfolder(logs_dir)
            mkdir(logs_dir);
        end
        
        log_filename = sprintf('MANIFEST_%s.txt', timestamp_filename);
        log_path = fullfile(logs_dir, log_filename);
        copyfile(txt_path, log_path);
        mapping.log_file = log_path;
        fprintf('Saved local log: %s\n', log_path);
    catch ME
        warning('Failed to save local log: %s', ME.message);
    end
    
    %% Determine target directory on SD card
    if options.UsePatternFolder
        target_dir = fullfile(sd_root, 'patterns');
    else
        target_dir = sd_root;
    end
    mapping.target_dir = target_dir;
    
    %% Format or clear SD card
    fprintf('\nPreparing SD card (%s)...\n', sd_root);

    did_format = false;

    if options.Format
        if is_windows && is_drive_letter
            % Windows: format with built-in format command
            fprintf('  Formatting as FAT32 (PATSD)...\n');
            [status, fmt_result] = system(sprintf('format %s: /FS:FAT32 /V:PATSD /Q /Y', sd_drive));
            if status ~= 0
                mapping.error = sprintf('Format failed: %s', fmt_result);
                return;
            end
            fprintf('  ✓ SD card formatted\n');
            did_format = true;

            % Create patterns folder if needed
            if options.UsePatternFolder
                mkdir(target_dir);
                fprintf('  ✓ Created patterns folder\n');
            end

        elseif ismac && ~is_drive_letter
            % Mac: format with diskutil eraseDisk
            % Detect device identifier
            [~, info] = system(sprintf('diskutil info "%s" 2>/dev/null', sd_root));
            dev_match = regexp(info, 'Device Identifier:\s+(disk\d+)', 'tokens');

            if ~isempty(dev_match)
                device = dev_match{1}{1};
                fprintf('  Will format %s (%s) as FAT32 with label PATSD.\n', sd_root, device);
                fprintf('  WARNING: ALL DATA ON %s WILL BE ERASED.\n', sd_root);
                reply = input('  Continue? (y/n): ', 's');

                if strcmpi(strtrim(reply), 'y')
                    fprintf('  Formatting...\n');
                    [status, fmt_result] = system(sprintf('diskutil eraseDisk FAT32 PATSD MBRFormat %s', device));
                    if status ~= 0
                        mapping.error = sprintf('diskutil format failed: %s', fmt_result);
                        return;
                    end
                    % Wait for volume to remount
                    fprintf('  Waiting for volume to remount...\n');
                    pause(3);

                    % Update sd_root to new mount point
                    sd_root = '/Volumes/PATSD';
                    if ~isfolder(sd_root)
                        % Try waiting a bit longer
                        pause(3);
                        if ~isfolder(sd_root)
                            mapping.error = 'Volume did not remount after format. Check /Volumes/ manually.';
                            return;
                        end
                    end

                    mapping.sd_drive = sd_root;
                    fprintf('  ✓ SD card formatted (now at %s)\n', sd_root);
                    did_format = true;

                    % Update target dir since sd_root changed
                    if options.UsePatternFolder
                        target_dir = fullfile(sd_root, 'patterns');
                        mapping.target_dir = target_dir;
                        mkdir(target_dir);
                        fprintf('  ✓ Created patterns folder\n');
                    end
                else
                    fprintf('\n  Format declined. To format manually, run in Terminal:\n');
                    fprintf('    diskutil eraseDisk FAT32 PATSD MBRFormat %s\n', device);
                    fprintf('  Then re-run this script.\n');
                    mapping.error = 'Format declined by user';
                    return;
                end
            else
                fprintf('  Warning: Could not determine device for %s. Skipping format.\n', sd_root);
                fprintf('  To format manually:\n');
                fprintf('    1. Run: diskutil list external\n');
                fprintf('    2. Find your SD card device (e.g., disk4)\n');
                fprintf('    3. Run: diskutil eraseDisk FAT32 PATSD MBRFormat diskN\n');
            end
        else
            fprintf('  Warning: Format not supported on this platform/configuration. Skipping.\n');
        end
    end

    if ~did_format
        % Manual cleanup (works on all platforms)
        if options.UsePatternFolder
            % Remove and recreate patterns folder
            if isfolder(target_dir)
                fprintf('  Removing old patterns folder...\n');
                rmdir(target_dir, 's');
            end
            mkdir(target_dir);
        else
            % Delete all files in root (but not directories)
            old_files = dir(fullfile(sd_root, '*.*'));
            for i = 1:length(old_files)
                if ~old_files(i).isdir
                    delete(fullfile(sd_root, old_files(i).name));
                end
            end
            fprintf('  ✓ Cleared existing files\n');
        end
        
        % Delete old manifest files from root (in case switching modes)
        old_manifest_bin = fullfile(sd_root, 'MANIFEST.bin');
        old_manifest_txt = fullfile(sd_root, 'MANIFEST.txt');
        if isfile(old_manifest_bin)
            delete(old_manifest_bin);
        end
        if isfile(old_manifest_txt)
            delete(old_manifest_txt);
        end
    end
    
    %% Copy patterns to SD card (FIRST - for correct dirIndex order)
    fprintf('  Copying %d patterns...\n', num_patterns);
    try
        for i = 1:num_patterns
            src = fullfile(staging_dir, 'patterns', sprintf('pat%04d.pat', i));
            dst = fullfile(target_dir, sprintf('pat%04d.pat', i));
            copyfile(src, dst);
        end
    catch ME
        mapping.error = sprintf('Failed to copy patterns to SD card: %s', ME.message);
        return;
    end
    fprintf('  ✓ Copied %d patterns\n', num_patterns);

    %% Clean up macOS resource fork files (._* files)
    %  macOS creates AppleDouble "._" files when copying to FAT32 volumes.
    %  These are invisible in Finder but occupy FAT32 directory entries,
    %  which shifts dirIndex ordering and causes the G4.1 controller to
    %  load wrong patterns. We must remove them before writing manifests.
    if ismac
        dot_files = dir(fullfile(target_dir, '._*'));
        if ~isempty(dot_files)
            fprintf('  Cleaning %d macOS resource fork files (._*)...\n', length(dot_files));
            for i = 1:length(dot_files)
                delete(fullfile(target_dir, dot_files(i).name));
            end
            fprintf('  ✓ Removed %d dot-files (prevents dirIndex corruption)\n', length(dot_files));
        end

        % Also clean root-level dot-files (in case manifests create them)
        dot_files_root = dir(fullfile(sd_root, '._*'));
        if ~isempty(dot_files_root)
            for i = 1:length(dot_files_root)
                delete(fullfile(sd_root, dot_files_root(i).name));
            end
        end
    end

    %% Copy manifest files to SD card (AFTER patterns for correct dirIndex)
    try
        copyfile(bin_path, fullfile(sd_root, 'MANIFEST.bin'));
        copyfile(txt_path, fullfile(sd_root, 'MANIFEST.txt'));
    catch ME
        mapping.error = sprintf('Failed to copy manifest files: %s', ME.message);
        return;
    end
    fprintf('  ✓ Copied manifest files\n');
    
    %% Final macOS dot-file cleanup (manifests may have created new ones)
    if ismac
        % Clean patterns dir
        dot_final = dir(fullfile(target_dir, '._*'));
        for i = 1:length(dot_final)
            delete(fullfile(target_dir, dot_final(i).name));
        end
        % Clean root dir
        dot_final_root = dir(fullfile(sd_root, '._*'));
        for i = 1:length(dot_final_root)
            delete(fullfile(sd_root, dot_final_root(i).name));
        end
        if ~isempty(dot_final) || ~isempty(dot_final_root)
            fprintf('  ✓ Final dot-file cleanup: removed %d files\n', ...
                length(dot_final) + length(dot_final_root));
        end
    end

    %% Clean macOS system directories from FAT32 root
    %  macOS creates .Spotlight-V100 and .fseventsd in the root of any
    %  mounted FAT32 volume. These occupy root directory entries that
    %  confuse the G4.1 controller firmware. We can delete .fseventsd
    %  after disabling Spotlight indexing; .Spotlight-V100 is locked by
    %  macOS and cannot be removed while mounted (see sd_card_deployment_notes.md).
    if ismac
        % Disable Spotlight indexing on this volume (prevents .fseventsd regrowth)
        [~, ~] = system(sprintf('mdutil -d "%s" 2>/dev/null', sd_root));
        [~, ~] = system(sprintf('mdutil -i off "%s" 2>/dev/null', sd_root));

        % Remove .fseventsd (deletable after Spotlight is disabled)
        fseventsd_path = fullfile(sd_root, '.fseventsd');
        if isfolder(fseventsd_path)
            [status, ~] = system(sprintf('rm -rf "%s" 2>/dev/null', fseventsd_path));
            if status == 0
                fprintf('  ✓ Removed .fseventsd (macOS filesystem events directory)\n');
            else
                warning('Could not remove .fseventsd — controller may not read this card.');
            end
        end

        % Report .Spotlight-V100 status (cannot delete, but inform user)
        spotlight_path = fullfile(sd_root, '.Spotlight-V100');
        if isfolder(spotlight_path)
            fprintf('  ⚠ .Spotlight-V100 present (macOS locks this — cannot delete while mounted)\n');
            fprintf('    The G4.1 controller may not read Mac-formatted cards.\n');
            fprintf('    Workaround: format SD card on Windows, then deploy patterns from any OS.\n');
        end
    end

    %% Verify (exclude macOS ._* resource fork files from count)
    all_pat = dir(fullfile(target_dir, '*.pat'));
    real_pat = all_pat(~startsWith({all_pat.name}, '._'));
    verify_count = length(real_pat);
    if verify_count ~= num_patterns
        mapping.error = sprintf('Verification failed: expected %d patterns, found %d on SD card', ...
            num_patterns, verify_count);
        return;
    end

    %% Summary
    fprintf('\n=== SD Card Ready ===\n');
    fprintf('Location: %s\n', sd_root);
    fprintf('Target: %s\n', target_dir);
    fprintf('Patterns: %d (dirIndex 0-%d)\n', num_patterns, num_patterns-1);
    fprintf('Manifests: dirIndex %d-%d\n', num_patterns, num_patterns+1);
    fprintf('Verification: PASSED\n');
    
    %% Success
    mapping.success = true;
end
