function setup(solver, optFlag)
%SETUP compiles the package and try adding the package into the search path.
%
%   Since MEX is the standard way of calling Fortran code in MATLAB, you
%   need to have MEX properly configured for compile Fortran before using
%   the package. It is out of the scope of this package to help the users
%   to configure MEX.
%
%   If MEX is correctly configured, then the compilation will be done
%   automatically by this script.
%
%   At the end of this script, we will try saving the path of this package
%   to the search path. This can be done only if you have the permission to
%   write the following path-defining file:
%
%   fullfile(matlabroot, 'toolbox', 'local', 'pathdef.m')
%   NOTE: MATLAB MAY CHANGE THE LOCATION OF THIS FILE IN THE FUTURE
%
%   Otherwise, you CAN still use the package, except that you need to run
%   the startup.m script in the current directory each time you start a new
%   MATLAB session that needs the package. startup.m will not re-compile
%   the package but only add it into the search path.
%
%   ***********************************************************************
%   Authors:    Tom M. RAGONNEAU (tom.ragonneau@connect.polyu.hk)
%               and Zaikun ZHANG (zaikun.zhang@polyu.edu.hk)
%               Department of Applied Mathematics,
%               The Hong Kong Polytechnic University.
%
%   Dedicated to late Professor M. J. D. Powell FRS (1936--2015).
%   ***********************************************************************

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Attribute: public (can be called directly by users)
%
% Remarks
%
% 1. Remarks on the directory interfaces_private.
% Functions and MEX files in the directory interfaces_private are
% automatically available to functions in the directory interfaces, and
% to scripts called by the functions that reside in interfaces. They are
% not available to other functions/scripts unless interfaces_private is
% added to the search path.
%
% 2. Remarks on the 'files_with_wildcard' function.
% MATLAB R2015b does not handle wildcard (*) properly. For example, if
% we would like to removed all the .mod files under a directory specified
% by dirname, then the following would workd for MATLAB later than R2016a:
% delete(fullfile(dirname, '*.mod'));
% However, MATLAB R2015b would complain that it cannot find '*.mod'.
% Similarly, to compile solver (see the code between 'try' and 'catch'),
% for MATLAB later than R2016a (but not 2015b), the following code would work:
% mex(adOption, optOption, '-silent', '-output', ['f', solver], fullfile(fsrc, 'pdfoconst.F'), ...
%   fullfile(fsrc, solver, '*.f'), fullfile(gateways, [solver, '-interface.F']));
% However, MATLAB R2015b would run into an error due to the wildcard.
% The 'files_with_wildcard' function provides a workaround.
%
% TODO: None
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% setup starts

% Check the version of MATLAB.
if verLessThan('matlab', '8.3') % MATLAB R2014a = MATLAB 8.3
    fprintf('\nSorry, this package does not support MATLAB R2013b or earlier releases.\n\n');
    return
end

% Check whether MEX is properly configured.
fprintf('\nVerifying the set-up of MEX ... \n\n');
language = 'FORTRAN'; % Language to compile
mex_well_conf = mex_well_configured(language);
if mex_well_conf == 0
    fprintf('\nVerification FAILED.\n')
    fprintf('\nThe MEX of your MATLAB is not properly configured for compiling Fortran.');
    fprintf('\nPlease configure MEX before using this package. Try ''help mex'' for more information.\n\n');
    return
elseif mex_well_conf == -1
    fprintf('\nmex(''-setup'', ''%s'') runs successfully but we cannot verify that MEX works properly.', language);
    fprintf('\nWe will try to continue.\n\n');
else
    fprintf('\nMEX is correctly set up.\n\n');
end

% Detect whether we are running a 32-bit MATLAB, where maxArrayDim = 2^31-1,
% and then set adOption accordingly. On a 64-bit MATLAB, maxArrayDim = 2^48-1
% according to the document of MATLAB R2019a.
% !!! Make sure that eveything is compiled with the SAME adOption !!!
% !!! Otherwise, Segmentation Fault may occur !!!
[~, maxArrayDim] = computer;
if log2(maxArrayDim) > 31
    adOption = '-largeArrayDims';
else
    adOption = '-compatibleArrayDims';
end

% Decide which solver to compile
if nargin == 0 || strcmpi(solver, 'ALL')
    solver_list = {'uobyqa', 'newuoa', 'bobyqa', 'lincoa', 'cobyla'};
else
    solver_list = {solver};
end

% Set optOption
if nargin <= 1
    optFlag = 0;
end
if optFlag == 1
    optOption = '-O';  % Optimize the object code
else % This is the default
    optOption = '-g';  % -g disables MEX's behavior of optimizing built object code
end

cpwd = fileparts(mfilename('fullpath')); % Current directory
fsrc = fullfile(cpwd, 'fsrc'); % Directory of the Fortran source code
fsrc_classical = fullfile(fsrc, 'classical'); % Directory of the classical Fortran source code
matd = fullfile(cpwd, 'matlab'); % Matlab directory
gateways = fullfile(matd, 'mex_gateways'); % Directory of the MEX gateway files
gateways_classical = fullfile(gateways, 'classical'); % Directory of the MEX gateways for the classical Fortran source code
interfaces = fullfile(matd, 'interfaces'); % Directory of the interfaces
interfaces_private = fullfile(interfaces, 'private'); % The private subdirectory of the interfaces
examples = fullfile(matd, 'examples'); % Directory containing some test examples

% Clean up the directories fsrc and gateways before compilation.
% This is important especially if there was previously another
% compilation with a different adOption. Without cleaning-up, the MEX
% files may be linked with wrong .mod or .o files, which can lead to
% serious errors including Segmentation Fault!
dir_list = {fsrc, fsrc_classical, gateways, gateways_classical, interfaces_private};
for idir = 1 : length(dir_list)
    modo_files = [files_with_wildcard(dir_list{idir}, '*.mod'), files_with_wildcard(dir_list{idir}, '*.o')];
    cellfun(@(filename) delete(filename), modo_files);
end

% Compilation starts
fprintf('Compilation starts. It may take some time ...\n');
cd(interfaces_private); % Change directory to interfaces_private; all the MEX files will output to this directory

try
% NOTE: Everything until 'catch' is conducted in interfaces_private.
% We use try ... catch so that we can change directory back to cpwd in
% case of an error.

    % Compilation of function gethuge
    mex(adOption, optOption, '-silent', '-output', 'gethuge', fullfile(fsrc, 'pdfoconst.F'), ...
       fullfile(gateways, 'gethuge.F'));

    for isol = 1 : length(solver_list)
        solver = solver_list{isol};

        % Compilation of solver
        fprintf('Compiling %s ... ', solver);
        % Clean up the source file directory
        modo_files = [files_with_wildcard(fullfile(fsrc, solver), '*.mod'), files_with_wildcard(fullfile(fsrc, solver), '*.o')];
        cellfun(@(filename) delete(filename), modo_files);
        % Compile
        src_files = files_with_wildcard(fullfile(fsrc, solver), '*.f');
        mex(adOption, optOption, '-silent', '-output', ['f', solver], fullfile(fsrc, 'pdfoconst.F'), ...
           src_files{:}, fullfile(gateways, [solver, '-interface.F']));

        % Compilation of the 'classical' version of solver
        % Clean up the source file directory
        modo_files = [files_with_wildcard(fullfile(fsrc_classical, solver), '*.mod'), files_with_wildcard(fullfile(fsrc_classical, solver), '*.o')];
        cellfun(@(filename) delete(filename), modo_files);
        % Compile
        src_files = files_with_wildcard(fullfile(fsrc_classical, solver), '*.f');
        mex(adOption, optOption, '-silent', '-output', ['f', solver, '_classical'], fullfile(fsrc, 'pdfoconst.F'), ...
           src_files{:}, fullfile(gateways_classical, [solver, '-interface.F']));

        fprintf('Done.\n');
    end

    % Clean up the .mod and .o files
    modo_files = [files_with_wildcard(fullfile(interfaces_private), '*.mod'), files_with_wildcard(fullfile(interfaces_private), '*.o')];
    cellfun(@(filename) delete(filename), modo_files);

catch exception % NOTE: Everything above 'catch' is conducted in interfaces_private.
    cd(cpwd); % In case of an error, change directory back to cpwd
    rethrow(exception)
end

cd(cpwd); % Compilation completes successfully; change directory back to cpwd

% Compilation ends
fprintf('Package compiled successfully!\n');

% Add interface (but not interfaces_private) to the search path
addpath(interfaces);

% Try saving path
path_saved = false;
if savepath == 0
    % SAVEPATH saves the current MATLABPATH in the path-defining file,
    % which is by default located at:
    % fullfile(matlabroot, 'toolbox', 'local', 'pathdef.m')
    % 0 if the file was saved successfully; 1 otherwise
    path_saved = true;
end

% If path not saved, try editing the startup.m of this user
edit_startup_failed = false;
user_startup = fullfile(userpath,'startup.m');
add_path_string = sprintf('addpath(''%s'');', interfaces);
% First, check whether add_path_string already exists in user_startup or not
if exist(user_startup, 'file')
    startup_text_cells = regexp(fileread(user_startup), '\n', 'split');
    if any(strcmp(startup_text_cells, add_path_string))
        path_saved = true;
    end
end

if ~path_saved && numel(userpath) > 0 
    % Administrators may set userpath to empty for certain users, especially 
    % on servers. In that case, userpath = [], and user_startup = 'startup.m'.
    % We will not use user_startup. Otherwise, we will only get a startup.m 
    % in the current directory, which will not be executed when MATLAB starts
    % from other directories.  
    try_again = true;
    niter = 1;
    fprintf('\nFor you to use the package in other MATLAB sessions, we will add the following line to your startup script:\n\n%s\n\n', add_path_string);
    user_input = input('Do you want us to do this? ([Y]/n) ', 's');
    while try_again && niter <= 3
        niter = niter + 1;
        if isempty(user_input) || strcmpi(user_input, 'Y') || strcmpi(user_input, 'YES')
            try_again = false;
            file_id = fopen(user_startup, 'a');
            if file_id == -1 % If FOPEN cannot open the file, it returns -1
                edit_startup_failed = true;
            else
                count = fprintf(file_id, '\n%s Added by PDFO (%s) %s\n%s\n', '%%%%%%', datestr(datetime), '%%%%%%', add_path_string);
                fclose(file_id);
                if count > 0 % Check whether the writing was successful
                    path_saved = true;
                else
                    edit_startup_failed = true;
                end
            end
        elseif strcmpi(user_input, 'N') || strcmpi(user_input, 'NO')
            try_again = false;
        else
            if niter <= 3
                try_again = true;
                user_input = input('Sorry, we did not understand your input. Try again ([Y]/n): ', 's');
            else
                try_again = false;
                edit_startup_failed = true;
                fprintf('Sorry, we did not understand your inputs.\n');
            end
        end
    end
end

if edit_startup_failed
    fprintf('\nFailed to edit your startup script. However, you CAN still use the package without any problem.\n');
else
    fprintf('\nThe package is ready to use.\n');
end

fprintf('\nYou may now try ''help pdfo'' for information on the usage of the package.\n');
addpath(examples);
fprintf('\nYou may also run ''testpdfo'' to test the package on a few examples.\n\n');

if ~path_saved % All the path-saving attempts failed
    fprintf('*** To use the pacakge in other MATLAB sessions, do one of the following. ***\n\n');
    fprintf('- EITHER run ''savepath'' right now if you have the permission to do so.\n\n');
    fprintf('- OR add the following line to your startup script\n');
    fprintf('  (see https://www.mathworks.com/help/matlab/ref/startup.html for information):\n\n');
    fprintf('  %s\n\n', add_path_string);
end

% setup ends
return

%%%%%%%%%%%%%%% Function for file names with handling wildcard %%%%%%%%%%%
function full_files = files_with_wildcard(dir_name, wildcard_string)
% Returns a cell array of files that match the wildcard_string under dir_name
% MATLAB R2015b does not handel commands with wildcards like
% delete(*.o)
% or
% mex(*.f)
% This function enables a workaround.
files = dir(fullfile(dir_name, wildcard_string));
full_files = cellfun(@(s)fullfile(dir_name, s), {files.name}, 'uniformoutput', false);
return

%%%%%%%%%%%%%%%%%% Function for verifying the set-up of MEX %%%%%%%%%%%%%%
function success = mex_well_configured(language)

warning('off','all'); % We do not want to see warnings when verifying MEX

callstack = dbstack;
funname = callstack(1).name; % Name of the current function

ulang = upper(language);

success = 1;
% At return,
% success = 1 means MEX is well configured,
% success = 0 means MEX is not well configured,
% success = -1 means "mex -setup" runs successfully, but either we cannot try
% it on the example file because such a file is not found, or the MEX file of
% the example file does not work as expected.

% Locate example_file, which is an example provided by MATLAB for trying MEX.
% NOTE: MATLAB MAY CHANGE THE LOCATION OF THIS FILE IN THE FUTURE.
switch ulang
case 'FORTRAN'
    example_file = fullfile(matlabroot, 'extern', 'examples', 'refbook', 'timestwo.F');
case {'C', 'C++', 'CPP'}
    example_file = fullfile(matlabroot, 'extern', 'examples', 'refbook', 'timestwo.c');
otherwise
    error(sprintf('%s:UnsupportedLang', funname), '%s: Language ''%s'' is not supported by %s.', funname, language, funname);
end

try
    %[~, mex_setup] = evalc('mex(''-setup'', ulang)'); % Use evalc so that no output will be displayed
    mex_setup = mex('-setup', ulang); % mex -setup may be interactive. So it is not good to mute it completely!!!
    if mex_setup ~= 0
        error(sprintf('%s:MexNotSetup', funname), '%s: MATLAB has not got MEX configured for compiling %s.', funname, language);
    end
catch
    fprintf('\nYour MATLAB failed to run mex(''-setup'', ''%s'').\n', language);
    success = 0;
end

if success == 1 && ~exist(example_file, 'file')
    fprintf('\n')
    wid = sprintf('%s:ExampleFileNotExist', funname);
    warning('on', wid);
    warning(wid, 'We cannot find\n%s,\nwhich is a MATLAB built-in example for trying MEX on %s. It will be ignored.\n', example_file, language);
    success = -1;
end

if success == 1
    try
        [~, mex_status] = evalc('mex(example_file)'); % Use evalc so that no output will be displayed
        if mex_status ~= 0
            error(sprintf('%s:MexFailed', funname), '%s: MATLAB failed to compile %s.', funname, example_file);
        end
    catch
        fprintf('\nThe MEX of your MATLAB failed to compile\n%s,\nwhich is a MATLAB built-in example for trying MEX on %s.\n', example_file, language);
        success = 0;
    end
end

if success == 1
    try
        [~, timestwo_out] = evalc('timestwo(1)'); % Try whether timestwo works correctly
    catch
        fprintf('\nThe MEX of your MATLAB compiled\n%s,\nbut the resultant MEX file does not work.\n', example_file);
        success = 0;
    end
end

if success == 1 && abs(timestwo_out - 2)/2 >= 10*eps
    fprintf('\n')
    wid = sprintf('%s:ExampleFileWorksIncorrectly', funname);
    warning('on', wid);
    warning(wid, 'The MEX of your MATLAB compiled\n%s,\nbut the resultant MEX file returns %.16f when calculating 2 times 1.', example_file, timestwo_out);
    success = -1;
end

cpwd = fileparts(mfilename('fullpath')); % Current directory
trash_files = files_with_wildcard(cpwd, 'timestwo.*');
cellfun(@(filename) delete(filename), trash_files);

warning('on','all'); % Restore the behavior of displaying warnings
return
