classdef ProtocolRunner < handle
    % PROTOCOLRUNNER Main orchestrator for experiment execution
    %
    % This class manages the complete lifecycle of an experiment:
    % - Parsing and validating the protocol file
    % - Initializing hardware and plugins
    % - Executing pretrial, trials, intertrial, and posttrial phases
    % - Logging and data management
    % - Cleanup and error handling
    
    properties (Access = private)
        protocolFilePath        % Path to YAML protocol file
        arenaIP
        protocolData            % Parsed protocol structure
        pluginManager           % PluginManager instance
        arenaController         % Arena hardware controller
        commandExecutor         % CommandExecutor instance
        parser                  % ProtocolParser instance
        logger                  % ExperimentLogger instance
        trialExecutionOrder     % Array of trial metadata structs
        outputDir               % output directory provided by user (defaults to yaml location)
        experimentDir           % the directory where the yaml is saved
        verbose                 % Verbose logging flag
        dryRun                  % Dry run mode (validate only)
        maxAttempts             % Max times to attempt a command before aborting. Default 2
        recoverableErrors
    end
    
    methods (Access = public)
        function self = ProtocolRunner(protocolFilePath, varargin)
            % PROTOCOLRUNNER Constructor
            %
            % Syntax:
            %   runner = ProtocolRunner(protocolFilePath)
            %   runner = ProtocolRunner(protocolFilePath, Name, Value)
            %
            % Input Arguments:
            %   protocolFilePath - Path to YAML protocol file
            %
            % Name-Value Pairs:
            %   'OutputDir' - Base output directory if different than the yaml's directory (default: '')
            %   'Verbose' - Enable verbose logging (default: true)
            %   'DryRun' - Validate without executing (default: false)
            
            % Parse inputs
            p = inputParser;
            addRequired(p, 'protocolFilePath', @ischar);
            addParameter(p, 'arenaIP', '', @ischar);
            addParameter(p, 'OutputDir', '', @ischar);
            addParameter(p, 'Verbose', true, @islogical);
            addParameter(p, 'DryRun', false, @islogical);
            addParameter(p, 'maxAttempts', 2, @(x) isnumeric(x) && x >= 1);
            parse(p, protocolFilePath, varargin{:});
            
            % Store configuration
            self.protocolFilePath = p.Results.protocolFilePath;
            self.outputDir = p.Results.OutputDir;
            self.verbose = p.Results.Verbose;
            self.dryRun = p.Results.DryRun;
            self.arenaIP = p.Results.arenaIP;
            self.maxAttempts = p.Results.maxAttempts;
            self.recoverableErrors = {
                'CommandExecutor:HardwareFailure', ...
                'SerialPlugin:NotConnected', ...
                'SerialPlugin:CriticalFailure'
            };
            
            % Initialize (validation only at construction)
            self.validateEnvironment();
            self.parseProtocol();
            if isempty(self.arenaIP)
                self.arenaIP = self.protocolData.controllerConfig.host;
            end
            if isempty(self.arenaIP)
                error('ProtocolRunner:NoArenaIP', ...
                ['No arena IP address found. Provide one via the ''arenaIP'' argument ' ...
                'or add controller.host to your rig config YAML.']);
            end

            %self.extractPatternMapping();
        end
        
        function run(self)
            % RUN Execute the complete experiment protocol
            %
            % Execution flow:
            %   1. Initialize experiment (hardware, plugins, logging)
            %   2. Generate trial order
            %   3. Execute pretrial phase
            %   4. Execute main trial loop
            %   5. Execute posttrial phase
            %   6. Cleanup and save data
            
            try
                % === Initialization ===
                self.initializeExperiment();
                
                % If dry run, stop here
                if self.dryRun
                    self.logger.log('INFO', 'Dry run complete - protocol is valid');
                    self.cleanup();
                    return;
                end
                
                % === Generate Trial Order ===
                self.generateTrialOrder();
                
                % === Execute Pretrial ===
                self.executePretrialPhase();
                
                % === Execute Main Trials ===
                self.executeMainTrialLoop();
                
                % === Execute Posttrial ===
                self.executePosttrialPhase();
                
                % === Finalize ===
                self.finalizeExperiment();

            catch ME
                self.logger.log('ERROR', sprintf('Experiment failed: %s', ME.message));
                self.cleanup();
                rethrow(ME);
            end
        end
        
        function cleanup(self)
            % Emergency cleanup of all resources
            %
            % Called on error or at end of experiment
            
            fprintf('Performing cleanup...\n');
            
            % Stop arena hardware
            if ~isempty(self.arenaController)
                try
                    self.arenaController.stopDisplay();
                    self.arenaController.close();
                    fprintf('  - Stopping arena hardware\n');
                catch ME
                    fprintf(2, '  - Warning: Could not stop arena: %s\n', ME.message);
                end
            end
            
            % Close all plugins
            if ~isempty(self.pluginManager)
                try
                    self.pluginManager.closeAll();
                    fprintf('  - Closed all plugins\n');
                catch ME
                    fprintf(2, '  - Warning: Could not close plugins: %s\n', ME.message);
                end
            end
            
            % Close logger
            if ~isempty(self.logger)
                try
                    self.logger.close();
                    fprintf('  - Closed log file\n');
                catch ME
                    fprintf(2, '  - Warning: Could not close logger: %s\n', ME.message);
                end
            end
            
            fprintf('Cleanup complete.\n');
        end
    end
    
    methods (Access = private)
        %% ================= Section 1: Initialization =================
        
        function validateEnvironment(self)
            % VALIDATEENVIRONMENT Check MATLAB version and toolboxes
            
            % Check MATLAB version
            v = ver('MATLAB');
            if str2double(v.Version) < 9.0  % R2016a
                warning('MATLAB version %s may not be fully supported', v.Version);
            end
            
            % Check for YAML parser (needs yamlmatlab or similar)
            % TODO: Add check for YAML parsing capability
            
            if self.verbose
                fprintf('Environment validation passed\n');
            end
        end
        
        function parseProtocol(self)
            % Instantiate ProtocolParser to parse yaml file and return
            % experiment data. Resulting data is structured as follows: 
            % self.protocolData is a struct with the following fields: 
            %    - version: the yaml file version
            %    - experimentInfo: a struct with three fields, "name",
            %     "date_created", and "author" 
            %     - arenaConfig: struct with three fields, "num_rows",
            %     "num_cols", and "generation"
            %     - plugins: cell array of structs. Each struct has a
            %     "name" and "type" field plus additional fields depending
            %     on type. Possible types are "serial_device", "class", and
            %     "script"
            %     - experimentStructure: struct with two fields,
            %     "repetitions", and "randomization", which is another
            %     small struct
            %     - pretrialCommands: A cell array of commands, each a
            %     struct with type, name, and other type dependent fields
            %     - blockConditions: a
            %     struct array. So blockConditions(1) is a struct with two
            %     fields, "id", and "commands", a  cell array of structs
            %     - intertrialCommands: cell array of commands for
            %     intertrial
            %     - posttrialCommands: cell array of commands for posttrial
            %     - filepath: path to the yaml file
            
            if self.verbose
                fprintf('Parsing protocol: %s\n', self.protocolFilePath);
            end
            self.parser = ProtocolParser('verbose', self.verbose);

            try
                self.protocolData = self.parser.parse(self.protocolFilePath);
                
            catch ME
                error('Failed to parse protocol file: %s', ME.message);
            end
        end
        
        function initializeExperiment(self)
            % Initialize all components for execution
            
            fprintf('\n=== Initializing Experiment ===\n');
            
            % Get experiment directory - assumes yaml was already saved in
            % experiment directory.
            self.getExperimentDirectory();
            
            % Initialize logger
            self.initializeLogger();
            
            % Log experiment start
            self.logger.log('INFO', '=== EXPERIMENT START ===');
            self.logger.log('INFO', sprintf('Protocol: %s', self.protocolFilePath));
            self.logger.log('INFO', sprintf('Output: %s', self.experimentDir));
            
            % Initialize plugins
            self.initializePlugins();
            
            % Initialize arena hardware
            self.initializeArenaHardware();
            
            % Create command executor
            self.commandExecutor = CommandExecutor(...
                self.arenaController, ...
                self.pluginManager, ...
                self.logger);
            
            self.logger.log('INFO', 'Initialization complete');
            fprintf('=== Initialization Complete ===\n\n');
        end
        
        function getExperimentDirectory(self)
            
            if ~isempty(self.outputDir)
                self.experimentDir = self.outputDir;
            else
                [self.experimentDir, ~] = fileparts(self.protocolFilePath);
            end

        end
        
        function initializeLogger(self)
            % Create experiment logger
            
            logFile = fullfile(self.experimentDir, 'logs', 'experiment.log');
            self.logger = ExperimentLogger(logFile, self.verbose);
        end
        
        function initializePlugins(self)
            % Initialize all plugins defined in protocol
            
            if isempty(self.protocolData.plugins)
                self.logger.log('INFO', 'No plugins defined in protocol');
                self.pluginManager = PluginManager(self.logger, self.experimentDir);
                return;
            end
            
            self.logger.log('INFO', 'Initializing plugins...');
            self.pluginManager = PluginManager(self.logger, self.experimentDir);
            
            plugins = self.protocolData.plugins;
            for i = 1:length(plugins)
                pluginDef = plugins{i};
                
                try
                    self.pluginManager.initializePlugin(pluginDef);
                    self.logger.log('INFO', sprintf('  ✓ Initialized plugin: %s', ...
                                                  pluginDef.name));
                catch ME
                    self.logger.log('ERROR', sprintf('  ✗ Failed to initialize plugin %s: %s', ...
                                                   pluginDef.name, ME.message));
                    error('Plugin initialization failed');
                end
            end
            
            self.logger.log('INFO', sprintf('All %d plugins initialized', length(plugins)));
        end
        
        function initializeArenaHardware(self)
            % Connect to and configure arena
            
            self.logger.log('INFO', 'Initializing arena hardware...');
            
            generation = self.protocolData.arenaConfig.generation;
            numRows = self.protocolData.arenaConfig.num_rows;
            numCols = self.protocolData.arenaConfig.num_cols;
            
            if strcmp(generation, 'G4.1')
                try
                    self.arenaController = PanelsController(self.arenaIP);  % Create actual controller   
                    self.arenaController.open(false);
                catch ME
                    self.logger.log('ERROR', sprintf(' call to create PanelsController object failed.'));
                    error('Call to create PanelsController object failed.');
                end
                % try                 
                %     self.arenaController.open(false);
                % catch ME
                %     self.logger.log('ERROR', sprintf(' attempt to open the controller failed.'));
                %     error('Call to open function in PanelsController failed.');
                % end
                % 
                self.logger.log('INFO', sprintf('  Arena: %s (%dx%d panels)', ...
                                              generation, numRows, numCols));
            else
                error('Unsupported arena generation: %s', generation);
            end
        end
        
        %% ================= Section 2: Trial Order Generation =================
        
        function generateTrialOrder(self)
            % Create trial execution sequence
            
            self.logger.log('INFO', 'Generating trial order...');
            
            % Extract configuration
            conditions = self.protocolData.blockConditions;
            reps = self.protocolData.experimentStructure.repetitions;
            
            % Get randomization settings
            if isfield(self.protocolData.experimentStructure, 'randomization') && ...
                isfield(self.protocolData.experimentStructure.randomization, 'enabled')
                randSettings.enabled = self.protocolData.experimentStructure.randomization.enabled;
            else
                randSettings.enabled = false;
            end
           
              
            % Create base condition list
            numConditions = length(conditions);
            conditionIDs = cell(1, numConditions);
            for i = 1:numConditions
                conditionIDs{i} = conditions(i).id;
            end
            
            % Replicate for repetitions
            totalTrials = ProtocolParser.get_total_trials(self.protocolData);
            totalConditionTrials = length(self.protocolData.blockConditions)*reps;
            self.trialExecutionOrder = struct('trialNumber', {}, ...
                                            'conditionID', {}, ...
                                            'repetition', {}, ...
                                            'blockNumber', {});
            
            trialCounter = 0;
            
            if randSettings.enabled
                randSettings.seed = self.protocolData.experimentStructure.randomization.seed;
                randSettings.method = self.protocolData.experimentStructure.randomization.method;
                % Set random seed if specified
                if ~isempty(randSettings.seed) && ~isnan(randSettings.seed)
                    rng(randSettings.seed);
                    self.logger.log('INFO', sprintf('  Using random seed: %d', randSettings.seed));
                else
                    seed = randi(1e6);
                    rng(seed);
                    self.logger.log('INFO', sprintf('  Generated random seed: %d', seed));
                end
                
                if strcmp(randSettings.method, 'block')
                    % Block randomization: shuffle within each repetition
                    for rep = 1:reps
                        shuffledIndices = randperm(numConditions);
                        for i = 1:numConditions
                            trialCounter = trialCounter + 1;
                            self.trialExecutionOrder(trialCounter).trialNumber = trialCounter;
                            self.trialExecutionOrder(trialCounter).conditionID = ...
                                conditionIDs{shuffledIndices(i)};
                            self.trialExecutionOrder(trialCounter).repetition = rep;
                            self.trialExecutionOrder(trialCounter).blockNumber = rep;
                        end
                    end
                else  % 'trial' method
                    % Trial randomization: shuffle all trials together
                    allConditionIDs = repmat(conditionIDs, 1, reps);
                    allReps = repelem(1:reps, numConditions);
                    shuffledIndices = randperm(totalConditionTrials);
                    
                    for i = 1:totalConditionTrials
                        trialCounter = trialCounter + 1;
                        idx = shuffledIndices(i);
                        self.trialExecutionOrder(trialCounter).trialNumber = trialCounter;
                        self.trialExecutionOrder(trialCounter).conditionID = allConditionIDs{idx};
                        self.trialExecutionOrder(trialCounter).repetition = allReps(idx);
                        self.trialExecutionOrder(trialCounter).blockNumber = NaN;
                    end
                end
            else
                % No randomization: sequential order
                for rep = 1:reps
                    for i = 1:numConditions
                        trialCounter = trialCounter + 1;
                        self.trialExecutionOrder(trialCounter).trialNumber = trialCounter;
                        self.trialExecutionOrder(trialCounter).conditionID = conditionIDs{i};
                        self.trialExecutionOrder(trialCounter).repetition = rep;
                        self.trialExecutionOrder(trialCounter).blockNumber = rep;
                    end
                end
            end
            
            self.logger.log('INFO', sprintf('  Generated %d trials', totalTrials));
            self.logger.log('INFO', sprintf('  %d conditions × %d repetitions', ...
                                          numConditions, reps));
            
            % Log trial order for reproducibility
            self.logger.log('INFO', 'Trial execution order:');
            for i = 1:min(10, length(self.trialExecutionOrder))
                trial = self.trialExecutionOrder(i);
                self.logger.log('INFO', sprintf('    Trial %d: Condition %s (Rep %d)', ...
                                              trial.trialNumber, ...
                                              trial.conditionID, ...
                                              trial.repetition));
            end
            if length(self.trialExecutionOrder) > 10
                self.logger.log('INFO', sprintf('    ... (%d more trials)', ...
                                              length(self.trialExecutionOrder) - 10));
            end
        end
        
        %% ================= Section 3: Execution Phases =================
        
        function executePretrialPhase(self)
            % Execute pretrial commands
            fprintf('\n=== Executing Pretrial ===\n');
            self.executePhase(self.protocolData.pretrialCommands, 'pretrial');
            fprintf('=== Pretrial Complete ===\n\n');
        end
        
        function executeMainTrialLoop(self)
            % Execute all experimental trials
            
            self.logger.log('INFO', '=== MAIN TRIAL LOOP START ===');
            fprintf('\n=== Starting Main Trials ===\n');
            
            numTrials = length(self.trialExecutionOrder);
            
            % Check if intertrial is defined
            hasIntertrial = isfield(self.protocolData, 'intertrialCommands') && ...
                           ~isempty(self.protocolData.intertrialCommands);
            
            for trialIdx = 1:numTrials
                trial = self.trialExecutionOrder(trialIdx);
                
                % Log trial start
                self.logger.log('INFO', sprintf('--- Trial %d/%d: Condition %s (Rep %d) ---', ...
                                              trial.trialNumber, numTrials, ...
                                              trial.conditionID, trial.repetition));
                fprintf('Trial %d/%d: %s\n', trial.trialNumber, numTrials, trial.conditionID);
                
                % Find condition definition
                conditionDef = self.findConditionByID(trial.conditionID);
                
                % Execute trial commands
                self.executePhase(conditionDef.commands, ...
                    sprintf('trial %d (condition %s)', trial.trialNumber, trial.conditionID));
                
                % Execute intertrial (if not last trial and intertrial exists)
                if trialIdx < numTrials && hasIntertrial
                    self.executePhase(self.protocolData.intertrialCommands, 'intertrial');
                end
            end
            
            self.logger.log('INFO', '=== MAIN TRIAL LOOP COMPLETE ===');
            fprintf('\n=== All Trials Complete ===\n\n');
        end
        
        function conditionDef = findConditionByID(self, conditionID)
            % Find condition definition by ID
            
            conditions = self.protocolData.blockConditions;
            for i = 1:length(conditions)
                if strcmp(conditions(i).id, conditionID)
                    conditionDef = conditions(i);
                    return;
                end
            end
            error('Condition not found: %s', conditionID);
        end
        
        function executePosttrialPhase(self)
            % Execute posttrial commands
            fprintf('\n=== Executing Posttrial ===\n');
            self.executePhase(self.protocolData.posttrialCommands, 'posttrial');
            fprintf('=== Posttrial Complete ===\n\n');
        end

        function executePhase(self, commands, phaseName)
            % Execute a list of commands with retry logic on recoverable errors
            %
            % Input Arguments:
            %   commands  - Cell array of command structs
            %   phaseName - String used in log messages and user prompts
            %               e.g. 'pretrial', 'intertrial', 'trial 3 (condition A)'

            if isempty(commands)
                self.logger.log('INFO', sprintf('No commands defined for %s, skipping', phaseName));
                return;
            end

            self.logger.log('INFO', sprintf('=== %s START ===', upper(phaseName)));
            startTime = tic;

            attempt = 1;
            success = false;
            while ~success && attempt <= self.maxAttempts
                try
                    for i = 1:length(commands)
                        self.commandExecutor.execute(commands{i});
                    end
                    success = true;
                catch ME
                    self.logger.log('ERROR', sprintf('%s failed on attempt %d: %s', ...
                        phaseName, attempt, ME.message));
                    if attempt < self.maxAttempts && ismember(ME.identifier, self.recoverableErrors)
                        attempt = attempt + 1;
                        switch ME.identifier
                            case 'CommandExecutor:HardwareFailure'
                                msg = sprintf(['\n*** Arena hardware failure during %s ***\n' ...
                                    'Command returned no confirmation from the arena.\n' ...
                                    'Please restart the arena controller and wait for it to come back online.\n' ...
                                    'Press Enter when ready to retry...'], phaseName);
                            case {'SerialPlugin:NotConnected', 'SerialPlugin:CriticalFailure'}
                                msg = sprintf(['\n*** Serial device failure during %s ***\n' ...
                                    'A serial device lost its connection.\n' ...
                                    'Please check the device connection and press Enter to retry...'], phaseName);
                        end
                        input(msg);
                    else
                        rethrow(ME);
                    end
                end
            end

            duration = toc(startTime);
            self.logger.log('INFO', sprintf('%s completed in %.2f seconds', phaseName, duration));
        end
        
        function finalizeExperiment(self)
            % Save data and close resources
            
            self.logger.log('INFO', 'Finalizing experiment...');
            
            % Save trial execution order
            trialOrder = self.trialExecutionOrder;
            if ~exist(fullfile(self.experimentDir, 'data'),'dir')
                mkdir(fullfile(self.experimentDir, 'data'));
            end
            save(fullfile(self.experimentDir, 'data', 'trial_order.mat'), 'trialOrder');
            
            % TODO: Save any additional data collected during experiment
            
            % Generate summary
            self.generateExperimentSummary();
            
            % Clean shutdown
            self.cleanup();
            
%            self.logger.log('INFO', '=== EXPERIMENT COMPLETE ===');
        end
        
        function generateExperimentSummary(self)
            % Create experiment summary file
            
            summaryFile = fullfile(self.experimentDir, 'summary.txt');
            fid = fopen(summaryFile, 'w');
            
            fprintf(fid, 'EXPERIMENT SUMMARY\n');
            fprintf(fid, '==================\n\n');
            fprintf(fid, 'Experiment: %s\n', self.protocolData.experimentInfo.name);
            fprintf(fid, 'Date: %s\n', datestr(now));
            fprintf(fid, 'Protocol: %s\n\n', self.protocolFilePath);
            
            fprintf(fid, 'Arena Configuration:\n');
            fprintf(fid, '  Generation: %s\n', self.protocolData.arenaConfig.generation);
            fprintf(fid, '  Dimensions: %dx%d panels\n', ...
                    self.protocolData.arenaConfig.num_rows, ...
                    self.protocolData.arenaConfig.num_cols);
            fprintf(fid, '\n');
            
            fprintf(fid, 'Experimental Design:\n');
            fprintf(fid, '  Conditions: %d\n', length(self.protocolData.blockConditions));
            fprintf(fid, '  Repetitions: %d\n', self.protocolData.experimentStructure.repetitions);
            fprintf(fid, '  Total Trials: %d\n', ProtocolParser.get_total_trials(self.protocolData));
            fprintf(fid, '\n');
            
            % TODO: Add more summary statistics
            
            fclose(fid);
            
            self.logger.log('INFO', sprintf('Summary saved to: %s', summaryFile));
        end
    end
end
