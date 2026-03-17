classdef PluginManager < handle
    % Manages initialization and execution of all plugins
    %
    % This class handles:
    % - Initializing serial device, class, and script plugins
    % - Storing plugin instances in a registry
    % - Executing plugin commands
    % - Cleanup and connection management
    
    properties (Access = private)
        pluginRegistry      % containers.Map: plugin ID -> Plugin object
        logger              % ExperimentLogger instance
        experimentDir
    end
    
    methods (Access = public)
        function self = PluginManager(logger, experimentDir)
            % Constructor
            %
            % Input Arguments:
            %   logger - ExperimentLogger instance for logging
            
            self.pluginRegistry = containers.Map();
            self.logger = logger;
            self.experimentDir = experimentDir;
        end
        
        function initializePlugin(self, pluginDef)
            % Initialize a plugin from definition
            %
            % Construction and hardware initialization are handled separately
            % for each plugin type, with targeted retry prompts:
            %
            %   serial_device - construction needs no retry (no hardware yet);
            %                   initialize() opens serial port -> hardware prompt
            %
            %   class         - construction may fail if class is missing from
            %                   MATLAB path -> path prompt and one retry;
            %                   developer errors (wrong interface etc.) abort
            %                   immediately; initialize() opens hardware
            %                   connection -> hardware prompt and one retry
            %
            %   script        - construction needs no retry; initialize()
            %                   locates and loads the script file -> script-
            %                   specific prompt and one retry
            %
            % Input Arguments:
            %   pluginDef - Struct containing plugin definition from YAML
            %               Required fields: name, type
            %               Additional fields depend on type

            pluginName = pluginDef.name;
            pluginType = pluginDef.type;

            self.logger.log('INFO', sprintf('Initializing %s plugin: %s', ...
                pluginType, pluginName));

            % Inject experimentDir into plugin config before constructing
            if ~isfield(pluginDef, 'config') || isempty(pluginDef.config)
                pluginDef.config = struct();
            end
            if ~isfield(pluginDef.config, 'saveDir') || isempty(pluginDef.config.saveDir)
                pluginDef.config.saveDir = self.experimentDir;
            end

            switch pluginType

                case 'serial_device'
                    % Construction is pure YAML parsing - no retry needed
                    plugin = SerialPlugin(pluginName, pluginDef, self.logger);

                    % initialize() opens the serial port - hardware may not
                    % be ready, so prompt and allow one retry
                    self.initializeWithHardwareRetry(plugin, pluginName);

                case 'class'
                    % Construction instantiates the user class - may fail if
                    % class is not on the MATLAB path
                    plugin = self.constructClassPluginWithRetry(pluginName, pluginDef);

                    % initialize() opens the hardware connection (serial,
                    % network, etc.) - prompt and allow one retry
                    self.initializeWithHardwareRetry(plugin, pluginName);

                case 'script'
                    % Construction is pure YAML parsing - no retry needed
                    plugin = ScriptPlugin(pluginName, pluginDef, self.logger);

                    % initialize() locates and loads the script file - may
                    % fail due to missing file or script errors
                    self.initializeWithScriptRetry(plugin, pluginName);

                otherwise
                    error('PluginManager:UnknownType', ...
                        'Unknown plugin type: %s', pluginType);
            end

            % Store in registry
            self.pluginRegistry(pluginName) = plugin;
            self.logger.log('INFO', sprintf('Plugin "%s" initialized and registered', pluginName));
        end
        
        function plugin = getPlugin(self, pluginName)
            % Retrieve plugin by ID
            %
            % Input Arguments:
            %   pluginName - Plugin identifier string
            %
            % Returns:
            %   plugin - Plugin object
            
            if ~self.pluginRegistry.isKey(pluginName)
                error('Plugin not found: %s', pluginName);
            end
            
            plugin = self.pluginRegistry(pluginName);
        end
        
        function result = executePluginCommand(self, pluginName, varargin)
            % Execute a command on a plugin
            %
            % Input Arguments:
            %   pluginName - Plugin identifier string
            %   varargin - Additional arguments depend on plugin type:
            %              For SerialPlugin: commandName, params
            %              For ClassPlugin: methodName, params
            %              For ScriptPlugin: (no additional args)
            %
            % Returns:
            %   result - Command execution result (plugin-dependent)
            
            plugin = self.getPlugin(pluginName);
            result = plugin.execute(varargin{:});
        end
        
        function closeAll(self)
            % Close all plugin connections
            
            self.logger.log('INFO', 'Closing all plugins...');
            
            pluginNames = keys(self.pluginRegistry);
            for i = 1:length(pluginNames)
                pluginName = pluginNames{i};
                try
                    plugin = self.pluginRegistry(pluginName);
                    plugin.cleanup();
                    self.logger.log('INFO', sprintf('  ✓ Closed plugin: %s', pluginName));
                catch ME
                    self.logger.log('WARNING', sprintf('  ✗ Failed to close plugin %s: %s', ...
                                                     pluginName, ME.message));
                end
            end
        end
        
        function count = getPluginCount(self)
            % Get number of registered plugins
            
            count = self.pluginRegistry.Count;
        end
        
        function ids = listpluginNames(self)
            % Get list of all plugin IDs
            
            ids = keys(self.pluginRegistry);
        end
    end

    methods (Access = private)

        function plugin = constructClassPluginWithRetry(self, pluginName, pluginDef)
            % Construct a ClassPlugin, prompting once if the class is missing
            % from the MATLAB path.
            %
            % Developer errors (wrong constructor signature, missing required
            % methods) are not retryable and abort immediately.

            attempt = 1;
            success = false;
            while ~success && attempt <= 2
                try
                    plugin = ClassPlugin(pluginName, pluginDef, self.logger);
                    success = true;
                catch ME
                    if strcmp(ME.identifier, 'ClassPlugin:ClassNotFound') && attempt < 2
                        attempt = attempt + 1;
                        self.logger.log('ERROR', sprintf( ...
                            'Class plugin "%s" not found on MATLAB path: %s', ...
                            pluginName, ME.message));
                        msg = sprintf(['\n*** Class plugin "%s" not found ***\n' ...
                            'The required class could not be located on the MATLAB path.\n' ...
                            'Please add the folder containing the class to the MATLAB path,\n' ...
                            'then press Enter to retry, or Ctrl+C to abort the experiment...\n'], ...
                            pluginName);
                        input(msg);
                    else
                        % Either a developer error (wrong interface, bad
                        % constructor) or a second ClassNotFound failure -
                        % neither is recoverable by the user at runtime
                        self.logger.log('ERROR', sprintf( ...
                            'Class plugin "%s" construction failed: %s', ...
                            pluginName, ME.message));
                        rethrow(ME);
                    end
                end
            end
        end

        function initializeWithHardwareRetry(self, plugin, pluginName)
            % Call plugin.initialize() with one retry on failure.
            %
            % Used for serial_device and class plugins where initialize()
            % opens a hardware connection. Prompts the user to check the
            % device before retrying.

            attempt = 1;
            success = false;
            while ~success && attempt <= 2
                try
                    plugin.initialize();
                    success = true;
                catch ME
                    if attempt < 2
                        attempt = attempt + 1;
                        self.logger.log('ERROR', sprintf( ...
                            'Hardware initialization failed for plugin "%s": %s', ...
                            pluginName, ME.message));
                        msg = sprintf(['\n*** Hardware initialization failed for plugin "%s" ***\n' ...
                            'Could not connect to the device.\n' ...
                            'Please check that the device is powered on and connected,\n' ...
                            'then press Enter to retry, or Ctrl+C to abort the experiment...\n'], ...
                            pluginName);
                        input(msg);
                    else
                        self.logger.log('ERROR', sprintf( ...
                            'Hardware initialization for plugin "%s" failed after retry: %s', ...
                            pluginName, ME.message));
                        rethrow(ME);
                    end
                end
            end
        end

        function initializeWithScriptRetry(self, plugin, pluginName)
            % Call plugin.initialize() with one retry on failure.
            %
            % Used for script plugins where initialize() locates and loads
            % the script file. Prompts the user to check the script path
            % and file contents before retrying.

            attempt = 1;
            success = false;
            while ~success && attempt <= 2
                try
                    plugin.initialize();
                    success = true;
                catch ME
                    if attempt < 2
                        attempt = attempt + 1;
                        self.logger.log('ERROR', sprintf( ...
                            'Script plugin "%s" failed to initialize: %s', ...
                            pluginName, ME.message));
                        msg = sprintf(['\n*** Script plugin "%s" failed to initialize ***\n' ...
                            'Error: %s\n' ...
                            'Please check that the script exists at the path defined in\n' ...
                            'the YAML and that it contains no syntax errors,\n' ...
                            'then press Enter to retry, or Ctrl+C to abort the experiment...\n'], ...
                            pluginName, ME.message);
                        input(msg);
                    else
                        self.logger.log('ERROR', sprintf( ...
                            'Script plugin "%s" initialization failed after retry: %s', ...
                            pluginName, ME.message));
                        rethrow(ME);
                    end
                end
            end
        end

    end
end
