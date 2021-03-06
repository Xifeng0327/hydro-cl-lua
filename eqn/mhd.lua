local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local file = require 'ext.file'
local template = require 'template'
local makestruct = require 'eqn.makestruct'
local Equation = require 'eqn.eqn'

local MHD = class(Equation)

MHD.name = 'MHD'

MHD.numWaves = 7
MHD.numIntStates = 8
MHD.numStates = 10

MHD.primVars = table{
	{rho = 'real'},
	{v = 'real3'},
	{P = 'real'},
	{B = 'real3'},
	{BPot = 'real'},
	{ePot = 'real'},	-- for selfgrav
}

MHD.consVars = table{
	{rho = 'real'},
	{m = 'real3'},
	{ETotal = 'real'},
	{B = 'real3'},
	{BPot = 'real'},
	{ePot = 'real'},	-- for selfgrav
}

MHD.mirrorVars = {{'m.x', 'B.x'}, {'m.y', 'B.y'}, {'m.z', 'B.z'}}

MHD.hasEigenCode = true
MHD.hasFluxFromConsCode = true
MHD.roeUseFluxFromCons = true

-- for connections
MHD.useSourceTerm = true

-- hmm, we want init.euler and init.mhd here ...
MHD.initStates = require 'init.euler'

function MHD:init(args)
	MHD.super.init(self, args)

	if self.solver.dim > 1 then
		local NoDiv = require 'op.nodiv'
		self.solver.ops:insert(NoDiv{solver=self.solver})
	end

	-- hmm...
	local SelfGrav = require 'op.selfgrav'
	self.gravOp = SelfGrav{solver=self.solver}
	self.solver.ops:insert(self.gravOp)
end

MHD.guiVars = {
	{name='heatCapacityRatio', value=2},	-- 5/3 for most problems, but 2 for Brio-Wu, so I will just set it here for now (in case something else is reading it before it is set there)
	{name='mu0', value=1},	-- this should be 4 pi for natural units, but I haven't verified that all mu0's are where they should be ...
}

function MHD:getCommonFuncCode()
	return template([[
inline real calc_eKin(<?=eqn.prim_t?> W, real3 x) { return .5 * coordLenSq(W.v, x); }
inline real calc_EKin(<?=eqn.prim_t?> W, real3 x) { return W.rho * calc_eKin(W, x); }
inline real calc_EInt(<?=eqn.prim_t?> W) { return W.P / (heatCapacityRatio - 1.); }
inline real calc_eInt(<?=eqn.prim_t?> W) { return calc_EInt(W) / W.rho; }
inline real calc_EMag(<?=eqn.prim_t?> W, real3 x) { return .5 * coordLenSq(W.B, x); }
inline real calc_eMag(<?=eqn.prim_t?> W, real3 x) { return calc_EMag(W, x) / W.rho; }
inline real calc_PMag(<?=eqn.prim_t?> W, real3 x) { return .5 * coordLenSq(W.B, x); }
inline real calc_EHydro(<?=eqn.prim_t?> W, real3 x) { return calc_EKin(W, x) + calc_EInt(W); }
inline real calc_eHydro(<?=eqn.prim_t?> W, real3 x) { return calc_EHydro(W, x) / W.rho; }
inline real calc_ETotal(<?=eqn.prim_t?> W, real3 x) { return calc_EKin(W, x) + calc_EInt(W) + calc_EMag(W, x) + W.rho * W.ePot; }
inline real calc_eTotal(<?=eqn.prim_t?> W, real3 x) { return calc_ETotal(W, x) / W.rho; }
inline real calc_H(real P) { return P * (heatCapacityRatio / (heatCapacityRatio - 1.)); }
inline real calc_h(real rho, real P) { return calc_H(P) / rho; }
inline real calc_HTotal(<?=eqn.prim_t?> W, real ETotal, real3 x) { return W.P + calc_PMag(W, x) + ETotal; }
inline real calc_hTotal(<?=eqn.prim_t?> W, real ETotal, real3 x) { return calc_HTotal(W, ETotal, x) / W.rho; }

//notice, this is speed of sound, to match the name convention of eqn/euler
//but Cs in eigen_t is the slow speed
//most the MHD papers use 'a' for the speed of sound
inline real calc_Cs(<?=eqn.prim_t?> W) { return sqrt(heatCapacityRatio * W.P / W.rho); }
]], {
		eqn = self,
	})
end

function MHD:getPrimConsCode()
	return template([[
inline <?=eqn.prim_t?> primFromCons(
	<?=eqn.cons_t?> U,
	real3 x
) {
	<?=eqn.prim_t?> W;
	W.rho = U.rho;
	W.v = real3_scale(U.m, 1./U.rho);
	W.B = U.B;
	real vSq = coordLenSq(W.v, x);
	real BSq = coordLenSq(W.B, x);
	real EKin = .5 * U.rho * vSq;
	real EMag = .5 * BSq;
	real EPot = U.rho * U.ePot;
	real EInt = U.ETotal - EKin - EMag - EPot;
	W.P = EInt * (heatCapacityRatio - 1.);
	W.P = max(W.P, (real)1e-7);
	W.rho = max(W.rho, (real)1e-7);
	W.BPot = U.BPot;
	W.ePot = U.ePot;
	return W;
}

inline <?=eqn.cons_t?> consFromPrim(<?=eqn.prim_t?> W, real3 x) {
	<?=eqn.cons_t?> U;
	U.rho = W.rho;
	U.m = real3_scale(W.v, W.rho);
	U.B = W.B;
	real vSq = coordLenSq(W.v, x);
	real BSq = coordLenSq(W.B, x);
	real EKin = .5 * W.rho * vSq;
	real EMag = .5 * BSq;
	real EInt = W.P / (heatCapacityRatio - 1.);
	U.ETotal = EInt + EKin + EMag;
	U.BPot = W.BPot;
	U.ePot = W.ePot;
	return U;
}

<?=eqn.cons_t?> apply_dU_dW(
	<?=eqn.prim_t?> WA, 
	<?=eqn.prim_t?> W, 
	real3 x
) {
	return (<?=eqn.cons_t?>){
		.rho = W.rho,
		.m = real3_add(
			real3_scale(WA.v, W.rho),
			real3_scale(W.v, WA.rho)),
		.B = WA.B,
		.ETotal = W.rho * .5 * real3_dot(WA.v, WA.v)
			+ WA.rho * real3_dot(W.v, WA.v)
			+ real3_dot(W.B, WA.B) / mu0
			+ W.P / (heatCapacityRatio - 1.)
			+ WA.rho * W.ePot,
		.BPot = W.BPot,
		.ePot = W.ePot,
	};
}

<?=eqn.prim_t?> apply_dW_dU(
	<?=eqn.prim_t?> WA,
	<?=eqn.cons_t?> U,
	real3 x
) {
	return (<?=eqn.prim_t?>){
		.rho = U.rho,
		.v = real3_sub(
			real3_scale(U.m, 1. / WA.rho),
			real3_scale(WA.v, U.rho / WA.rho)),
		.B = U.B,
		.P = (heatCapacityRatio - 1.) *  (
			.5 * U.rho * real3_dot(WA.v, WA.v)
			- real3_dot(U.m, WA.v)
			- real3_dot(U.B, WA.B) / mu0
			+ U.ETotal
			- WA.rho * U.ePot),
		.BPot = U.BPot,
		.ePot = U.ePot,
	};
}
]], {
		eqn = self,
	})
end

MHD.initStateCode = [[
<? local xNames = require 'common'().xNames ?>
kernel void initState(
	global <?=eqn.cons_t?>* UBuf
) {
	SETBOUNDS(0,0);
	real3 x = cell_x(i);
	real3 mids = real3_scale(real3_add(mins, maxs), .5);
	bool lhs = true
<?
for i=1,solver.dim do
	local xi = xNames[i]
?>	&& x.<?=xi?> < mids.<?=xi?>
<?
end
?>;

	real rho = 0;
	real3 v = _real3(0,0,0);
	real P = 0;
	real3 B = _real3(0,0,0);

	<?=code?>
	
	<?=eqn.prim_t?> W = {
		.rho = rho,
		.v = cartesianToCoord(v, x),
		.P = P,
		.B = cartesianToCoord(B, x),
		.BPot = 0,
	};
	UBuf[index] = consFromPrim(W, x);
}
]]

MHD.solverCodeFile = 'eqn/mhd.cl'

MHD.displayVarCodeUsesPrims = true

function MHD:getDisplayVars()
	return MHD.super.getDisplayVars(self):append{
		{v = '*valuevec = W.v;', type='real3'},
		{['div B'] = template([[
	*value = .5 * (0.
<? 
for j=0,solver.dim-1 do 
?>		+ (U[stepsize.s<?=j?>].<?=field?>.s<?=j?> 
			- U[-stepsize.s<?=j?>].<?=field?>.s<?=j?>
		) / grid_dx<?=j?>
<? 
end 
?>	)<? 
if field == 'epsE' then 
?> / eps0<?
end
?>;
]], {solver=self.solver, field='B'})},
		{['BPot'] = '*value = U->BPot;'},
		{P = '*value = W.P;'},
		--{PMag = '*value = calc_PMag(W, x);'},
		--{PTotal = '*value = W.P + calc_PMag(W, x);'},
		--{eInt = '*value = calc_eInt(W);'},
		{EInt = '*value = calc_EInt(W);'},
		--{eKin = '*value = calc_eKin(W, x);'},
		{EKin = '*value = calc_EKin(W, x);'},
		--{eHydro = '*value = calc_eHydro(W, x);'},
		{EHydro = '*value = calc_EHydro(W, x);'},
		--{eMag = '*value = calc_eMag(W, x);'},
		{EMag = '*value = calc_EMag(W, x);'},
		--{eTotal = '*value = U->ETotal / W.rho;'},
		{S = '*value = W.P / pow(W.rho, (real)heatCapacityRatio);'},
		{H = '*value = calc_H(W.P);'},
		--{h = '*value = calc_H(W.P) / W.rho;'},
		--{HTotal = '*value = calc_HTotal(W, U->ETotal, x);'},
		--{hTotal = '*value = calc_hTotal(W, U->ETotal, x);'},
		--{Cs = '*value = calc_Cs(W); },
		{['primitive reconstruction error'] = template([[
		//prim have just been reconstructed from cons
		//so reconstruct cons from prims again and calculate the difference
		<?=eqn.cons_t?> U2 = consFromPrim(W, x);
		*value = 0;
		for (int j = 0; j < numIntStates; ++j) {
			*value += fabs(U->ptr[j] - U2.ptr[j]);
		}
]], {
	eqn = self,
})},
	}
end


-- these are calculated based on cell-centered (or extrapolated) conserved vars
-- they are used to calculate the eigensystem at a cell center or edge 
MHD.roeVars = table{
	{rho = 'real'},
	{v = 'real3'},
	{hTotal = 'real'},
	{B = 'real3'},
	{X = 'real'},
	{Y = 'real'},
}


-- here's the variables that an eigensystem uses to compute a left, right, or flux transform 
MHD.eigenVars = table(MHD.roeVars):append{

	{hHydro = 'real'},
	{aTildeSq = 'real'},

	{Cs = 'real'},
	{CAx = 'real'},
	{Cf = 'real'},

	{BStarPerpLen = 'real'},
	{betaY = 'real'},
	{betaZ = 'real'},
	{betaStarY = 'real'},
	{betaStarZ = 'real'},
	{betaStarSq = 'real'},

	{alphaF = 'real'},
	{alphaS = 'real'},

	{sqrtRho = 'real'},
	{sbx = 'real'},
	{Qf = 'real'},
	{Qs = 'real'},
	{Af = 'real'},
	{As = 'real'},
}


function MHD:getEigenTypeCode()
	return table{
		makestruct.makeStruct('Roe_t', self.roeVars),
		MHD.super.getEigenTypeCode(self),
	}:concat'\n'
end

function MHD:eigenWaveCode(side, eig, x, waveIndex)
	eig = '('..eig..')'
	return ({
		eig..'.v.x - '..eig..'.Cf',
		eig..'.v.x - '..eig..'.CAx',
		eig..'.v.x - '..eig..'.Cs',
		eig..'.v.x',
		eig..'.v.x + '..eig..'.Cs',
		eig..'.v.x + '..eig..'.CAx',
		eig..'.v.x + '..eig..'.Cf',
	})[waveIndex+1]
end

-- this is all temporary fix until I properly code the inlining

MHD.hasCalcDTCode = true

function MHD:consWaveCodePrefix(side, U, x)
	return template([[
	range_t lambda = calcCellMinMaxEigenvalues_<?=side?>(&<?=U?>, <?=x?>); 
]], {
		side = side,
		U = '('..U..')',
		x = x,
	})
end

function MHD:consMinWaveCode(side, U, x)
	return 'lambda.min'
end

function MHD:consMaxWaveCode(side, U, x)
	return 'lambda.max'
end

return MHD
