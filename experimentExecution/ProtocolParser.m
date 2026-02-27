classdef ProtocolParser < handle
    % Parse  and validate YAML protocol files
    %
    % This class reads YAML protocol files and extracts all sections into
    % a structured format. It validates the protocol structure and provides
    % detailed error messages for any issues.
    %
    % Example usage:
    %   parser = ProtocolParser('verbose', true);
    %   protocol = parser.parse('./protocols/my_experiment.yaml');
    %   
    %   % Access parsed data:
    %   experimentName = protocol.experimentInfo.name;
    %   numConditions = length(protocol.blockConditions);
    
    properties (Access = private)
        verbose         % Whether to print parsing progress
        filepath        % Path to protocol file being parsed
    end

    properties (Constant)
        SUPPORTED_VERSIONS = [2];
        REQUIRED_YAML_SECTIONS = {'experiment_info', 'rig', 'experiment_structure', 'block'};
        REQUIRED_ARENA_FIELDS = {'num_rows', 'num_cols', 'generation'};
        SUPPORTED_GENERATIONS = {'G3', 'G4', 'G4.1', 'G6'};
        SUPPORTED_RANDOMIZATION_METHODS = {'block'};
        SUPPORTED_PLUGIN_TYPES = {'serial_device', 'class', 'script'};
    end
    
    methods (Access = public)
        function self = ProtocolParser(varargin)
            % Constructor
            %
            % Optional Name-Value Arguments:
            %   'verbose' - Print parsing progress (default: false)
            %
            % Example:
            %   parser = ProtocolParser('verbose', true);
            
            % Parse input arguments
            p = inputParser;
            addParameter(p, 'verbose', false, @islogical);
            parse(p, varargin{:});
            
            self.verbose = p.Results.verbose;
        end
        
        function protocol = parse(self, filepath)
            % Parse a Version 2 YAML protocol file
            %
            % Input Arguments:
            %   filepath - Path to YAML protocol file (version 2)
            %
            % Returns:
            %   protocol - Struct containing all parsed protocol data.
            %              Fields:
            %     .version             - Protocol version number (2)
            %     .filepath            - Path to the protocol YAML file
            %     .experimentInfo      - Struct: name, date_created, author,
            %                           pattern_library
            %     .rigConfig           - Full resolved rig config struct
            %                           (from load_rig_config). Contains:
            %                             .name, .description
            %                             .arena    - arena fields (see below)
            %                             .derived  - computed arena properties
            %                             .controller.host / .port
            %                             .plugins  - rig-level plugin hardware
            %                                         configs, keyed by name
            %     .arenaConfig         - Shortcut to rigConfig.arena. Fields:
            %                             .generation, .num_rows, .num_cols,
            %                             .column_order, .orientation,
            %                             .angle_offset_deg,
            %                             .columns_installed (null = all)
            %     .derivedConfig       - Shortcut to rigConfig.derived. Fields:
            %                             .pixels_per_panel, .total_pixels_x,
            %                             .total_pixels_y, .panel_width_mm,
            %                             .inner_radius_mm,
            %                             .num_columns_installed,
            %                             .azimuth_coverage_deg
            %     .controllerConfig    - Shortcut to rigConfig.controller.
            %                           Fields: .host (IP string), .port
            %     .rigFilepath         - Resolved path to the rig YAML file
            %     .arenaFilepath       - Resolved path to the arena YAML file
            %     .plugins             - Cell array of plugin definition structs.
            %                           Each struct has .name, .type, and
            %                           type-specific fields (.matlab.class,
            %                           .script_path, etc.). The .config field
            %                           is populated by merging the rig YAML's
            %                           plugin hardware settings with any config
            %                           defined in the experiment YAML
            %                           (experiment values win on conflict).
            %     .experimentStructure - Struct: .repetitions, .randomization
            %     .pretrialCommands    - Cell array of command structs, or []
            %     .blockConditions     - Struct array. Each element has .id
            %                           and .commands (cell array of structs)
            %     .intertrialCommands  - Cell array of command structs, or []
            %     .posttrialCommands   - Cell array of command structs, or []
            %
            % Example:
            %   protocol = parser.parse('./experiments/exp001/protocol.yaml');
            %   fprintf('Rig: %s\n', protocol.rigConfig.name);
            %   fprintf('Controller IP: %s\n', protocol.controllerConfig.host);
            
            self.filepath = filepath;
            
            if self.verbose
                fprintf('Parsing protocol: %s\n', filepath);
            end
            
            % Check file exists
            if ~isfile(filepath)
                error('ProtocolParser:FileNotFound', ...
                      'Protocol file not found: %s', filepath);
            end
            
            try
                % Read YAML file using yamlread found in yamlSupport
                rawData = yamlread(filepath);
                
                if self.verbose
                    fprintf('  YAML file loaded successfully\n');
                end
                
                % Validate protocol structure
                self.validateProtocol(rawData);
                
                % Extract all sections into structured format
                protocol = self.extractProtocol(rawData);
                
                % Store filepath in protocol for reference
                protocol.filepath = filepath;
                
                if self.verbose
                    fprintf('  Protocol parsed successfully\n');
                    self.printProtocolSummary(protocol);
                end
                
            catch ME
                % Provide context for parsing errors
                if strcmp(ME.identifier, 'ProtocolParser:ValidationError')
                    rethrow(ME);
                else
                    error('ProtocolParser:ParseError', ...
                          'Failed to parse protocol file: %s\nError: %s', ...
                          filepath, ME.message);
                end
            end
        end
    

        %% Getters to be used by other classes
    
        function output = get_supported_versions(self)
            output = self.SUPPORTED_VERSIONS;
        end


    end
    
    methods (Access = private)

        function validateProtocol(self, data)
            % Check that protocol has required structure
            %
            % Input Arguments:
            %   data - Raw parsed YAML data

            % Check version field exists
            if ~isfield(data, 'version')
                self.throwValidationError('Protocol missing required "version" field');
            end

            % Check version is supported
            if ~ismember(data.version, self.SUPPORTED_VERSIONS)
                self.throwValidationError(['Unsupported protocol version: %d\n' ...
                    'Only version 2 is supported.\n' ...
                    'If this is a version 1 protocol, migrate it by replacing\n' ...
                    '"arena_info" with a rig reference: rig: "path/to/rig.yaml"'], ...
                    data.version);
            end

            % Check all required top-level sections exist
            for i = 1:length(self.REQUIRED_YAML_SECTIONS)
                section = self.REQUIRED_YAML_SECTIONS{i};
                if ~isfield(data, section)
                    self.throwValidationError('Protocol missing required "%s" section', section);
                end
            end

            % Validate experiment_info
            self.validateExperimentInfo(data.experiment_info);

            % Validate rig reference (resolves rig and arena files)
            self.validateRigReference(data.rig);

            % Validate experiment_structure
            self.validateExperimentStructure(data.experiment_structure);

            % Validate plugins (if present)
            if isfield(data, 'plugins')
                self.validatePlugins(data.plugins);
            end

            % Validate trial sections
            self.validateTrialSections(data);

            if self.verbose
                fprintf('  Protocol validation passed\n');
            end
        end
        
        function validateExperimentInfo(self, experimentInfo)
            % Validate experiment_info section
            
            if ~isfield(experimentInfo, 'name')
                self.throwValidationError('experiment_info missing required "name" field');
            end
            
            if ~ischar(experimentInfo.name) && ~isstring(experimentInfo.name)
                self.throwValidationError('experiment_info.name must be a string');
            end
        end
        
        function validateSerialPlugin(self, plugin)
            % Validate serial_device plugin

            requiredFields = {'baudrate', 'commands'};
            for i = 1:length(requiredFields)
                field = requiredFields{i};
                if ~isfield(plugin, field)
                    self.throwValidationError('Serial plugin "%s" missing required "%s" field', ...
                                             plugin.name, field);
                end
            end

            % Must have at least one port field (generic, Windows, or POSIX)
            if ~isfield(plugin, 'port') && ...
               ~isfield(plugin, 'port_windows') && ...
               ~isfield(plugin, 'port_posix')
                self.throwValidationError(['Serial plugin "%s" must define at least one port field ' ...
                    '(port, port_windows, or port_posix)'], plugin.name);
            end
        end

        function validateRigReference(self, rigRef)
            % Validate rig reference (Version 2 format)
            %
            % The rig field should be a path to a rig YAML file which
            % contains the arena configuration and controller settings.

            if ~ischar(rigRef) && ~isstring(rigRef)
                self.throwValidationError(['rig field must be a file path string.\n' ...
                    'Example: rig: "configs/rigs/my_rig.yaml"']);
            end

            % Resolve path relative to protocol file
            rig_path = self.resolveRelativePath(rigRef);

            if ~isfile(rig_path)
                self.throwValidationError('Rig config file not found: %s', rig_path);
            end

            % Load and validate the rig config
            try
                rig_config = load_rig_config(rig_path);

                % Validate that rig has resolved arena
                if ~isfield(rig_config, 'arena')
                    self.throwValidationError('Rig config missing arena configuration');
                end

                % Validate arena fields
                arena = rig_config.arena;
                for i = 1:length(self.REQUIRED_ARENA_FIELDS)
                    field = self.REQUIRED_ARENA_FIELDS{i};
                    if ~isfield(arena, field)
                        self.throwValidationError('Rig arena missing required "%s" field', field);
                    end
                end

                % Validate generation
                if strcmpi(arena.generation, 'G5')
                    self.throwValidationError('G5 is deprecated. Use G6 for 20x20 pixel panels.');
                end
                if ~ismember(arena.generation, self.SUPPORTED_GENERATIONS)
                    self.throwValidationError('arena.generation must be one of: %s', ...
                                             strjoin(self.SUPPORTED_GENERATIONS, ', '));
                end

                if self.verbose
                    fprintf('  Rig config loaded: %s\n', rig_config.name);
                    fprintf('  Arena: %s (%dx%d)\n', arena.generation, ...
                            arena.num_rows, arena.num_cols);
                end

            catch ME
                self.throwValidationError('Failed to load rig config: %s\nError: %s', ...
                                         rig_path, ME.message);
            end
        end

        function resolved = resolveRelativePath(self, rel_path)
            % Resolve a relative path from the protocol file location

            [protocol_dir, ~, ~] = fileparts(self.filepath);

            % Handle absolute paths
            if (ispc() && length(rel_path) >= 2 && rel_path(2) == ':') || ...
               (~ispc() && startsWith(rel_path, '/'))
                resolved = rel_path;
            else
                resolved = fullfile(protocol_dir, rel_path);
            end

            % Normalize path
            resolved = char(java.io.File(resolved).getCanonicalPath());
        end
        
        function validateExperimentStructure(self, experimentStructure)
            % Validate experiment_structure section
            
            if ~isfield(experimentStructure, 'repetitions')
                self.throwValidationError('experiment_structure missing required "repetitions" field');
            end
            
            if ~isnumeric(experimentStructure.repetitions) || ...
               experimentStructure.repetitions < 1
                self.throwValidationError('experiment_structure.repetitions must be a positive integer');
            end
            
            % Validate randomization (if present)
            if isfield(experimentStructure, 'randomization')
                rand = experimentStructure.randomization;
                
                if isfield(rand, 'enabled') && rand.enabled
                    if ~isfield(rand, 'method')
                        self.throwValidationError('randomization.method required when randomization enabled');
                    end
                    
                    if ~ismember(rand.method, self.SUPPORTED_RANDOMIZATION_METHODS)
                        self.throwValidationError('randomization.method not supported');
                    end
                end
            end
        end
        
        function validatePlugins(self, plugins)
            % Validate plugins section
            
            if isstruct(plugins) && ~iscell(plugins)
                plugins = arrayfun(@(s) s, plugins, 'UniformOutput', false);
            end
            
            if ~iscell(plugins)
                self.throwValidationError('plugins must be a list (cell array)');
            end
            
            for i = 1:length(plugins)
                plugin = plugins{i};
                
                % Check required fields
                if ~isfield(plugin, 'name')
                    self.throwValidationError('Plugin %d missing required "name" field', i);
                end
                
                if ~isfield(plugin, 'type')
                    self.throwValidationError('Plugin "%s" missing required "type" field', ...
                                             plugin.name);
                end
                
                % Validate plugin type
                if ~ismember(plugin.type, self.SUPPORTED_PLUGIN_TYPES)
                    self.throwValidationError('Plugin "%s" has invalid type "%s" (must be: %s)', ...
                                             plugin.name, plugin.type, ...
                                             strjoin(self.SUPPORTED_PLUGIN_TYPES, ', '));
                end
                
                % Type-specific validation
                switch plugin.type
                    case 'serial_device'
                        self.validateSerialPlugin(plugin);
                    case 'class'
                        self.validateClassPlugin(plugin);
                    case 'script'
                        self.validateScriptPlugin(plugin);
                end
            end
        end
        
        function validateClassPlugin(self, plugin)
            % Validate class plugin
            
            % Must have matlab and/or python implementation
            if ~isfield(plugin, 'matlab') && ~isfield(plugin, 'python')
                self.throwValidationError('Class plugin "%s" must define matlab and/or python implementation', ...
                                         plugin.name);
            end
            
            % Validate matlab implementation
            if isfield(plugin, 'matlab')
                if ~isfield(plugin.matlab, 'class')
                    self.throwValidationError('Class plugin "%s" matlab implementation missing "class" field', ...
                                             plugin.name);
                end
            end
            
            % Validate python implementation
            if isfield(plugin, 'python')
                pythonRequired = {'module', 'class'};
                for i = 1:length(pythonRequired)
                    field = pythonRequired{i};
                    if ~isfield(plugin.python, field)
                        self.throwValidationError('Class plugin "%s" python implementation missing "%s" field', ...
                                                 plugin.name, field);
                    end
                end
            end
        end
        
        function validateScriptPlugin(self, plugin)
            % Validate script plugin
            
            if ~isfield(plugin, 'script_path')
                self.throwValidationError('Script plugin "%s" missing required "script_path" field', ...
                                         plugin.name);
            end
        end
        
        function validateTrialSections(self, data)
            % Validate pretrial, block, intertrial, posttrial
            
            % Block is required and must have conditions
            if ~isfield(data, 'block')
                self.throwValidationError('Protocol missing required "block" section');
            end
            
            if ~isfield(data.block, 'conditions')
                self.throwValidationError('block section missing required "conditions" field');
            end
            
            if ~isstruct(data.block.conditions) || isempty(data.block.conditions)
                self.throwValidationError('block.conditions must be a non-empty list');
            end
            
            % Validate each condition
            for i = 1:length(data.block.conditions)
                condition = data.block.conditions(i);
                
                if ~isfield(condition, 'id')
                    self.throwValidationError('Block condition %d missing required "id" field', i);
                end
                
                if ~isfield(condition, 'commands')
                    self.throwValidationError('Block condition "%s" missing required "commands" field', ...
                                             condition.id);
                end
                
                if isstruct(condition.commands) && ~iscell(condition.commands)
                    condition.commands = arrayfun(@(s) s, condition.commands, 'UniformOutput', false);
                end
                if ~iscell(condition.commands)
                    self.throwValidationError('Block condition "%s" commands must be a list', ...
                                             condition.id);
                end
                
                % Validate commands in condition
                self.validateCommands(condition.commands, ...
                                     sprintf('Block condition "%s"', condition.id));
            end
            
            % Validate optional sections (if included)
            optionalSections = {'pretrial', 'intertrial', 'posttrial'};
            for i = 1:length(optionalSections)
                section = optionalSections{i};
                if isfield(data, section)
                    self.validateOptionalSection(data.(section), section);
                end
            end
        end
        
        function validateOptionalSection(self, section, sectionName)
            % Validate pretrial/intertrial/posttrial
            
            if ~isfield(section, 'include')
                self.throwValidationError('%s section missing required "include" field', sectionName);
            end
            
            if ~islogical(section.include) && ~isnumeric(section.include)
                self.throwValidationError('%s.include must be true or false', sectionName);
            end
            
            % If included, must have commands
            if section.include
                if ~isfield(section, 'commands')
                    self.throwValidationError('%s section has include=true but missing "commands" field', ...
                                             sectionName);
                end
                
                if isstruct(section.commands) && ~iscell(section.commands)
                    section.commands = arrayfun(@(s) s, section.commands, 'UniformOutput', false);
                end
                if ~iscell(section.commands)
                    self.throwValidationError('%s.commands must be a list', sectionName);
                end
                
                % Validate commands
                self.validateCommands(section.commands, sectionName);
            end
        end
        
        function validateCommands(self, commands, context)
            % Validate a list of commands
            %
            % Input Arguments:
            %   commands - Cell array of command structs
            %   context - String describing where these commands are from
            
            for i = 1:length(commands)
                command = commands{i};
                
                % Every command must have a type
                if ~isfield(command, 'type')
                    self.throwValidationError('%s command %d missing required "type" field', ...
                                             context, i);
                end
                
                % Validate based on type
                switch command.type
                    case 'controller'
                        self.validateControllerCommand(command, context, i);
                    case 'wait'
                        self.validateWaitCommand(command, context, i);
                    case 'plugin'
                        self.validatePluginCommand(command, context, i);
                    otherwise
                        self.throwValidationError('%s command %d has invalid type "%s"', ...
                                                 context, i, command.type);
                end
            end
        end
        
        function validateControllerCommand(self, command, context, index)
            % Validate controller command
            
            if ~isfield(command, 'command_name')
                self.throwValidationError('%s controller command %d missing "command_name" field', ...
                                         context, index);
            end
            
            % Note: We don't validate command-specific parameters here
            % That will be done in CommandExecutor during execution
        end
        
        function validateWaitCommand(self, command, context, index)
            % Validate wait command
            
            if ~isfield(command, 'duration')
                self.throwValidationError('%s wait command %d missing "duration" field', ...
                                         context, index);
            end
            
            if ~isnumeric(command.duration) || command.duration < 0
                self.throwValidationError('%s wait command %d duration must be non-negative number', ...
                                         context, index);
            end
        end
        
        function validatePluginCommand(self, command, context, index)
            % Validate plugin command
            
            if ~isfield(command, 'plugin_name')
                self.throwValidationError('%s plugin command %d missing "plugin_name" field', ...
                                         context, index);
            end
            
            % Note: command_name field is validated later by CommandExecutor
            % based on plugin type (some plugins like scripts don't need it)
        end
        
        function protocol = extractProtocol(self, data)
            % Extract all protocol sections into structured format
            %
            % Input Arguments:
            %   data - Raw parsed YAML data
            %
            % Returns:
            %   protocol - Struct with organized protocol data

            protocol = struct();

            % Store version
            protocol.version = data.version;

            % Extract experiment metadata
            protocol.experimentInfo = data.experiment_info;

            % Load rig config (resolves arena config inside)
            rig_path = self.resolveRelativePath(data.rig);
            rig_config = load_rig_config(rig_path);

            protocol.rigConfig     = rig_config;
            protocol.arenaConfig   = rig_config.arena;
            protocol.derivedConfig = rig_config.derived;
            protocol.rigFilepath   = rig_path;
            protocol.arenaFilepath = rig_config.arena_file;

            % Convenience shortcut so callers don't have to dig into rigConfig
            if isfield(rig_config, 'controller')
                protocol.controllerConfig = rig_config.controller;
            else
                protocol.controllerConfig = struct('host', '', 'port', 62222);
            end

            if self.verbose
                fprintf('  Loaded rig: %s\n', rig_config.name);
                fprintf('  Controller: %s:%d\n', protocol.controllerConfig.host, ...
                        protocol.controllerConfig.port);
            end

            % Extract experiment structure
            protocol.experimentStructure = data.experiment_structure;

            % Extract plugins (if present) and merge rig-level hardware config
            if isfield(data, 'plugins')
                exp_plugins = data.plugins;
                % Normalize to cell array (yamlread may return struct array)
                if isstruct(exp_plugins) && ~iscell(exp_plugins)
                    exp_plugins = arrayfun(@(s) s, exp_plugins, 'UniformOutput', false);
                end
                % Merge rig plugin hardware config into each plugin definition
                exp_plugins = self.mergeRigPluginConfig(exp_plugins, rig_config.plugins);
                protocol.plugins = exp_plugins;
                if self.verbose
                    fprintf('  Found %d plugin definitions\n', length(protocol.plugins));
                end
            else
                protocol.plugins = [];
                if self.verbose
                    fprintf('  No plugins defined\n');
                end
            end

            % Extract pretrial commands
            protocol.pretrialCommands = self.extractOptionalSection(data, 'pretrial');
            if isstruct(protocol.pretrialCommands) && ~iscell(protocol.pretrialCommands)
                protocol.pretrialCommands = arrayfun(@(s) s, protocol.pretrialCommands, 'UniformOutput', false);
            end
            if self.verbose
                if isempty(protocol.pretrialCommands)
                    fprintf('  Pretrial: skipped\n');
                else
                    fprintf('  Pretrial: %d commands\n', length(protocol.pretrialCommands));
                end
            end

            % Extract block conditions
            protocol.blockConditions = data.block.conditions;
            for cond = 1:length(protocol.blockConditions)
                if isstruct(protocol.blockConditions(cond).commands) && ...
                        ~iscell(protocol.blockConditions(cond).commands)
                    protocol.blockConditions(cond).commands = arrayfun(@(s) s, ...
                        protocol.blockConditions(cond).commands, 'UniformOutput', false);
                end
            end
            if self.verbose
                fprintf('  Block: %d conditions\n', length(protocol.blockConditions));
            end

            % Extract intertrial commands
            protocol.intertrialCommands = self.extractOptionalSection(data, 'intertrial');
            if isstruct(protocol.intertrialCommands) && ~iscell(protocol.intertrialCommands)
                protocol.intertrialCommands = arrayfun(@(s) s, protocol.intertrialCommands, 'UniformOutput', false);
            end
            if self.verbose
                if isempty(protocol.intertrialCommands)
                    fprintf('  Intertrial: skipped\n');
                else
                    fprintf('  Intertrial: %d commands\n', length(protocol.intertrialCommands));
                end
            end

            % Extract posttrial commands
            protocol.posttrialCommands = self.extractOptionalSection(data, 'posttrial');
            if isstruct(protocol.posttrialCommands) && ~iscell(protocol.posttrialCommands)
                protocol.posttrialCommands = arrayfun(@(s) s, protocol.posttrialCommands, 'UniformOutput', false);
            end
            if self.verbose
                if isempty(protocol.posttrialCommands)
                    fprintf('  Posttrial: skipped\n');
                else
                    fprintf('  Posttrial: %d commands\n', length(protocol.posttrialCommands));
                end
            end
        end
        
        function exp_plugins = mergeRigPluginConfig(self, exp_plugins, rig_plugins)
            % Merge rig-level plugin hardware config into experiment plugin definitions
            %
            % The rig YAML stores hardware-specific settings (IP, port, executable
            % paths, etc.) keyed by plugin name. The experiment YAML stores
            % behavioural/class definitions. This method combines them so that each
            % plugin definition passed to PluginManager is fully populated.
            %
            % Merge rules:
            %   - Rig fields are written into plugin.config
            %   - If the experiment YAML already has a matching field in plugin.config,
            %     the experiment value is kept (experiment wins on conflict)
            %   - The 'enabled' field from the rig is skipped (rig-level metadata only)
            %
            % Input Arguments:
            %   exp_plugins - Cell array of plugin structs from experiment YAML
            %   rig_plugins - Struct of plugin hardware configs from rig YAML,
            %                 keyed by plugin name (e.g., rig_plugins.camera)
            %
            % Returns:
            %   exp_plugins - Same cell array with .config fields augmented

            if isempty(rig_plugins) || ~isstruct(rig_plugins)
                return;
            end

            rig_plugin_names = fieldnames(rig_plugins);

            for i = 1:length(exp_plugins)
                plugin = exp_plugins{i};
                plugin_name = plugin.name;

                if ~ismember(plugin_name, rig_plugin_names)
                    continue;  % No rig config for this plugin — leave as-is
                end

                rig_plugin = rig_plugins.(plugin_name);
                if ~isstruct(rig_plugin)
                    continue;
                end

                % Ensure plugin.config exists
                if ~isfield(plugin, 'config') || isempty(plugin.config)
                    plugin.config = struct();
                end

                % Copy rig fields into plugin.config, skipping 'enabled' and
                % any field already specified in the experiment YAML
                rig_fields = fieldnames(rig_plugin);
                for j = 1:length(rig_fields)
                    field = rig_fields{j};
                    if strcmp(field, 'enabled')
                        continue;
                    end
                    if ~isfield(plugin.config, field)
                        plugin.config.(field) = rig_plugin.(field);
                    end
                end

                exp_plugins{i} = plugin;

                if self.verbose
                    fprintf('  Merged rig hardware config into plugin: %s\n', plugin_name);
                end
            end
        end

        function commands = extractOptionalSection(self, data, sectionName)
            % Extract commands from optional section
            %
            % Returns empty array if section not included
            
            if isfield(data, sectionName) && ...
               isfield(data.(sectionName), 'include') && ...
               data.(sectionName).include && ...
               isfield(data.(sectionName), 'commands')
                
                commands = data.(sectionName).commands;
            else
                commands = [];
            end
        end
        
        function printProtocolSummary(self, protocol)
            % Print summary of parsed protocol

            fprintf('\n=== Protocol Summary ===\n');
            fprintf('Experiment: %s\n', protocol.experimentInfo.name);

            if isfield(protocol.experimentInfo, 'author')
                fprintf('Author: %s\n', protocol.experimentInfo.author);
            end

            if isfield(protocol.experimentInfo, 'date_created')
                fprintf('Date Created: %s\n', protocol.experimentInfo.date_created);
            end

            fprintf('Rig: %s\n', protocol.rigConfig.name);
            fprintf('Controller: %s:%d\n', protocol.controllerConfig.host, ...
                    protocol.controllerConfig.port);
            fprintf('Arena: %dx%d panels (%s)\n', ...
                    protocol.arenaConfig.num_rows, ...
                    protocol.arenaConfig.num_cols, ...
                    protocol.arenaConfig.generation);
            if isfield(protocol.arenaConfig, 'column_order')
                fprintf('Column order: %s\n', protocol.arenaConfig.column_order);
            end
            if isfield(protocol.derivedConfig, 'total_pixels_x')
                fprintf('Pattern dimensions: %dx%d px\n', ...
                        protocol.derivedConfig.total_pixels_x, ...
                        protocol.derivedConfig.total_pixels_y);
            end

            fprintf('Repetitions: %d\n', protocol.experimentStructure.repetitions);

            if isfield(protocol.experimentStructure, 'randomization') && ...
               isfield(protocol.experimentStructure.randomization, 'enabled')
                if protocol.experimentStructure.randomization.enabled
                    fprintf('Randomization: enabled (%s)\n', ...
                            protocol.experimentStructure.randomization.method);
                else
                    fprintf('Randomization: disabled\n');
                end
            end

            total_trials = ProtocolParser.get_total_trials(protocol);

            fprintf('Conditions: %d\n', length(protocol.blockConditions));
            fprintf('Total trials: %d\n', total_trials);
            fprintf('========================\n\n');
        end
        
        function throwValidationError(self, varargin)
            % Throw validation error with context
            
            % Format error message
            msg = sprintf(varargin{:});
            
            % Add file context
            fullMsg = sprintf('Protocol validation failed (%s):\n%s', ...
                             self.filepath, msg);
            
            error('ProtocolParser:ValidationError', '%s', fullMsg);
        end
    end
    
    methods (Static)

        function output = get_total_trials(protocol)

            num_conds = length(protocol.blockConditions);
            reps = protocol.experimentStructure.repetitions;
            pre = 0;
            inter = 0;
            post = 0;
            if ~isempty(protocol.pretrialCommands)
                pre = 1;
            end
            if ~isempty(protocol.intertrialCommands)
                inter = 1;
            end
            if ~isempty(protocol.posttrialCommands)
                post = 1;
            end
            output = (num_conds*reps) + inter*((num_conds*reps)-1) + pre + post;
            
        end
    end

end