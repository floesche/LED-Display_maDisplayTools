function simple_demo()
    
    %% Use yaml file saved in examples/yamls as yaml path
    % Update to match path on your machine
    % Make sure you open this yaml and update all paths/config fields to match your
    % machine. Ensure the path to the rig yaml is pointing to a rig yaml
    % configured for your rig. 
    yamlPath = './examples/yamls/full_experiment_test.yaml';

    % Change this path to a location easy to find on your computer. This is
    % where the new updated yaml will be saved after consolidating patterns
    % on the SD card, and will likely serve as the experiment folder where
    % experiment results will be saved.
    outputFolder = 'Path/to/outputs';

    % This yaml file uses patterns saved in
    % patterns/reference/G41_2x12_cw. They are for a 2 row, 12 column
    % arena. These reference patterns are provided with the repository and
    % used in all our examples. The experiment yaml should have the
    % complete path to this folder as its pattern library. 

    %% Next you must set up the sd card to contain the patterns for the demo.

    % Once you have created a yaml for an experiment, you must get the
    % patterns needed for the experiment onto an SD card. This prep step
    % will do some validation of the yaml, to ensure it is formatted
    % correctly and the patterns are all present and the right size. 
    
    sd_drive = 'D'; % Set the drive letter for the sd card when it's plugged into the PC
    deploy_experiments_to_sd(yamlPath, sd_drive, outputFolder);

    %% next you call run_protocol.m with the following inputs: 
    %   path to yaml - required
    %   'arenaIP' as string, value pair (IP address) - optional, overrides
    %                   IP address in the rig yaml if provided 
    %   'OutputDir' as string, value pair (output filepath) - optional 
    %   'Verbose' as string, value pair (true or false) - optional
    %   'DryRun' as string, value pair (true or false) - optional

    % If you don't provide an output directory, outputs will be saved in 
    % the same folder where the yaml file lives (the outputFolder you provided above). 
    % Verbose defaults to true and provides more information about what's happening 
    % as it happens. DryRun defaults to false, set it to true if you want to validate 
    % your experiment but not actually run it. 

    run_protocol(yamlPath, 'Verbose', false);
    

end