local class = require 'ext.class'
local table = require 'ext.table'
local Equation = require 'equation'

local Euler3D = class(Equation)
Euler3D.name = 'Euler3D'

Euler3D.numStates = 5

Euler3D.consVars = table{'rho', 'mx', 'my', 'mz', 'ETotal'}
Euler3D.primVars = table{'rho', 'vx', 'vy', 'vz', 'P'}
Euler3D.displayVars = {
	'rho',
	'vx', 'vy', 'vz', 'v',
	'mx', 'my', 'mz', 'm',
	'eInt',
	'eKin', 
	'eTotal', 
	'EInt', 
	'EKin', 
	'ETotal', 
	'P',
	'S', 
	'h',
	'H', 
	'hTotal',
	'HTotal',
} 

Euler3D.initStateInfos = {
	{
		name='Sod',
		code=[[
	rho = lhs ? 1 : .125;
	P = lhs ? 1 : .1;
]]
	},
	{
		name='Sedov',
		code=[[
	rho = 1;
	P = (i.x == gridSize.x/2 && i.y == gridSize.y/2 && i.z == gridSize.z/2) ? 1e+3 : 1;
]]
	},
	{
		name='constant',
		code='rho=2+x.x; P=1;'
	},
	{
		name='linear',
		code='rho=2+x.x; P=1;'
	},
	{
		name='gaussian',
		code=[[
	real sigma = 1. / sqrt(10.);
	rho = exp(-x.x*x.x / (sigma*sigma)) + .1;
	P = 1 + .1 * (exp(-x.x*x.x / (sigma*sigma)) + 1) / (gamma_1 * rho);
]]
	},
	{
		name='rarefaction_wave',
		code=[[
	real delta = .1;
	rho = 1;	// lhs ? .2 : .8;
	vx = lhs ? .5 - delta : .5 + delta;
	P = 1;
]]
	},

	--from SRHD Marti & Muller 2000
	{
		name='shock_wave',
		code=[[
	rho = 1;
	vx = lhs ? .5 : 0;
	P = lhs ? 1e+3 : 1;
]]
	},
	{
		name='relativistic_blast_wave_interaction',
		code=[[
	real xL = .9 * mins_x + .1 * maxs_x;
	real xR = .1 * mins_x + .9 * maxs_x;
	rho = 1;
	P = x.x < xL ? 1000 : (x.x > xR ? 100 : .01);
]]
	},
	{
		name='relativistic_blast_wave_test_problem_1',
		gamma = 5/3,
		code=[[
	rho = lhs ? 10 : 1;
	P = gamma_1 * rho * (lhs ? 2 : 1e-6);
]]
	},
}

Euler3D.initStateNames = table.map(Euler3D.initStateInfos, function(info) return info.name end)

function Euler3D:getTypeCode()
	return [[

typedef struct { 
	real rho;
	union {
		struct { real vx, vy, vz; };
		real v[3];
	};
	real P;
} prim_t;

enum {
	cons_rho,
	cons_mx,
	cons_my,
	cons_mz,
	cons_ETotal,
};

typedef struct {
	real rho;
	union {
		struct { real mx, my, mz; };
		real m[3];
	};
	real ETotal;
} cons_t;

]]
end

function Euler3D:solverCode(clnumber, solver)
	local initState = self.initStateInfos[1+solver.initStatePtr[0]]
	assert(initState, "couldn't find initState "..solver.initStatePtr[0])	
	local initStateDefLines = '#define INIT_STATE_CODE \\\n'
		.. initState.code:gsub('\n', '\\\n')
	
	-- TODO make this a gui variable, and modifyable in realtime?
	local gamma = initState.gamma or 7/5
	
	return table{
		'#define gamma '..clnumber(gamma),
		initStateDefLines,
		'#include "euler3d.cl"',
	}:concat'\n'
end

-- TODO boundary methods, esp how to handle mirror

return Euler3D
