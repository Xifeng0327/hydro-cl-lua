local class = require 'ext.class'
local table = require 'ext.table'
local file = require 'ext.file'
local processcl = require 'processcl'
local clnumber = require 'clnumber'
local Equation = require 'eqn.eqn'

local Euler = class(Equation)
Euler.name = 'Euler'

Euler.numStates = 5

Euler.consVars = {'rho', 'mx', 'my', 'mz', 'ETotal'}
Euler.primVars = {'rho', 'vx', 'vy', 'vz', 'P'}
Euler.mirrorVars = {{'m.x'}, {'m.y'}, {'m.z'}}
Euler.displayVars = {
	'rho',
	'vx', 'vy', 'vz', 'v',
	'mx', 'my', 'mz', 'm',
	'eInt',
	'eKin', 
	'ePot',
	'eTotal', 
	'EInt', 
	'EKin', 
	'EPot',
	'ETotal', 
	'P',
	'S', 
	'h',
	'H', 
	'hTotal',
	'HTotal',
} 

Euler.hasEigenCode = true
Euler.hasCalcDT = true
-- only for geometry's sake ...
Euler.useSourceTerm = true

Euler.initStates = require 'init.euler'
Euler.initStateNames = table.map(Euler.initStates, function(info) return info.name end)

Euler.guiVars = table{
	require 'guivar.float'{name='gamma', value=7/5}
}
Euler.guiVarsForName = Euler.guiVars:map(function(var) return var, var.name end)

function Euler:getTypeCode()
	return [[
typedef struct { 
	real rho;
	real3 v;
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
	real3 m;
	real ETotal;
} cons_t;
]]
end

function Euler:getCodePrefix()
	return table{
		Euler.super.getCodePrefix(self),
		[[
#define gamma_1 (gamma-1.)

inline real calc_H(real P) { return P * (gamma / gamma_1); }
inline real calc_h(real rho, real P) { return calc_H(P) / rho; }
inline real calc_hTotal(real rho, real P, real ETotal) { return (P + ETotal) / rho; }
inline real calc_HTotal(real P, real ETotal) { return P + ETotal; }
inline real calc_eKin(prim_t W) { return .5 * coordLenSq(W.v); }
inline real calc_EKin(prim_t W) { return W.rho * calc_eKin(W); }
inline real calc_EInt(prim_t W) { return W.P / gamma_1; }
inline real calc_eInt(prim_t W) { return calc_EInt(W) / W.rho; }
inline real calc_EKin_fromCons(cons_t U) { return .5 * coordLenSq(U.m) / U.rho; }
inline real calc_ETotal(prim_t W, real ePot) {
	real EPot = W.rho * ePot;
	return calc_EKin(W) + calc_EInt(W) + EPot;
}
inline real calc_Cs(prim_t W) { return sqrt(gamma * W.P / W.rho); }
inline prim_t primFromCons(cons_t U, real ePot) {
	real EPot = U.rho * ePot;
	real EKin = calc_EKin_fromCons(U);
	real EInt = U.ETotal - EPot - EKin;
	return (prim_t){
		.rho = U.rho,
		.v = real3_scale(U.m, 1./U.rho),
		.P = EInt / gamma_1,
	};
}
]],
	}:concat'\n'
end

function Euler:getInitStateCode(solver)
	local initState = self.initStates[1+solver.initStatePtr[0]]
	assert(initState, "couldn't find initState "..solver.initStatePtr[0])	
	local code = initState.init(solver)	
	return table{
		[[
cons_t consFromPrim(prim_t W, real ePot) {
	return (cons_t){
		.rho = W.rho,
		.m = real3_scale(W.v, W.rho),
		.ETotal = calc_ETotal(W, ePot),
	};
}

__kernel void initState(
	__global cons_t* UBuf,
	__global real* ePotBuf
) {
	SETBOUNDS(0,0);
	
	//TODO should 'x' be in embedded or coordinate space? coordinate 
	//should 'vx vy vz' be embedded or coordinate space? coordinate
	real3 x = cell_x(i);
	real3 mids = real3_scale(real3_add(mins, maxs), .5);
	bool lhs = x.x < mids.x
#if dim > 1
		&& x.y < mids.y
#endif
#if dim > 2
		&& x.z < mids.z
#endif
	;
	real rho = 0;
	real3 v = _real3(0,0,0);
	real P = 0;
	real ePot = 0;

]]..code..[[

	prim_t W = {.rho=rho, .v=v, .P=P};
	UBuf[index] = consFromPrim(W, ePot);
	ePotBuf[index] = ePot;
}
]],
	}:concat'\n'
end

function Euler:getSolverCode(solver)	
	return processcl(assert(file['eqn/euler.cl']), {eqn=self, solver=solver})
end

function Euler:getCalcDisplayVarCode()
	return [[
	prim_t W = primFromCons(U, ePot);
	switch (displayVar) {
	case display_U_rho: value = W.rho; break;
	case display_U_vx: value = W.v.x; break;
	case display_U_vy: value = W.v.y; break;
	case display_U_vz: value = W.v.z; break;
	case display_U_v: value = coordLen(W.v); break;
	case display_U_mx: value = U.m.x; break;
	case display_U_my: value = U.m.y; break;
	case display_U_mz: value = U.m.z; break;
	case display_U_m: value = coordLen(U.m); break;
	case display_U_P: value = W.P; break;
	case display_U_eInt: value = calc_eInt(W); break;
	case display_U_eKin: value = calc_eKin(W); break;
	case display_U_ePot: value = ePot; break;
	case display_U_eTotal: value = U.ETotal / W.rho; break;
	case display_U_EInt: value = calc_EInt(W); break;
	case display_U_EKin: value = calc_EKin(W); break;
	case display_U_EPot: value = W.rho * ePot; break;
	case display_U_ETotal: value = U.ETotal; break;
	case display_U_S: value = W.P / pow(W.rho, (real)gamma); break;
	case display_U_H: value = calc_H(W.P); break;
	case display_U_h: value = calc_h(W.rho, W.P); break;
	case display_U_HTotal: value = calc_HTotal(W.P, U.ETotal); break;
	case display_U_hTotal: value = calc_hTotal(W.rho, W.P, U.ETotal); break;
	}
]]
end

function Euler:getEigenTypeCode(solver)
	return [[
typedef struct {
	// Roe-averaged vars
	real rho;
	real3 v;
	real hTotal;

	// derived vars
	real vSq;
	real Cs;
} eigen_t;
]]
end

function Euler:getEigenDisplayVars(solver)
	return {'rho', 'vx', 'vy', 'vz', 'v', 'hTotal', 'vSq', 'Cs'}
end

function Euler:getEigenCalcDisplayVarCode(solver)
	return [[
	switch (displayVar) {
	case display_eigen_rho: value = eigen->rho; break;
	case display_eigen_vx: value = eigen->v.x; break;
	case display_eigen_vy: value = eigen->v.y; break;
	case display_eigen_vz: value = eigen->v.z; break;
	case display_eigen_v: value = coordLen(eigen->v); break;
	case display_eigen_hTotal: value = eigen->hTotal; break;
	case display_eigen_vSq: value = eigen->vSq; break;
	case display_eigen_Cs: value = eigen->Cs; break;
	}
]]
end

return Euler
