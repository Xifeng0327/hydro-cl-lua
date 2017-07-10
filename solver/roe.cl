// Roe solver:

<? if solver.checkFluxError or solver.checkOrthoError then ?>
kernel void calcErrors(
	global error_t* errorBuf,
	const global real* waveBuf,
	const global <?=eqn.eigen_t?>* eigenBuf
) {
	SETBOUNDS(0,0);
	real3 x = cell_x(i);

	<? for side=0,solver.dim-1 do ?>{
		const int side = <?=side?>;
		int indexInt = side + dim * index;
		const global real* wave = waveBuf + numWaves * indexInt;
		const global <?=eqn.eigen_t?>* eig = eigenBuf + indexInt;
		
		real3 xInt = x;
		xInt.s<?=side?> -= .5 * grid_dx<?=side?>;

		real orthoError = 0;
		real fluxError = 0;

<?	if solver.checkOrthoError then
?>		//the flux transform is F v = R Lambda L v, I = R L
		//but if numWaves < numStates then certain v will map to the nullspace 
		//so to test orthogonality for only numWaves dimensions, I will verify that Qinv Q v = v 
		//I = L R
		for (int k = 0; k < numWaves; ++k) {
			real basis[numWaves];
			for (int j = 0; j < numWaves; ++j) {
				basis[j] = k == j ? 1 : 0;
			}
			
			real eigenInvCoords[numStates];
			eigen_rightTransform_<?=side?>__global_(eigenInvCoords, eig, basis, xInt);
		
			real newbasis[numWaves];
			eigen_leftTransform_<?=side?>__global_(newbasis, eig, eigenInvCoords, xInt);
			
			for (int j = 0; j < numWaves; ++j) {
				orthoError += fabs(newbasis[j] - basis[j]);
			}
		}
<? 	end
	if solver.checkFluxError then	
?>		for (int k = 0; k < numStates; ++k) {
			real basis[numStates];
			for (int j = 0; j < numStates; ++j) {
				basis[j] = k == j ? 1 : 0;
			}

			real eigenCoords[numWaves];
			eigen_leftTransform_<?=side?>__global_(eigenCoords, eig, basis, xInt);

			real eigenScaled[numWaves];
			for (int j = 0; j < numWaves; ++j) {
				eigenScaled[j] = eigenCoords[j] * wave[j];
			}
			
			real newtransformed[numStates];
			eigen_rightTransform_<?=side?>__global_(newtransformed, eig, eigenScaled, xInt);
			
			real transformed[numStates];
			eigen_fluxTransform_<?=side?>__global_(transformed, eig, basis, xInt);
			
			for (int j = 0; j < numStates; ++j) {
				fluxError += fabs(newtransformed[j] - transformed[j]);
			}
		}
<?	end
?>		errorBuf[indexInt] = (error_t){
			.ortho = orthoError,
			.flux = fluxError,
		};
	}<? end ?>
}
<? end ?>

kernel void calcDeltaUEig(
	global real* deltaUEigBuf,
	<?= solver.getULRArg ?>,
	const global <?=eqn.eigen_t?>* eigenBuf
) {
	SETBOUNDS(2,1);	
	real3 x = cell_x(i);
	int indexR = index;
	<? for side=0,solver.dim-1 do ?>{
		const int side = <?=side?>;
		int indexL = index - stepsize[side];
		
		real3 xInt = x;
		xInt.s<?=side?> -= .5 * grid_dx<?=side?>;
		
		<?= solver.getULRCode ?>

		<?=eqn.cons_t?> deltaU;
		for (int j = 0; j < numStates; ++j) {
			deltaU.ptr[j] = UR->ptr[j] - UL->ptr[j];
		}
	
		int indexInt = side + dim * index;	
		global real* deltaUEig = deltaUEigBuf + indexInt * numWaves;
		const global <?=eqn.eigen_t?>* eig = eigenBuf + indexInt;
		eigen_leftTransform_<?=side?>_global_global_(deltaUEig, eig, deltaU.ptr, xInt);
	}<? end ?>
}

<? if solver.fluxLimiter[0] > 0 then ?>
kernel void calcREig(
	global real* rEigBuf,
	const global real* deltaUEigBuf,
	const global real* waveBuf
) {
	SETBOUNDS(2,1);
	<? for side=0,solver.dim-1 do ?>{
		const int side = <?=side?>;
		int indexL = index - stepsize[side];
		int indexR = index + stepsize[side];
		int indexInt = side + dim * index;
		int indexIntL = side + dim * indexL;
		int indexIntR = side + dim * indexR;
		global real* rEig = rEigBuf + indexInt * numWaves;
		const global real* deltaUEig = deltaUEigBuf + indexInt * numWaves;
		const global real* deltaUEigL = deltaUEigBuf + indexIntL * numWaves;
		const global real* deltaUEigR = deltaUEigBuf + indexIntR * numWaves;
		const global real* wave = waveBuf + indexInt * numWaves;
		for (int j = 0; j < numWaves; ++j) {
			if (deltaUEig[j] == 0) {
				rEig[j] = 0;
			} else {
				if (wave[j] >= 0) {
					rEig[j] = deltaUEigL[j] / deltaUEig[j];
				} else {
					rEig[j] = deltaUEigR[j] / deltaUEig[j];
				}
			}
		}
	}<? end ?>
}
<? end ?>

//TODO entropy fix ... for the Euler equations at least
kernel void calcFlux(
	global <?=eqn.cons_t?>* fluxBuf,
	<?= solver.getULRArg ?>,
	const global real* waveBuf, 
	const global <?=eqn.eigen_t?>* eigenBuf, 
	const global real* deltaUEigBuf,
	real dt
<? if solver.fluxLimiter[0] > 0 then ?>
	,const global real* rEigBuf
<? end ?>
) {
	SETBOUNDS(2,1);
	real3 xR = cell_x(i);
	int indexR = index;
	<? for side=0,solver.dim-1 do ?>{
		const int side = <?=side?>;	
		real dt_dx = dt / grid_dx<?=side?>;//dx<?=side?>_at(i);
		int indexL = index - stepsize[side];
		
		real3 xInt = xR;
		xInt.s<?=side?> -= .5 * grid_dx<?=side?>;

		<?= solver.getULRCode ?>
		
		int indexInt = side + dim * index;
		const global <?=eqn.eigen_t?>* eig = eigenBuf + indexInt;

		real fluxEig[numWaves];
<? if not eqn.hasFluxFromCons then ?>
		<?=eqn.cons_t?> UAvg;
		for (int j = 0; j < numStates; ++j) {
			UAvg.ptr[j] = .5 * (UL->ptr[j] + UR->ptr[j]);
		}
		eigen_leftTransform_<?=side?>__global_(fluxEig, eig, UAvg.ptr, xInt);
<? end ?>

		const global real* lambdas = waveBuf + numWaves * indexInt;
		const global real* deltaUEig = deltaUEigBuf + numWaves * indexInt;
<? if solver.fluxLimiter[0] > 0 then ?>
		const global real* rEig = rEigBuf + numWaves * indexInt;
<? end ?>

		for (int j = 0; j < numWaves; ++j) {
			real lambda = lambdas[j];
<? if not eqn.hasFluxFromCons then ?>
			fluxEig[j] *= lambda;
<? else ?>
			fluxEig[j] = 0.;
<? end ?>
			real theta = lambda >= 0 ? 1 : -1;
		
<? if solver.fluxLimiter[0] > 0 then ?>
			real phi = fluxLimiter(rEig[j]);
<? end ?>

			real epsilon = lambda * dt_dx;
			real deltaFluxEig = lambda * deltaUEig[j];
			fluxEig[j] -= .5 * deltaFluxEig * (theta
<? if solver.fluxLimiter[0] > 0 then ?>
				+ phi * (epsilon - theta)
<? end ?>			
			);
		}
			
		global <?=eqn.cons_t?>* flux = fluxBuf + indexInt;
		eigen_rightTransform_<?=side?>_global_global_(flux->ptr, eig, fluxEig, xInt);
		
<? if eqn.hasFluxFromCons then ?>
		// should the metric evaluation be at the interface, or at the cell center where the state is?
		//I'll try for the cell centers, so there is consistency with the state variables themselves
		real3 xL = xR;
		xL.s<?=side?> -= grid_dx<?=side?>;
		
		<?=eqn.cons_t?> FL = fluxFromCons_<?=side?>(*UL, xL);
		<?=eqn.cons_t?> FR = fluxFromCons_<?=side?>(*UR, xR);
		for (int j = 0; j < numStates; ++j) {
			flux->ptr[j] += .5 * (FL.ptr[j] + FR.ptr[j]);
		}
<? end ?>
	}<? end ?>
}

kernel void calcDerivFromFlux(
	global <?=eqn.cons_t?>* derivBuf,
	const global <?=eqn.cons_t?>* fluxBuf
) {
	SETBOUNDS(2,2);
	global <?=eqn.cons_t?>* deriv = derivBuf + index;

	real3 iIntL = _real3((real)i.x-.5, (real)i.y-.5, (real)i.z-.5);
	real3 xIntL = cell_x(iIntL);
	real3 iIntR = _real3((real)i.x+.5, (real)i.y+.5, (real)i.z+.5);
	real3 xIntR = cell_x(iIntR);
	
	//integral over volume of the coordinates
#if defined(geometry_cylinder)
	//integral of r dr dtheta dz
	real r1 = xIntL.x, theta1 = xIntL.y, z1 = xIntL.z;
	real r2 = xIntR.x, theta2 = xIntR.y, z2 = xIntR.z;
	real dr = r2 - r1;
	real dtheta = theta2 - theta1;
	real dz = z2 - z1;
#if dim == 1
	real volume = .5 * (r2*r2 - r1*r1);
	real3 sideL = _real3(1., 1., 1.);
	real3 sideR = _real3(1., 1., 1.);
#elif dim == 2
	real volume = .5 * (r2*r2 - r1*r1) * dtheta;
	real3 sideL = _real3(r1 * dtheta, dr, 1.);
	real3 sideR = _real3(r2 * dtheta, dr, 1.);
#elif dim == 3
	real volume = .5 * (r2*r2 - r1*r1) * dtheta * dz;
	real3 sideL = _real3(r1 * dtheta * dz, dr * dz, .5 * (r2*r2 - r1*r1) * dtheta);
	real3 sideR = _real3(r2 * dtheta * dz, dr * dz, .5 * (r2*r2 - r1*r1) * dtheta);
#endif

#else
	//general case -- use the metric 
	real3 x = cell_x(i);
	real volume = volume_at(x);
	real3 dxs = _real3(grid_dx0, grid_dx1, grid_dx2);
	real3 sideL = _real3(volume / dxs.x, volume / dxs.y, volume / dxs.z); 
	real3 sideR = sideL;
#endif

	<? for side=0,solver.dim-1 do ?>{
		const int side = <?=side?>;

		int indexIntL = side + dim * index;
		int indexIntR = indexIntL + dim * stepsize[side]; 
		const global <?=eqn.cons_t?>* fluxL = fluxBuf + indexIntL;
		const global <?=eqn.cons_t?>* fluxR = fluxBuf + indexIntR;
		for (int j = 0; j < numStates; ++j) {
			deriv->ptr[j] -= (
				fluxR->ptr[j] * sideR.s<?=side?> 
				- fluxL->ptr[j] * sideL.s<?=side?>
			) / volume;
		}
	}<? end ?>
}
