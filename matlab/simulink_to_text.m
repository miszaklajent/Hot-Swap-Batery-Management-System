function simulink_to_text(modelName, outputFile)
% SIMULINK_TO_TEXT Exports Simulink and Simscape model architecture,
% block parameters, settings, state targets, initial conditions, 
% MATLAB functions, Stateflow logic, and solver settings to a structured text file.
%
% Usage:
%   simulink_to_text()                   % Auto-detects model (e.g. open system or 'dual_module')
%   simulink_to_text('dual_module')      % Exports 'dual_module' to 'dual_module_description.txt'
%   simulink_to_text('single_module', 'custom_output.txt')

    %% Resolve Model Name
    if nargin < 1 || isempty(modelName)
        loadedModels = find_system('SearchDepth', 0);
        loadedModels(strcmp(loadedModels, 'simulink')) = []; % exclude Simulink root library
        if ~isempty(loadedModels)
            modelName = loadedModels{1};
        elseif exist('dual_module.slx', 'file')
            modelName = 'dual_module';
        else
            modelName = 'dual_module';
        end
    end
    modelName = 'dual_module';
    
    % Strip .slx or directory path if provided
    [~, modelName, ~] = fileparts(modelName);
    
    %% Resolve Output File
    if nargin < 2 || isempty(outputFile)
        outputFile = [modelName '_description.txt'];
    end
    
    %% Load Model into Memory
    if ~bdIsLoaded(modelName)
        load_system(modelName);
    end
    
    %% Open File for Writing
    fid = fopen(outputFile, 'w');
    if fid == -1
        error('Could not create output file: %s', outputFile);
    end
    
    fprintf(fid, '==================================================\n');
    fprintf(fid, 'SIMULINK MODEL STRUCTURE, SETTINGS & CODE DUMP\n');
    fprintf(fid, 'Model Name: %s\n', modelName);
    fprintf(fid, 'Generated on: %s\n', datestr(now));
    fprintf(fid, '==================================================\n\n');
    
    %% 1. DUMP MODEL HIERARCHY, SETTINGS & STATES
    fprintf(fid, '--- 1. SYSTEM BLOCK HIERARCHY, SETTINGS & STATES ---\n');
    allBlocks = find_system(modelName, 'IncludeCommented', 'off', 'Type', 'block');
    
    for i = 1:length(allBlocks)
        block = allBlocks{i};
        blockType = get_param(block, 'BlockType');
        
        depth = length(strfind(block, '/'));
        indent = repmat('  ', 1, depth);
        
        % Normalize block name removing internal newlines
        cleanBlock = regexprep(block, '[\r\n]+', ' ');
        
        % Additional metadata for Simscape blocks
        blockExtra = '';
        if strcmp(blockType, 'SimscapeBlock')
            try
                cPath = get_param(block, 'ComponentPath');
                if ~isempty(cPath)
                    blockExtra = sprintf(' (Component: %s)', cPath);
                end
            catch
            end
        end
        
        fprintf(fid, '%s- [%s] %s%s\n', indent, blockType, cleanBlock, blockExtra);
        
        % Extract block settings, parameters and states
        paramLines = extract_block_settings(block, blockType);
        if ~isempty(paramLines)
            settingIndent = [indent '    * '];
            valIndent = [indent '        '];
            fprintf(fid, '%sSettings & States:\n', settingIndent);
            for pIdx = 1:length(paramLines)
                fprintf(fid, '%s%s\n', valIndent, paramLines{pIdx});
            end
        end
    end
    fprintf(fid, '\n');
    
    %% 2. DUMP INTERFACE PORTS
    fprintf(fid, '--- 2. ROOT LEVEL PORTS ---\n');
    inports = find_system(modelName, 'SearchDepth', 1, 'BlockType', 'Inport');
    outports = find_system(modelName, 'SearchDepth', 1, 'BlockType', 'Outport');
    
    fprintf(fid, 'Root Inports:\n');
    if isempty(inports)
        fprintf(fid, '  (none)\n');
    else
        for i = 1:length(inports)
            pName = regexprep(get_param(inports{i}, 'Name'), '[\r\n]+', ' ');
            pNum = get_param(inports{i}, 'Port');
            fprintf(fid, '  * %s (Port %s)\n', pName, pNum);
        end
    end
    
    fprintf(fid, 'Root Outports:\n');
    if isempty(outports)
        fprintf(fid, '  (none)\n');
    else
        for i = 1:length(outports)
            pName = regexprep(get_param(outports{i}, 'Name'), '[\r\n]+', ' ');
            pNum = get_param(outports{i}, 'Port');
            fprintf(fid, '  * %s (Port %s)\n', pName, pNum);
        end
    end
    fprintf(fid, '\n');

    %% 3. EXTRACT INTEGRATED MATLAB FUNCTIONS
    fprintf(fid, '--- 3. EMBEDDED MATLAB FUNCTION BLOCKS ---\n');
    try
        rt = sfroot;
        mFunctions = rt.find('-isa', 'Stateflow.EMFunction', '-and', 'Machine', modelName);
        if isempty(mFunctions)
            fprintf(fid, 'No integrated MATLAB Function Blocks found.\n\n');
        else
            for i = 1:length(mFunctions)
                func = mFunctions(i);
                cleanPath = regexprep(func.Path, '[\r\n]+', ' ');
                fprintf(fid, '==================================================\n');
                fprintf(fid, 'MATLAB FUNCTION: %s\n', cleanPath);
                fprintf(fid, '==================================================\n');
                fprintf(fid, '%s\n\n', func.Script);
            end
        end
    catch ME
        fprintf(fid, 'Could not query Stateflow/MATLAB functions: %s\n\n', ME.message);
    end
    
    %% 4. EXTRACT STATEFLOW CHARTS
    fprintf(fid, '--- 4. STATEFLOW CHARTS & STATE LOGIC ---\n');
    try
        rt = sfroot;
        charts = rt.find('-isa', 'Stateflow.Chart', '-and', 'Machine', modelName);
        if isempty(charts)
            fprintf(fid, 'No Stateflow Charts found.\n\n');
        else
            for i = 1:length(charts)
                chart = charts(i);
                cleanPath = regexprep(chart.Path, '[\r\n]+', ' ');
                fprintf(fid, 'CHART: %s\n', cleanPath);
                states = chart.find('-isa', 'Stateflow.State');
                for j = 1:length(states)
                    fprintf(fid, '  State: %s\n', states(j).Name);
                    if ~isempty(states(j).LabelString)
                        fprintf(fid, '    Execution Code:\n%s\n', states(j).LabelString);
                    end
                end
                fprintf(fid, '\n');
            end
        end
    catch ME
        fprintf(fid, 'Could not query Stateflow charts: %s\n\n', ME.message);
    end
    
    %% 5. MODEL CONFIGURATION & SOLVER SETTINGS
    fprintf(fid, '--- 5. MODEL SIMULATION & SOLVER SETTINGS ---\n');
    solverParams = {'SolverType', 'Solver', 'SolverName', 'StartTime', 'StopTime', ...
                    'FixedStep', 'MaxStep', 'MinStep', 'RelTol', 'AbsTol', ...
                    'ZeroCrossControl', 'SimscapeLocalSolverGroupChoice', ...
                    'SimscapeUseLocalSolver', 'SimscapeLocalSolverChoice'};
    for sIdx = 1:length(solverParams)
        sParam = solverParams{sIdx};
        try
            sVal = get_param(modelName, sParam);
            if ~isempty(sVal)
                fprintf(fid, '  %-30s = %s\n', sParam, string(sVal));
            end
        catch
        end
    end
    fprintf(fid, '\n');
    
    fclose(fid);
    fprintf('Success! Clean text file saved to: %s\n', outputFile);
end

%% ========================================================================
% HELPER FUNCTIONS
% ========================================================================

function paramLines = extract_block_settings(b, bType)
    paramLines = {};
    isMasked = hasmask(b);
    
    % Common ignore list for purely visual, display, or internal boilerplate
    ignoreList = {'IconDisplay', 'IconShape', 'LockScale', 'RndMeth', ...
                  'SaturateOnIntegerOverflow', 'SampleTimeType', ...
                  'SignalName', 'SignalObject', 'StorageClass', ...
                  'VectorParams1D', 'DisplayOption', 'Inputs1D', ...
                  'PortDimensions', 'Interpolate', 'FramePeriod', ...
                  'OutMin', 'OutMax', 'MaximizeAxes', 'AxesScaling', ...
                  'AxesScalingNumUpdates', 'TimeSpanOverrunAction', ...
                  'TimeUnits', 'TimeDisplayOffset', 'TimeAxisLabels', ...
                  'ShowTimeAxisLabel', 'ActiveDisplayString', ...
                  'OpenAtSimulationStart', 'DisplayFullPath', ...
                  'FrameBasedProcessingString', 'ContentPreviewEnabled'};
    
    % --- 1. Unmasked SubSystems ---
    if strcmp(bType, 'SubSystem') && isMasked == 0
        try
            atomic = get_param(b, 'TreatAsAtomicUnit');
            if strcmp(atomic, 'on')
                paramLines{end+1} = 'TreatAsAtomicUnit = on';
            end
        catch
        end
        return;
    end
    
    % --- 2. Simscape Blocks ---
    if strcmp(bType, 'SimscapeBlock')
        paramLines = extract_simscape_settings(b);
        return;
    end
    
    % --- 3. Masked Blocks (Subsystems or primitive masked blocks) ---
    if isMasked > 0
        try
            maskNames = get_param(b, 'MaskNames');
            maskValues = get_param(b, 'MaskValues');
            if ~isempty(maskNames)
                for j = 1:length(maskNames)
                    pName = maskNames{j};
                    pVal = maskValues{j};
                    
                    if ismember(pName, ignoreList)
                        continue;
                    end
                    
                    % Skip internal mask/RTW/variant plumbing
                    if isempty(pVal) || strcmp(pVal, '[]') || strcmp(pVal, '''''')
                        continue;
                    end
                    if contains(pName, 'RTW') || contains(pName, 'Variant')
                        continue;
                    end
                    
                    % Skip inherited data type boilerplate
                    if endsWith(pName, 'DataTypeStr') && startsWith(pVal, 'Inherit:')
                        continue;
                    end
                    
                    valStr = clean_val_str(pVal);
                    
                    % Identify initial conditions or states
                    if is_state_param(pName)
                        paramLines{end+1} = sprintf('%s [State/IC] = %s', pName, valStr);
                    else
                        paramLines{end+1} = sprintf('%s = %s', pName, valStr);
                    end
                end
            end
        catch
        end
        
        % If mask parameters were found, return them
        if ~isempty(paramLines)
            return;
        end
    end
    
    % --- 4. Standard Simulink Blocks ---
    dp = get_param(b, 'DialogParameters');
    if ~isempty(dp)
        pNames = fieldnames(dp);
                  
        for j = 1:length(pNames)
            p = pNames{j};
            if ismember(p, ignoreList)
                continue;
            end
            
            try
                val = get_param(b, p);
                valStr = clean_val_str(val);
                if isempty(valStr) || strcmp(valStr, '[]') || strcmp(valStr, '''''')
                    continue;
                end
                
                % Skip default unconfigured inherited data types
                if endsWith(p, 'DataTypeStr') && startsWith(valStr, 'Inherit:')
                    continue;
                end
                
                % Check if this is an initial condition or state
                if is_state_param(p)
                    paramLines{end+1} = sprintf('%s [State/IC] = %s', p, valStr);
                else
                    paramLines{end+1} = sprintf('%s = %s', p, valStr);
                end
            catch
            end
        end
    end
end

function lines = extract_simscape_settings(b)
    lines = {};
    dp = get_param(b, 'DialogParameters');
    if isempty(dp)
        return;
    end
    fn = fieldnames(dp);
    
    for i = 1:length(fn)
        p = fn{i};
        
        % Skip companion helper fields
        if endsWith(p, '_unit') || endsWith(p, '_conf') || endsWith(p, '_specify') || ...
           endsWith(p, '_priority') || endsWith(p, '_nominal_specify') || ...
           endsWith(p, '_nominal_value') || endsWith(p, '_nominal_unit')
            continue;
        end
        
        try
            val = get_param(b, p);
            valStr = clean_val_str(val);
            if isempty(valStr) || strcmp(valStr, '[]') || strcmp(valStr, '''''')
                continue;
            end
            
            % Read companion unit if present
            unitStr = '';
            if isfield(dp, [p '_unit'])
                u = get_param(b, [p '_unit']);
                if ~isempty(u) && ~strcmp(u, '1')
                    unitStr = [' ' char(u)];
                end
            end
            
            % Read companion state target info (e.g. initial voltage, current, charge)
            stateStr = '';
            if isfield(dp, [p '_specify'])
                spec = get_param(b, [p '_specify']);
                prio = '';
                if isfield(dp, [p '_priority'])
                    prio = get_param(b, [p '_priority']);
                end
                % Mark state target if priority is set or specify is on
                if strcmp(spec, 'on') || (~isempty(prio) && ~strcmp(prio, 'None'))
                    stateStr = sprintf(' [State Target: specify=%s, priority=%s]', spec, prio);
                end
            end
            
            lines{end+1} = sprintf('%s = %s%s%s', p, valStr, unitStr, stateStr);
        catch
        end
    end
end

function tf = is_state_param(p)
    stateKeywords = {'InitialCondition', 'InitialStates', 'X0', 'InitialOutput', ...
                     'InitialConditionSetting', 'InitialConditionForIntegrator', ...
                     'InitialConditionForFilter', 'InitialTriggerSignalState'};
    tf = ismember(p, stateKeywords);
end

function str = clean_val_str(val)
    if ischar(val) || isstring(val)
        str = strtrim(string(val));
    elseif isnumeric(val) || islogical(val)
        str = mat2str(val);
    else
        str = string(val);
    end
    
    % Compact single-line display
    str = regexprep(str, '[\r\n]+', ' ');
    
    % Trim excessively long arrays or tables
    if strlength(str) > 100
        str = extractBefore(str, 97) + "...";
    end
end
