function result = detect_sd_card(options)
%DETECT_SD_CARD Cross-platform SD card auto-detection
%
%   result = detect_sd_card()
%   result = detect_sd_card('Label', 'PATSD')
%   result = detect_sd_card('Verbose', true)
%
%   Scans for removable/external volumes that match the expected label.
%   Works on Windows (D:-Z: drive scan) and Mac (/Volumes scan).
%
%   INPUTS (name-value pairs):
%       'Label'   ('PATSD')  - Expected volume label to match
%       'Verbose' (true)     - Print detection progress
%
%   OUTPUTS:
%       result - Struct with fields:
%           found    (logical) - Whether a matching SD card was found
%           path     (char)    - Mount path (e.g., '/Volumes/PATSD' or 'E:')
%           device   (char)    - Device identifier (Mac: 'disk4', Windows: 'E')
%           label    (char)    - Volume label found
%           platform (char)    - 'windows', 'mac', or 'linux'
%           candidates (cell)  - Other non-system volumes found
%           error    (char)    - Error message if detection failed
%
%   EXAMPLES:
%       % Auto-detect
%       sd = detect_sd_card();
%       if sd.found
%           fprintf('SD card at: %s\n', sd.path);
%       end
%
%       % Check for custom label
%       sd = detect_sd_card('Label', 'MYCARD');
%
%   See also: prepare_sd_card_crossplatform, prepare_sd_card

    arguments
        options.Label char = 'PATSD'
        options.Verbose (1,1) logical = true
    end

    result = struct();
    result.found = false;
    result.path = '';
    result.device = '';
    result.label = '';
    result.candidates = {};
    result.error = '';

    if ispc
        result.platform = 'windows';
        result = detect_windows(result, options);
    elseif ismac
        result.platform = 'mac';
        result = detect_mac(result, options);
    else
        result.platform = 'linux';
        result = detect_linux(result, options);
    end
end

function result = detect_windows(result, options)
    % Scan drives D: through Z: looking for volume named PATSD
    if options.Verbose
        fprintf('Scanning Windows drives D:-Z: for volume "%s"...\n', options.Label);
    end

    for letter = 'D':'Z'
        candidate = [letter, ':'];
        if ~isfolder(candidate)
            continue;
        end

        [~, vol_out] = system(['vol ' letter ':']);
        if contains(vol_out, options.Label)
            result.found = true;
            result.path = candidate;
            result.device = letter;
            result.label = options.Label;
            if options.Verbose
                fprintf('  Found: %s: (label: %s)\n', letter, options.Label);
            end
            return;
        else
            % Extract volume name for candidates list
            vol_match = regexp(vol_out, 'Volume in drive . is (.+)', 'tokens');
            if ~isempty(vol_match)
                vol_name = strtrim(vol_match{1}{1});
                result.candidates{end+1} = struct('path', candidate, ...
                    'label', vol_name, 'device', letter);
                if options.Verbose
                    fprintf('  %s: — label: %s (not %s)\n', letter, vol_name, options.Label);
                end
            end
        end
    end

    if ~result.found && options.Verbose
        fprintf('  No drive with label "%s" found.\n', options.Label);
    end
end

function result = detect_mac(result, options)
    % Scan /Volumes for matching label, filter system volumes
    if options.Verbose
        fprintf('Scanning /Volumes for volume "%s"...\n', options.Label);
    end

    % System volumes to skip
    system_vols = {'Macintosh HD', 'Macintosh HD - Data', 'Recovery', 'Preboot', 'VM', 'Update'};

    % First check the exact expected path
    exact_path = fullfile('/Volumes', options.Label);
    if isfolder(exact_path)
        result.found = true;
        result.path = exact_path;
        result.label = options.Label;

        % Get device identifier via diskutil
        result.device = get_mac_device(exact_path, options.Verbose);

        if options.Verbose
            fprintf('  Found: %s (device: %s)\n', exact_path, result.device);
        end
        return;
    end

    % Scan all volumes
    vols = dir('/Volumes');
    for v = 1:length(vols)
        vname = vols(v).name;
        if startsWith(vname, '.'), continue; end
        if ismember(vname, system_vols), continue; end

        vol_path = fullfile('/Volumes', vname);

        % Check if this is the target label (case-insensitive)
        if strcmpi(vname, options.Label)
            result.found = true;
            result.path = vol_path;
            result.label = vname;
            result.device = get_mac_device(vol_path, options.Verbose);
            if options.Verbose
                fprintf('  Found: %s (device: %s)\n', vol_path, result.device);
            end
            return;
        end

        % Add as candidate
        device_id = get_mac_device(vol_path, false);
        result.candidates{end+1} = struct('path', vol_path, ...
            'label', vname, 'device', device_id);
        if options.Verbose
            fprintf('  %s — label: %s (not %s)\n', vol_path, vname, options.Label);
        end
    end

    if ~result.found && options.Verbose
        fprintf('  No volume with label "%s" found.\n', options.Label);
        if ~isempty(result.candidates)
            fprintf('  Other non-system volumes:\n');
            for c = 1:length(result.candidates)
                cand = result.candidates{c};
                fprintf('    %s (label: %s, device: %s)\n', cand.path, cand.label, cand.device);
            end
        end
    end
end

function result = detect_linux(result, options)
    % Check common mount points on Linux
    if options.Verbose
        fprintf('Scanning Linux mount points for volume "%s"...\n', options.Label);
    end

    % Common Linux mount locations
    mount_dirs = {'/media', '/mnt', '/run/media'};

    for d = 1:length(mount_dirs)
        base = mount_dirs{d};
        if ~isfolder(base), continue; end

        % For /media and /run/media, check subdirectories (user mounts)
        subdirs = dir(base);
        for s = 1:length(subdirs)
            if startsWith(subdirs(s).name, '.'), continue; end
            if ~subdirs(s).isdir, continue; end

            check_path = fullfile(base, subdirs(s).name);

            % Direct match
            if strcmpi(subdirs(s).name, options.Label) && isfolder(check_path)
                result.found = true;
                result.path = check_path;
                result.label = subdirs(s).name;
                result.device = '';
                return;
            end

            % Check one level deeper (e.g., /media/username/PATSD)
            inner = dir(check_path);
            for i = 1:length(inner)
                if startsWith(inner(i).name, '.'), continue; end
                if ~inner(i).isdir, continue; end
                if strcmpi(inner(i).name, options.Label)
                    result.found = true;
                    result.path = fullfile(check_path, inner(i).name);
                    result.label = inner(i).name;
                    result.device = '';
                    return;
                end
            end
        end
    end

    if ~result.found && options.Verbose
        fprintf('  No volume with label "%s" found.\n', options.Label);
    end
end

function device = get_mac_device(vol_path, verbose)
    % Get device identifier (e.g., 'disk4') for a mounted volume
    device = '';
    try
        [status, info] = system(sprintf('diskutil info "%s" 2>/dev/null', vol_path));
        if status == 0
            dev_match = regexp(info, 'Device Identifier:\s+(disk\d+)', 'tokens');
            if ~isempty(dev_match)
                device = dev_match{1}{1};
            end
        end
    catch
        if verbose
            fprintf('  Warning: could not determine device for %s\n', vol_path);
        end
    end
end
