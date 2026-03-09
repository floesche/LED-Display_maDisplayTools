function results = benchmark_streaming(pc, backend_name)
%BENCHMARK_STREAMING Test G4.1 frame streaming performance
%
%   results = benchmark_streaming(pc, backend_name)
%
%   Tests streamFrame at increasing frame rates for G4.1 (2x12 panel config).
%   Stops when errors occur or jitter becomes too high.
%
%   Inputs:
%       pc           - PanelsController or PanelsControllerNative instance
%       backend_name - String identifier for reporting
%
%   Output:
%       results - Struct with streaming benchmark results

    arguments
        pc
        backend_name (1,:) char = 'unknown'
    end

    fprintf('\n=== Streaming Benchmark (G4.1): %s ===\n\n', backend_name);

    results = struct();
    results.backend = backend_name;

    % Ensure connection
    if ~pc.isOpen
        try
            pc.open(false);
        catch ME
            fprintf('ERROR: Could not connect: %s\n', ME.message);
            results.error = ME.message;
            return;
        end
    end

    % G4.1 frame streaming using streamFrame
    fprintf('--- Frame Streaming (streamFrame) ---\n');
    fprintf('  Panel config: 2x12 (32 rows x 192 cols)\n');
    fprintf('  Frame size: ~3176 bytes\n\n');

    % FPS list: 1-10
    results.streaming = benchmark_streamframe(pc, [1, 2, 5, 10]);

    % Summary table
    fprintf('\n--- Summary: %s ---\n', backend_name);
    fprintf('%-6s | %6s | %8s | %8s | %8s | %8s | %8s | %s\n', ...
        'FPS', 'Frames', 'Mean ms', 'P50 ms', 'P95 ms', 'P99 ms', 'SendAvg', 'Errors');
    fprintf('%s\n', repmat('-', 1, 78));

    r = results.streaming;
    for i = 1:length(r.fps_tested)
        s = r.stats{i};
        fprintf('%4d   | %6d | %8.1f | %8.1f | %8.1f | %8.1f | %8.1f | %d/%d\n', ...
            s.fps, s.total, s.mean_interval_ms, s.p50_ms, s.p95_ms, s.p99_ms, ...
            s.mean_send_ms, s.errors, s.total);
    end

    if isfield(r, 'max_fps') && r.max_fps > 0
        fprintf('\nMax reliable FPS: %d (jitter: %.1f%%)\n', ...
            r.max_fps, r.jitter_at_max);
    end

    % Save results
    filename = sprintf('benchmark_%s_%s.mat', backend_name, datestr(now, 'yyyy-mm-dd_HHMMSS'));
    save(filename, 'results');
    fprintf('Results saved to: %s\n\n', filename);
end


function result = benchmark_streamframe(pc, fps_list)
%BENCHMARK_STREAMFRAME Test streamFrame at various FPS for G4.1
    result = struct();
    result.fps_tested = [];
    result.stats = {};
    result.max_fps = 0;
    result.jitter_at_max = 0;

    % Pre-generate animated frames for G4.1 (2x12 panels = 32 rows x 192 cols)
    % Scrolling bright stripe across full screen
    num_anim_frames = 48;  % Cycle length (stripe moves 4 cols per frame)
    stripe_width = 24;     % Width of bright stripe in columns
    try
        frames = cell(1, num_anim_frames);
        for f = 1:num_anim_frames
            pattern = zeros(32, 192);
            % Full-height stripe that scrolls left to right
            col_start = mod((f-1) * 4, 192) + 1;
            for c = 0:(stripe_width - 1)
                col = mod(col_start - 1 + c, 192) + 1;
                pattern(:, col) = 15;  % Full brightness, all rows
            end
            frames{f} = maDisplayTools.make_framevector_gs16(pattern, 0);
        end
        fprintf('  %d animated frames generated: %d bytes each\n\n', ...
            num_anim_frames, length(frames{1}));
    catch ME
        fprintf('  Failed to generate frames: %s\n', ME.message);
        result.error = ME.message;
        return;
    end

    for fps = fps_list
        % Check connection before each test
        if ~pc.isOpen
            fprintf('  %3d FPS: STOPPED (disconnected)\n', fps);
            result.stopped_at = fps;
            result.reason = 'disconnected';
            break;
        end

        duration_sec = 10;  % 10 seconds per FPS level
        num_frames = fps * duration_sec;
        fprintf('  %3d FPS: sending %d frames over %ds...', fps, num_frames, duration_sec);

        try
            [success, stats] = test_streamframe_fps(pc, fps, duration_sec, frames);

            result.fps_tested(end+1) = fps;
            result.stats{end+1} = stats;

            if success
                result.max_fps = fps;
                result.jitter_at_max = stats.jitter_pct;
            end

            status = 'OK';
            if stats.jitter_pct > 10, status = 'HIGH JITTER'; end
            if ~success, status = 'FAILED'; end

            fprintf(' jitter %.1f%% (p50=%.1f p95=%.1f p99=%.1f ms), errors %d/%d, mean=%.1f ms (%s)\n', ...
                stats.jitter_pct, stats.p50_ms, stats.p95_ms, stats.p99_ms, ...
                stats.errors, stats.total, stats.mean_interval_ms, status);

            % Stop if error rate too high
            if ~success
                result.stopped_at = fps;
                result.reason = 'high_error_rate';
                break;
            end

            % Stop if jitter too high
            if stats.jitter_pct > 20
                fprintf('  STOPPED: jitter exceeded 20%%\n');
                result.stopped_at = fps;
                result.reason = 'high_jitter';
                break;
            end

        catch ME
            fprintf(' ERROR - %s\n', ME.message);
            result.stopped_at = fps;
            result.reason = ME.message;

            try
                pc.stopDisplay();
                pause(0.5);
            catch
            end
            break;
        end

        pause(1);  % Recovery between frame rates
    end

    try
        pc.stopDisplay();
    catch
        % Connection may already be broken
    end
end


function [success, stats] = test_streamframe_fps(pc, fps, duration_sec, frames)
%TEST_STREAMFRAME_FPS Test streamFrame at a specific FPS with rich stats
    interval = 1 / fps;
    num_frames = fps * duration_sec;
    num_anim = length(frames);
    times = zeros(1, num_frames);
    send_times = zeros(1, num_frames);
    errors = 0;

    start = tic;
    for i = 1:num_frames
        % Wait for next frame time
        target_time = (i-1) * interval;
        while toc(start) < target_time
            % Busy wait (more accurate than pause for timing)
        end

        times(i) = toc(start);

        % Cycle through animated frames
        frame = frames{mod(i-1, num_anim) + 1};

        % Send frame and measure send duration
        send_start = tic;
        try
            if ~pc.streamFrame(0, 0, frame)
                errors = errors + 1;
            end
        catch
            errors = errors + 1;
        end
        send_times(i) = toc(send_start) * 1000;  % ms
    end

    % Interval stats
    actual_intervals = diff(times) * 1000;  % ms
    ideal_interval_ms = interval * 1000;

    stats = struct();
    stats.fps = fps;
    stats.total = num_frames;
    stats.errors = errors;
    stats.error_rate = errors / num_frames;
    stats.duration_sec = times(end) - times(1);

    % Interval percentiles
    stats.mean_interval_ms = mean(actual_intervals);
    stats.std_interval_ms = std(actual_intervals);
    stats.p50_ms = median(actual_intervals);
    stats.p95_ms = prctile(actual_intervals, 95);
    stats.p99_ms = prctile(actual_intervals, 99);
    stats.min_interval_ms = min(actual_intervals);
    stats.max_interval_ms = max(actual_intervals);

    % Jitter as percentage of ideal interval
    stats.jitter_pct = stats.std_interval_ms / ideal_interval_ms * 100;

    % Send time stats
    stats.mean_send_ms = mean(send_times);
    stats.p95_send_ms = prctile(send_times, 95);
    stats.max_send_ms = max(send_times);

    success = (stats.error_rate < 0.1);  % <10% error rate
end
