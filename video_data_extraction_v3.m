%% Confocal Video Data Extraction Tool - Version 3
% Extracts metrics from immunostaining confocal videos
% 
% NEW FEATURES:
% - 360x360 analysis crop (centered)
% - Baseline subtraction for AvgRedIntensity (first frame = 0)
% - Overlap ratio calculation vs reference GT
% - Separate thresholds for GT and AI models
% - Removed COM and MeanRadius metrics
%
% Author: Data Extraction Tool
% Date: November 2025

clear all; close all; clc;

%% ========================================================================
%  CONFIGURATION SECTION
%% ========================================================================

config.videoFolder = './videos/';
config.outputFolder = './results/';

% Analysis crop region (360x360 centered on 512x512 frame)
config.analysisCropSize = 360;

% Custom crop for average intensity calculation
config.intensityCropWidth = 140;
config.intensityCropHeight = 100;
config.intensityCropCenterX = 256;  % X center (bottom-left origin, 512x512 coordinates)
config.intensityCropCenterY = 342;  % Y center (bottom-left origin, 512x512 coordinates)

% Red signal detection thresholds
config.redThreshold_GroundTruth = 0;  % For Ground Truth videos
config.redThreshold_AIModels = 10;      % For AI-generated videos  
config.redPurityRatio = 1.5;            % Red > Green * ratio

% Reference Ground Truth video for overlap calculation
% Specify the exact GT video filename (without .mp4) to use as reference
% Examples: 'JH-ICA', 'JH-ICA-GT', 'Patient1-Location2-GT-1'
% Leave empty '' to automatically use first GT video in each category
config.referenceGTVideo = 'RC-ICA-GT-1';  % e.g., 'JH-ICA-GT-1'

%% ========================================================================

% Create output directory
if ~exist(config.outputFolder, 'dir')
    mkdir(config.outputFolder);
end

fprintf('=== Video Data Extraction v3 ===\n');
fprintf('Analysis crop: %dx%d (centered)\n', config.analysisCropSize, config.analysisCropSize);
fprintf('Intensity crop: %dx%d at (%d,%d)\n\n', ...
        config.intensityCropWidth, config.intensityCropHeight, ...
        config.intensityCropCenterX, config.intensityCropCenterY);

%% Organize Videos
fprintf('=== Organizing Videos ===\n');
[videoCategories] = organizeVideos(config.videoFolder);

for i = 1:length(videoCategories)
    fprintf('\nCategory %d: %s\n', i, videoCategories(i).name);
    fprintf('  Videos: %d\n', length(videoCategories(i).videos));
end

%% Process Each Category
for catIdx = 1:length(videoCategories)
    category = videoCategories(catIdx);
    fprintf('\n\n=== Processing Category: %s ===\n', category.name);
    
    % Find reference GT video
    gtVideos = category.videos(strcmp({category.videos.model}, 'GroundTruth'));
    if isempty(gtVideos)
        warning('No Ground Truth videos found. Skipping category.');
        continue;
    end
    
    % Select reference GT video
    if isempty(config.referenceGTVideo)
        % Use first GT video
        referenceGTPath = fullfile(config.videoFolder, gtVideos(1).filename);
        fprintf('Reference GT (auto-selected first): %s\n', gtVideos(1).filename);
    else
        % Look for specified GT video
        refFilename = [config.referenceGTVideo, '.mp4'];
        refIdx = find(strcmp({gtVideos.filename}, refFilename));
        
        if isempty(refIdx)
            warning('Specified reference GT "%s" not found. Using first GT instead.', config.referenceGTVideo);
            referenceGTPath = fullfile(config.videoFolder, gtVideos(1).filename);
            fprintf('Reference GT (fallback to first): %s\n', gtVideos(1).filename);
        else
            referenceGTPath = fullfile(config.videoFolder, gtVideos(refIdx(1)).filename);
            fprintf('Reference GT (user-specified): %s\n', gtVideos(refIdx(1)).filename);
        end
    end
    
    % Load reference GT data
    fprintf('Loading reference GT for overlap calculation...\n');
    refGTData = loadAndProcessVideo(referenceGTPath, config);
    
    % Get reference dimensions
    refHeight = refGTData.height;
    refWidth = refGTData.width;
    fprintf('Reference dimensions: %dx%d\n', refWidth, refHeight);
    
    % Process all videos
    allMetrics = [];
    
    for vidIdx = 1:length(category.videos)
        video = category.videos(vidIdx);
        fprintf('\nProcessing %d/%d: %s (Model: %s)\n', vidIdx, length(category.videos), ...
                video.filename, video.model);
        
        % Load video (already resized to 512x512 then cropped to 360x360)
        videoPath = fullfile(config.videoFolder, video.filename);
        videoData = loadAndProcessVideo(videoPath, config);
        
        % All videos should now be 360x360 after processing
        if videoData.height ~= refHeight || videoData.width ~= refWidth
            error('Video dimensions mismatch! Expected %dx%d but got %dx%d', ...
                  refWidth, refHeight, videoData.width, videoData.height);
        end
        
        % Extract metrics
        videoNameClean = strrep(video.filename, '.mp4', '');
        metrics = extractVideoMetrics(videoData, videoNameClean, video.model, ...
                                       category.name, refGTData, config);
        
        % Combine
        if isempty(allMetrics)
            allMetrics = metrics;
        else
            allMetrics = [allMetrics; metrics];
        end
    end
    
    % Save to Excel
    excelFilename = fullfile(config.outputFolder, sprintf('%s_raw_metrics.xlsx', ...
                            matlab.lang.makeValidName(category.name)));
    fprintf('\nSaving metrics to: %s\n', excelFilename);
    saveMetricsToExcel(allMetrics, excelFilename);
    fprintf('Saved %d videos\n', length(allMetrics));
end

fprintf('\n=== Extraction Complete ===\n');

%% ========================================================================
%  FUNCTIONS
%% ========================================================================

function [categories] = organizeVideos(videoFolder)
    videoFiles = dir(fullfile(videoFolder, '*.mp4'));
    
    videoInfo = struct('filename', {}, 'category', {}, 'model', {});
    
    for i = 1:length(videoFiles)
        filename = videoFiles(i).name;
        [~, name, ~] = fileparts(filename);
        parts = strsplit(name, '-');
        
        if length(parts) >= 2
            info.filename = filename;
            info.category = strcat(parts{1}, '-', parts{2});
            
            if length(parts) == 2 || strcmpi(parts{3}, 'GT')
                info.model = 'GroundTruth';
            else
                info.model = parts{3};
            end
            
            videoInfo(end+1) = info;
        end
    end
    
    uniqueCategories = unique({videoInfo.category});
    categories = struct('name', {}, 'videos', {});
    
    for i = 1:length(uniqueCategories)
        cat.name = uniqueCategories{i};
        cat.videos = videoInfo(strcmp({videoInfo.category}, uniqueCategories{i}));
        categories(i) = cat;
    end
end

function videoData = loadAndProcessVideo(videoPath, config)
    fprintf('  Reading: %s\n', videoPath);
    vidObj = VideoReader(videoPath);
    
    numFrames = floor(vidObj.Duration * vidObj.FrameRate);
    originalHeight = vidObj.Height;
    originalWidth = vidObj.Width;
    
    fprintf('  Original dimensions: %dx%d\n', originalWidth, originalHeight);
    
    % Target size: resize to 512x512 if needed
    targetSize = 512;
    needsResize = (originalWidth ~= targetSize) || (originalHeight ~= targetSize);
    
    if needsResize
        fprintf('  Will resize to %dx%d\n', targetSize, targetSize);
    else
        fprintf('  Already %dx%d, no resize needed\n', targetSize, targetSize);
    end
    
    % Calculate 360x360 crop boundaries (centered on 512x512)
    cropSize = config.analysisCropSize; % 360
    centerX = round(targetSize / 2);  % 256
    centerY = round(targetSize / 2);  % 256
    cropHalf = floor(cropSize / 2);   % 180
    
    cropXmin = centerX - cropHalf;  % 76
    cropXmax = centerX + cropHalf - 1;  % 435
    cropYmin = centerY - cropHalf;  % 76
    cropYmax = centerY + cropHalf - 1;  % 435
    
    actualCropHeight = cropYmax - cropYmin + 1;  % 360
    actualCropWidth = cropXmax - cropXmin + 1;   % 360
    
    fprintf('  Cropping to [%d:%d, %d:%d] = %dx%d\n', ...
            cropYmin, cropYmax, cropXmin, cropXmax, ...
            actualCropWidth, actualCropHeight);
    
    redChannel = zeros(actualCropHeight, actualCropWidth, numFrames, 'uint8');
    greenChannel = zeros(actualCropHeight, actualCropWidth, numFrames, 'uint8');
    
    frameIdx = 1;
    while hasFrame(vidObj)
        frame = readFrame(vidObj);
        
        if needsResize
            % STEP 1: Resize to 512x512
            frameResized = imresize(frame, [targetSize, targetSize], 'bilinear');
        else
            % Already 512x512, no resize needed
            frameResized = frame;
        end
        
        % STEP 2: Crop to 360x360 centered region
        redChannel(:,:,frameIdx) = frameResized(cropYmin:cropYmax, cropXmin:cropXmax, 1);
        greenChannel(:,:,frameIdx) = frameResized(cropYmin:cropYmax, cropXmin:cropXmax, 2);
        
        frameIdx = frameIdx + 1;
    end
    
    redChannel = redChannel(:,:,1:frameIdx-1);
    greenChannel = greenChannel(:,:,1:frameIdx-1);
    
    videoData.green = greenChannel;
    videoData.red = redChannel;
    videoData.numFrames = frameIdx - 1;
    videoData.height = actualCropHeight;
    videoData.width = actualCropWidth;
    videoData.cropOffset = [cropYmin, cropXmin]; % Store offset for coordinate mapping
    
    if needsResize
        fprintf('  Loaded %d frames (resized to 512x512, then cropped to %dx%d)\n', ...
                videoData.numFrames, actualCropWidth, actualCropHeight);
    else
        fprintf('  Loaded %d frames (cropped to %dx%d, no resize)\n', ...
                videoData.numFrames, actualCropWidth, actualCropHeight);
    end
end

function metrics = extractVideoMetrics(videoData, videoName, modelName, categoryName, refGTData, config)
    fprintf('  Extracting metrics...\n');
    
    numFrames = videoData.numFrames;
    height = videoData.height;
    width = videoData.width;
    
    % Pre-allocate
    metrics = struct();
    metrics.Category = repmat({categoryName}, numFrames, 1);
    metrics.ModelName = repmat({modelName}, numFrames, 1);
    metrics.VideoName = repmat({videoName}, numFrames, 1);
    metrics.FrameNumber = (1:numFrames)';
    metrics.TimePercentage = (1:numFrames)' / numFrames * 100;
    metrics.AvgRedIntensity = zeros(numFrames, 1);
    metrics.TotalRedArea = zeros(numFrames, 1);
    metrics.OverlapRatio = zeros(numFrames, 1);
    
    % Get threshold for this model
    if strcmp(modelName, 'GroundTruth')
        redThreshold = config.redThreshold_GroundTruth;
    else
        redThreshold = config.redThreshold_AIModels;
    end
    
    % Map intensity crop to cropped coordinates
    % Original coordinates are for 512x512, need to adjust for 360x360 crop
    offset = (512 - 360) / 2; % Crop starts at (76, 76) in original frame
    
    intensityCropCenterX_cropped = config.intensityCropCenterX - offset;
    intensityCropCenterY_cropped = 360 - (config.intensityCropCenterY - offset); % Flip Y for image coords
    
    cropHalfW = floor(config.intensityCropWidth / 2);
    cropHalfH = floor(config.intensityCropHeight / 2);
    
    intCropXmin = max(1, round(intensityCropCenterX_cropped - cropHalfW));
    intCropXmax = min(width, round(intensityCropCenterX_cropped + cropHalfW - 1));
    intCropYmin = max(1, round(intensityCropCenterY_cropped - cropHalfH));
    intCropYmax = min(height, round(intensityCropCenterY_cropped + cropHalfH - 1));
    
    intensityCropArea = (intCropXmax - intCropXmin + 1) * (intCropYmax - intCropYmin + 1);
    
    fprintf('  Intensity crop (in 360x360): [%d:%d, %d:%d]\n', intCropYmin, intCropYmax, intCropXmin, intCropXmax);
    
    % Get baseline (first frame) for intensity
    firstRedFrame = double(videoData.red(:,:,1));
    firstGreenFrame = double(videoData.green(:,:,1));
    firstRedCrop = firstRedFrame(intCropYmin:intCropYmax, intCropXmin:intCropXmax);
    firstGreenCrop = firstGreenFrame(intCropYmin:intCropYmax, intCropXmin:intCropXmax);
    
    firstRedMask = (firstRedCrop > redThreshold) & (firstRedCrop > firstGreenCrop * config.redPurityRatio);
    baselineIntensity = sum(firstRedCrop(firstRedMask)) / intensityCropArea;
    
    fprintf('  Baseline intensity (frame 1): %.6f\n', baselineIntensity);
    
    % Process each frame
    for frameIdx = 1:numFrames
        redFrame = double(videoData.red(:,:,frameIdx));
        greenFrame = double(videoData.green(:,:,frameIdx));
        
        %% Metric 1: Avg Red Intensity (baseline subtracted)
        redCrop = redFrame(intCropYmin:intCropYmax, intCropXmin:intCropXmax);
        greenCrop = greenFrame(intCropYmin:intCropYmax, intCropXmin:intCropXmax);
        
        redMaskInt = (redCrop > redThreshold) & (redCrop > greenCrop * config.redPurityRatio);
        
        if sum(redMaskInt(:)) > 0
            frameIntensity = sum(redCrop(redMaskInt)) / intensityCropArea;
        else
            frameIntensity = 0;
        end
        
        metrics.AvgRedIntensity(frameIdx) = frameIntensity - baselineIntensity;
        
        %% Metric 2: Total Red Area (full 360x360 crop)
        redMaskFull = (redFrame > redThreshold) & (redFrame > greenFrame * config.redPurityRatio);
        metrics.TotalRedArea(frameIdx) = sum(redMaskFull(:));
        
        %% Metric 3: Overlap Ratio with Reference GT
        if frameIdx <= refGTData.numFrames
            refRedFrame = double(refGTData.red(:,:,frameIdx));
            refGreenFrame = double(refGTData.green(:,:,frameIdx));
            refRedMask = (refRedFrame > config.redThreshold_GroundTruth) & ...
                        (refRedFrame > refGreenFrame * config.redPurityRatio);
            
            % Calculate overlap
            overlapMask = redMaskFull & refRedMask;
            overlapArea = sum(overlapMask(:));
            
            modelArea = sum(redMaskFull(:));
            gtArea = sum(refRedMask(:));
            
            % Divide by larger area
            if modelArea == 0 && gtArea == 0
                metrics.OverlapRatio(frameIdx) = NaN;
            else
                metrics.OverlapRatio(frameIdx) = overlapArea / max(modelArea, gtArea);
            end
        else
            metrics.OverlapRatio(frameIdx) = NaN;
        end
    end
    
    fprintf('  Extraction complete: %d frames\n', numFrames);
end

function saveMetricsToExcel(allMetrics, filename)
    numVideos = length(allMetrics);
    allTables = [];
    
    for i = 1:numVideos
        videoTable = struct2table(allMetrics(i));
        allTables = [allTables; videoTable];
    end
    
    writetable(allTables, filename, 'Sheet', 'Raw_Metrics');
    fprintf('  Saved %d rows to Excel\n', height(allTables));
end
