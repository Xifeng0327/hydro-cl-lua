local class = require 'ext.class'
local symmath = require 'symmath'
local geometry = require 'geom.geom'
	
local sin, cos = symmath.sin, symmath.cos
local Tensor = symmath.Tensor

local Cylinder = class(geometry)

function Cylinder:init(args)
	args.embedded = table{symmath.vars('x', 'y', 'z')}
	local r, theta, z = symmath.vars('r', 'theta', 'z')
	args.coords = table{r, theta, z}
	args.chart = function() 
		return ({
			Tensor('^I', r),
			Tensor('^I', r * cos(theta), r * sin(theta)),
			Tensor('^I', r * cos(theta), r * sin(theta), z),
		})[args.solver.dim]
	end
	Cylinder.super.init(self, args)
end

return Cylinder
