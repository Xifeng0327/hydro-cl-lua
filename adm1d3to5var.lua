local class = require 'ext.class'
local table = require 'ext.table'
local Equation = require 'equation'

local BonaMassoADM1D3to5Var = class(Equation)
BonaMassoADM1D3to5Var.name = 'BonaMassoADM1D3to5Var' 

BonaMassoADM1D3to5Var.numStates = 5

BonaMassoADM1D3to5Var.consVars = {'alpha', 'gamma_xx', 'a_x', 'd_xxx', 'KTilde_xx'}
BonaMassoADM1D3to5Var.mirrorVars = {{'gamma_xx', 'a_x', 'd_xxx', 'KTilde_xx'}}

BonaMassoADM1D3to5Var.initStateNames = {'gaussianWave'}

BonaMassoADM1D3to5Var.displayVars = table()
	:append(BonaMassoADM1D3to5Var.consVars)
	:append{'K_xx', 'volume'}

function BonaMassoADM1D3to5Var:getInitStateCode(solver)
	local symmath = require 'symmath'
symmath.tostring = require 'symmath.tostring.SingleLine'		
	local x = symmath.var'x'
	local alphaVar = symmath.var'alpha'
	local xc = 150
	local H = 5
	local sigma = 10
	
	--if self.initState[0] == 0 then ...
	local h = H * symmath.exp(-(x - xc)^2 / sigma^2)
	
	local kappa = 1
	local alpha = 1
	--[=[
	alpha = 1/2 * (
		(1 + symmath.sqrt(1 + kappa))
		* symmath.sqrt((1-h:diff(x))/(1+h:diff(x)))
		- 
		kappa / (1 + symmath.sqrt(1 + kappa))
		* symmath.sqrt((1+h:diff(x))/(1-h:diff(x)))
	),
	--]=]
	local gamma_xx = 1 - h:diff(x)^2
	local K_xx = -h:diff(x,x) / gamma_xx^.5

	--local f = 1
	--local f = 1.69
	--local f = .49
	local f = 1 + kappa / alphaVar^2

	-- above this line is the initial condition expressions
	-- below is the symmath codegen

	local function makesym(expr, k)
		return symmath.clone(expr):simplify(), k
	end
	
	local exprs = table{
		alpha = alpha,
		gamma_xx = gamma_xx,
		K_xx = K_xx,
	}:map(makesym)
	exprs.dx_alpha = exprs.alpha:diff(x):simplify()
	exprs.dx_gamma_xx = exprs.gamma_xx:diff(x):simplify()

	local function compileC(expr, args)
print('compile',expr,table.map(args,tostring):concat', ')
		local code = require 'symmath.tostring.C':compile(expr, args)
print('...to',code)
		return code
	end

	local codes = exprs:map(function(expr, name)
print(name)		
		return compileC(expr, {x}), name
	end)
	
	f = makesym(f)
print'f'
	codes.f = compileC(f, {alphaVar})

print'dalpha_f'
	local dalpha_f = f:diff(alphaVar):simplify()
	codes.dalpha_f = compileC(dalpha_f, {alphaVar})

	self.codes = codes

	return table{
		self:codePrefix(),
		[[
__kernel void initState(
	__global cons_t* UBuf
) {
	SETBOUNDS(0,0);
	real4 xs = CELL_X(i);
	real x = xs[0];
	__global cons_t* U = UBuf + index;
	U->alpha = init_calc_alpha(x);
	U->gamma_xx = init_calc_gamma_xx(x);
	U->a_x = init_calc_dx_alpha(x) / init_calc_alpha(x);
	U->d_xxx = .5 * init_calc_dx_gamma_xx(x);
	real K_xx = init_calc_K_xx(x);
	U->KTilde_xx = K_xx / sqrt(U->gamma_xx);
}
]],
	}:concat'\n'
end

--[[
this is called by getInitStateCode and by solverCode
getInitStateCode is called when initState changes, which rebuilds this, since it is dependent on initState (even though I only have one right now)
solverCode also uses this, but doesn't calculate it
so this will all only work right so long as solverCode() is only ever called after getInitStateCode()
--]]
function BonaMassoADM1D3to5Var:codePrefix()
	return self.codes:map(function(code,name,t)
		return 'real init_calc_'..name..code, #t+1
	end):concat'\n'
end

function BonaMassoADM1D3to5Var:solverCode()
	return table{
		self:codePrefix(),
		'#include "adm1d3to5var.cl"',
	}:concat'\n'
end

BonaMassoADM1D3to5Var.eigenVars = {'f'}
function BonaMassoADM1D3to5Var:getEigenInfo()
	local eigenType = 'eigen_t'
	return {
		type = eigenType,
		typeCode = require 'makestruct'(eigenType, self.eigenVars),
		-- don't use the default matrix stuff. instead it'll be provided in adm1d3to5var.cl
		code = nil,
		displayVars = self.eigenVars,
	}
end

return BonaMassoADM1D3to5Var 