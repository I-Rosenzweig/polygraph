clear;
clc;

% Connect to Arduino with I2C, Analog Input for GSR & EKG
a = arduino("COM5", "Uno", "Libraries", "I2C");

% MAX30105 I2C Setup
sensor = device(a, 'I2CAddress', '0x57');

% Configure MAX30105 (SpO2 & Heart Rate Mode)
writeRegister(sensor, 0x09, 0x03); % Mode Configuration (Enable SpO2 mode)
writeRegister(sensor, 0x0A, 0x27); % SpO2 Configuration
writeRegister(sensor, 0x0C, 0x24); % LED1 (Red) Pulse Amplitude
writeRegister(sensor, 0x0D, 0x24); % LED2 (IR) Pulse Amplitude

pause(0.1); % Small delay for initialization

% Initialize figure for subplots
figure;

subplot(6,1,1);
hold on; grid on;
title("IR & RED LED Readings");
xlabel("Time (s)"); ylabel("Sensor Value");
hIR = plot(nan, nan, 'r', 'LineWidth', 1.5);  
hRED = plot(nan, nan, 'b', 'LineWidth', 1.5);  
legend("IR", "RED");

subplot(6,1,2);
hold on; grid on;
title("Heart Rate (BPM)");
xlabel("Time (s)"); ylabel("BPM");
hHR = plot(nan, nan, 'g', 'LineWidth', 1.5);  
ylim([40, 180]); % Add reasonable y-limits for BPM

subplot(6,1,3);
hold on; grid on;
title("SpO₂ (%)");
xlabel("Time (s)"); ylabel("SpO₂");
hSPO2 = plot(nan, nan, 'm', 'LineWidth', 1.5);
ylim([80, 100]); % Add reasonable y-limits for SpO2

subplot(6,1,4);
hold on; grid on;
title("Skin Conductance (GSR)");
xlabel("Time (s)"); ylabel("µS");
hGSR = plot(nan, nan, 'k', 'LineWidth', 1.5);

subplot(6,1,5);
hold on; grid on;
title("Estimated BP Fluctuation (%)");
xlabel("Time (s)"); ylabel("BP % Change");
hBP = plot(nan, nan, 'c', 'LineWidth', 1.5);

subplot(6,1,6);
hold on; grid on;
title("EKG Signal (A1)");
xlabel("Time (s)"); ylabel("mV");
hEKG = plot(nan, nan, 'y', 'LineWidth', 1.5);

% Data storage (rolling window for speed)
maxDataPoints = 300;
timeData = zeros(1, maxDataPoints);
irData = zeros(1, maxDataPoints);
redData = zeros(1, maxDataPoints);
heartRateData = zeros(1, maxDataPoints);
spo2Data = zeros(1, maxDataPoints);
gsrData = zeros(1, maxDataPoints);
bpFluctuationData = zeros(1, maxDataPoints);
ekgData = zeros(1, maxDataPoints);

% Scaling factors
GSR_SCALE = 10; % Adjust for µS scaling
BP_SCALE = 5;   % Adjust for relative BP changes
EKG_SCALE = 1000; % Convert V to mV

% Moving average filter window
filterSize = 5;

% Peak detection variables
lastPeakTime = 0;
peakThreshold = 5000; % Adjust based on your sensor's typical values
minPeakInterval = 0.4; % Minimum time between peaks (in seconds)
previousPeaks = zeros(1, 10); % Store last 10 peak intervals
peakIndex = 1;

% Start live reading loop
dataLog = [];
tic;
while true
    % Read sensor data
    rawIR = double(readRegister(sensor, 0x07, 'uint16'));
    rawRED = double(readRegister(sensor, 0x08, 'uint16'));
    rawGSR = readVoltage(a, "A0") * GSR_SCALE;  % Convert V to µS
    rawEKG = readVoltage(a, "A1") * EKG_SCALE;  % Convert V to mV

    currentTime = toc;

    % Improved Heart Rate Estimation
    % Look for peaks in real-time with proper time tracking
    if rawIR > peakThreshold && (currentTime - lastPeakTime) > minPeakInterval
        % Found a peak
        if lastPeakTime > 0
            peakInterval = currentTime - lastPeakTime;
            
            % Store in circular buffer
            previousPeaks(peakIndex) = peakInterval;
            peakIndex = mod(peakIndex, 10) + 1;
            
            % Calculate heart rate from valid intervals
            validPeaks = previousPeaks(previousPeaks > 0);
            if ~isempty(validPeaks)
                avgInterval = mean(validPeaks);
                heartRate = 60 / avgInterval;
                % Add bounds check for realistic heart rates
                heartRate = min(max(heartRate, 40), 180);
            else
                heartRate = nan;
            end
        else
            heartRate = nan;
        end
        lastPeakTime = currentTime;
    end

    % Apply Moving Average Filter (Heart Rate)
    heartRateData = [heartRateData(2:end), heartRate];
    validHeartRates = heartRateData(~isnan(heartRateData));
    if length(validHeartRates) >= 3  % Need at least 3 valid measurements
        heartRate = mean(validHeartRates(max(1, end-filterSize+1):end));
    end

    % Estimate SpO₂ (fix bounds)
    if rawIR > 100  % Simple validity check
        R = (rawRED / rawIR);
        spo2 = 110 - (25 * R);
        % Add bounds check for realistic SpO2
        spo2 = min(max(spo2, 80), 100);
    else
        spo2 = nan;
    end

    % Apply Moving Average Filter (SpO₂)
    spo2Data = [spo2Data(2:end), spo2];
    if sum(~isnan(spo2Data(end-min(filterSize, length(spo2Data))+1:end))) > 0
        spo2 = mean(spo2Data(end-min(filterSize, length(spo2Data))+1:end), 'omitnan');
    end

    % Estimate BP fluctuation
    if ~isnan(heartRate) && ~isnan(spo2)
        bpFluctuation = (heartRate / 100) * (spo2 / 100) * BP_SCALE;
    else
        bpFluctuation = nan;
    end

    % Shift data (fast rolling window update)
    timeData = [timeData(2:end), currentTime];
    irData = [irData(2:end), rawIR];
    redData = [redData(2:end), rawRED];
    heartRateData = [heartRateData(2:end), heartRate];
    spo2Data = [spo2Data(2:end), spo2];
    gsrData = [gsrData(2:end), rawGSR];
    bpFluctuationData = [bpFluctuationData(2:end), bpFluctuation];
    ekgData = [ekgData(2:end), rawEKG];

    % Update plots
    set(hIR, 'XData', timeData, 'YData', irData);
    set(hRED, 'XData', timeData, 'YData', redData);
    set(hHR, 'XData', timeData, 'YData', heartRateData);
    set(hSPO2, 'XData', timeData, 'YData', spo2Data);
    set(hGSR, 'XData', timeData, 'YData', gsrData);
    set(hBP, 'XData', timeData, 'YData', bpFluctuationData);
    set(hEKG, 'XData', timeData, 'YData', ekgData);

    drawnow;
    pause(0.02); % Faster update rate

    % Log Data for Analysis
    dataLog = [dataLog; currentTime, rawIR, rawRED, heartRate, spo2, rawGSR, bpFluctuation, rawEKG];

    % Save Data to File Every 10 Seconds (fix file writing)
    if mod(length(dataLog), 500) == 0
        try
            csvwrite("sensor_data.csv", dataLog);
        catch
            warning('Could not save data, continuing...');
        end
    end
    
    % Add a display in console to check values
    if mod(round(currentTime*10), 50) == 0  % Display every ~5 seconds
        fprintf('Time: %.1f, IR: %.0f, Heart Rate: %.1f BPM, SpO2: %.1f%%\n', ...
                currentTime, rawIR, heartRate, spo2);
    end
end
