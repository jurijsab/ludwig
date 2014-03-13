/*****************************************************************************
 *
 *  nernst_planck.c
 *
 *  A solution for the Nerst-Planck equation, which is the advection
 *  diffusion equation for charged species \rho_k in the presence of
 *  a potential \psi.
 *
 *  We have, in the most simple case:
 *
 *  d_t rho_k + div . (rho_k u) = div . D_k (grad rho_k + Z_k rho_k grad psi)
 *
 *  where u is the velocity field, D_k are the diffusion constants for
 *  each species k, and Z_k = (valancy_k e / k_bT) = beta valency_k e.
 *  e is the unit charge.
 *
 *  If the chemical potential is mu_k for species k, the diffusive
 *  flux may be written as
 *
 *    j_k = - D_k rho_k grad (beta mu_k)
 *
 *  with mu_k = mu_k^ideal + mu_k^ex = k_bT ln(rho_k) + valency_k e psi.
 *  (For more complex problems, there may be other terms in the chemical
 *  potential.)
 *
 *  As it is important to conserve charge, we solve in a flux form.
 *  Following Capuani, Pagonabarraga and Frenkel, J. Chem. Phys.
 *  \textbf{121} 973 (2004) we include factors to ensure that the
 *  charge densities follow a Boltzmann distribution in equilbrium.
 *
 *  This writes the flux as
 *    j_k = - D_k exp[beta mu_k^ex] grad (rho_k exp[beta mu_k^ex])
 *
 *  which we approximate at the cell faces by (e.g., for x only)
 *
 *    -D_k (1/2) { exp[-beta mu_k^ex(i)] + exp[-beta mu_k^ex(i+1)] }
 *    * { rho_k(i+1) exp[beta mu_k^ex(i+1)] - rho_k(i) exp[beta mu_k^ex(i)] }
 *
 *  We then compute the divergence of the fluxes to update via an
 *  Euler forward step. The advective fluxes (again computed at the
 *  cells faces) may be added to the diffusive fluxes to solve the
 *  whole thing. Appropraite advective fluxes may be computed via
 *  the advection.h interface.
 *
 *  Solid boundaries simply involve enforcing a no normal flux
 *  condition at the cell face.
 *
 *  The potential and charge species are available via the psi_s
 *  object.
 *
 *  $Id$
 *
 *  Edinbrugh Soft Matter and Statistical Physics Group and
 *  Edinburgh Parallel Computing Centre
 *
 *  Kevin Stratford (kevin@epcc.ed.ac.uk)
 *  (c) 2012 The University of Edinbrugh
 *
 *****************************************************************************/

#include <assert.h>
#include <math.h>
#include <stdlib.h>

#include "pe.h"
#include "coords.h"
#include "psi_s.h"
#include "advection_bcs.h"
#include "nernst_planck.h"


static int nernst_planck_fluxes(psi_t * psi, double * fw, double * fe,
				double * fy, double * fz);
static int nernst_planck_update(psi_t * psi, double * fe, double * fw,
				double * fy, double * fz);


/*****************************************************************************
 *
 *  nernst_planck_driver
 *
 *****************************************************************************/

int nernst_planck_driver(psi_t * psi) {

  int nk;              /* Number of electrolyte species */
  int nsites;          /* Number of lattice sites */

  double * fw = NULL;
  double * fe = NULL;
  double * fy = NULL;
  double * fz = NULL;

  psi_nk(psi, &nk);
  nsites = coords_nsites();

 /* Allocate fluxes */

  fw = calloc(nsites*nk, sizeof(double));
  fe = calloc(nsites*nk, sizeof(double));
  fy = calloc(nsites*nk, sizeof(double));
  fz = calloc(nsites*nk, sizeof(double));
  if (fw == NULL) fatal("calloc(fw) failed\n");
  if (fe == NULL) fatal("calloc(fe) failed\n");
  if (fy == NULL) fatal("calloc(fy) failed\n");
  if (fz == NULL) fatal("calloc(fz) failed\n");

  /* U halo if required, and advection */

  nernst_planck_fluxes(psi, fe, fw, fy, fz);
  advection_bcs_no_normal_flux(nk, fe, fw, fy, fz);
  nernst_planck_update(psi, fe, fw, fy, fz);

  free(fz);
  free(fy);
  free(fe);
  free(fw);

  return 0;
}

/*****************************************************************************
 *
 *  nernst_planck_fluxes
 *
 *  Compute diffusive fluxes.
 *  IF WANT ADVECTIVE FLXUES THIS MUST BE AN ACCUMULATION!
 *
 *  As we compute rho(n+1) = rho(n) - div.flux in the update routine,
 *  there is an extra minus sign in the fluxes here. This conincides
 *  with the sign of the advective fluxes, if present.
 *
 *****************************************************************************/

static int nernst_planck_fluxes(psi_t * psi, double * fw, double * fe,
				double * fy, double * fz) {
  int ic, jc, kc, index;
  int nlocal[3];
  int nhalo;
  int zs, ys, xs;
  int n, nk;

  double eunit;
  double beta;
  double b0, b1;
  double mu0, mu1;
  double rho0, rho1;

  nhalo = coords_nhalo();
  coords_nlocal(nlocal);

  zs = 1;
  ys = zs*(nlocal[Z] + 2*nhalo);
  xs = ys*(nlocal[Y] + 2*nhalo);

  psi_nk(psi, &nk);
  psi_unit_charge(psi, &eunit);
  psi_beta(psi, &beta);

  for (ic = 1; ic <= nlocal[X]; ic++) {
    for (jc = 0; jc <= nlocal[Y]; jc++) {
      for (kc = 0; kc <= nlocal[Z]; kc++) {

	index = coords_index(ic, jc, kc);

	for (n = 0; n < nk; n++) {

	  mu0 = psi->valency[n]*eunit*psi->psi[index];
	  rho0 = psi->rho[nk*index + n]*exp(beta*mu0);
	  b0 = exp(-beta*mu0);

	  /* x-direction (between ic-1 and ic) note sign (rho0 - rho1) */

	  mu1 = psi->valency[n]*eunit*psi->psi[index - xs];
	  rho1 = psi->rho[nk*(index - xs) + n]*exp(beta*mu1);
	  b1 = exp(-beta*mu1);

	  fw[nk*index + n] -= psi->diffusivity[n]*0.5*(b0 + b1)*(rho0 - rho1);

	  /* x-direction (between ic and ic+1) */

	  mu1 = psi->valency[n]*eunit*psi->psi[index + xs];
	  rho1 = psi->rho[nk*(index + xs) + n]*exp(beta*mu1);
	  b1 = exp(-beta*mu1);

	  fe[nk*index + n] -= psi->diffusivity[n]*0.5*(b0 + b1)*(rho1 - rho0);

	  /* y-direction (between jc and jc+1) */

	  mu1 = psi->valency[n]*eunit*psi->psi[index + ys];
	  rho1 = psi->rho[nk*(index + ys) + n]*exp(beta*mu1);
	  b1 = exp(-beta*mu1);

	  fy[nk*index + n] -= psi->diffusivity[n]*0.5*(b0 + b1)*(rho1 - rho0);

	  /* z-direction (between kc and kc+1) */

	  mu1 = psi->valency[n]*eunit*psi->psi[index + zs];
	  rho1 = psi->rho[nk*(index + zs) + n]*exp(beta*mu1);
	  b1 = exp(-beta*mu1);

	  fz[nk*index + n] -= psi->diffusivity[n]*0.5*(b0 + b1)*(rho1 - rho0);
	}

	/* Next face */
      }
    }
  }

  return 0;
}

/*****************************************************************************
 *
 *  nernst_planck_update
 *
 *  Update the rho_k from the fluxes. Euler forward step.
 *
 *****************************************************************************/

static int nernst_planck_update(psi_t * psi, double * fe, double * fw,
				double * fy, double * fz) {
  int ic, jc, kc, index;
  int nlocal[3];
  int nhalo;
  int zs, ys;
  int n, nk;

  nhalo = coords_nhalo();
  coords_nlocal(nlocal);

  zs = 1;
  ys = zs*(nlocal[Z] + 2*nhalo);

  psi_nk(psi, &nk);

  for (ic = 1; ic <= nlocal[X]; ic++) {
    for (jc = 1; jc <= nlocal[Y]; jc++) {
      for (kc = 1; kc <= nlocal[Z]; kc++) {

	index = coords_index(ic, jc, kc);

	for (n = 0; n < nk; n++) {
	  psi->rho[nk*index + n]
	    -= (+ fe[nk*index + n] - fw[nk*index + n]
		+ fy[nk*index + n] - fy[nk*(index-ys) + n]
		+ fz[nk*index + n] - fz[nk*(index-zs) + n]);
	}
      }
    }
  }

  return 0;
}