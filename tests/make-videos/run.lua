#!/usr/bin/env luajit
--[[
this will make movies of predefined configurations
it expects ffmpeg to be installed
--]]

local ffi = require 'ffi'
package.cpath = package.cpath .. [[;C:\Users\moorece\lib\luajit-2.1.0-beta3\?.dll]]
local lfs = require 'lfs'
local rundir = lfs.currentdir()
lfs.chdir'../..'

local sdl = require 'ffi.sdl'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local io = require 'ext.io'

__disableGUI__ = true	-- set this before require 'app'

local function run(...)
	print(...)
	return os.execute(...)
end

--[[
outer({{a=1}, {a=2}}, {{b=1}, {b=2}})
returns {{a=1,b=1}, {a=1,b=2}, {a=2,b=1}, {a=2,b=2}}
--]]
local function outer(...)
	local args = {...}
	local n = #args
	local is = table()
	for i=1,n do is[i] = 1 end
	local ts = table()
	local done
	repeat
		ts:insert(table( is:map(function(j,i) return args[i][j] end):unpack() ))
		for j=1,n do
			is[j] = is[j] + 1
			if is[j] > #args[j] then
				is[j] = 1
				if j == n then
					done = true
					break
				end
			else
				break
			end
		end
	until done
	return ts
end

local configurations = outer(
	{ 
		{eqn='euler', gridSize={256} },
	},
	{
		{initState='Sod', solver='roe', integrator='forward Euler', fluxLimiter='superbee'},
		{initState='Sod', solver='roe', integrator='forward Euler', usePLM='plm-eig-prim-ref'},
		{initState='Sod', solver='euler-burgers', integrator='forward Euler', fluxLimiter='superbee'},
		
		{initState='Sedov', solver='roe', integrator='forward Euler', fluxLimiter='superbee'},
		{initState='Sedov', solver='roe', integrator='forward Euler', usePLM='plm-eig-prim-ref'},
		{initState='Sedov', solver='roe', integrator='backward Euler', usePLM='plm-eig-prim-ref'},		-- b.e. gets nans
		{initState='Sedov', solver='hll', integrator='forward Euler', usePLM='plm-eig-prim-ref'},
	
		{initState='self-gravitation test 1', solver='roe', integrator='forward Euler', fluxLimiter='superbee'},
		{initState='self-gravitation test 1', solver='hll', integrator='forward Euler', fluxLimiter='superbee'},
	}
):append(
	outer(
	{
		{eqn='euler', gridSize={256,256} },
	},
	table{
		{initState='Sod', solver='roe', integrator='forward Euler', fluxLimiter='superbee'},
		{initState='Sod', solver='roe', integrator='forward Euler', usePLM='plm-eig-prim-ref'},
		{initState='Sod', solver='hll', integrator='forward Euler', fluxLimiter='superbee'},
		{initState='Sod', solver='hll', integrator='forward Euler', usePLM='plm-eig-prim-ref'},
		
		{initState='Sedov', solver='hll', integrator='forward Euler', fluxLimiter='superbee'},
		{initState='Sedov', solver='hll', integrator='forward Euler', usePLM='plm-eig-prim-ref'},
		{initState='Sedov', solver='hll', integrator='Runge-Kutta 4, TVD', usePLM='plm-eig-prim-ref'},
	}:append(outer(
		{
			{solver='roe', integrator='forward Euler', fluxLimiter='superbee'},
			{solver='roe', integrator='forward Euler', usePLM='plm-eig-prim-ref'},
			{solver='roe', integrator='backward Euler', usePLM='plm-eig-prim-ref'},
			{solver='hll', integrator='forward Euler', fluxLimiter='superbee'},
			{solver='hll', integrator='forward Euler', usePLM='plm-eig-prim-ref'},
			{solver='hll', integrator='backward Euler', usePLM='plm-eig-prim-ref'},
		},
		{
			{initState='Kelvin-Helmholtz', movieFrameDT=.1, movieEndTime=10},
			{initState='shock bubble interaction', movieEndTime=5},
			{initState='configuration 1', movieEndTime=.3},
			{initState='configuration 2', movieEndTime=.3},
			{initState='configuration 3', movieEndTime=.3},
			{initState='configuration 4', movieEndTime=.3},
			{initState='configuration 5', movieEndTime=.3},
			{initState='configuration 6', movieEndTime=.3},
		}
	)):append(outer(
		{
			{solver='roe', integrator='forward Euler', fluxLimiter='superbee'},
			{solver='roe', integrator='backward Euler', fluxLimiter='superbee'},
			{solver='hll', integrator='forward Euler', fluxLimiter='superbee'},
		},
		{
			{initState='self-gravitation test 1'},
			{initState='self-gravitation test 1 spinning'},
			{initState='self-gravitation test 2'},
			{initState='self-gravitation test 2 orbiting'},
		}
	))
))

for _,cfg in ipairs(configurations) do

	local args = {
		app = self,
		eqn = cfg.eqn,
		dim = #cfg.gridSize,
		integrator = cfg.integrator,
		fluxLimiter = cfg.fluxLimiter,
		usePLM = cfg.usePLM,
		geometry = 'cartesian',
		mins = {-1,-1,-1},
		maxs = {1,1,1},
		gridSize = cfg.gridSize,
		boundary = {
			xmin = 'freeflow',
			xmax = 'freeflow',
			ymin = 'freeflow',
			ymax = 'freeflow',
			zmin = 'freeflow',
			zmax = 'freeflow',
		},
		initState = cfg.initState,
	}
		
	local destMovieName = table{
		'eqn='..args.eqn,
		'solver='..cfg.solver,
		'integrator='..args.integrator,
	}:append(args.usePLM 
		-- plm:
		and table{
			'plm='..args.usePLM,
		}:append(
			args.slopeLimiter and {'slopeLimiter='..args.slopeLimiter} or nil
		) 
		-- non-plm: use flux limiter
		or (
			args.fluxLimiter and {'fluxLimiter='..args.fluxLimiter} or nil
		)
	):append{	
		'init='..args.initState,
		'gridSize='..range(args.dim):map(function(i) return args.gridSize[i] end):concat'x',
	}:append{
		cfg.movieStartTime and ('t0='..cfg.movieStartTime) or nil,
	}:append{
		cfg.movieEndTime and ('t1='..cfg.movieEndTime) or nil,
	}:append{
		cfg.movieFrameDT and ('dt='..cfg.movieFrameDT) or nil,
	}:concat', '..'.mp4'
	print(destMovieName)
		
	if io.fileexists(rundir..'/'..destMovieName) then
		print("I already found movie "..destMovieName)
	else
		local movieStartTime = cfg.movieStartTime or 0
		local movieEndTime = cfg.movieEndTime or 1
		local movieFrameDT = cfg.movieFrameDT or 0 

		local App = class(require 'app')
		function App:setup(clArgs)
			args.app = self
			self.solvers:insert(require('solver.'..cfg.solver)(args))
			sdl.SDL_SetWindowSize(self.window, 1280, 720)
			
			-- why am I getting weird graphics glitches upon startup?
			-- first it was imgui giving a DeltaTime>=0 assert fail only for the *second* app run in a batch
			-- now it is the apps losing all their textures ... which I think might be SDL_SetWindowSize 
			sdl.SDL_Delay(1)
			
			self.running = true
			self.exitTime = movieEndTime + movieStartTime
			self.displayVectorField_step = 8
		end
		
		local recording
		local nextCaptureTime
		function App:update(...)
	
			local oldestSolver = self.solvers:inf(function(a,b) return a.t < b.t end)
			
			-- if the recording hasn't started then start it ... 
			-- ... as soon as it passes the movieStartTime 
			if not recording then
				if not movieStartTime 
				or oldestSolver.t >= movieStartTime
				then
					recording = true
				end
			end

			if recording then
				if not nextCaptureTime
				or nextCaptureTime <= oldestSolver.t
				then
					self.createAnimation = 'once'
					nextCaptureTime = oldestSolver.t + movieFrameDT
				end
			end

			return App.super.update(self, ...)
		end
		local app  = App()
		
		app:run()

		-- once we're done ...
		local ext = app.screenshotExts[app.screenshotExtIndex]
		local dir = 'screenshots/'..app.screenshotDir
		assert(run('ffmpeg -y -i "'..dir..'/%05d.'..ext..'" "'..rundir..'/'..destMovieName..'"'))
		for i=0,app.screenshotIndex-1 do
			os.remove(dir..('/%05d.'):format(i)..ext)
		end
		local sep = ffi.os == 'Windows' and '\\' or '/'
		run('rmdir '..dir:gsub('/', sep))
	end
end