// the default eigen transforms, using eigen struct as a dense matrix:

<? for side=0,2 do ?>
void eigen_leftTransform_<?=side?>(
	real* y,
	const global eigen_t* eigen,
	const real* x
) {
	const global real* A = eigen->evL;
	for (int i = 0; i < numWaves; ++i) {
		real sum = 0;
		for (int j = 0; j < numStates; ++j) {
			sum += A[i+numWaves*j] * x[j];
		}
		y[i] = sum;
	}
}

void eigen_rightTransform_<?=side?>(
	real* y,
	const global eigen_t* eigen,
	const real* x
) {
	const global real* A = eigen->evR;
	for (int i = 0; i < numWaves; ++i) {
		real sum = 0;
		for (int j = 0; j < numStates; ++j) {
			sum += A[i+numWaves*j] * x[j];
		}
		y[i] = sum;
	}
}

<? if solver.checkFluxError then ?>
void fluxTransform_<?=side?>(
	real* y,
	const global eigen_t* eigen,
	const real* x
) {
	const global real* A = eigen->A;
	for (int i = 0; i < numStates; ++i) {
		real sum = 0;
		for (int j = 0; j < numStates; ++j) {
			sum += A[i+numStates*j] * x[j];
		}
		y[i] = sum;
	}
}
<?	end ?>
<? end ?>
