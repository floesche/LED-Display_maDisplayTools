function results = simple_comparison(ip)
%SIMPLE_COMPARISON Simple comparison between pnet and tcpclient backends
%
%   results = simple_comparison()
%   results = simple_comparison('192.168.10.62')
%
%   A minimal test script comparing PanelsController (pnet) and
%   PanelsControllerNative (tcpclient) implementations on G4.1/Teensy.
%
%   Tests only core commands:
%   - allOn/allOff (small commands, basic connectivity)
%   - stopDisplay (basic command with response)
%   - streamFrame (large packet test, ~3176 bytes)
%
%   Inputs:
%       ip - Host IP address (default: '192.168.10.62')
%
%   Output:
%       results - Struct with comparison results

    arguments
        ip (1,:) char = '192.168.10.62'
    end

    fprintf('\n');
    fprintf('========================================\n');
    fprintf('   Simple TCP Backend Comparison\n');
    fprintf('========================================\n');
    fprintf('Host: %s\n', ip);
    fprintf('========================================\n');

    results = struct();
    results.ip = ip;
    results.timestamp = datetime('now');

    %% Test pnet version
    fprintf('\n--- PanelsController (pnet) ---\n');
    try
        pc = PanelsController(ip);
        pc.open(false);
        results.pnet = run_simple_tests(pc, 'pnet');
        pc.close(true);
        results.pnet.error = [];
    catch ME
        fprintf('ERROR: %s\n', ME.message);
        results.pnet.error = ME.message;
    end

    pause(2);  % Recovery between backends

    %% Test native version
    fprintf('\n--- PanelsControllerNative (tcpclient) ---\n');
    try
        pcn = PanelsControllerNative(ip);
        pcn.open(false);
        results.native = run_simple_tests(pcn, 'native');
        pcn.close(true);
        results.native.error = [];
    catch ME
        fprintf('ERROR: %s\n', ME.message);
        results.native.error = ME.message;
    end

    %% Print comparison summary
    print_summary(results);

    %% Save results
    filename = sprintf('simple_comparison_%s.mat', datestr(now, 'yyyy-mm-dd_HHMMSS'));
    save(filename, 'results');
    fprintf('\nResults saved to: %s\n', filename);
end


function r = run_simple_tests(pc, name)
%RUN_SIMPLE_TESTS Run core command tests
    r = struct();
    r.backend = name;

    N = 50;  % iterations per command

    % Test 1: allOn
    fprintf('  allOn:       ');
    r.allOn = test_command(@() pc.allOn(), N);
    fprintf('%d/%d, %.1f +/- %.1f ms (med %.1f)\n', r.allOn.passed, N, r.allOn.mean_ms, r.allOn.std_ms, r.allOn.median_ms);

    pause(0.2);

    % Test 2: allOff
    fprintf('  allOff:      ');
    r.allOff = test_command(@() pc.allOff(), N);
    fprintf('%d/%d, %.1f +/- %.1f ms (med %.1f)\n', r.allOff.passed, N, r.allOff.mean_ms, r.allOff.std_ms, r.allOff.median_ms);

    pause(0.2);

    % Test 3: stopDisplay
    fprintf('  stopDisplay: ');
    r.stop = test_command(@() pc.stopDisplay(), N);
    fprintf('%d/%d, %.1f +/- %.1f ms (med %.1f)\n', r.stop.passed, N, r.stop.mean_ms, r.stop.std_ms, r.stop.median_ms);

    pause(0.2);

    % Test 4: streamFrame (large packet test)
    fprintf('  streamFrame: ');
    try
        frame = maDisplayTools.make_framevector_gs16(zeros(32, 192), 0);
        r.stream = test_command(@() pc.streamFrame(0, 0, frame), N);
        fprintf('%d/%d, %.1f +/- %.1f ms (med %.1f) [%d bytes]\n', r.stream.passed, N, r.stream.mean_ms, r.stream.std_ms, r.stream.median_ms, length(frame));
    catch ME
        fprintf('SKIPPED - %s\n', ME.message);
        r.stream = struct('passed', 0, 'failed', N, 'mean_ms', 0, 'median_ms', 0, 'std_ms', 0, 'error', ME.message);
    end
end


function r = test_command(fn, n, delay)
%TEST_COMMAND Test a command n times and return stats
%   delay - optional pause between commands (default: 0.15s for WiFi reliability)
    if nargin < 3
        delay = 0.15;
    end

    passed = 0;
    failed = 0;
    times = zeros(1, n);

    for i = 1:n
        try
            tic;
            result = fn();
            times(i) = toc * 1000;

            if result
                passed = passed + 1;
            else
                failed = failed + 1;
            end
        catch
            times(i) = toc * 1000;
            failed = failed + 1;
        end

        if i < n && delay > 0
            pause(delay);
        end
    end

    r = struct();
    r.passed = passed;
    r.failed = failed;
    r.mean_ms = mean(times);
    r.median_ms = median(times);
    r.std_ms = std(times);
    r.times = times;
end


function print_summary(results)
%PRINT_SUMMARY Print comparison summary

    fprintf('\n');
    fprintf('========================================\n');
    fprintf('           Comparison Summary\n');
    fprintf('========================================\n\n');

    % Check for errors
    pnet_ok = isfield(results, 'pnet') && isempty(results.pnet.error);
    native_ok = isfield(results, 'native') && isempty(results.native.error);

    if ~pnet_ok && isfield(results.pnet, 'error')
        fprintf('pnet: FAILED - %s\n', results.pnet.error);
    end
    if ~native_ok && isfield(results.native, 'error')
        fprintf('native: FAILED - %s\n', results.native.error);
    end

    if ~pnet_ok || ~native_ok
        fprintf('\nOne or both backends failed to connect.\n');
        return;
    end

    N = results.pnet.allOn.passed + results.pnet.allOn.failed;

    % Reliability table
    fprintf('%-15s %10s %10s\n', 'Passed', 'pnet', 'native');
    fprintf('%-15s %10s %10s\n', '-------', '----', '------');
    fprintf('%-15s %7d/%d %7d/%d\n', 'allOn', ...
        results.pnet.allOn.passed, N, results.native.allOn.passed, N);
    fprintf('%-15s %7d/%d %7d/%d\n', 'allOff', ...
        results.pnet.allOff.passed, N, results.native.allOff.passed, N);
    fprintf('%-15s %7d/%d %7d/%d\n', 'stopDisplay', ...
        results.pnet.stop.passed, N, results.native.stop.passed, N);
    fprintf('%-15s %7d/%d %7d/%d\n', 'streamFrame', ...
        results.pnet.stream.passed, N, results.native.stream.passed, N);

    % Timing comparison (median +/- std)
    fprintf('\n%-15s %16s %16s\n', 'Timing (ms)', 'pnet', 'native');
    fprintf('%-15s %16s %16s\n', '-----------', '----', '------');
    cmds = {'allOn', 'allOff', 'stopDisplay', 'streamFrame'};
    fields = {'allOn', 'allOff', 'stop', 'stream'};
    for i = 1:length(cmds)
        p = results.pnet.(fields{i});
        n = results.native.(fields{i});
        fprintf('%-15s %8.1f +/- %3.1f %8.1f +/- %3.1f\n', cmds{i}, ...
            p.median_ms, p.std_ms, n.median_ms, n.std_ms);
    end

    % Overall assessment
    fprintf('\n----------------------------------------\n');

    pnet_total = results.pnet.allOn.passed + results.pnet.allOff.passed + ...
                 results.pnet.stop.passed + results.pnet.stream.passed;
    native_total = results.native.allOn.passed + results.native.allOff.passed + ...
                   results.native.stop.passed + results.native.stream.passed;
    total = N * 4;

    fprintf('Total passed:   pnet=%d/%d  native=%d/%d\n', pnet_total, total, native_total, total);

    if native_total >= pnet_total
        fprintf('Status: Native backend matches or exceeds pnet\n');
    else
        fprintf('Status: Native backend needs investigation\n');
    end

    fprintf('========================================\n\n');
end
