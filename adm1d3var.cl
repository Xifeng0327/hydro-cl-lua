real calcDisplayVar_UBuf(int displayVar, const __global real* U_) {
	const __global cons_t* U = (const __global cons_t*)U_;
	switch (displayVar) {
	case display_U_alpha: return U->alpha;
	case display_U_gamma_xx: return U->gamma_xx;
	case display_U_a_x: return U->a_x;
	case display_U_d_xxx: return U->d_xxx;
	case display_U_KTilde_xx: return U->KTilde_xx;
	case display_U_K_xx: return U->KTilde_xx * sqrt(U->gamma_xx);
	case display_U_volume: return U->alpha * sqrt(U->gamma_xx);
	}
	return 0;
}

real calcMaxEigenvalue(real alpha, real gamma_xx) {
	real f = calc_f(alpha);
	real lambda = alpha * sqrt(f / gamma_xx);
	return lambda;
}

range_t calcCellMinMaxEigenvalues(
	const __global real* U_,
	int side
) {
	const __global cons_t* U = (const __global cons_t*)U_;
	real lambda = calcMaxEigenvalue(U->alpha, U->gamma_xx);
	return (range_t){.min=-lambda, .max=lambda};
}

//alpha, gamma_xx, f
typedef fluxXform_t Roe_t;

Roe_t calcEigenBasisSide(cons_t UL, cons_t UR) {
	real alpha = .5 * (UL.alpha + UR.alpha);
	real gamma_xx = .5 * (UL.gamma_xx + UR.gamma_xx);
	real f = calc_f(alpha);
	return (Roe_t){.alpha=alpha, .gamma_xx=gamma_xx, .f=f};
}

__kernel void calcEigenBasis(
	__global real* waveBuf,
	__global eigen_t* eigenBuf,
	__global fluxXform_t* fluxXformBuf,
	const __global cons_t* UBuf
) {
	SETBOUNDS(2,1);
	int indexR = index;
	for (int side = 0; side < dim; ++side) {
		int indexL = index - stepsize[side];

		Roe_t roe = calcEigenBasisSide(UBuf[indexL], UBuf[indexR]);

		int intindex = side + dim * index;	
		__global real* wave = waveBuf + numWaves * intindex;
		real lambda = calcMaxEigenvalue(roe.alpha, roe.gamma_xx); 
		wave[0] = -lambda;
		wave[1] = 0;
		wave[2] = lambda;
	
		eigenBuf[intindex].f = roe.f;	

		//only used for eigen basis reconstruction validity testing
		fluxXformBuf[intindex] = roe;
	}
}

void fluxTransform(
	real* y,
	const __global fluxXform_t* flux,
	const real* x,
	int side
) {
	y[0] = 0;
	y[1] = 0;
	y[2] = x[4] * flux->alpha * flux->f / sqrt(flux->gamma_xx);
	y[3] = x[4] * 2. * flux->alpha / sqrt(flux->gamma_xx);
	y[4] = x[2] * flux->alpha / sqrt(flux->gamma_xx);
}

void eigen_leftTransform(
	real* y,
	const __global eigen_t* eigen,
	const real* x,
	int side
) {
	real sqrt_f = sqrt(eigen->f);
	y[0] = x[2] / (2. * eigen->f) - x[4] / (2. * sqrt_f);
	y[1] = -2. * x[2] / eigen->f + x[3];
	y[2] = x[2] / (2. * eigen->f) + x[4] / (2. * sqrt_f);
}

void eigen_rightTransform(
	real* y,
	const __global eigen_t* eigen,
	const real* x,
	int side
) {
	y[0] = 0;
	y[1] = 0;
	y[2] = (x[0] + x[2]) * eigen->f;
	y[3] = 2. * x[0] + x[1] + 2. * x[2];
	y[4] = sqrt(eigen->f) * (x[2] - x[0]);
}

real eigen_calcDisplayVar(
	int displayVar,
	const __global eigen_t* eigen
) {
	return eigen->f;
}

kernel void addSourceTerm(
	__global cons_t* derivBuf,
	const __global cons_t* UBuf
) {
	SETBOUNDS(0,0);
	const __global cons_t* U = UBuf + index;
	__global cons_t* deriv = derivBuf + index;
	real f = calc_f(U->alpha);
	real K_xx = U->KTilde_xx / sqrt(U->gamma_xx);
	deriv->alpha -= U->alpha * U->alpha * f * K_xx / U->gamma_xx;
	deriv->gamma_xx -= 2. * U->alpha * K_xx;
}
