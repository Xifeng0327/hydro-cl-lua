local table = require 'ext.table'

-- create this after 'real' is defined
--  specifically the call to 'refreshGridSize' within it
local dim = 1
local args = {
	app = self, 
	
	eqn = cmdline.eqn,
	
	dim = cmdline.dim or dim,
	
	integrator = cmdline.integrator or 'forward Euler',	
	--integrator = 'Runge-Kutta 2',
	--integrator = 'Runge-Kutta 2 Heun',
	--integrator = 'Runge-Kutta 2 Ralston',
	--integrator = 'Runge-Kutta 3',
	--integrator = 'Runge-Kutta 4',
	--integrator = 'Runge-Kutta 4, 3/8ths rule',
	--integrator = 'Runge-Kutta 2, TVD',
	--integrator = 'Runge-Kutta 2, non-TVD',
	--integrator = 'Runge-Kutta 3, TVD',
	--integrator = 'Runge-Kutta 4, TVD',
	--integrator = 'Runge-Kutta 4, non-TVD',
	--integrator = 'backward Euler',

	--fixedDT = .0001,
	--cfl = .25/dim,

	fluxLimiter = cmdline.fluxLimiter or 'superbee',

	--usePLM = true,	-- piecewise-linear slope limiter
	--fluxLimiter = 'donor cell',
	--slopeLimiter = 'minmod',
	
	-- [[ Cartesian
	geometry = 'cartesian',
	mins = cmdline.mins or {-1, -1, -1},
	maxs = cmdline.maxs or {1, 1, 1},
	-- 256^2 = 2^16 = 2 * 32^3
	gridSize = ({
		{256,1,1},
		{128,128,1},
		{32,32,32},
	})[dim],
	boundary = {
		xmin=cmdline.boundary or 'freeflow',
		xmax=cmdline.boundary or 'freeflow',
		ymin=cmdline.boundary or 'freeflow',
		ymax=cmdline.boundary or 'freeflow',
		zmin=cmdline.boundary or 'freeflow',
		zmax=cmdline.boundary or 'freeflow',
	},
	--]]
	--[[ cylinder
	geometry = 'cylinder',
	mins = cmdline.mins or {.1, 0, -1},
	maxs = cmdline.maxs or {1, 2*math.pi, 1},
	gridSize = ({
		{128, 1, 1}, -- 1D
		{32, 128, 1}, -- 2D
		{16, 64, 16}, -- 3D
	})[dim],
	boundary = {
		xmin=cmdline.boundary or 'freeflow',		-- hmm, how to treat the r=0 boundary ...
		xmax=cmdline.boundary or 'freeflow',
		ymin=cmdline.boundary or 'periodic',
		ymax=cmdline.boundary or 'periodic',
		zmin=cmdline.boundary or 'freeflow',
		zmax=cmdline.boundary or 'freeflow',
	},
	--]]
	--[[ sphere
	geometry = 'sphere',
	mins = cmdline.mins or {0, -math.pi, .5},
	maxs = cmdline.maxs or {math.pi, math.pi, 1},
	gridSize = {
		cmdline.gridSize or 64,
		cmdline.gridSize or 128,
		cmdline.gridSize or 64,
	},
	boundary = {
		xmin=cmdline.boundary or 'freeflow',
		xmax=cmdline.boundary or 'freeflow',
		ymin=cmdline.boundary or 'freeflow',
		ymax=cmdline.boundary or 'freeflow',
		zmin=cmdline.boundary or 'freeflow',
		zmax=cmdline.boundary or 'freeflow',
	},
	--]]
	--[[ sphere1d
	geometry = 'sphere1d',
	mins = cmdline.mins or {1, -math.pi, .5},
	maxs = cmdline.maxs or {100, math.pi, 1},
	gridSize = {
		cmdline.gridSize or 256,
		cmdline.gridSize or 128,
		cmdline.gridSize or 64,
	},
	boundary = {
		xmin=cmdline.boundary or 'freeflow',
		xmax=cmdline.boundary or 'freeflow',
		ymin=cmdline.boundary or 'freeflow',
		ymax=cmdline.boundary or 'freeflow',
		zmin=cmdline.boundary or 'freeflow',
		zmax=cmdline.boundary or 'freeflow',
	},
	--]]

	--useGravity = true,

	-- TODO separate initStates for each class of equation
	-- this would cohese better with the combined solvers
	-- i.e. a fluid initState, an EM init-state, and a numrel init-state
	-- ... but that means splitting the MHD init-states across M and HD ...
	-- how about just stacking initStates?
	-- and letting each one assign what values it wants.
	-- still to solve -- how do we specify initStates for combined solvers with multiple sets of the same variables (ion/electron, etc)

	-- no initial state means use the first
	--initState = cmdline.initState,
	
	-- Euler / SRHD / MHD initial states:
	--initState = 'constant',
	--initState = 'constant with motion',
	--initState = 'linear',
	--initState = 'gaussian',
	--initState = 'advect wave',
	--initState = 'sphere',
	--initState = 'rarefaction wave',
	
	initState = 'Sod',
	--initState = 'Sedov',
	--initState = 'Kelvin-Hemholtz',
	--initState = 'Rayleigh-Taylor',
	--initState = 'Colella-Woodward',
	--initState = 'double mach reflection',
	--initState = 'square cavity',
	--initState = 'shock bubble interaction',

	--initState = 'configuration 1',
	--initState = 'configuration 2',
	--initState = 'configuration 3',
	--initState = 'configuration 4',
	--initState = 'configuration 5',
	--initState = 'configuration 6',

	-- self-gravitation tests:
	--initState = 'self-gravitation test 1',
	--initState = 'self-gravitation test 1 spinning',
	--initState = 'self-gravitation test 2',
	--initState = 'self-gravitation test 2 orbiting',
	--initState = 'self-gravitation test 4',
	--initState = 'self-gravitation soup',
	
	-- those designed for SRHD / GRHD:
	--initState = 'relativistic shock reflection',			-- not working.  these initial conditions are constant =P
	--initState = 'relativistic blast wave test problem 1',
	--initState = 'relativistic blast wave test problem 2',
	--initState = 'relativistic blast wave interaction',

	-- MHD-only init states: (that use 'b')
	--initState = 'Brio-Wu',
	--initState = 'Orszag-Tang',
	
	-- EM:
	--initState = 'Maxwell default',
	--initState = 'Maxwell scattering around cylinder',
	--initState = 'Maxwell wire',
	
	--initState = 'two-fluid EMHD soliton ion',
	--initState = 'two-fluid EMHD soliton electron',
	--initState = 'two-fluid EMHD soliton maxwell',

	-- GR
	--initState = 'gaussian perturbation',
	--initState = 'plane gauge wave',
	--initState = 'Alcubierre warp bubble',
	--initState = 'Schwarzschild black hole',
	--initState = 'black hole - isotropic',
	--initState = 'binary black holes - isotropic',
	--initState = 'stellar model',
	--initState = 'stellar model 2',
	--initState = 'stellar model 3',
	--initState = '1D black hole - wormhole form',
}

-- HD - Roe
self.solvers:insert(require 'solver.roe'(table(args, {eqn='euler'})))

-- HD - Burgers
-- f.e. and b.e. are working, but none of the r.k. integrators 
-- PLM isn't implemented yet
-- neither is source term / poisson stuff
--self.solvers:insert(require 'solver.euler-burgers'(args))

-- SRHD.  
-- rel blast wave 1 & 2 works in 1D at 256 with superbee flux lim
-- rel blast wave interaction works with superbee flux lim in 1D works at 256, fails at 1024 with float (works with double)
-- 	256x256 double fails with F.E., RK2-Heun, RK2-Ralston, RK2-TVD, RK3, RK4-3/8ths,
-- rel blast wave 1 doesn't work in 64x64. with superbee flux lim
-- rel blast wave 2 with superbee flux lim, Roe solver, works at 64x64 with forward euler
-- 	at 256x256 fails with F.E, RK2, RK2-non-TVD., RK3-TVD, RK4, RK4-TVD, RK4-non-TVD 
--    but works with RK2-Heun, RK2-Ralston, RK2-TVD, RK3, RK4-3/8ths
-- Kelvin-Hemholtz works for all borderes freeflow, float precision, 256x256, superbee flux limiter
--self.solvers:insert(require 'solver.srhd-roe'(args))

-- GRHD
-- right now this is just like srhd except extended by Font's eqns
-- this has plug-ins for ADM metric alpha, beta, gammas, but I need to make a composite solver to combine it with GR equations. 
--self.solvers:insert(require 'solver.grhd-roe'(args))

-- GRHD+GR
-- here's the GRHD solver with the BSSNOK plugged into it
--self.solvers:insert(require 'solver.gr-hd-separate'(args))

-- M+HD. 
-- with superbee flux lim:  
-- Brio-Wu works in 1D at 256, works in 2D at 64x64 in a 1D profile in the x and y directions.
-- Orszag-Tang with forward Euler integrator fails at 64x64 around .7 or .8
-- 		but works with 'Runge-Kutta 4, TVD' integrator at 64x64
-- 		RK4-TVD fails at 256x256 at just after t=.5
--		and works fine with backwards Euler 
-- when run alongside HD Roe solver, curves don't match (different heat capacity ratios?)
--		but that could be because of issues with simultaneous solvers.
--self.solvers:insert(require 'solver.roe'(table(args, {eqn='mhd'})))

-- EM
--self.solvers:insert(require 'solver.roe'(table(args, {eqn='maxwell'})))

-- EM+HD
-- I'm having some memory issues with two solvers running simultanously .. 
--self.solvers:insert(require 'solver.twofluid-emhd-separate-roe'(args))
-- so to try and get around that, here the two are combined into one solver:
--self.solvers:insert(require 'solver.twofluid-emhd-roe'(args))

-- GR
--self.solvers:insert(require 'solver.roe'(table(args, {eqn='adm1d_v1'})))
--self.solvers:insert(require 'solver.roe'(table(args, {eqn='adm1d_v2'})))
--self.solvers:insert(require 'solver.roe'(table(args, {eqn='adm3d'})))
--
-- the BSSNOK solver works similar to the adm3d for the warp bubble simulation
--  but something gets caught up in the freeflow boundary conditions, and it explodes
-- so I have set constant Minkowski boundary conditions?
-- the BSSNOK solver sometimes explodes / gets errors / nonzero Hamiltonian constraint for forward euler
-- however they tend to not explode with backward euler ... though these numerical perturbations still appear, but at least they don't explode
--self.solvers:insert(require 'solver.bssnok-fd'(args))

-- TODO GR+HD by combining the SR+HD 's alphas and gammas with the GR's alphas and gammas