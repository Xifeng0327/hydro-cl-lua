--[[
based on Trangenstein

for curved space, I'll keep my vectors in covariant form
this way the Levi-Civita tensor in teh flux, multiplied by the connection coefficents, when used in a holonomic basis, makes them cancel
and when used in a static grid, the g^ij_,t terms vanish,
and you get

eps0 E_i,t - 1/sqrt(g) g_il 1/mu0  epsBar^ljk      B_k,j = -j_i
     B_i,t + 1/sqrt(g) g_il 1/eps0 epsBar^ljk eps0 E_k,j =   0

so during flux computation, I need to not apply the sqrt det g
and after computing the flux vector I need to apply the metric


but there's a more advanced version in the slides by Chatterjee "Finite Volume Time Domain (FVTD) Computations for Electromagnetic Scattering"
B,t + curl E = -rho H
D,t - curl H = -J_i - sigma E
D = eps' E
B = mu' H
sigma = omega eps"
rho = omega mu"
eps_r = eps' - j eps"
mu_r = mu' - j mu"
what is rho?
what is sigma? conductance
what is eps', eps", mu', mu", omega, j?
then using Shokin, Fedurok, Lebedev, Chubarov "Parallel FVTD for Solving Maxwell Equations in Dielectric-Metal Composite Media"
I get 
D,t - curl H = 0
B,t + curl E = 0
D = eps0 eps_r E
B = mu0 H
div D = rho_free
div B = 0
Drude model: eps(omega) = eps_inf - omega_p^2 / (omega (omega + i Gamma))
--]]
local class = require 'ext.class'
local table = require 'ext.table'
local file = require 'ext.file'
local range = require 'ext.range'
local Equation = require 'eqn.eqn'
local template = require 'template'

local common = require 'common'()
local xNames = common.xNames

local Maxwell = class(Equation)

-- don't incorporate the Conn^k_ij E_k terms into the flux
Maxwell.weightFluxByGridVolume = false

Maxwell.postComputeFluxCode = [[
		//TODO shouldn't I be transforming both the left and right fluxes by the metrics at their respective coordinates?
		//flux is computed raised via Levi-Civita upper
		//so here we lower it
		real _1_sqrt_det_g = 1. / sqrt_det_g_grid(x);
		flux.epsE = real3_scale(coord_lower(flux.epsE, x), _1_sqrt_det_g);
		flux.B = real3_scale(coord_lower(flux.B, x), _1_sqrt_det_g);
]]

Maxwell.name = 'Maxwell'
Maxwell.numWaves = 6
Maxwell.numIntStates = 6

Maxwell.consVars = {
	{epsE = 'real3'},
	{B = 'real3'},
	
	{epsEPot = 'real'},
	{BPot = 'real'},
	
	{rhoCharge = 'real'},
	{sigma = 'real'},
	{eps = 'real'},
	{mu = 'real'},
}

Maxwell.mirrorVars = {{'epsE.x', 'B.x'}, {'epsE.y', 'B.y'}, {'epsE.z', 'B.z'}}

Maxwell.hasEigenCode = true
Maxwell.hasFluxFromConsCode = true
Maxwell.useSourceTerm = true
Maxwell.roeUseFluxFromCons = true

Maxwell.initStates = require 'init.euler'

function Maxwell:init(args)
	Maxwell.super.init(self, args)

	local NoDiv = require 'op.nodiv'
	self.solver.ops:insert(NoDiv{
		solver = self.solver,
	})
	-- should I be fixing div E = rhoCharge, 
	-- or should I get rid of the rhoCharge field and the div E constraint?
	self.solver.ops:insert(NoDiv{
		solver = self.solver,
		potentialField = 'epsEPot',
		chargeField = 'rhoCharge',
	})
end

function Maxwell:getCommonFuncCode()
	return template([[
//hmm, for E and B, even if the coord is 2D, we need all 3D components ...
//this means we need coordLen functions with guaranteed dimensions, including tangent spaces

real ESq(<?=eqn.cons_t?> U, real3 x) { 
	return coordLenSq(U.epsE, x) / (U.eps * U.eps);
}

real BSq(<?=eqn.cons_t?> U, real3 x) {
	return coordLenSq(U.B, x);
}

]], {
		eqn = self,
	})
end

Maxwell.initStateCode = [[
kernel void initState(
	global <?=eqn.cons_t?>* UBuf
) {
	SETBOUNDS(0,0);
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
	global <?=eqn.cons_t?>* U = UBuf + index;

	//used
	real3 E = _real3(0,0,0);
	real3 B = _real3(0,0,0);
	real conductivity = 1.;
	
	//natural units say eps0 = 1/4pi, mu0 = 4pi
	//but waves don't make it to the opposite side...
	//mu0 eps0 = 1/c^2
	real permittivity = 1.; //1. / (4. * M_PI);
	real permeability = 1.; //4. * M_PI;
	
	//throw-away
	real rho = 0;
	real3 v = _real3(0,0,0);
	real P = 0;
	real ePot = 0;
	
	<?=code?>
	
	U->epsE = cartesianToCoord(real3_scale(E, permittivity), x);
	U->B = cartesianToCoord(B, x);
	U->BPot = 0;
	U->sigma = conductivity;
	U->eps = permittivity;
	U->mu = permeability;
}
]]

function Maxwell:getSolverCode()
	return template(file['eqn/maxwell.cl'], {eqn=self})
end

-- k is 0,1,2
local function curl(eqn,k,result,field)
	local i = (k+1)%3
	local j = (i+1)%3
	return {['curl '..field..' '..xNames[k+1]] = template([[
	if (OOB(1,1)) {
		<?=result?> = 0.;
	} else {

<? if i+1 <= solver.dim then ?>
		global const <?=eqn.cons_t?>* Uim = U - stepsize.s<?=i?>;
		global const <?=eqn.cons_t?>* Uip = U + stepsize.s<?=i?>;
		real vim_j = Uim-><?=field?>.s<?=j?>;
		real vip_j = Uip-><?=field?>.s<?=j?>;
<? else ?>
		real vim_j = 0.;
		real vip_j = 0.;
<? end?>

<? if j+1 <= solver.dim then ?>
		global const <?=eqn.cons_t?>* Ujm = U - stepsize.s<?=j?>;
		global const <?=eqn.cons_t?>* Ujp = U + stepsize.s<?=j?>;
		real vjm_i = Ujm-><?=field?>.s<?=i?>;
		real vjp_i = Ujp-><?=field?>.s<?=i?>;
<? else ?>
		real vjm_i = 0.;
		real vjp_i = 0.;
<? end ?>

		<?=result?> = (vjp_i - vjm_i) / (2. * grid_dx<?=i?>)
				- (vip_j - vim_j) / (2. * grid_dx<?=j?>);
	}
]], {
		i = i,
		j = j,
		eqn = eqn,
		solver = eqn.solver,
		result = result,
		field = field,
	})}
end

--[[
for E = [0, sin(x-t), 0]
dEy/dx = cos(x-t)
so curl(E).z = -cos(x-t)
--]]
function Maxwell:getDisplayVars()
	local vars = Maxwell.super.getDisplayVars(self):append{ 
		{E = '*valuevec = real3_scale(U->epsE, 1. / U->eps);', type='real3'},
		{S = '*valuevec = real3_scale(real3_cross(U->epsE, U->B), 1. / U->eps);', type='real3'},
		{energy = [[
	*value = .5 * (coordLenSq(U->epsE, x) + coordLenSq(U->B, x) / (U->mu * U->mu));
]]},
	}:append(table{'E','B'}:map(function(var,i)
		local field = assert( ({E='epsE', B='B'})[var] )
		return {['div '..var] = template([[
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
?> / U->eps<?
end
?>;
]], {solver=self.solver, field=field})}
	end))

	for _,field in ipairs{'epsE', 'B'} do
		local v = range(0,2):map(function(i) 
			return curl(self,i,'valuevec->s'..i,field) 
		end)
		vars:insert{['curl '..field]= template([[
	<? for i=0,2 do ?>{
		<?=select(2,next(v[i+1]))?>
	}<? end ?>
]], {v=v}), type='real3'}
	end

	return vars 
end

Maxwell.eigenVars = table{
	{sqrt_eps = 'real'},
	{sqrt_mu = 'real'},
}

function Maxwell:eigenWaveCodePrefix(side, eig, x, waveIndex)
	return template([[
	real eig_lambda = 1. / (<?=eig?>.sqrt_eps * <?=eig?>.sqrt_mu);
]], {
		eig = '('..eig..')',
	})
end

function Maxwell:eigenWaveCode(side, eig, x, waveIndex)
	if waveIndex == 0 or waveIndex == 1 then
		return '-eig_lambda'
	elseif waveIndex == 2 or waveIndex == 3 then
		return '0'
	elseif waveIndex == 4 or waveIndex == 5 then
		return 'eig_lambda'
	else
		error'got a bad waveIndex'
	end
end

function Maxwell:consWaveCodePrefix(side, U, x, waveIndex)
	return template([[
	real eig_lambda = 1. / sqrt(<?=U?>.eps * <?=U?>.mu);
]], {
		U = '('..U..')',
	})
end
Maxwell.consWaveCode = Maxwell.eigenWaveCode

return Maxwell
