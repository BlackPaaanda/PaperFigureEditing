%% Analyze Time-Point Data from Raw Metrics
% Reads raw metrics Excel files and extracts snapshots at specific time points
% Works with output from video_data_extraction.m
%
% Input: *_raw_metrics.xlsx files
% Output: *_timepoint_analysis.xlsx files with data at 30%, 50%, 70%, 90%
%
% Author: Time-Point Analysis Tool
% Date: November 2025

clear all; close all; clc;

%% Configuration
config.inputFolder = './results/';
config.outputFolder = './results/';
config.timePoints = [30, 50, 70, 90]; % Time percentages to extract

% Reference point for distance calculation (bottom-left origin)
% config.referencePoint_X = 253;
% config.referencePoint_Y = 236;

fprintf('=== Time-Point Analysis from Raw Metrics ===\n');
fprintf('Time points to analyze: %s\n', mat2str(config.timePoints));
% fprintf('Reference point for distance: (%.0f, %.0f)\n', config.referencePoint_X, config.referencePoint_Y);
fprintf('\n');

%% Find all raw metric files
metricFiles = dir(fullfile(config.inputFolder, '*_raw_metrics.xlsx'));

if isempty(metricFiles)
    error('No raw metric files found. Please run video_data_extraction.m first');
end

fprintf('Found %d category file(s):\n', length(metricFiles));
for i = 1:length(metricFiles)
    fprintf('  - %s\n', metricFiles(i).name);
end
fprintf('\n');

%% Process each category file
for fileIdx = 1:length(metricFiles)
    filename = metricFiles(fileIdx).name;
    filepath = fullfile(config.inputFolder, filename);
    
    % Extract category name from filename
    categoryName = strrep(filename, '_raw_metrics.xlsx', '');
    
    fprintf('=== Processing: %s ===\n', categoryName);
    
    % Read raw metrics
    fprintf('  Reading raw metrics...\n');
    rawMetrics = readtable(filepath, 'Sheet', 'Raw_Metrics');
    
    fprintf('  Loaded %d rows\n', height(rawMetrics));
    
    % Check if required columns exist
    if ~all(ismember({'Category', 'ModelName', 'VideoName', 'TimePercentage'}, rawMetrics.Properties.VariableNames))
        warning('Missing required columns. Skipping this file.');
        continue;
    end
    
    % Get unique videos
    uniqueVideos = unique(rawMetrics.VideoName);
    numVideos = length(uniqueVideos);
    
    fprintf('  Found %d unique videos\n', numVideos);
    
    % Get unique models
    uniqueModels = unique(rawMetrics.ModelName);
    fprintf('  Models: %s\n', strjoin(uniqueModels, ', '));
    
    % Initialize combined data array
    combinedData = [];
    
    % For each time point
    for tpIdx = 1:length(config.timePoints)
        targetTime = config.timePoints(tpIdx);
        fprintf('\n  Extracting data at %d%% time point...\n', targetTime);
        
        % Pre-allocate arrays for this time point
        timePointCategory = cell(numVideos, 1);
        timePointModel = cell(numVideos, 1);
        timePointVideo = cell(numVideos, 1);
        timePointIntensity = zeros(numVideos, 1);
        timePointArea = zeros(numVideos, 1);
        timePointOverlap = zeros(numVideos, 1);
        
        % For each video, find the frame closest to target time
        for vidIdx = 1:numVideos
            videoName = uniqueVideos{vidIdx};
            
            % Get all rows for this video
            videoRows = strcmp(rawMetrics.VideoName, videoName);
            videoData = rawMetrics(videoRows, :);
            
            % Find frame closest to target time percentage, prioritizing before or equal
            % Get frames at or before target time
            beforeOrEqual = videoData.TimePercentage <= targetTime;
            
            if any(beforeOrEqual)
                % Find the closest frame that is <= target time
                candidateFrames = videoData(beforeOrEqual, :);
                [~, relativeIdx] = max(candidateFrames.TimePercentage);
                closestIdx = find(beforeOrEqual);
                closestIdx = closestIdx(relativeIdx);
            else
                % No frames before target time, use the first frame (closest available)
                closestIdx = 1;
                warning('Video %s has no frames <= %d%%. Using first frame.', videoName, targetTime);
            end
            
            % Extract metrics at this frame
            timePointCategory{vidIdx} = videoData.Category{closestIdx};
            timePointModel{vidIdx} = videoData.ModelName{closestIdx};
            timePointVideo{vidIdx} = videoName;
            timePointIntensity(vidIdx) = videoData.AvgRedIntensity(closestIdx);
            timePointArea(vidIdx) = videoData.TotalRedArea(closestIdx);
            timePointOverlap(vidIdx) = videoData.OverlapRatio(closestIdx);
        end
        
        fprintf('    Extracted metrics for %d videos\n', numVideos);
        
        % Create table for this time point
        timePointTable = table(...
            repmat(targetTime, numVideos, 1), ...
            timePointCategory, ...
            timePointModel, ...
            timePointVideo, ...
            timePointIntensity, ...
            timePointArea, ...
            timePointOverlap, ...
            'VariableNames', {'TimePoint_Percent', 'Category', 'ModelName', 'VideoName', ...
                              'AvgRedIntensity', 'TotalRedArea', 'OverlapRatio'});
        
        % Add to combined data
        combinedData = [combinedData; timePointTable];
        
        % Calculate summary statistics per model at this time point
        fprintf('    Summary at %d%%:\n', targetTime);
        for modelIdx = 1:length(uniqueModels)
            modelName = uniqueModels{modelIdx};
            modelMask = strcmp(timePointModel, modelName);
            
            if sum(modelMask) > 0
                meanIntensity = mean(timePointIntensity(modelMask), 'omitnan');
                meanArea = mean(timePointArea(modelMask), 'omitnan');
                meanOverlap = mean(timePointOverlap(modelMask), 'omitnan');
                
                fprintf('      %12s (n=%d): Int=%.4f, Area=%.0f, Overlap=%.3f\n', ...
                        modelName, sum(modelMask), meanIntensity, meanArea, meanOverlap);
            end
        end
    end
    
    % Save combined data to Excel
    outputFilename = fullfile(config.outputFolder, sprintf('%s_timepoint_analysis.xlsx', categoryName));
    fprintf('\n  Saving combined time-point data to: %s\n', outputFilename);
    writetable(combinedData, outputFilename, 'Sheet', 'All_TimePoints');
    fprintf('    Saved %d rows (all videos × all time points)\n', height(combinedData));
    
    % Also save separate sheets for each time point
    for tpIdx = 1:length(config.timePoints)
        targetTime = config.timePoints(tpIdx);
        sheetName = sprintf('Time_%d_Percent', targetTime);
        
        % Filter for this time point
        tpData = combinedData(combinedData.TimePoint_Percent == targetTime, :);
        
        writetable(tpData, outputFilename, 'Sheet', sheetName);
        fprintf('    Sheet "%s" saved (%d videos)\n', sheetName, height(tpData));
    end
    
    fprintf('  Complete!\n\n');
end

%% Generate Cross-Time-Point Statistics
fprintf('=== Generating Model Statistics Across Time Points ===\n');

for fileIdx = 1:length(metricFiles)
    filename = metricFiles(fileIdx).name;
    categoryName = strrep(filename, '_raw_metrics.xlsx', '');
    analysisFile = fullfile(config.outputFolder, sprintf('%s_timepoint_analysis.xlsx', categoryName));
    
    fprintf('\nCategory: %s\n', categoryName);
    
    % Read combined data
    combinedData = readtable(analysisFile, 'Sheet', 'All_TimePoints');
    
    % Get unique models
    uniqueModels = unique(combinedData.ModelName);
    
    % Create statistics table
    statsData = [];
    
    for modelIdx = 1:length(uniqueModels)
        modelName = uniqueModels{modelIdx};
        modelData = combinedData(strcmp(combinedData.ModelName, modelName), :);
        
        % For each time point
        for tpIdx = 1:length(config.timePoints)
            targetTime = config.timePoints(tpIdx);
            tpData = modelData(modelData.TimePoint_Percent == targetTime, :);
            
            if isempty(tpData)
                continue;
            end
            
            % Calculate statistics
            n = height(tpData);
            meanIntensity = mean(tpData.AvgRedIntensity, 'omitnan');
            stdIntensity = std(tpData.AvgRedIntensity, 0, 'omitnan');
            meanArea = mean(tpData.TotalRedArea, 'omitnan');
            stdArea = std(tpData.TotalRedArea, 0, 'omitnan');
            meanOverlap = mean(tpData.OverlapRatio, 'omitnan');
            stdOverlap = std(tpData.OverlapRatio, 0, 'omitnan');
            
            % Add to stats table
            statsRow = table(...
                targetTime, {modelName}, n, ...
                meanIntensity, stdIntensity, ...
                meanArea, stdArea, ...
                meanOverlap, stdOverlap, ...
                'VariableNames', {'TimePoint', 'ModelName', 'N', ...
                                  'Mean_Intensity', 'Std_Intensity', ...
                                  'Mean_Area', 'Std_Area', ...
                                  'Mean_Overlap', 'Std_Overlap'});
            
            statsData = [statsData; statsRow];
        end
    end
    
    % Save statistics
    writetable(statsData, analysisFile, 'Sheet', 'Model_Statistics');
    fprintf('  Statistics sheet saved (%d rows)\n', height(statsData));
    
    %% Generate GraphPad Prism Format Sheet for Average Red Intensity
    fprintf('  Generating GraphPad Prism format sheet...\n');
    
    % Get unique models and sort (GroundTruth first, then alphabetically)
    uniqueModels = unique(combinedData.ModelName);
    gtIdx = strcmp(uniqueModels, 'GroundTruth');
    if any(gtIdx)
        % Put GroundTruth first
        modelsOrdered = [uniqueModels(gtIdx); sort(uniqueModels(~gtIdx))];
    else
        modelsOrdered = sort(uniqueModels);
    end
    
    % Prism format: Each model gets 5 columns (for 5 replicates)
    numModels = length(modelsOrdered);
    maxReplicates = 5;
    
    % Create header row
    headerRow = {'Time'};
    for m = 1:numModels
        modelName = modelsOrdered{m};
        % Add 5 columns for this model (one per replicate)
        for rep = 1:maxReplicates
            headerRow{end+1} = sprintf('%s_%d', modelName, rep);
        end
    end
    
    % Initialize data matrix
    numTimePoints = length(config.timePoints);
    prismData = cell(numTimePoints, 1 + numModels * maxReplicates);
    
    % Fill in time points and data
    for tpIdx = 1:numTimePoints
        targetTime = config.timePoints(tpIdx);
        prismData{tpIdx, 1} = targetTime; % Time column
        
        % Get data for this time point
        tpData = combinedData(combinedData.TimePoint_Percent == targetTime, :);
        
        % For each model, fill in up to 5 replicates
        for m = 1:numModels
            modelName = modelsOrdered{m};
            
            % Get all videos for this model at this time point
            modelData = tpData(strcmp(tpData.ModelName, modelName), :);
            intensities = modelData.AvgRedIntensity;
            
            % Fill in up to 5 replicates
            colOffset = 1 + (m-1) * maxReplicates;
            for rep = 1:maxReplicates
                if rep <= length(intensities)
                    prismData{tpIdx, colOffset + rep} = intensities(rep);
                else
                    prismData{tpIdx, colOffset + rep} = NaN; % Empty cell if < 5 replicates
                end
            end
        end
    end
    
    % Convert to table
    prismTable = cell2table(prismData, 'VariableNames', headerRow);
    
    % Save to Excel
    writetable(prismTable, analysisFile, 'Sheet', 'Prism_AvgIntensity');
    fprintf('  GraphPad Prism format sheet saved (AvgIntensity)\n');
    fprintf('    Format: Time | Model1_1 | Model1_2 | ... | Model1_5 | Model2_1 | ...\n');
    fprintf('    Models: %s\n', strjoin(modelsOrdered, ', '));
    
    %% Generate GraphPad Prism Format Sheet for Total Red Area
    fprintf('  Generating GraphPad Prism format sheet for Total Red Area...\n');
    
    % Create header row (same structure as intensity)
    headerRow = {'Time'};
    for m = 1:numModels
        modelName = modelsOrdered{m};
        % Add 5 columns for this model (one per replicate)
        for rep = 1:maxReplicates
            headerRow{end+1} = sprintf('%s_%d', modelName, rep);
        end
    end
    
    % Initialize data matrix
    prismDataArea = cell(numTimePoints, 1 + numModels * maxReplicates);
    
    % Fill in time points and data
    for tpIdx = 1:numTimePoints
        targetTime = config.timePoints(tpIdx);
        prismDataArea{tpIdx, 1} = targetTime; % Time column
        
        % Get data for this time point
        tpData = combinedData(combinedData.TimePoint_Percent == targetTime, :);
        
        % For each model, fill in up to 5 replicates
        for m = 1:numModels
            modelName = modelsOrdered{m};
            
            % Get all videos for this model at this time point
            modelData = tpData(strcmp(tpData.ModelName, modelName), :);
            areas = modelData.TotalRedArea;
            
            % Fill in up to 5 replicates
            colOffset = 1 + (m-1) * maxReplicates;
            for rep = 1:maxReplicates
                if rep <= length(areas)
                    prismDataArea{tpIdx, colOffset + rep} = areas(rep);
                else
                    prismDataArea{tpIdx, colOffset + rep} = NaN; % Empty cell if < 5 replicates
                end
            end
        end
    end
    
    % Convert to table
    prismTableArea = cell2table(prismDataArea, 'VariableNames', headerRow);
    
    % Save to Excel
    writetable(prismTableArea, analysisFile, 'Sheet', 'Prism_TotalRedArea');
    fprintf('  GraphPad Prism format sheet saved (TotalRedArea)\n');
    fprintf('    Format: Time | Model1_1 | Model1_2 | ... | Model1_5 | Model2_1 | ...\n');
    fprintf('    Models: %s\n', strjoin(modelsOrdered, ', '));
    
    %% Generate GraphPad Prism Format Sheet for Overlap Ratio
    fprintf('  Generating GraphPad Prism format sheet for Overlap Ratio...\n');
    
    % Create header row (same structure as intensity and area)
    headerRow = {'Time'};
    for m = 1:numModels
        modelName = modelsOrdered{m};
        % Add 5 columns for this model (one per replicate)
        for rep = 1:maxReplicates
            headerRow{end+1} = sprintf('%s_%d', modelName, rep);
        end
    end
    
    % Initialize data matrix
    prismDataOverlap = cell(numTimePoints, 1 + numModels * maxReplicates);
    
    % Fill in time points and data
    for tpIdx = 1:numTimePoints
        targetTime = config.timePoints(tpIdx);
        prismDataOverlap{tpIdx, 1} = targetTime; % Time column
        
        % Get data for this time point
        tpData = combinedData(combinedData.TimePoint_Percent == targetTime, :);
        
        % For each model, fill in up to 5 replicates
        for m = 1:numModels
            modelName = modelsOrdered{m};
            
            % Get all videos for this model at this time point
            modelData = tpData(strcmp(tpData.ModelName, modelName), :);
            overlaps = modelData.OverlapRatio;
            
            % Fill in up to 5 replicates
            colOffset = 1 + (m-1) * maxReplicates;
            for rep = 1:maxReplicates
                if rep <= length(overlaps)
                    prismDataOverlap{tpIdx, colOffset + rep} = overlaps(rep);
                else
                    prismDataOverlap{tpIdx, colOffset + rep} = NaN; % Empty cell if < 5 replicates
                end
            end
        end
    end
    
    % Convert to table
    prismTableOverlap = cell2table(prismDataOverlap, 'VariableNames', headerRow);
    
    % Save to Excel
    writetable(prismTableOverlap, analysisFile, 'Sheet', 'Prism_OverlapRatio');
    fprintf('  GraphPad Prism format sheet saved (OverlapRatio)\n');
    fprintf('    Format: Time | Model1_1 | Model1_2 | ... | Model1_5 | Model2_1 | ...\n');
    fprintf('    Models: %s\n', strjoin(modelsOrdered, ', '));
end

fprintf('\n=== Analysis Complete ===\n');
fprintf('Time-point analysis files created in: %s\n', config.outputFolder);
fprintf('\nNext steps:\n');
fprintf('  1. Open Excel files to view data at each time point\n');
fprintf('  2. Compare GroundTruth vs AI models\n');
fprintf('  3. Analyze temporal evolution (30%% → 50%% → 70%% → 90%%)\n');
fprintf('  4. Create visualizations (box plots, line plots, etc.)\n');
