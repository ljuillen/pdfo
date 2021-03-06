function [fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon, options, probinfo] = prepdfo(fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon, options)
%PREPDFO preprocesses the input to pdfo and its solvers. 
%
%   ***********************************************************************
%   Authors:    Tom M. RAGONNEAU (tom.ragonneau@connect.polyu.hk) 
%               and Zaikun ZHANG (zaikun.zhang@polyu.edu.hk)
%               Department of Applied Mathematics,
%               The Hong Kong Polytechnic University
%
%   Dedicated to late Professor M. J. D. Powell FRS (1936--2015).
%   ***********************************************************************

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Attribute: private (not supposed to be called by users)
%
% Remarks
% 1. Input/output names: MATLAB allows to use the same name for inputs and outputs.
% 2. invoker: invoker is the function that calls prepdfo
%
% TODO: None
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% prepdfo starts

warnings = {}; % A cell that records all the warnings, will be recorded in probinfo

% Who is calling this function? Is it a correct invoker?
invoker_list = {'pdfo', 'uobyqa', 'newuoa', 'bobyqa', 'lincoa', 'cobyla'};
callstack = dbstack;
funname = callstack(1).name; % Name of the current function 
if (length(callstack) == 1 || ~ismember(callstack(2).name, invoker_list))
    % Private/unexpected error
    error(sprintf('%s:InvalidInvoker', funname), ...
    '%s: UNEXPECTED ERROR: %s should only be called by %s.', funname, funname, mystrjoin(invoker_list, ', '));
else
    invoker = callstack(2).name; % Name of the function who calls this function
end

if (nargin ~= 1) && (nargin ~= 10)
    % Private/unexpected error
    error(sprintf('%s:InvalidInput', funname), '%s: UNEXPECTED ERROR: 1 or 10 inputs.', funname);
end

% Decode the problem if it is defined by a structure. 
if (nargin == 1)
    [fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon, options, warnings] = decode_problem(invoker, fun, warnings);
end

% Save the raw data (date before validation/preprocessing) in probinfo.
% The raw data can be useful when debugging. At the end of prepdfo, if
% we are not in debug mode, raw_data will be removed from probinfo. 
% NOTE: Surely, here we are making copies of the data, which may take some
% time and space, matrices Aineq and Aeq being the major concern here.  
% However, fortunately, this package is not intended for large problems. 
% It is designed for problems with at most ~1000 variables and several
% thousands of constriants, tens/hundreds of variables and tens/hundreds 
% of constriants being typical. Therefore, making several copies (<10) of 
% the data does not do much harm, especially when we solve problems with 
% expensive (temporally or monetarily) function evaluations. 
probinfo = struct(); % Initialize probinfo as an empty structure
probinfo.raw_data = struct('objective', fun, 'x0', x0, 'Aineq', Aineq, 'bineq', bineq, ...
    'Aeq', Aeq, 'beq', beq, 'lb', lb, 'ub', ub, 'nonlcon', nonlcon, 'options', options);

if (length(callstack) >= 3) && strcmp(callstack(3).name, 'pdfo')
    % The invoker is a solver called by pdfo. Then prepdfo should have been called in pdfo.
    if nargin ~= 10 % There should be 10 input arguments 
        % Private/unexpected error
        error(sprintf('%s:InvalidInput', funname), ... 
        '%s: UNEXPECTED ERROR: %d inputs received; this should not happen as prepdfo has been called once in pdfo.', funname, nargin);
    end
    probinfo.infeasible = false;
    probinfo.nofreex= false;
    return % Return because prepdfo has already been called in pdfo.
end

% Validate and preprocess fun
[fun, warnings] = pre_fun(invoker, fun, warnings);

% Validate and preprocess x0 
x0 = pre_x0(invoker, x0);
lenx0 = length(x0); 
% Within this file, for clarity, we denote length(x0) by lenx0 instead of n

% Validate and preprocess the linear constraints
% The 'trivial constraints' will be excluded (if any). 
% In addition, get the indices of infeasible and trivial constraints (if any) 
% and save the information in probinfo.
[Aineq, bineq, Aeq, beq, infeasible_lineq, trivial_lineq, infeasible_leq, trivial_leq] = pre_lcon(invoker, Aineq, bineq, Aeq, beq, lenx0);
probinfo.infeasible_lineq = infeasible_lineq; % A vector of true/false
probinfo.trivial_lineq = trivial_lineq; % A vector of true/false
probinfo.infeasible_leq = infeasible_leq; % A vector of true/false
probinfo.trivial_leq = trivial_leq; % A vector of true/false

% Validate and preprocess the bound constraints
% In addition, get the indices of infeasible bounds and 'fixed variables' 
% such that ub-lb < 2eps (if any) and save the information in probinfo  
[lb, ub, infeasible_bound, fixedx, fixedx_value] = pre_bcon(invoker, lb, ub, lenx0);
probinfo.infeasible_bound = infeasible_bound; % A vector of true/false
probinfo.fixedx = fixedx; % A vector of true/false
probinfo.fixedx_value = fixedx_value; % Value of the fixed x entries

% After preprocessing the linear/bound constraints, the problem may
% turn out infeasible, or x may turn out fixed by the bounds
if ~any([probinfo.infeasible_lineq; probinfo.infeasible_leq; probinfo.infeasible_bound])
    probinfo.infeasible = false;
else % The problem turns out infeasible 
    probinfo.infeasible = true;
end
if any(~fixedx)
    probinfo.nofreex = false;
else % x turns out fixed by the bound constraints 
    probinfo.constrv_fixedx = constrv(probinfo.fixedx_value, Aineq, bineq, Aeq, beq, lb, ub, nonlcon);
    probinfo.nofreex = true;
end

% Validate and preprocess the nonlinear constraints 
nonlcon = pre_nonlcon(invoker, nonlcon);

% Reduce the problem if some variables are fixed by the bound constraints
probinfo.raw_dim = lenx0; % Problem dimension before reduction
probinfo.raw_type = problem_type(Aineq, Aeq, lb, ub, nonlcon); % Problem type before reduction
probinfo.reduced = false;
if any(fixedx) && ~probinfo.nofreex && ~probinfo.infeasible 
    [fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon] = reduce_problem(fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon, fixedx);
    lenx0 = length(x0); 
    probinfo.reduced = true;
end
probinfo.refined_dim = lenx0; % Problem dimension after reduction
probinfo.refined_type = problem_type(Aineq, Aeq, lb, ub, nonlcon); % Problem type after reduction

% Can the invoker handle the given problem? 
% This should be done after the problem type has bee 'refined'.
if ~prob_solv_match(probinfo.refined_type, invoker) 
    if strcmp(invoker, 'pdfo') || (nargin ~= 1) 
        % Private/unexpected error
        error(sprintf('%s:InvalidProb', funname), ...
        '%s: UNEXPECTED ERROR: problem and solver do not match; this should not happen when %s is called by %s or the problem is not a structure.', funname, funname, invoker);
    else
        % Public/normal error
        error(sprintf('%s:InvalidProb', invoker), ...
        '%s: %s problem received; %s cannot solve it.', invoker, strrep(probinfo.refined_type, '-', ' '), invoker);
    end
end

% Validate and preprocess options, adopt default options if needed.
% This should be done after reducing the problem, because BOBYQA
% requires rhobeg <= min(ub-lb)/2.
[options, warnings] = pre_options(invoker, options, lenx0, lb, ub, warnings);

% Revise x0 for bound and linearly constrained problems
% This is necessary for LINCOA, which accepts only feasible x0.
% Should we do this even if there are nonlinear constraints? 
% For now, we do not, because doing so may dramatically increase the
% infeasibility of x0 with respect to the nonlinear constraints.
if ismember(probinfo.refined_type, {'bound-constrained', 'linearly-constrained'}) && ~probinfo.nofreex && ~probinfo.infeasible
    x0_old = x0;
    % Another possibility for bound-constrained problems: 
    % xind = (x0 < lb) | (x0 > ub);
    % x0(xind) = (lb(xind) + ub(xind))/2; 
    x0 = project(Aineq, bineq, Aeq, beq, lb, ub, x0); 
    if norm(x0_old-x0) > eps*max(1, norm(x0_old))
        wid = sprintf('%s:ReviseX0', invoker);
        wmessage = sprintf('%s: x0 is revised to satisfy the constraints.', invoker);
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    end
end

% Scale the problem if necessary and if intended. 
% x_before_scaling = scaling_factor.*x_after_scaling + shift
% This should be done after revising x0, which can affect the shift.
probinfo.scaled = false;
if options.scale && ~probinfo.nofreex && ~probinfo.infeasible
    [fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon, scaling_factor, shift, substantially_scaled, warnings] = scale_problem(invoker, fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon, warnings);
    % Scale and shift the problem so that 
    % 1. for the variables that have both lower bound and upper bound, the bounds become [-1, 1] 
    % 2. the other variables will be shifted so that the corresponding component of x0 becomes 0 
    probinfo.scaled = true;
    probinfo.scaling_factor = scaling_factor;
    probinfo.shift = shift;
    % If the problem is substantially scaled, then rhobeg and rhoend may need to be revised
    if substantially_scaled
        options.rhobeg = 1;
        options.rhoend = options.rhoend/options.rhobeg;
    end
end

% Select a solver if invoker='pdfo'. 
% Some options will be revised accordingly, including npt, rhobeg, rhoend.
% Of course, if the user-defined options.solver is valid, we accept it.
if strcmp(invoker, 'pdfo') 
    if strcmp(probinfo.refined_type, 'bound-constrained')
        % lb and ub will be used for defining rhobeg if bobyqa is selected.
        probinfo.lb = lb;
        probinfo.ub = ub;
    end
    [solver, options, warnings] = select_solver(invoker, options, probinfo, warnings);
    options.solver = solver;
    % Signature: [solver, options, warnings] = select_solver(options, probinfo, warnings)
end

probinfo.warnings = warnings; % Record the warnings in probinfo

% The refined data can be useful when debugging. It will be used in
% postpdfo even we are not in debug mode. 
probinfo.refined_data = struct('objective', fun, 'x0', x0, 'Aineq', Aineq, 'bineq', bineq, ...
    'Aeq', Aeq, 'beq', beq, 'lb', lb, 'ub', ub, 'nonlcon', nonlcon, 'options', options);
if ~options.debug % Do not carry the raw data with us unless in debug mode.
    probinfo = rmfield(probinfo, 'raw_data');
end

% prepdfo ends 
return

%%%%%%%%%%%%%%%%%%%%%%%% Function for problem decoding %%%%%%%%%%%%%%%%%
function [fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon, options, warnings] = decode_problem(invoker, problem, warnings)
% Read the fields of the 'problem' structure but do not validate them. 
% The decoded problem will be sent to the prepdfo function for validation.
% NOTE: We treat field names case-sensitively.

% Possible invokers
invoker_list = {'pdfo', 'uobyqa', 'newuoa', 'bobyqa', 'lincoa', 'cobyla'};

callstack = dbstack; 
funname = callstack(1).name; % Name of the current function
if ~ismember(invoker, invoker_list)
    % invoker affects the behavior of this function, so we check invoker
    % again, even though it should have been checked in function prepdfo
    % Private/unexpcted error
    error(sprintf('%s:InvalidInvoker', funname), ...
    '%s: UNEXPECTED ERROR: %s serves only %s.', funname, funname, mystrjoin(invoker_list, ', '));
end

if ~isa(problem, 'struct') 
    % Public/normal error
    error(sprintf('%s:InvalidProb', invoker), '%s: the unique input is not a problem-defining structure.', invoker);
end

% Which fields are specified? 
problem = rmempty(problem); % Remove empty fields
problem_field = fieldnames(problem); 

% Are the obligatory field(s) present?
obligatory_field = {'x0'}; % There is only 1 obligatory field
missing_field = setdiff(obligatory_field, problem_field);
if ~isempty(missing_field)
    % Public/normal error
    error(sprintf('%s:InvalidProb', invoker), ...
    '%s: PROBLEM misses the %s field(s).', invoker, mystrjoin(missing_field, ', '));
end
x0 = problem.x0;

if isfield(problem, 'objective') 
    fun = problem.objective;
else % There is no objective; put a fake one
    wid = sprintf('%s:NoObjective', invoker);
    wmessage = sprintf('%s: there is no objective function.', invoker);
    warning(wid, '%s', wmessage);
    warnings = [warnings, wmessage]; 
    fun = @(x) 0; 
end

% Are there unknown fields?
known_field = {'objective', 'x0', 'Aineq', 'bineq', 'Aeq', 'beq', 'lb', 'ub', 'nonlcon', 'options', 'solver'};
% 1. When invoker is in {uobyqa, ..., cobyla}, we will not complain that
%    a solver is specified unless invoker~=solver. See function pre_options.
% 2. When invoker is in {uobyqa, ..., cobyla}, if the problem turns out
%    unsolvable for the invoker, then we will raise an error in prepdfo.
%    We do not do it here because the problem has not been validated/preprocessed 
%    yet. Maybe some constraints are trivial and hence can be removed 
%    (e.g., bineq=inf, lb=-inf), which can change the problem type. 

unknown_field = setdiff(problem_field, known_field);

if ~isempty(unknown_field) 
    wid = sprintf('%s:UnknownProbFiled', invoker);
    if length(unknown_field) == 1
        wmessage = sprintf('%s: problem with an unknown field %s; it is ignored.', invoker, mystrjoin(unknown_field, ', '));  
    else
        wmessage = sprintf('%s: problem with unknown fields %s; they are ignored.', invoker, mystrjoin(unknown_field, ', '));  
    end
    warning(wid, '%s', wmessage);
    warnings = [warnings, wmessage]; 
end

% Read the fields of problem. They will be validated in function predfo
Aineq = [];
bineq = [];
Aeq = [];
beq = [];
lb= [];
ub = [];
nonlcon = [];
options = struct();
if isfield(problem,'Aineq')
    Aineq = problem.Aineq;
end
if isfield(problem,'bineq')
    bineq = problem.bineq;
end
if isfield(problem,'Aeq')
    Aeq = problem.Aeq;
end  
if isfield(problem,'beq')
    beq = problem.beq;
end
if isfield(problem,'lb')
    lb = problem.lb;
end
if isfield(problem,'ub')
    ub = problem.ub;
end
if isfield(problem,'nonlcon')
    nonlcon = problem.nonlcon;
end
if isfield(problem,'options')
    options = problem.options;
end
if isfield(problem,'solver')
    options.solver = problem.solver;
    % After last step, options.solver = problem.options.solver;
    % after this step, if problem.solver is defined and nonempty, 
    % then options.solver = problem.solver.
end
return

%%%%%%%%%%%%%%%%%%%%%%%% Function for fun preprocessing %%%%%%%%%%%%%%%%%
function [fun, warnings] = pre_fun(invoker, fun, warnings)
if ~(isempty(fun) || isa(fun, 'char') || isa(fun, 'string') || isa(fun, 'function_handle'))
    % Public/normal error
    error(sprintf('%s:InvalidFun', invoker), ...
        '%s: FUN should be a function handle or a function name.', invoker);
end
if isempty(fun)
    fun = @(x) 0; % No objective function
    wid = sprintf('%s:NoObjective', invoker);
    wmessage = sprintf('%s: there is no objective function.', invoker);
    warning(wid, '%s', wmessage);
    warnings = [warnings, wmessage]; 
elseif isa(fun, 'char') || isa(fun, 'string')
    fun = str2func(fun); 
    % Work with function handels instread of function names to avoid using 'feval'
end
if ~exist('OCTAVE_VERSION', 'builtin') 
    % Check whether fun has at least 1 output.
    % nargout(fun) = #outputs in the definition of fun. 
    % If fun includes varargout in definition, nargout(fun) = -#outputs. 
    % Octave does not support nargout for built-in function (as of 2019-08-16)!
    try 
    % If fun is not a properly defined function, then nargout
    % can encounter an error. Wrap the error as a public error. 
        nout = nargout(fun);
    catch exception
        % Public/normal error
        % Note that the identifier of a public error should start with 'invoker:'
        error(sprintf('%s:InvalidFun', invoker), '%s: %s', invoker, exception.message);
    end
    if (nout == 0)
        % Public/normal error
        error(sprintf('%s:InvalidFun', invoker), ...
        '%s: FUN has no output; it should return the objective function value.', invoker);
    end
end
fun = @(x) evalobj(invoker, fun, x); 
return

function f = evalobj(invoker, fun, x)
f = fun(x);
if ~isnumeric(f) || numel(f) ~= 1 
    % Public/normal error
    error(sprintf('%s:ObjectiveNotScalar', invoker), '%s: objective function should return a scalar value.', invoker);
end
f = double(real(f)); % Some functions like 'asin' can return complex values even when it is not intended
% Use extreme barrier to cope with 'hidden constraints' 
hugefun = gethuge('fun');
if (f ~= f) || (f > hugefun)
    f = hugefun;
end
return

%%%%%%%%%%%%%%%%%%%%%%%% Function for x0 preprocessing %%%%%%%%%%%%%%%%%
function x0 = pre_x0(invoker, x0)
[isrv, lenx0]  = isrealvector(x0);
if ~(isrv && (lenx0 > 0))
    % Public/normal error
    error(sprintf('%s:InvalidX0', invoker), '%s: X0 should be a real vector/scalar.', invoker);
end
x0 = double(x0(:));
return

%%%%%%%%%%%%%%%%% Function for linear constraint preprocessing %%%%%%%%%%  
function [Aineq, bineq, Aeq, beq, infeasible_lineq, trivial_lineq, infeasible_leq, trivial_leq] = pre_lcon(invoker, Aineq, bineq, Aeq, beq, lenx0)
% inequalities: Aineq*x <= bineq
[isrm, mA, nA] = isrealmatrix(Aineq);
[isrc, lenb] = isrealcolumn(bineq);
if ~(isrm && isrc && (mA == lenb) && (nA == lenx0 || nA == 0))
    % Public/normal error
    error(sprintf('%s:InvalidLinIneq', invoker), ...
    '%s: Aineq should be a real matrix, Bineq should be a real column, and size(Aineq)=[length(Bineq), length(X0)] unless Aineq=Bineq=[].', invoker);
end
if (mA == 0)
    infeasible_lineq = [];
    trivial_lineq = [];
else
    Aineq = double(Aineq);
    bineq = double(bineq);
    rownorminf = max(abs(Aineq), [], 2);
    zero_ineq = (rownorminf == 0);
    infeasible_zero_ineq = (rownorminf == 0) & (bineq < 0);
    trivial_zero_ineq = (rownorminf == 0) & (bineq >= 0);
    rownorminf(zero_ineq) = 1;
    infeasible_lineq = (bineq./rownorminf == -inf) | infeasible_zero_ineq; % A vector of true/false
    trivial_lineq = (bineq./rownorminf == inf) | trivial_zero_ineq;
    Aineq = Aineq(~trivial_lineq, :); % Remove the trivial linear inequalities
    bineq = bineq(~trivial_lineq);
end
if isempty(Aineq) 
    % We uniformly use [] to represent empty objects; its size is 0x0
    % Changing this may cause matrix dimension inconsistency 
    Aineq = [];
    bineq = [];
end

% equalities: Aeq*x == beq
[isrm, mA, nA] = isrealmatrix(Aeq);
[isrc, lenb] = isrealcolumn(beq);
if ~(isrm && isrc && (mA == lenb) && (nA == lenx0 || nA == 0))
    % Public/normal error
    error(sprintf('%s:InvalidLinEq', invoker), ...
    '%s: Aeq should be a real matrix, Beq should be a real column, and size(Aeq)=[length(Beq), length(X0)] unless Aeq=Beq=[].', invoker);
end
if (mA == 0)
    infeasible_leq = [];
    trivial_leq = [];
else
    Aeq = double(Aeq);
    beq = double(beq);
    rownorminf = max(abs(Aeq), [], 2);
    zero_eq = (rownorminf == 0);
    infeasible_zero_eq = (rownorminf == 0) & (beq ~= 0);
    trivial_zero_eq = (rownorminf == 0) & (beq == 0);
    rownorminf(zero_eq) = 1;
    infeasible_leq = (abs(beq./rownorminf) == inf) | infeasible_zero_eq; % A vector of true/false
    trivial_leq = trivial_zero_eq;
    Aeq = Aeq(~trivial_leq, :); % Remove trivial linear equalities 
    beq = beq(~trivial_leq);
end
if isempty(Aeq) 
    % We uniformly use [] to represent empty objects; its size is 0x0
    % Changing this may cause matrix dimension inconsistency 
    Aeq = [];
    beq = [];
end
return

%%%%%%%%%%%%%%%%% Function for bound constraint preprocessing %%%%%%%%%%
function [lb, ub, infeasible_bound, fixedx, fixedx_value] = pre_bcon(invoker, lb, ub, lenx0)
% Lower bounds (lb)
[isrvlb, lenlb] = isrealvector(lb);
if ~(isrvlb && (lenlb == lenx0 || lenlb == 0))
    % Public/normal error
    error(sprintf('%s:InvalidBound', invoker), ...
    '%s: lb should be a real vector and length(lb)=length(x0) unless lb=[].', invoker);
end
if (lenlb == 0) 
    lb = -inf(lenx0,1); % After pre_bcon, lb nonempty
end
lb = double(lb(:));

% Upper bounds (ub)
[isrvub, lenub] = isrealvector(ub);
if ~(isrvub && (lenub == lenx0 || lenub == 0))
    % Public/normal error
    error(sprintf('%s:InvalidBound', invoker), ...
    '%s: ub should be a real vector and length(ub)=length(x0) unless ub=[].', invoker);
end
if (lenub == 0)
    ub = inf(lenx0,1); % After pre_bcon, ub nonempty
end
ub = double(ub(:));

infeasible_bound = (lb > ub); % A vector of true/false
fixedx = (abs(lb - ub) < 2*eps);
fixedx_value = (lb(fixedx)+ub(fixedx))/2;
return

%%%%%%%%%%%%%%%%% Function for nonlinear constraint preprocessing %%%%%%%%%%
function nonlcon = pre_nonlcon(invoker, nonlcon)
if ~(isempty(nonlcon) || isa(nonlcon, 'function_handle') || isa(nonlcon, 'char') || isa(nonlcon, 'string'))
    % Public/normal error
    error(sprintf('%s:InvalidCon', invoker), ...
    '%s: nonlcon should be a function handle or a function name.', invoker);
end
if isempty(nonlcon)
    nonlcon = []; % We uniformly use [] to represent empty objects; its size is 0x0
else
    if isa(nonlcon, 'char') || isa(nonlcon, 'string') 
        nonlcon = str2func(nonlcon); 
        % work with function handles instead of function names to avoid using 'feval'
    end
    if ~exist('OCTAVE_VERSION', 'builtin')
        % Check whether nonlcon has at least 2 outputs.
        % nargout(fun) = #outputs in the definition of fun. 
        % If fun includes varargout in definition, nargout(fun) = -#outputs. 
        % Octave does not support nargout for built-in function (as of 2019-08-16)!
        try 
        % If nonlcon is not a properly defined function, then nargout
        % can encounter an error. Wrap the error as a public error. 
            nout = nargout(nonlcon);
        catch exception
            % Public/normal error
            % Note that the identifier of a public error should start with 'invoker:'
            error(sprintf('%s:InvalidCon', invoker), '%s: %s', invoker, exception.message);
        end
        if (nout == 0) || (nout == 1)
            % Public/normal error
            error(sprintf('%s:InvalidCon', invoker), ...
            '%s: nonlcon has too few outputs; it should return [cineq, ceq], the constraints being cineq(x)<=0, ceq(x)=0.', invoker);
        end
    end
    nonlcon = @(x) evalcon(invoker, nonlcon, x); 
end
return

function [cineq, ceq] = evalcon(invoker, nonlcon, x)
[cineq, ceq] = nonlcon(x);
if ~(isempty(cineq) || isnumeric(cineq)) || ~(isempty(ceq) || isnumeric(ceq))
    % Public/normal error
    error(sprintf('%s:ConstrNotNumeric', invoker), '%s: constraint function should return two numeric vectors.', invoker);
end
cineq = double(real(cineq(:))); % Some functions like 'asin' can return complex values even when it is not intended
ceq = double(real(ceq(:))); 
% Use extreme barrier to cope with 'hidden constraints' 
hugecon = gethuge('con');
cineq(cineq > hugecon) = hugecon;
cineq(cineq ~= cineq) = hugecon;
ceq(ceq > hugecon) = hugecon;
ceq(ceq < -hugecon) = -hugecon;
ceq(ceq ~= ceq) = hugecon;

% This part is NOT extreme barrier. We replace extremely negative values of
% cineq (which leads to no constraint violation) by -hugecon. Otherwise,
% NaN or Inf may occur in the interpolation models.
cineq(cineq < -hugecon) = -hugecon;
return

%%%%%%%%%%%%%%%%% Function for option preprocessing %%%%%%%%%%
function [options, warnings] = pre_options(invoker, options, lenx0, lb, ub, warnings)

% NOTE: We treat field names case-sensitively.

% Possible solvers 
solver_list = {'uobyqa', 'newuoa', 'bobyqa', 'lincoa', 'cobyla'}; 
% We may add other solvers in the future!
% If a new solver is included, we should do the following.
% 0. Include it into the invoker_list (in this and other functions).
% 1. What options does it expect? Set known_field accoridngly.
% 2. Set default options accordingly.
% 3. Check other functions (especially decode_problem, whose behavior
%    depends on the invoker/solver. See known_field there).

% Possible invokers
invoker_list = ['pdfo', solver_list];

callstack = dbstack;
funname = callstack(1).name;
% invoker affects the behavior of this function, so we check invoker
% again, even though it should have been checked in function prepdfo
if ~ismember(invoker, invoker_list)
    % Private/unexpcted error
    error(sprintf('%s:InvalidInvoker', funname), ...
    '%s: UNEXPECTED ERROR: %s serves only %s.', funname, funname, mystrjoin(invoker_list, ', '));
end

% Default values of the options. 

% npt = ! LATER ! % The default npt depends on solver and will be set later in this function 
maxfun = 500*lenx0;
rhobeg = 1; % The default rhobeg and rhoend will be revised if solver = 'bobyqa'
rhoend = 1e-6;
ftarget = -inf;
classical = false; % Call the classical Powell code? Classical mode recommended only for research purpose  
scale = false; % Scale the problem according to bounds? % Scale only if the bounds reflect well the scale of the problem
quiet = true;
debugflag = false; % Do not use 'debug' as the name, which is a MATLAB function
chkfunval = false;

if ~(isa(options, 'struct') || isempty(options))
    % Public/normal error
    error(sprintf('%s:InvalidOptions', invoker), '%s: OPTIONS should be a structure.', invoker);
end

% Which fields are specified?
options = rmempty(options); % Remove empty fields
options_field = fieldnames(options);

% Validate options.solver  
% We need to know what is the solver in order to decide which fields
% are 'known' (e.g., expected), and also to set npt, rhobeg, rhoend.
% We do the following:
% 1. If invoker='pdfo':
% 1.1 If no/empty solver specified or solver='pdfo', we do not complain
% and set options.solver=solver=[]; 
% 1.2 Else if solver is not in solver_list, we warn about 'unknown solver' 
% and set options.solver=solver=[];
% 1.3 Else, we set solver=options.solver.
% 2. If invoker is in solver_list:
% 2.1 If options.solver exists but options.solver~=invoker, we warn
% about 'unknown solver' and set options.solver=solver=invoker;
% 2.2 Else, we do not complain and set options.solver=solver=invoker.
% In this way, options.solver and solver either end up with a member of
% solver_list or []. The second case is possible only if invoker=[],
% and solver will be selected later.
if isfield(options, 'solver') && ~isa(options.solver, 'char') && ~isa(options.solver, 'string')
    options.solver = 'UNKNOWN_SOLVER';
    % We have to change options.solver to a char/string so that we can use strcmpi
end
if strcmp(invoker, 'pdfo')
    solver = [];
    if isfield(options, 'solver') 
        if any(strcmpi(options.solver, solver_list))
            solver = options.solver;
        elseif ~strcmpi(options.solver, 'pdfo') 
        % We should not complain about 'unknown solver' if invoker=options.solver='pdfo'
            wid = sprintf('%s:UnknownSolver', invoker); 
            wmessage = sprintf('%s: unknown solver specified; %s will select one automatically.', invoker, invoker);
            warning(wid, '%s', wmessage);
            warnings = [warnings, wmessage]; 
        end
    end
else % invoker is in {'uobyqa', ..., 'cobyla'}
    if isfield(options, 'solver') && ~strcmpi(options.solver, invoker)
        wid = sprintf('%s:InvalidSolver', invoker);
        wmessage = sprintf('%s: a solver different from %s is specified; it is ignored.', invoker, invoker); 
        % Do not display the value of solver in last message, because it
        % can be 'unknow_solver'.
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    end
    solver = invoker;
end
options.solver = solver; % Record solver in options.solver; will be used in postpdfo

% Check unknown fields according to solver
if any(strcmpi(solver, {'newuoa', 'bobyqa', 'lincoa'}))
    known_field = {'npt', 'maxfun', 'rhobeg', 'rhoend', 'ftarget', 'classical', 'scale', 'quiet', 'debug', 'chkfunval', 'solver'};
else
    known_field = {'maxfun', 'rhobeg', 'rhoend', 'ftarget', 'classical', 'scale', 'quiet', 'debug', 'chkfunval', 'solver'};
end
unknown_field = setdiff(options_field, known_field);
if ~isempty(unknown_field) 
    wid = sprintf('%s:UnknownOption', invoker);
    if length(unknown_field) == 1
        wmessage = sprintf('%s: unknown option %s; it is ignored.', invoker, mystrjoin(unknown_field, ', '));
    else
        wmessage = sprintf('%s: unknown options %s; they are ignored.', invoker, mystrjoin(unknown_field, ', '));
    end
    warning(wid, '%s', wmessage);
    warnings = [warnings, wmessage]; 
end

% Set default npt according to solver
% If solver=[], then invoker must be pdfo, and a solver will be selected 
% later; when the solver is chosen, a valid npt will be defined. So we
% do not need to consider the case with solver=[] here.
% Note we have to take maxfun into consideration when selecting the solver, 
% because npt < maxfun-1 is needed! See function select_solver for details.
if isempty(solver)
    npt = NaN; % We do not need options.npt in this case; it will be (and should be) set when solver is selected
else
    switch lower(solver)
    case {'newuoa', 'bobyqa', 'lincoa'}
        npt = 2*lenx0 + 1;
    case {'uobyqa'}
        npt = (lenx0+1)*(lenx0+2)/2;
    case {'cobyla'}
        npt = lenx0+1;
		% uobyqa and cobyla do not need npt an option, but we need npt to validate/set maxfun
    end
end

% Revise default rhobeg and rhoend according to solver
if strcmpi(solver, 'bobyqa')
    rhobeg_bobyqa = min(rhobeg, min(ub-lb)/2);        
    if (isfield(options, 'scale') && islogicalscalar(options.scale) && ~options.scale) || (~(isfield(options, 'scale') && islogicalscalar(options.scale)) && ~scale)
        % If we are going to scale the problem later, then we keep the
        % default value for rhoend; otherwise, we scale it as follows.
        rhoend = (rhoend/rhobeg)*rhobeg_bobyqa;
    end
    rhobeg = rhobeg_bobyqa;
end

% Validate the user-specified options; adopt the default values if needed 

% Validate options.npt
validated = false;
if isfield(options, 'npt') && any(strcmpi(solver, {'newuoa', 'bobyqa', 'lincoa'}))
    % Only newuoa, bobyqa and lincoa accept an npt option
    if ~isintegerscalar(options.npt) || options.npt < lenx0+2 || options.npt > (lenx0+1)*(lenx0+2)/2 
        wid = sprintf('%s:InvalidNpt', invoker);
        wmessage = sprintf('%s: invalid npt. for %s, it should be an integer and n+2 <= npt <= (n+1)*(n+2)/2; it is set to 2n+1.', invoker, solver);
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    else
        validated = true; 
    end
end
if ~validated % options.npt has not got a valid value yet
    options.npt = npt; 
    % For uobyqa and cobyla or empty solver, we adopt the 'default npt'
    % defined above, although it will NOT be used by the solver
end
options.npt = double(options.npt);
% Although npt and maxfun are integers logically, they have to be
% passed to the mexified code as double variables. In mex, data is
% passed by pointers, but there are only very limited functions that
% can read an integer value from a pointer or write an interger
% value to a pointer (mxCopyPtrToInteger1, mxCopyInteger1ToPtr,
% mxCopyPtrToInteger2, mxCopyInteger2ToPtr, mxCopyPtrToInteger4,
% mxCopyInteger4ToPtr; no function for integer*8). This makes it
% impossible to pass integer data properly unless we know the kind
% of the integer. Therefore, in general, it is recommended to pass
% integers as double variables and then cast them back to integers
% when needed. 
% Indeed, in matlab, even if we define npt = 1000,
% the class of npt is double! To get an integer npt, we would
% have to define npt = int32(1000) or npt = int64(1000)! 

% Validate options.maxfun 
validated = false;
if isfield(options, 'maxfun')
    if ~isintegerscalar(options.maxfun) || options.maxfun <= 0 
        wid = sprintf('%s:InvalidMaxfun', invoker);
        wmessage = sprintf('%s: invalid maxfun; it should be a positive integer; it is set to %d.', invoker, maxfun);
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    elseif isempty(solver) && options.maxfun <= lenx0+1
        options.maxfun = lenx0+2; % Here we take lenx0+2 (the smallest possible value for npt)
        validated = true; %!!! % Set validated=true so that options.maxfun will not be set to the default value later
        wid = sprintf('%s:InvalidMaxfun', invoker);
        wmessage = sprintf('%s: invalid maxfun; it should be a positive integer at least n+2; it is set to n+2.', invoker);
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    elseif ~isempty(solver) && options.maxfun <= options.npt 
        options.maxfun = options.npt+1; % Here we take npt+1 instead of the default maxfun
        validated = true; %!!! % Set validated=true so that options.maxfun will not be set to the default value later
        wid =  sprintf('%s:InvalidMaxfun', invoker);
        switch lower(solver) % The warning message depends on solver
        case {'newuoa', 'lincoa', 'bobyqa'}
            wmessage = sprintf('%s: invalid maxfun; %s requires maxfun > npt; it is set to npt+1.', invoker, solver);
        case 'uobyqa'
            wmessage = sprintf('%s: invalid maxfun; %s requires maxfun > (n+1)*(n+2)/2; it is set to (n+1)*(n+2)/2+1.', invoker, solver);
        case 'cobyla'
            wmessage = sprintf('%s: invalid maxfun; %s requires maxfun > n+1; it is set to n+2.', invoker, solver);
        end
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    else
        validated = true;
    end
end
if ~validated % options.maxfun has not got a valid value yet
    options.maxfun = max(maxfun, options.npt+1);
end
options.maxfun = double(options.maxfun); % maxfun will be passed as a double
% One can check that options.maxfun >= n+2;

% Validate options.rhobeg
validated = false;
if isfield(options, 'rhobeg')
    if ~isrealscalar(options.rhobeg) || options.rhobeg <= 0
        wid = sprintf('%s:InvalidRhobeg', invoker);
        wmessage = sprintf('%s: invalid rhobeg; it should be a positive number; it is set to max(%f, rhoend).', invoker, rhobeg);
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    elseif strcmpi(solver, 'bobyqa') && options.rhobeg > min(ub-lb)/2 
        wid = sprintf('%s:InvalidRhobeg', invoker);
        wmessage = sprintf('%s: invalid rhobeg; %s requires rhobeg <= min(ub-lb)/2; it is set to min(ub-lb)/2.', invoker, solver);
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
        options.rhobeg = min(ub-lb)/2; % Here we do not take the default rhobeg
        validated = true; %!!! % Set validated=true so that options.rhobeg will not be set to the default value later
    else
        validated = true;
    end
end
if ~validated % options.rhobeg has not got a valid value yet
    if isfield(options, 'rhoend') && isrealscalar(options.rhoend)
        options.rhobeg = max(rhobeg, options.rhoend);
    else
        options.rhobeg = rhobeg;
    end
end
options.rhobeg = double(max(options.rhobeg, eps));

% Validate options.rhoend
validated = false;
if isfield(options, 'rhoend')
    if ~isrealscalar(options.rhoend) || options.rhoend > options.rhobeg
        wid = sprintf('%s:InvalidRhoend', invoker);
        wmessage = sprintf('%s: invalid rhoend; we should have rhobeg >= rhoend > 0; it is set to %f*rhobeg.', invoker, rhoend/rhobeg);
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    else
        validated = true;
    end
end
if ~validated % options.rhoend has not got a valid value yet
    options.rhoend = (rhoend/rhobeg)*options.rhobeg;
end
options.rhoend = double(max(options.rhoend, eps));

% Validate options.ftarget
validated = false;
if isfield(options, 'ftarget')
    if ~isrealscalar(options.ftarget)
        wid = sprintf('%s:InvalidFtarget', invoker); 
        wmessage = sprintf('%s: invalid ftarget; it should be real number; it is set to %f.', invoker, ftarget);
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    else
        validated = true;
    end
end
if ~validated % options.ftarget has not got a valid value yet
    options.ftarget = ftarget; 
end
options.ftarget = double(options.ftarget);

% Validate options.classical
validated = false;
if isfield(options, 'classical')
    if ~islogicalscalar(options.classical)
        wid = sprintf('%s:InvalidClassicalFlag', invoker);
        wmessage = sprintf('%s: invalid classical flag; it should be true(1) or false(0); it is set to %s.', invoker, mat2str(classical));
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    else
        validated = true;
    end
end
if ~validated % options.classical has not got a valid value yet
    options.classical = classical; 
end
options.classical = logical(options.classical);
if options.classical
    wid = sprintf('%s:Classical', invoker);
    wmessage = sprintf('%s: in classical mode, which is recommended only for research purpose; set options.classical=false to disable classical mode.', invoker);
    warning(wid, '%s', wmessage);
    warnings = [warnings, wmessage]; 
end

% Validate options.scale
validated = false;
if isfield(options, 'scale')
    if ~islogicalscalar(options.scale)
        wid = sprintf('%s:InvalidScaleFlag', invoker);
        wmessage = sprintf('%s: invalid scale flag; it should be true(1) or false(0); it is set to %s.', invoker, mat2str(scale));
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    else
        validated = true;
    end
end
if ~validated % options.scale has not got a valid value yet
    options.scale = scale; 
end
options.scale = logical(options.scale);

% Validate options.quiet
validated = false;
if isfield(options, 'quiet')
    if ~islogicalscalar(options.quiet)
        wid = sprintf('%s:InvalidQuietFlag', invoker);
        wmessage = sprintf('%s: invalid quiet flag; it should be true(1) or false(0); it is set to %s.', invoker, mat2str(quiet));
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    else
        validated = true;
    end
end
if ~validated % options.quiet has not got a valid value yet
    options.quiet = quiet;
end
options.quiet = logical(options.quiet);

% Validate options.debug
validated = false;
if isfield(options, 'debug')
    if ~islogicalscalar(options.debug)
        wid = sprintf('%s:InvalidDebugflag', invoker);
        wmessage = sprintf('%s: invalid debug flag; it should be true(1) or false(0); it is set to %s.', invoker, mat2str(debugflag));
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    else
        validated = true;
    end
end
if ~validated % options.debug has not got a valid value yet
    options.debug = debugflag;
end
options.debug = logical(options.debug);
if options.debug
    wid = sprintf('%s:Debug', invoker);
    wmessage = sprintf('%s: in debug mode; set options.debug=false to disable debug.', invoker);
    warning(wid, '%s', wmessage);
    warnings = [warnings, wmessage]; 
%    if options.quiet
%        options.quiet = false;
%        wid = sprintf('%s:Debug', invoker);
%        wmessage = sprintf('%s: options.quiet is set to false because options.debug=true.', invoker);
%        warning(wid, '%s', wmessage);
%        warnings = [warnings, wmessage]; 
%    end
end

% Validate options.chkfunval
validated = false;
if isfield(options, 'chkfunval')
    if ~islogicalscalar(options.chkfunval)
        wid = sprintf('%s:InvalidChkfunval', invoker);
        wmessage = sprintf('%s: invalid chkfunval flag; it should be true(1) or false(0); it is set to %s.', invoker, mat2str(chkfunval&&options.debug));
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    elseif logical(options.chkfunval) && ~options.debug
        wid = sprintf('%s:InvalidChkfunval', invoker);
        wmessage = sprintf('%s: chkfunval=true but debug=false; chkfunval is set to false; set both flags to true to check function values.', invoker);
        warning(wid, '%s', wmessage);
        warnings = [warnings, wmessage]; 
    else
        validated = true;
    end
end
if ~validated % options.chkfunval has not got a valid value yet
    options.chkfunval = logical(chkfunval) && options.debug;
end
if options.chkfunval
    wid = sprintf('%s:Chkfunval', invoker);
    if strcmp(solver, 'cobyla')
        wmessage = sprintf('%s: checking whether fx=fun(x) and conval=con(x) at exit, which costs an extra function/constraint evaluation; set options.chkfunval=false to disable the check.', invoker);
    else
        wmessage = sprintf('%s: checking whether fx=fun(x) at exit, which costs an extra function evaluation; set options.chkfunval=false to disable the check.', invoker);
    end
    warning(wid, '%s', wmessage);
    warnings = [warnings, wmessage]; 
end

% pre_options finished
return

%%%%%%%%%%%%%%%%%%%%%% Function for reducing the problem %%%%%%%%%%%%%%%%
function [fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon] = reduce_problem(fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon, fixedx)
freex = ~fixedx;
fixedx_value = (lb(fixedx) + ub(fixedx))/2;
fun = @(freex_value) fun(fullx(freex_value, fixedx_value, freex, fixedx));
x0 = x0(freex);
if ~isempty(Aineq) 
    bineq = bineq - Aineq(:, fixedx) * fixedx_value;
    Aineq = Aineq(:, freex);
end
if ~isempty(Aeq)
    beq = beq - Aeq(:, fixedx) * fixedx_value;
    Aeq = Aeq(:, freex);
end
if ~isempty(lb) 
    lb = lb(freex);
end
if ~isempty(ub)
    ub = ub(freex);
end
if ~isempty(nonlcon)
    nonlcon = @(freex_value) nonlcon(fullx(freex_value, fixedx_value, freex, fixedx));
end
return

function x = fullx(freex_value, fixedx_value, freex, fixedx) 
x = NaN(length(freex_value)+length(fixedx_value), 1);
x(freex) = freex_value;
x(fixedx) = fixedx_value;
return

%%%%%%%%%%%%%%%%%%%%%% Function for scaling the problem %%%%%%%%%%%%%%%%
function [fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon, scaling_factor, shift, substantially_scaled, warnings] = scale_problem(invoker, fun, x0, Aineq, bineq, Aeq, beq, lb, ub, nonlcon, warnings)
% x_before_scaling = scaling_factor.*x_after_scaling + shift

% Question: What about scaling according to the magnitude of x0, lb, ub, 
% x0-lb, ub-x0?
% This can be useful if lb and ub reflect the nature of the problem
% well, and x0 is a reasonable approximation to the optimal solution.
% Otherwise, it may be a bad idea. 

callstack = dbstack;
funname =callstack(1).name; % Name of the current function

substantially_scaled_threshold = 4;
% We consider the problem substantially scaled_threshold if  
% max(scaling_factor)/min(scaling_factor) > substantially_scaled_threshold

lenx0 = length(x0);
index_lub = (lb > -inf) & (ub < inf); % Variables with lower and upper bounds
scaling_factor = ones(lenx0, 1);
shift = zeros(lenx0, 1);
scaling_factor(index_lub) = (ub(index_lub) - lb(index_lub))/2;
shift(index_lub) = (lb(index_lub) + ub(index_lub))/2;
shift(~index_lub) = x0(~index_lub); % Shift x0 to 0 unless both lower and upper bounds are present

fun = @(x) fun(scaling_factor.*x+shift);
x0 = (x0-shift)./scaling_factor;
if ~isempty(Aineq) 
% Aineq*x_before_scaling <= bineq 
% <==> Aineq*(scaling_factor.*x_after_scaling+shift) <= bineq  
% <==> (Aineq*diag(scaling_factor))*x_after_scaling <= bineq - Aineq*shift 
    bineq = bineq - Aineq*shift;
    Aineq = Aineq*diag(scaling_factor); 
end
if ~isempty(Aeq)
    beq = beq - Aeq*shift;
    Aeq = Aeq*diag(scaling_factor); 
end
if ~isempty(lb) 
% lb < x_before_scaling < ub
% <==> lb < scaling_factor.*x_after_scaling + shift < ub
% <==> (lb-shift)./scaling_factor < x_after_scaling < (ub-shift)./scaling_facor
    lb = (lb-shift)./scaling_factor;
end
if ~isempty(ub)
    ub = (ub-shift)./scaling_factor;
end
if ~isempty(nonlcon)
    nonlcon = @(x) nonlcon(scaling_factor.*x+shift);
end

if any(scaling_factor ~= 1)
    wid = sprintf('%s:ProblemScaled', invoker);
    wmessage = sprintf('%s: problem scaled according to bound constraints; do this only if the bounds reflect the scaling of variables; if not, set options.scale=false to disable scaling.', invoker);
    warning(wid, '%s', wmessage);
    warnings = [warnings, wmessage]; 
end

substantially_scaled = false;
%if (max([scaling_factor; 1./scaling_factor]) > substantially_scaled_threshold)
if max(scaling_factor)/min(scaling_factor) > substantially_scaled_threshold
    substantially_scaled = true;
    % This will affect the setting of rhobeg and rhoend: If x is substantially
    % scaled, then we 
    % rhobeg = 1, rhoend = previously_defiend_rhoend/previously_defined_rhobeg. 
end

if min(scaling_factor) < eps
    % Private/unexpcted error
    error(sprintf('%s:InvalidScaling', funname), '%s: UNEXPECTED ERROR: invalid scaling factor returned.', funname);
end
return

%%%%%%%%%%%%%%%%%%%%%%%% Function for selecting solver %%%%%%%%%%%%%%%%%%%%
function [solver, options, warnings] = select_solver(invoker, options, probinfo, warnings)

invoker_list = {'pdfo'};
% Only pdfo needs select_solver. We may have other invokers in the future!
solver_list = {'uobyqa', 'newuoa', 'bobyqa', 'lincoa', 'cobyla'}; 
% We may add other solvers in the future! 
% Note that pdfo is not a possible solver here! 
callstack = dbstack;
funname =callstack(1).name; % Name of the current function

if ~ismember(invoker, invoker_list) 
    % Private/unexpected error
    error(sprintf('%s:InvalidInvoker', funname), ...
    '%s: UNEXPECTED ERROR: %s serves only %s.', funname, funname, mystrjoin(invoker_list, ', '));
end
% After pre_options, options.solver is either a member of solver_list or [].
% 1. If options.solver is in solver_list, we check whether it can solve the
% problem. If yes, we set solver=options.solver; otherwise, we warn about 
% 'invalid solver' and select a solver. 
% 2. If options.solver is [], we do not complain but select a solver. We
% should not complain because either the user does not specify a solver, which 
% is perfectly fine, or an unknown solver was specified, which has already 
% invoked a warning in pre_options.

solver = options.solver; 
ptype = probinfo.refined_type;
n = probinfo.refined_dim;

% Is the user-defined options.solver correct?
solver_correct = ~isempty(solver) && prob_solv_match(ptype, solver); 

if ~solver_correct 
    if ~isempty(solver) % Do not complain if options.solver is empty.
        wid = sprintf('%s:InvalidSolver', invoker);
        wmessage = sprintf('%s: %s cannot solve a %s problem; %s will select a solver automatically.', invoker, solver, strrep(ptype, '-', ' '), invoker);
        warning(wid, '%s', wmessage); 
        warnings = [warnings, wmessage];
    end
    switch ptype
    case 'unconstrained'
        if (n >= 2 && n <= 8 && options.maxfun >= (n+1)*(n+2)/2 + 1)
            solver = 'uobyqa'; % uobyqa does not need options.npt
        elseif (options.maxfun <= n+2) % After prepdfo, options.maxfun>=n+2 is ensured. Thus options.maxfun<=n+2 indeed means options.maxfun=n+2
            solver = 'cobyla'; % cobyla does not need options.npt
        else 
            solver = 'newuoa';
            options.npt = min(2*n+1, options.maxfun - 1);
            % Interestingly, we note in our test that lincoa outperformed 
            % newuoa on unconstrained CUTEst problems when the dimension 
            % was not large (i.e., <=50) or the precision requirement
            % was not high (i.e., >=1e-5). Therefore, it is worthwhile to 
            % try lincoa when an unconstrained problem is given. 
            % Nevertheless, for the moment, we set the default solver 
            % for unconstrained problems to be newuoa.
        end
    case 'bound-constrained'
        if (options.maxfun <= n+2)
            solver = 'cobyla'; % cobyla does not need options.npt
        else
            solver = 'bobyqa';
            options.npt = min(2*n+1, options.maxfun - 1);
            rhobeg_bobyqa = min(options.rhobeg, min(probinfo.ub-probinfo.lb)/2);
            options.rhoend = (options.rhoend/options.rhobeg)*rhobeg_bobyqa;
            options.rhobeg = max(rhobeg_bobyqa, eps);
            options.rhoend = max(options.rhoend, eps);
        end
    case 'linearly-constrained'
        if (options.maxfun <= n+2)
            solver = 'cobyla'; % cobyla does not need options.npt
        else
            solver = 'lincoa';
            options.npt = min(2*n+1, options.maxfun - 1);
        end
    case 'nonlinearly-constrained'
        solver = 'cobyla'; % cobyla does not need options.npt
    otherwise
        % Private/unexpected error
        error(sprintf('%s:InvalidProbType', funname), '%s: UNEXPECTED ERROR: unknown problem type ''%s'' received.', funname, ptype);
    end
end
if ~ismember(solver, solver_list) || ~prob_solv_match(ptype, solver)
    % Private/unexpected error
    error(sprintf('%s:InvalidSolver', funname), '%s: UNEXPECTED ERROR: invalid solver ''%s'' selected.', funname, solver);
end
return

%%%%%%%%%%%%%%%%%%%%%%% Function for checking problem type %%%%%%%%%%%%%% 
function ptype = problem_type(Aineq, Aeq, lb, ub, nonlcon)
callstack = dbstack;
funname = callstack(1).name; % Name of the current function 

ptype_list = {'unconstrained', 'bound-constrained', 'linearly-constrained', 'nonlinearly-constrained'}; 

if ~isempty(nonlcon) 
    ptype = 'nonlinearly-constrained';
elseif ~isempty(Aineq) || ~isempty(Aeq)
    ptype = 'linearly-constrained';
elseif (~isempty(lb) && max(lb) > -inf) || (~isempty(ub) && min(ub) < inf)
    ptype = 'bound-constrained';
else
    ptype = 'unconstrained';
end

if ~ismember(ptype, ptype_list)
    % Private/unexpected error
    error(sprintf('%s:InvalidProbType', funname), ...
        '%s: UNEXPECTED ERROR: unknown problem type ''%s'' returned.', funname, ptype);
end
return

%%%%%%% Function for checking whether problem type matches solver  %%%%%%
function match = prob_solv_match(ptype, solver)
callstack = dbstack;
funname = callstack(1).name; % Name of the current function 

solver_list = {'uobyqa', 'newuoa', 'bobyqa', 'lincoa', 'cobyla', 'pdfo'}; 
% Note: pdfo is also a possible solver when prob_solv_match is called in
% prepdfo to check whether the invoker can handle the problem. 
if ~ismember(solver, solver_list)
    % Private/unexpected error
    error(sprintf('%s:InvalidSolver', funname), ...
    '%s: UNEXPECTED ERROR: unknown solver ''%s'' received.', funname, solver);
end

match = true;
switch ptype
case 'unconstrained'
    match = true;
    % Essentially do nothing. DO NOT remove this case. Otherwise, the
    % case would be included in 'otherwise', which is not correct. 
case 'bound-constrained'
    if any(strcmp(solver, {'uobyqa', 'newuoa'}))
        match = false;
    end
case 'linearly-constrained'
    if any(strcmp(solver, {'uobyqa', 'newuoa', 'bobyqa'}))
        match = false;
    end
case 'nonlinearly-constrained'
    if any(strcmp(solver, {'uobyqa', 'newuoa', 'bobyqa', 'lincoa'}))
        match = false;
    end
otherwise
    % Private/unexpected error
    error(sprintf('%s:InvalidProbType', funname), '%s: UNEXPECTED ERROR: unknown problem type ''%s'' received.', funname, ptype);
end
return

%%%%%%%%%%%%%%% Function for calculating constraint violation %%%%%%%%%%
function constrviolation = constrv(x, Aineq, bineq, Aeq, beq, lb, ub, nonlcon)
constrviolation = max(0, max([lb-x; x-ub]./max(1, abs([lb; ub]))));
if ~isempty(Aineq)
    constrviolation = max([constrviolation; (Aineq*x - bineq)./max(1, abs(bineq))]);
end
if ~isempty(Aeq)
    constrviolation = max([constrviolation; abs(Aeq*x - beq)./max(1, abs(beq))]);
end
if ~isempty(nonlcon)
    [nlcineq, nlceq] = nonlcon(x);
    constrviolation = max([constrviolation; nlcineq; abs(nlceq)]);
end
return

%%%%%%%%%%%%%%%%%%%%%%%%%%% Auxiliary functions %%%%%%%%%%%%%%%%%%%%%%%%%%
function [isrm, m, n] = isrealmatrix(x)  % isrealmatrix([]) = true
if isempty(x)
    isrm = true;
    m = 0;
    n = 0;
elseif isnumeric(x) && isreal(x) && ismatrix(x)
    isrm = true;
    [m, n] = size(x);
else
    isrm = false;
    m = NaN;
    n = NaN;
end
return

function [isrc, len] = isrealcolumn(x) % isrealcolumn([]) = true
if isempty(x)
    isrc = true;
    len = 0;
elseif isnumeric(x) && isreal(x) && isvector(x) && (size(x, 2) == 1)
    isrc = true;
    len = length(x);
else
    isrc = false;
    len = NaN;
end
return

function [isrr, len] = isrealrow(x) % isrealrow([]) = true
if isempty(x)
    isrr = true;
    len = 0;
elseif isnumeric(x) && isreal(x) && isvector(x) && size(x, 1) == 1
    isrr = true;
    len = length(x);
else
    isrr = false;
    len = NaN;
end
return

function [isrv, len] = isrealvector(x)  % isrealvector([]) = true
if isrealrow(x) || isrealcolumn(x)
    isrv = true;
    len = length(x);
else
    isrv = false;
    len = NaN;
end
return

function isrs = isrealscalar(x)  % isrealscalar([]) = FALSE !!! 
isrs = isnumeric(x) && isreal(x) && isscalar(x);
return

function isis = isintegerscalar(x)  % isintegerscalar([]) = FALSE !!! 
isis = isrealscalar(x) && (rem(x,1) == 0);
return

function isls = islogicalscalar(x) % islogicalscalar([]) = FALSE !!!
if isa(x, 'logical') && isscalar(x)
    isls = true;
elseif isrealscalar(x) && (x==1 || x==0) % !!!
    isls = true;
else
    isls = false;
end
return

function T = rmempty(S) % Remove empty fields in a structure
callstack = dbstack; 
funname =callstack(1).name; % Name of the current function
if isempty(S)
    S = struct(); % Here we do not disthinguish empty objects. It is fine in this package, but may not be in others
end
if ~isa(S, 'struct')
    % Private/unexpected error
    error(sprintf('%s:InvalidInput', funname), '%s: UNEXPECTED ERROR: input should be a structure.', funname);
end
fn = fieldnames(S);
empty_index = cellfun(@(f) isempty(S.(f)), fn);
T = rmfield(S, fn(empty_index));
return
