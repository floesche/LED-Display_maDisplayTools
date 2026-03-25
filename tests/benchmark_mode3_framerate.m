%% benchmark_mode3_framerate.m — Mode 3 frame rate characterization
%
% Measures MATLAB-side streaming performance for Mode 3 (stream pattern
% position) across a range of target frame rates. For each rate, records
% per-frame timestamps to compute actual achieved fps, inter-frame jitter,
% and command send latency.
%
% Also compares MATLAB pause()-based timing against the controller's own
% duration tracking (waitForEnd=true round-trip).
%
% NOTE: setPositionX() is fire-and-forget (no controller ack), so we are
% measuring MATLAB TCP send latency, not actual panel refresh timing.
% True panel timing would require external instrumentation (photodiode).
%
% Prerequisites:
%   - SD card with patterns from create_g41_experiment_patterns.m
%   - Arena powered, connected, Mode 2 verified
%
% Usage:
%   benchmark_mode3_framerate              % run all tests
%   benchmark_mode3_framerate('IP', '10.102.40.61')  % custom IP

%% Configuration
function benchmark_mode3_framerate(options)
    arguments
        options.IP char = '10.102.40.209'
        options.PatternID (1,1) double = 5      % sine grating 30deg GS16
        options.NumFrames (1,1) double = 16     % frames in the pattern
        options.Duration (1,1) double = 10      % seconds per rate test
        options.Rates (1,:) double = [10 15 20 25 30 40 50 60 70 80 90 100]
    end

    ip_addr = options.IP;
    patID = options.PatternID;
    num_frames = options.NumFrames;
    dur_sec = options.Duration;
    target_rates = options.Rates;

    fprintf('=== Mode 3 Frame Rate Benchmark ===\n');
    fprintf('Arena IP: %s\n', ip_addr);
    fprintf('Pattern ID: %d (%d frames)\n', patID, num_frames);
    fprintf('Duration per rate: %d sec\n', dur_sec);
    fprintf('Target rates: %s Hz\n\n', mat2str(target_rates));

    %% Connect
    pc = PanelsController(ip_addr);
    pc.open(false);
    pc.allOn(); pause(0.5);
    pc.allOff(); pause(0.5);
    fprintf('Connected.\n\n');

    cleanupObj = onCleanup(@() cleanup(pc));

    %% Part 1: Frame rate sweep
    fprintf('--- Part 1: Frame Rate Sweep ---\n\n');

    nRates = length(target_rates);
    results = struct('target_hz', num2cell(target_rates), ...
                     'actual_hz', 0, ...
                     'mean_interval_ms', 0, ...
                     'std_interval_ms', 0, ...
                     'max_interval_ms', 0, ...
                     'min_interval_ms', 0, ...
                     'total_updates', 0, ...
                     'intervals', []);

    for r = 1:nRates
        target_hz = target_rates(r);
        num_updates = target_hz * dur_sec;
        pause_sec = 1.0 / target_hz;

        fprintf('  %3d Hz: sending %d updates over %d sec... ', ...
            target_hz, num_updates, dur_sec);

        % Start mode 3 trial with extra 2 sec buffer
        controller_dur = (dur_sec + 3) * 10;
        pc.trialParams(3, patID, 0, 1, 0, controller_dur, false);
        pause(0.1);  % let controller settle

        % Pre-allocate timestamp array
        timestamps = zeros(1, num_updates + 1);
        timestamps(1) = toc(tic);  % prime the timer

        % Streaming loop — record wall-clock time of each send
        t_ref = tic;
        timestamps(1) = 0;
        for i = 1:num_updates
            frameIdx = mod(i - 1, num_frames) + 1;
            pc.setPositionX(frameIdx);
            timestamps(i + 1) = toc(t_ref);

            % Adaptive pause: account for time already spent
            expected_time = i * pause_sec;
            remaining = expected_time - timestamps(i + 1);
            if remaining > 0
                pause(remaining);
            end
        end
        elapsed = toc(t_ref);

        pc.stopDisplay();
        pause(0.3);

        % Compute intervals
        intervals_ms = diff(timestamps) * 1000;  % ms
        actual_hz = num_updates / elapsed;

        results(r).actual_hz = actual_hz;
        results(r).mean_interval_ms = mean(intervals_ms);
        results(r).std_interval_ms = std(intervals_ms);
        results(r).max_interval_ms = max(intervals_ms);
        results(r).min_interval_ms = min(intervals_ms);
        results(r).total_updates = num_updates;
        results(r).intervals = intervals_ms;

        pct = 100 * actual_hz / target_hz;
        fprintf('actual: %5.1f Hz (%4.0f%%)  jitter: %.1f +/- %.1f ms (max %.1f)\n', ...
            actual_hz, pct, results(r).mean_interval_ms, ...
            results(r).std_interval_ms, results(r).max_interval_ms);
    end

    %% Summary table
    fprintf('\n--- Summary ---\n');
    fprintf('%-10s %-10s %-8s %-12s %-10s %-10s\n', ...
        'Target Hz', 'Actual Hz', '% Hit', 'Mean ms', 'Std ms', 'Max ms');
    fprintf('%s\n', repmat('-', 1, 62));
    for r = 1:nRates
        pct = 100 * results(r).actual_hz / results(r).target_hz;
        fprintf('%-10d %-10.1f %-8.0f %-12.2f %-10.2f %-10.2f\n', ...
            results(r).target_hz, results(r).actual_hz, pct, ...
            results(r).mean_interval_ms, results(r).std_interval_ms, ...
            results(r).max_interval_ms);
    end

    %% Part 2: Controller round-trip — pause() vs waitForEnd
    fprintf('\n--- Part 2: Controller Round-Trip Timing ---\n');
    fprintf('  Comparing MATLAB pause() vs controller waitForEnd=true\n\n');

    test_dur = 5;  % 5 seconds

    % Test A: pause()-based (current approach)
    fprintf('  A) pause(%d) timing... ', test_dur);
    pc.trialParams(3, patID, 0, 1, 0, test_dur * 10, false);
    t_pause = tic;
    pause(test_dur);
    elapsed_pause = toc(t_pause);
    pc.stopDisplay();
    pause(0.3);
    fprintf('elapsed: %.3f sec (target: %d)\n', elapsed_pause, test_dur);

    % Test B: waitForEnd=true (controller reports completion)
    fprintf('  B) waitForEnd=true... ');
    t_wait = tic;
    rtn = pc.trialParams(3, patID, 0, 1, 0, test_dur * 10, true);
    elapsed_wait = toc(t_wait);
    fprintf('elapsed: %.3f sec (target: %d), controller returned: %s\n', ...
        elapsed_wait, test_dur, string(rtn));

    pause(0.3);

    % Test C: Measure setPositionX command latency in isolation
    fprintf('  C) setPositionX() command latency (1000 calls)... ');
    pc.trialParams(3, patID, 0, 1, 0, 100, false);  % 10 sec buffer
    pause(0.1);
    n_calls = 1000;
    latencies = zeros(1, n_calls);
    for i = 1:n_calls
        t_cmd = tic;
        pc.setPositionX(mod(i - 1, num_frames) + 1);
        latencies(i) = toc(t_cmd);
    end
    pc.stopDisplay();
    latencies_us = latencies * 1e6;
    fprintf('mean: %.0f us, std: %.0f us, max: %.0f us\n', ...
        mean(latencies_us), std(latencies_us), max(latencies_us));

    fprintf('\n  Theoretical max fps from command latency: %.0f Hz\n', ...
        1 / mean(latencies));

    %% Done
    fprintf('\n=== Benchmark Complete ===\n');
    fprintf('Results struct saved in workspace as ''results''.\n');
    assignin('base', 'mode3_results', results);
end

function cleanup(pc)
    try
        pc.allOff();
        pc.close();
        fprintf('Cleanup: arena off, connection closed.\n');
    catch
        % Ignore cleanup errors
    end
end
