function analyze_cooling(csvPath)
%ANALYZE_COOLING Plot and independently check Engine Cooling Controller output.
% Compatible with MATLAB R2024a; no optional toolboxes required.
% Run from the repository root:
%   addpath('matlab'); analyze_cooling

    root = fileparts(fileparts(mfilename('fullpath')));
    if nargin < 1
        csvPath = fullfile(root, 'results', 'cooling_trace.csv');
    end
    assert(isfile(csvPath), ...
        'CSV not found. In Git Bash, run: make trace');
    data = readtable(csvPath);

    required = {'step','heat_rate_c_per_step','plant_temp_c', ...
        'measured_temp_c','signal_valid','fan_state', ...
        'pwm_pct','sensor_fault','fault_led','valid_streak'};
    assert(all(ismember(required, data.Properties.VariableNames)), ...
        'CSV is missing one or more expected columns.');
    assert(height(data) == 20 && isequal(data.step, (1:20)'), ...
        'Expected 20 consecutive simulation steps.');

    % Build the expected result separately from the C implementation.
    [refState, refFault, refStreak] = reference_controller( ...
        data.measured_temp_c, data.signal_valid);
    assert(isequal(data.fan_state, refState), ...
        'C state sequence differs from the MATLAB reference model.');
    assert(isequal(data.sensor_fault, refFault), ...
        'C sensor fault flags differ from the MATLAB reference model.');
    assert(isequal(data.valid_streak, refStreak), ...
        'C recovery counters differ from the MATLAB reference model.');
    assert(all(data.pwm_pct == 50 .* data.fan_state), ...
        'PWM does not match OFF/LOW/HIGH mapping.');
    assert(isequal(data.fault_led, data.sensor_fault), ...
        'Fault LED must match sensor_fault.');
    assert(any(data.signal_valid == 0) && ...
           any(data.measured_temp_c < -40 | data.measured_temp_c > 150), ...
        'Both signal and range fault injections must be exercised.');
    assert(all(data.fan_state(data.sensor_fault == 1) == 2), ...
        'Sensor fault must command HIGH cooling.');

    fprintf('[PASS] 20 C states match independent MATLAB FSM\n');
    fprintf('[PASS] Sensor fault flags and three-sample recovery match\n');
    fprintf('[PASS] PWM stages and fault LED agree with controller outputs\n');
    fprintf('[PASS] Both fault injection scenarios are present\n');

    fig = figure('Name','Engine Cooling Controller Validation', ...
        'Color','w','Position',[100 80 1150 900]);
    layout = tiledlayout(fig,4,1,'TileSpacing','compact','Padding','compact');
    title(layout,'Engine Cooling Controller | C trace validated by MATLAB');

    nexttile;
    plot(data.step,data.plant_temp_c,'-o','LineWidth',1.5,'MarkerSize',4);
    hold on;
    yline(95,':','LOW OFF 95 C');
    yline(100,'--','LOW ON 100 C');
    yline(105,':','HIGH OFF 105 C');
    yline(110,'--','HIGH ON 110 C');
    ylabel('Plant temp (C)'); grid on;
    title('Actual simulated plant temperature (not the injected sensor reading)');

    nexttile;
    plot(data.step,data.measured_temp_c,'-o','LineWidth',1.4,'MarkerSize',4);
    hold on;
    bad = data.signal_valid == 0 | ...
          data.measured_temp_c < -40 | data.measured_temp_c > 150;
    scatter(data.step(bad),data.measured_temp_c(bad),70,'r','filled');
    ylabel('Sensor (C)'); grid on;
    title('Measurement, including injected faults at steps 12 and 13');

    nexttile;
    stairs(data.step,data.pwm_pct,'LineWidth',2);
    ylim([-10 110]); yticks([0 50 100]);
    ylabel('PWM (%)'); grid on;
    title('Simulated PWM command (0 / 50 / 100 percent)');

    nexttile;
    stairs(data.step,data.sensor_fault,'LineWidth',2);
    ylim([-0.15 1.15]); yticks([0 1]);
    ylabel('Fault'); xlabel('Simulation step'); grid on;
    title('Sensor fault flag and recovery');

    output = fullfile(root,'results','cooling_analysis.png');
    exportgraphics(layout, output, 'Resolution', 160);
    fprintf('[PASS] Plot saved: %s\n', output);
end

function [states, faults, streaks] = reference_controller(temps, signalValid)
% Independent reference behavior based on the documented requirements.
    n = numel(temps);
    states = zeros(n,1); faults = zeros(n,1); streaks = zeros(n,1);
    current = 0; fault = false; streak = 0;

    for k = 1:n
        temp = temps(k);
        good = signalValid(k) ~= 0 && temp >= -40 && temp <= 150;
        if ~good
            current = 2; fault = true; streak = 0;
        else
            if fault
                streak = streak + 1;
                if streak < 3
                    current = 2;
                    states(k) = current;
                    faults(k) = 1;
                    streaks(k) = streak;
                    continue;
                end
                fault = false;
                streak = 0;
            end
            switch current
                case 0 % OFF
                    if temp >= 110
                        current = 2;
                    elseif temp >= 100
                        current = 1;
                    end
                case 1 % LOW
                    if temp >= 110
                        current = 2;
                    elseif temp <= 95
                        current = 0;
                    end
                case 2 % HIGH
                    if temp <= 95
                        current = 0;
                    elseif temp <= 105
                        current = 1;
                    end
                otherwise
                    error('Unexpected reference state');
            end
        end
        states(k) = current;
        faults(k) = double(fault);
        streaks(k) = streak;
    end
end
