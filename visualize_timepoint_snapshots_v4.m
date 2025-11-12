%% Time-Point Snapshot Visualization with Multi-Model Overlay
% Creates 4 "long exposure" style plots (one per time point: 30%, 50%, 70%, 90%)
% Each plot shows accumulated red signal across all videos for each model
% - Ground Truth: Black color
% - Clot: Gray color  
% - Other models: Other distinct colors
%
% More videos showing signal at same location = Darker/more opaque
%
% Author: Time-Point Snapshot Visualization Tool
% Date: November 2025

clear all; close all; clc;

%% ========================================================================
%  CONFIGURATION SECTION - MODIFY AS NEEDED
%% ========================================================================

config.videoFolder = './videos/';
config.outputFolder = './timepoint_snapshots/';
config.timePoints = [30, 50, 70, 90]; % Time percentages to visualize

% SELECT WHICH VIDEO TO USE FOR EACH MODEL (by index, 1-based)
% For each model, specify which video number to use (1 = first video, 2 = second, etc.)
config.videoIndex.GroundTruth = 1;   % Use 1st Ground Truth video
config.videoIndex.Clot = 3;          % Use 1st Clot video
config.videoIndex.Sora = 3;          % Use 1st Sora video
config.videoIndex.Hailuo = 4;        % Use 1st Hailuo video
config.videoIndex.Hunyuan = 3;       % Use 1st Hunyuan video
config.videoIndex.Kling = 2;         % Use 1st Kling video
config.videoIndex.Seedance = 5;      % Use 1st Seedance video
config.videoIndex.Wan = 2;           % Use 1st Wan video

% Create output directory
if ~exist(config.outputFolder, 'dir')
    mkdir(config.outputFolder);
end

% Signal detection parameters
config.redThreshold = 30;           % Minimum red intensity (0-255)
config.redPurityRatio = 1.5;        % Red must be this much stronger than green

% Model colors (RGB triplets) - for accumulated display
config.colors.GroundTruth = [0.0, 0.0, 0.0];      % Black
config.colors.Clot = [0.4, 0.4, 0.4];              % Gray
% Viridis colormap colors for other models (from reference image)
config.colors.Sora = [0.267, 0.529, 0.529];        % Teal (from viridis)
config.colors.Hailuo = [0.153, 0.659, 0.506];      % Green-cyan (from viridis)
config.colors.Hunyuan = [0.369, 0.788, 0.384];     % Green (from viridis)
config.colors.Kling = [0.816, 0.847, 0.176];       % Yellow-green (from viridis)
config.colors.Seedance = [0.416, 0.227, 0.569];    % Purple (from viridis)
config.colors.Wan = [0.282, 0.361, 0.616];         % Blue (from viridis)
config.colors.Default = [0.5, 0.5, 0.5];           % Medium gray

% Maximum opacity per model (0-1)
config.maxAlpha.GroundTruth = 0.9;   % Very opaque
config.maxAlpha.Clot = 0.8;          % Opaque
config.maxAlpha.Sora = 0.7;          % Semi-transparent
config.maxAlpha.Hailuo = 0.7;
config.maxAlpha.Hunyuan = 0.7;
config.maxAlpha.Kling = 0.7;
config.maxAlpha.Seedance = 0.7;
config.maxAlpha.Wan = 0.7;
config.maxAlpha.Default = 0.7;

% Figure size
config.figureSize = [100, 100, 1000, 1000];

%% ========================================================================
%  END OF CONFIGURATION
%% ========================================================================

fprintf('=== Time-Point Snapshot Visualization ===\n');
fprintf('Time points: %s\n', mat2str(config.timePoints));
fprintf('\n');

%% Step 1: Organize videos by category and model
fprintf('=== Organizing Videos ===\n');
videoFiles = dir(fullfile(config.videoFolder, '*.mp4'));

if isempty(videoFiles)
    error('No video files found in %s', config.videoFolder);
end

fprintf('Found %d video file(s)\n', length(videoFiles));

% Parse video information
videoInfo = struct('filename', {}, 'category', {}, 'model', {}, 'path', {});

for i = 1:length(videoFiles)
    filename = videoFiles(i).name;
    [~, name, ~] = fileparts(filename);
    
    % Parse naming convention: Patient-Location-Model-Index
    parts = strsplit(name, '-');
    
    if length(parts) >= 2
        info.filename = filename;
        info.category = strcat(parts{1}, '-', parts{2}); % e.g., "JH-ICA"
        info.path = fullfile(config.videoFolder, filename);
        
        % Determine model
        if length(parts) == 2 || strcmpi(parts{3}, 'GT')
            info.model = 'GroundTruth';
        else
            info.model = parts{3};
        end
        
        videoInfo(end+1) = info;
    end
end

% Group by category
uniqueCategories = unique({videoInfo.category});
fprintf('Categories: %s\n\n', strjoin(uniqueCategories, ', '));

%% Step 2: Process each category
for catIdx = 1:length(uniqueCategories)
    categoryName = uniqueCategories{catIdx};
    
    fprintf('=== Processing Category: %s ===\n', categoryName);
    
    % Get all videos in this category
    catVideos = videoInfo(strcmp({videoInfo.category}, categoryName));
    
    if isempty(catVideos)
        continue;
    end
    
    % Get unique models in this category
    uniqueModels = unique({catVideos.model});
    fprintf('  Models in category: %s\n', strjoin(uniqueModels, ', '));
    
    % Reorder: Other models first, GroundTruth second-to-last, Clot last (on top)
    modelsOrdered = {};
    
    % First add all other models (not GT or Clot)
    otherModels = uniqueModels(~strcmp(uniqueModels, 'GroundTruth') & ~strcmp(uniqueModels, 'Clot'));
    for i = 1:length(otherModels)
        modelsOrdered{end+1} = otherModels{i};
    end
    
    % Then add GroundTruth (if exists) - will be on top of other models
    if any(strcmp(uniqueModels, 'GroundTruth'))
        modelsOrdered{end+1} = 'GroundTruth';
    end
    
    % Finally add Clot (if exists) - will be on top layer
    if any(strcmp(uniqueModels, 'Clot'))
        modelsOrdered{end+1} = 'Clot';
    end
    
    fprintf('  Plotting order (bottom to top): %s\n', strjoin(modelsOrdered, ' -> '));
    
    % Load reference dimensions from first video
    fprintf('  Loading reference video for dimensions...\n');
    firstVideo = loadVideoFrame(catVideos(1).path, 0); % Load first frame only
    refHeight = firstVideo.height;
    refWidth = firstVideo.width;
    fprintf('  Reference dimensions: %dx%d\n', refWidth, refHeight);
    
    %% Extract vessel contour from first Clot video
    fprintf('  Extracting vessel contour from first Clot video...\n');
    vesselContourMask = [];
    
    % Find first Clot video
    clotVideos = catVideos(strcmp({catVideos.model}, 'Clot'));
    if ~isempty(clotVideos)
        firstClotPath = clotVideos(1).path;
        fprintf('    Using: %s\n', clotVideos(1).filename);
        
        % Load first frame
        vesselFrame = loadVideoFrame(firstClotPath, 0.1); % Load frame at ~0.1% (very first frame)
        
        % Resize if needed
        if vesselFrame.height ~= refHeight || vesselFrame.width ~= refWidth
            vesselFrame.green = imresize(vesselFrame.green, [refHeight, refWidth], 'bilinear');
        end
        
        % Threshold green channel to find vessel
        greenThreshold = 20; % Adjust if needed
        vesselMask = vesselFrame.green > greenThreshold;
        
        % Fill holes to get outer contour only
        vesselContourMask = imfill(vesselMask, 'holes');
        
        fprintf('    Vessel contour extracted\n');
    else
        fprintf('    No Clot videos found, skipping vessel contour\n');
    end
    
    %% Step 3: Create one plot per time point
    for tpIdx = 1:length(config.timePoints)
        targetTime = config.timePoints(tpIdx);
        
        fprintf('\n  === Time Point: %d%% ===\n', targetTime);
        
        % Initialize RGB image (white background)
        rgbImage = ones(refHeight, refWidth, 3);
        
        % Display the white background
        fig = figure('Position', config.figureSize, 'Name', sprintf('%s - %d%%', categoryName, targetTime));
        imshow(rgbImage);
        hold on;
        
        % Process each model - draw contours only
        for modelIdx = 1:length(modelsOrdered)
            modelName = modelsOrdered{modelIdx};
            
            fprintf('    Processing model: %s\n', modelName);
            
            % Get all videos for this model
            modelVideos = catVideos(strcmp({catVideos.model}, modelName));
            numVideos = length(modelVideos);
            
            if numVideos == 0
                fprintf('      No videos found, skipping\n');
                continue;
            end
            
            % Get which video index to use for this model
            if isfield(config.videoIndex, modelName)
                videoIdx = config.videoIndex.(modelName);
            else
                videoIdx = 1; % Default to first video
            end
            
            % Check if video index is valid
            if videoIdx > numVideos
                fprintf('      WARNING: Video index %d exceeds available videos (%d), using last video\n', videoIdx, numVideos);
                videoIdx = numVideos;
            end
            
            fprintf('      Using video %d/%d: %s\n', videoIdx, numVideos, modelVideos(videoIdx).filename);
            
            % Load the selected video at target time
            videoPath = modelVideos(videoIdx).path;
            frameData = loadVideoFrame(videoPath, targetTime);
            
            % Resize if needed
            if frameData.height ~= refHeight || frameData.width ~= refWidth
                fprintf('          Resizing from %dx%d to %dx%d\n', ...
                        frameData.width, frameData.height, refWidth, refHeight);
                frameData.red = imresize(frameData.red, [refHeight, refWidth], 'bilinear');
                frameData.green = imresize(frameData.green, [refHeight, refWidth], 'bilinear');
            end
            
            % Detect pure red signal
            redFrame = double(frameData.red);
            greenFrame = double(frameData.green);
            
            % Check threshold and purity
            redAboveThreshold = redFrame > config.redThreshold;
            redDominant = redFrame > (greenFrame * config.redPurityRatio);
            redMask = redAboveThreshold & redDominant;
            
            % Get color for this model
            if isfield(config.colors, modelName)
                modelColor = config.colors.(modelName);
            else
                modelColor = config.colors.Default;
            end
            
            % Draw contour (no fill, just outline)
            if any(redMask(:))
                if strcmp(modelName, 'GroundTruth')
                    % Ground Truth: black filled with transparency
                    contour(redMask, [0.5 0.5], 'LineColor', modelColor, 'LineWidth', 2, 'Fill', 'on', 'FaceAlpha', 0.7);
                elseif strcmp(modelName, 'Clot')
                    % Clot: pure red wire, no fill
                    contour(redMask, [0.5 0.5], 'LineColor', [1, 0, 0], 'LineWidth', 1);
                else
                    % Other models: 1pt wire using viridis colors
                    contour(redMask, [0.5 0.5], 'LineColor', modelColor, 'LineWidth', 1);
                end
                fprintf('      Contour drawn for %s\n', modelName);
            else
                fprintf('      No red signal detected for %s\n', modelName);
            end
        end
        
        % Draw vessel outer contour (if available)
        if ~isempty(vesselContourMask)
            fprintf('      Drawing vessel outer contour\n');
            contour(vesselContourMask, [0.5 0.5], 'LineColor', [0, 0, 0], 'LineWidth', 2, 'LineStyle', '-.');
        end
        
        %% Add legend (keep hold on for this)
        fprintf('    Adding legend...\n');
        
        % Create legend entries
        legendHandles = [];
        legendLabels = {};
        
        % Add vessel boundary first
        if ~isempty(vesselContourMask)
            h_vessel = plot(NaN, NaN, '-.', 'Color', [0, 0, 0], 'LineWidth', 2);
            legendHandles(end+1) = h_vessel;
            legendLabels{end+1} = 'Vessel Boundary';
        end
        
        % Add each model
        for modelIdx = 1:length(modelsOrdered)
            modelName = modelsOrdered{modelIdx};
            
            if isfield(config.colors, modelName)
                modelColor = config.colors.(modelName);
            else
                modelColor = config.colors.Default;
            end
            
            h_model = plot(NaN, NaN, '-', 'Color', modelColor, 'LineWidth', 2);
            legendHandles(end+1) = h_model;
            legendLabels{end+1} = modelName;
        end
        
        % Display legend
        if ~isempty(legendHandles)
            legend(legendHandles, legendLabels, 'Location', 'best', 'FontSize', 10);
        end
        
        hold off;
        
        %% Format figure
        fprintf('    Formatting figure...\n');
        title(sprintf('%s - Time Point: %d%%\nAccumulated Red Signal Across All Videos', ...
                     strrep(categoryName, '_', ' '), targetTime), ...
              'FontSize', 14, 'FontWeight', 'bold');
        
        fprintf('    Figure created for %d%% time point\n', targetTime);
    end
    
    fprintf('\n  Category %s complete!\n\n', categoryName);
end

fprintf('=== All Categories Processed ===\n');
fprintf('All figures created and kept open.\n');
fprintf('Save the figures you want manually.\n');

%% ========================================================================
%  FUNCTION DEFINITIONS
%% ========================================================================

function frameData = loadVideoFrame(videoPath, targetTimePercent)
    % Load video and extract frame at target time percentage
    % Applies 360x360 centered crop (same as extraction code)
    % If targetTimePercent = 0, just load first frame for dimensions
    
    vidObj = VideoReader(videoPath);
    
    originalHeight = vidObj.Height;
    originalWidth = vidObj.Width;
    
    % Target size: resize to 512x512 if needed
    targetSize = 512;
    needsResize = (originalWidth ~= targetSize) || (originalHeight ~= targetSize);
    
    % Calculate 360x360 crop boundaries (centered on 512x512)
    cropSize = 360;
    centerX = round(targetSize / 2);  % 256
    centerY = round(targetSize / 2);  % 256
    cropHalf = floor(cropSize / 2);   % 180
    
    cropXmin = centerX - cropHalf;  % 76
    cropXmax = centerX + cropHalf - 1;  % 435
    cropYmin = centerY - cropHalf;  % 76
    cropYmax = centerY + cropHalf - 1;  % 435
    
    frameData.height = cropSize;
    frameData.width = cropSize;
    
    if targetTimePercent == 0
        % Just return dimensions
        frameData.red = [];
        frameData.green = [];
        return;
    end
    
    % Calculate total frames
    totalFrames = floor(vidObj.Duration * vidObj.FrameRate);
    
    % Find target frame (frame at or before target time)
    targetFrameNum = max(1, floor(totalFrames * targetTimePercent / 100));
    
    % Read until target frame
    currentFrame = 0;
    while hasFrame(vidObj) && currentFrame < targetFrameNum
        frame = readFrame(vidObj);
        currentFrame = currentFrame + 1;
    end
    
    % Resize if needed
    if needsResize
        frame = imresize(frame, [targetSize, targetSize], 'bilinear');
    end
    
    % Apply 360x360 centered crop
    frameCropped = frame(cropYmin:cropYmax, cropXmin:cropXmax, :);
    
    % Extract channels from cropped frame
    frameData.red = frameCropped(:,:,1);
    frameData.green = frameCropped(:,:,2);
end
