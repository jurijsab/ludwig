/*****************************************************************************
 *
 *  advection.c
 *
 *  Computes advective order parameter fluxes from the current
 *  velocity field (from hydrodynamics) and the the current
 *  order parameter(s).
 *
 *  Fluxes are all computed at the interface of the control cells
 *  surrounding each lattice site. Unique face fluxes guarantee
 *  conservation of the order parameter.
 *
 *  To deal with Lees-Edwards boundaries positioned at x = constant
 *  we have to allow the 'east' face flux to be stored separately
 *  to the 'west' face flux. There's no effect in the y- or z-
 *  directions.
 *
 *  Any solid-fluid boundary conditions are dealt with post-hoc by
 *  in advection_bcs.c
 *
 *  Edinburgh Soft Matter and Statistical Physics Group and
 *  Edinburgh Parallel Computing Centre
 *
 *  (c) 2010-2016  The University of Edinburgh
 *
 *  Contributing authors:
 *  Kevin Stratford (kevin@epcc.ed.ac.uk)
 *  Alan Gray (alang@epcc.ed.ac.uk)
 *
 *****************************************************************************/

#include <assert.h>
#include <stdlib.h>

#include "pe.h"
#include "coords.h"
#include "leesedwards.h"
#include "field_s.h"
#include "advection_s.h"
#include "psi_gradients.h"
#include "hydro_s.h"
#include "timer.h"

static int advection_le_1st(advflux_t * flux, hydro_t * hydro, int nf,
			    field_t * field);
static int advection_le_2nd(advflux_t * flux, hydro_t * hydro, int nf,
			    double * f);
static int advection_le_3rd(advflux_t * flux, hydro_t * hydro, int nf,
			    field_t * field);
static int advection_le_4th(advflux_t * flux, hydro_t * hydro, int nf,
			    double * f);
static int advection_le_5th(advflux_t * flux, hydro_t * hydro, int nf,
			    double * f);

static int order_ = 1; /* Default is upwind (bad!) */

/*****************************************************************************
 *
 *  advection_order_set
 *
 *****************************************************************************/

int advection_order_set(const int n) {

  order_ = n;
  return 0;
}

/*****************************************************************************
 *
 *  advection_order
 *
 *****************************************************************************/

int advection_order(int * order) {

  assert(order);

  *order = order_;

  return 0;
}

/*****************************************************************************
 *
 *  advflux_create
 *
 *****************************************************************************/

int advflux_create(int nf, advflux_t ** pobj) {

  int nsites;
  double * tmpptr;
  advflux_t * obj = NULL;

  assert(pobj);

  obj = (advflux_t*) calloc(1, sizeof(advflux_t));
  if (obj == NULL) fatal("calloc(advflux) failed\n");

  nsites = le_nsites();

  obj->fe = (double*) calloc(nsites*nf, sizeof(double));
  obj->fw = (double*) calloc(nsites*nf, sizeof(double));
  obj->fy = (double*) calloc(nsites*nf, sizeof(double));
  obj->fz = (double*) calloc(nsites*nf, sizeof(double));

  if (obj->fe == NULL) fatal("calloc(advflux->fe) failed\n");
  if (obj->fw == NULL) fatal("calloc(advflux->fw) failed\n");
  if (obj->fy == NULL) fatal("calloc(advflux->fy) failed\n");
  if (obj->fz == NULL) fatal("calloc(advflux->fz) failed\n");


  /* allocate target copy of structure */

  targetMalloc((void **) &(obj->tcopy), sizeof(advflux_t));

  targetCalloc((void **) &tmpptr, nf*nsites*sizeof(double));
  copyToTarget(&(obj->tcopy->fe), &tmpptr, sizeof(double *)); 

  targetCalloc((void **) &tmpptr, nf*nsites*sizeof(double));
  copyToTarget(&(obj->tcopy->fw), &tmpptr, sizeof(double *)); 

  targetCalloc((void **) &tmpptr, nf*nsites*sizeof(double));
  copyToTarget(&(obj->tcopy->fy), &tmpptr, sizeof(double *)); 

  targetCalloc((void **) &tmpptr, nf*nsites*sizeof(double));
  copyToTarget(&(obj->tcopy->fz), &tmpptr, sizeof(double *)); 

  *pobj = obj;

  return 0;
}

/*****************************************************************************
 *
 *  advflux_free
 *
 *****************************************************************************/

void advflux_free(advflux_t * obj) {

  double * tmpptr;

  assert(obj);

  free(obj->fe);
  free(obj->fw);
  free(obj->fy);
  free(obj->fz);

  copyFromTarget(&tmpptr, &(obj->tcopy->fe), sizeof(double *)); 
  targetFree(tmpptr);
  copyFromTarget(&tmpptr, &(obj->tcopy->fw), sizeof(double *)); 
  targetFree(tmpptr);
  copyFromTarget(&tmpptr, &(obj->tcopy->fy), sizeof(double *)); 
  targetFree(tmpptr);
  copyFromTarget(&tmpptr, &(obj->tcopy->fz), sizeof(double *)); 
  targetFree(tmpptr);

  targetFree(obj->tcopy);
  free(obj);

  return;
}

/*****************************************************************************
 *
 *  advection_x
 *
 *****************************************************************************/

int advection_x(advflux_t * obj, hydro_t * hydro, field_t * field) {

  int nf;

  assert(obj);
  assert(hydro);
  assert(field);

  field_nf(field, &nf);

  /* For given LE , and given order, compute fluxes */

  switch (order_) {
  case 1:
    advection_le_1st(obj, hydro, nf, field);
    break;
  case 2:
    advection_le_2nd(obj, hydro, nf, field->data);
    break;
  case 3:
    advection_le_3rd(obj, hydro, nf, field);
    break;
  case 4:
    advection_le_4th(obj, hydro, nf, field->data);
    break;
  case 5:
    advection_le_5th(obj, hydro, nf, field->data);
    break; 
  default:
    fatal("Unexpected advection scheme order\n");
  }

  return 0;
}

/*****************************************************************************
 *
 *  advection_le_1st
 *
 *  The advective fluxes are computed via first order upwind
 *  allowing for LE planes.
 * 
 *  The following are set (as for all the upwind routines):
 *
 *  fluxw  ('west') is the flux in x-direction between cells ic-1, ic
 *  fluxe  ('east') is the flux in x-direction between cells ic, ic+1
 *  fluxy           is the flux in y-direction between cells jc, jc+1
 *  fluxz           is the flux in z-direction between cells kc, kc+1
 *
 *****************************************************************************/

__targetEntry__ void advection_le_1st_lattice(advflux_t * flux,
					      hydro_t * hydro, int nf,
					      field_t * field) {

#ifndef OLD_SHIT
  assert(1);
#endif

  int index;
  __targetTLP__(index, tc_nSites) {

    int index0, index1, n;
    int icm1, icp1;
    int nsites;
    double u0[3], u1[3], u;
    double phi0;
    int i;
    
    int coords[3];
    nsites = le_nsites();
    targetCoords3D(coords,tc_Nall,index);

    /* if not a halo site: */
    if (coords[X] >= (tc_nhalo) &&
    	coords[Y] >= (tc_nhalo-1) &&
    	coords[Z] >= (tc_nhalo-1) &&
    	coords[X] < (tc_Nall[X]-tc_nhalo) &&
	coords[Y] < (tc_Nall[Y]-tc_nhalo)  &&
	coords[Z] < (tc_Nall[Z]-tc_nhalo)) {

      index0 = targetIndex3D(coords[X],coords[Y],coords[Z],tc_Nall);

#ifdef __NVCC__
      icm1 = coords[X]-1;
      icp1 = coords[X]+1;
#else
      /* enable LE planes (not yet supported for CUDA) */
      icm1 = le_index_real_to_buffer(coords[X]-tc_nhalo+1, -1)+tc_nhalo-1;
      icp1 = le_index_real_to_buffer(coords[X]-tc_nhalo+1, +1)+tc_nhalo-1;
#endif

      for (n = 0; n < nf; n++) {

#ifndef OLD_SHIT
	phi0 = field->data[addr_rank1(nsites, nf, index0, n)];
	for (i = 0; i < 3; i++) {
	  u0[i] = hydro->u[addr_hydro(index0, i)];
	}
#else
	phi0 = field->data[FLDADR(tc_nSites,nf,index0,n)];
	for (i = 0; i < 3; i++) {
	  u0[i]=hydro->u[HYADR(tc_nSites,3,index0,i)];
	}
#endif
	/* west face (icm1 and ic) */

	index1 = targetIndex3D(icm1,coords[Y],coords[Z],tc_Nall);
#ifndef OLD_SHIT
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[addr_hydro(index1, i)];
	}
#else
	for (i = 0; i < 3; i++) {
	  u1[i]=hydro->u[HYADR(tc_nSites,3,index1,i)];
	}
#endif
	u = 0.5*(u0[X] + u1[X]);

	if (u > 0.0) {
#ifndef OLD_SHIT
	  nsites = le_nsites();
	  flux->fw[addr_rank1(nsites, nf, index0, n)]
	    = u*field->data[addr_rank1(nsites, nf, index1, n)];
#else
	  flux->fw[ADVADR(tc_nSites,nf,index0,n)] = u*field->data[FLDADR(tc_nSites,nf,index1,n)];
#endif
	}
	else {
#ifndef OLD_SHIT
	  flux->fw[addr_rank1(nsites, nf, index0, n)] = u*phi0;
#else
	  flux->fw[ADVADR(tc_nSites,nf,index0,n)] = u*phi0;
#endif
	}

	/* east face (ic and icp1) */

	index1 = targetIndex3D(icp1,coords[Y],coords[Z],tc_Nall);
#ifndef OLD_SHIT
	for(i = 0; i < 3; i++) {
	  u1[i] = hydro->u[addr_hydro(index1, i)];
	}
#else
	for(i = 0; i < 3; i++) {
	  u1[i]=hydro->u[HYADR(tc_nSites,3,index1,i)];
	}
#endif
	u = 0.5*(u0[X] + u1[X]);

	if (u < 0.0) {
#ifndef OLD_SHIT
	  flux->fe[addr_rank1(nsites, nf, index0, n)]
	    = u*field->data[addr_rank1(le_nsites(), nf, index1, n)];
#else
	  flux->fe[ADVADR(tc_nSites,nf,index0,n)] = u*field->data[FLDADR(tc_nSites,nf,index1,n)];
#endif
	}
	else {
#ifndef OLD_SHIT
	  flux->fe[addr_rank1(nsites, nf, index0, n)] = u*phi0;
#else
	  flux->fe[ADVADR(tc_nSites,nf,index0,n)] = u*phi0;
#endif
	}

	/* y direction */

	index1 = targetIndex3D(coords[X],coords[Y]+1,coords[Z],tc_Nall);
#ifndef OLD_SHIT
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[addr_hydro(index1, i)];
	}
#else
	for (i = 0; i < 3; i++) {
	  u1[i]=hydro->u[HYADR(tc_nSites,3,index1,i)];
	}
#endif
	u = 0.5*(u0[Y] + u1[Y]);

	if (u < 0.0) {
#ifndef OLD_SHIT
	  flux->fy[addr_rank1(nsites, nf, index0, n)]
	    = u*field->data[addr_rank1(nsites, nf, index1, n)];
#else
	  flux->fy[ADVADR(tc_nSites,nf,index0,n)] = u*field->data[FLDADR(tc_nSites,nf,index1,n)];
#endif
	}
	else {
#ifndef OLD_SHIT
	  flux->fy[addr_rank1(nsites, nf, index0, n)] = u*phi0;
#else
	  flux->fy[ADVADR(tc_nSites,nf,index0,n)] = u*phi0;
#endif
	}

	/* z direction */

	index1 = targetIndex3D(coords[X],coords[Y],coords[Z]+1,tc_Nall);
#ifndef OLD_SHIT
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[addr_hydro(index1, i)];
	}
#else
	for (i = 0; i < 3; i++) {
	  u1[i]=hydro->u[HYADR(tc_nSites,3,index1,i)];
	}
#endif
	u = 0.5*(u0[Z] + u1[Z]);

	if (u < 0.0) {
#ifndef OLD_SHIT
	  flux->fz[addr_rank1(nsites, nf, index0, n)]
	    = u*field->data[addr_rank1(nsites, nf, index1, n)];
#else
	  flux->fz[ADVADR(tc_nSites,nf,index0,n)] = u*field->data[FLDADR(tc_nSites,nf,index1,n)];
#endif
	}
	else {
#ifndef OLD_SHIT
	  flux->fz[addr_rank1(nsites, nf, index0, n)] = u*phi0;
#else
	  flux->fz[ADVADR(tc_nSites,nf,index0,n)] = u*phi0;
#endif
	}
      }
      /* Next site */
    }
  }

  return;
}

/*****************************************************************************
 *
 *  advection_le_1st
 *
 *  Kernel driver routine
 *
 *****************************************************************************/

static int advection_le_1st(advflux_t * flux, hydro_t * hydro, int nf,
			    field_t * field) {
  int nlocal[3];
  int nhalo;
  int nSites;
  int Nall[3];
  double * tmpptr;

  assert(flux);
  assert(hydro);
  assert(field->data);

  coords_nlocal(nlocal);
  nhalo = coords_nhalo();

  Nall[X] = nlocal[X] + 2*nhalo;
  Nall[Y] = nlocal[Y] + 2*nhalo;
  Nall[Z] = nlocal[Z] + 2*nhalo;
  nSites  = Nall[X]*Nall[Y]*Nall[Z];

  /* copy input data to target */

#ifndef KEEPHYDROONTARGET
  copyFromTarget(&tmpptr, &(hydro->tcopy->u), sizeof(double *)); 
  copyToTarget(tmpptr, hydro->u, 3*nSites*sizeof(double));
#endif

#ifndef KEEPFIELDONTARGET
  copyFromTarget(&tmpptr, &(field->tcopy->data), sizeof(double *)); 
  copyToTarget(tmpptr, field->data, nf*nSites*sizeof(double));
#endif

  /* copy lattice shape constants to target ahead of execution */

  copyConstToTarget(&tc_nSites, &nSites, sizeof(int));
  copyConstToTarget(&tc_nhalo, &nhalo, sizeof(int));
  copyConstToTarget(tc_Nall, Nall, 3*sizeof(int));

  TIMER_start(ADVECTION_X_KERNEL);
#ifdef __NVCC__
  advection_le_1st_lattice __targetLaunch__(nSites) (flux->tcopy, hydro->tcopy, nf,field->tcopy);
#else
  /* use host copies of input just now, because of LE plane buffers*/
  advection_le_1st_lattice __targetLaunch__(nSites) (flux->tcopy, hydro, nf,field);
#endif
  TIMER_stop(ADVECTION_X_KERNEL);

  targetSynchronize();

#ifndef KEEPFIELDONTARGET
  copyFromTarget(&tmpptr, &(flux->tcopy->fe), sizeof(double *)); 
  copyFromTarget(flux->fe, tmpptr, nf*nSites*sizeof(double));

  copyFromTarget(&tmpptr, &(flux->tcopy->fw), sizeof(double *)); 
  copyFromTarget(flux->fw, tmpptr, nf*nSites*sizeof(double));

  copyFromTarget(&tmpptr, &(flux->tcopy->fy), sizeof(double *)); 
  copyFromTarget(flux->fy, tmpptr, nf*nSites*sizeof(double));

  copyFromTarget(&tmpptr, &(flux->tcopy->fz), sizeof(double *)); 
  copyFromTarget(flux->fz, tmpptr, nf*nSites*sizeof(double));
#endif

  return 0;
}

/*****************************************************************************
 *
 *  advection_le_2nd
 *
 *  'Centred difference' advective fluxes, allowing for LE planes.
 *
 *  Symmetric two-point stencil.
 *
 *****************************************************************************/

static int advection_le_2nd(advflux_t * flux, hydro_t * hydro, int nf,
			    double * f) {
  int nlocal[3];
  int ic, jc, kc;
  int n;
  int index0, index1;
  int icp1, icm1;
  double u0[3], u1[3], u;

  assert(flux);
  assert(hydro);
  assert(f);

  coords_nlocal(nlocal);
  assert(coords_nhalo() >= 1);
#ifndef OLD_SHIT
  assert(1);
#endif
  for (ic = 1; ic <= nlocal[X]; ic++) {
    icm1 = le_index_real_to_buffer(ic, -1);
    icp1 = le_index_real_to_buffer(ic, +1);
    for (jc = 0; jc <= nlocal[Y]; jc++) {
      for (kc = 0; kc <= nlocal[Z]; kc++) {

	index0 = le_site_index(ic, jc, kc);
	hydro_u(hydro, index0, u0);

	/* west face (icm1 and ic) */

	index1 = le_site_index(icm1, jc, kc);
	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[X] + u1[X]);
#ifndef OLD_SHIT
	for (n = 0; n < nf; n++) {
	  flux->fw[addr_rank1(le_nsites(), nf, index0, n)]
	    = u*0.5*(f[addr_rank1(le_nsites(), nf, index1, n)]
		     + f[addr_rank1(le_nsites(), nf, index0, n)]);
	}	
#else
	for (n = 0; n < nf; n++) {
	  flux->fw[nf*index0 + n] = u*0.5*(f[nf*index1 + n] + f[nf*index0 + n]);
	}	
#endif
	/* east face (ic and icp1) */

	index1 = le_site_index(icp1, jc, kc);

	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[X] + u1[X]);

	for (n = 0; n < nf; n++) {
	  flux->fe[nf*index0 + n] = u*0.5*(f[nf*index1 + n] + f[nf*index0 + n]);
	}

	/* y direction */

	index1 = le_site_index(ic, jc+1, kc);

	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[Y] + u1[Y]);
#ifndef OLD_SHIT
	for (n = 0; n < nf; n++) {
	  flux->fy[addr_rank1(le_nsites(), nf, index0, n)]
	    = u*0.5*(f[addr_rank1(le_nsites(), nf, index1, n)]
		     + f[addr_rank1(le_nsites(), nf, index0, n)]);
	}
#else
	for (n = 0; n < nf; n++) {
	  flux->fy[nf*index0 + n] = u*0.5*(f[nf*index1 + n] + f[nf*index0 + n]);
	}
#endif
	/* z direction */

	index1 = le_site_index(ic, jc, kc+1);

	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[Z] + u1[Z]);
#ifndef OLD_SHIT
	for (n = 0; n < nf; n++) {
	  flux->fz[addr_rank1(le_nsites(), nf, index0, n)]
	    = u*0.5*(f[addr_rank1(le_nsites(), nf, index1, n)]
		     + f[addr_rank1(le_nsites(), nf, index0, n)]);
	}
#else
	for (n = 0; n < nf; n++) {
	  flux->fz[nf*index0 + n] = u*0.5*(f[nf*index1 + n] + f[nf*index0 + n]);
	}
#endif
	/* Next site */
      }
    }
  }

  return 0;
}

/*****************************************************************************
 *
 *  advection_le_3rd
 *
 *  Advective fluxes, allowing for LE planes.
 *
 *  In fact, formally second order wave-number extended scheme
 *  folowing Li, J. Comp. Phys. 113 235--255 (1997).
 *
 *  The stencil is three points, biased in upwind direction,
 *  with weights a1, a2, a3.
 *
 *****************************************************************************/

__targetEntry__ void advection_le_3rd_lattice(advflux_t * flux, 
					      hydro_t * hydro, int nf,
					      field_t * field) {

  assert(flux);
  assert(hydro);
  assert(field);
#ifndef OLD_SHIT
  assert(1);
#endif
  int index;

  __targetTLP__(index, tc_nSites) {

    int n;
    int nsites;
    double u0[3], u1[3], u;
    int i;
    
    int icm2,  icm1, icp1, icp2;
    
    const double a1 = -0.213933;
    const double a2 =  0.927865;
    const double a3 =  0.286067;
        
    int coords[3];
    targetCoords3D(coords,tc_Nall,index);
    
    /* if not a halo site: */
    if (coords[X] >= (tc_nhalo) &&
    	coords[Y] >= (tc_nhalo-1) &&
    	coords[Z] >= (tc_nhalo-1) &&
    	coords[X] < (tc_Nall[X]-tc_nhalo) &&
	coords[Y] < (tc_Nall[Y]-tc_nhalo)  &&
	coords[Z] < (tc_Nall[Z]-tc_nhalo)) {


      int index0, index1, index2;
      index0 = targetIndex3D(coords[X],coords[Y],coords[Z],tc_Nall);
#ifndef OLD_SHIT
      nsites = le_nsites();
      for (i = 0; i < 3; i++) {
        u0[i] = hydro->u[addr_hydro(index0, i)];
      }
#else
      for (i = 0; i < 3; i++) {
        u0[i] = hydro->u[HYADR(tc_nSites,3,index0,i)];
      }
#endif
	/* west face (icm1 and ic) */

#ifdef __NVCC__
      icm2 = coords[X]-2;
      icm1 = coords[X]-1;
      icp1 = coords[X]+1;
      icp2 = coords[X]+2;
#else
      /* enable LE planes (not yet supported for CUDA) */
      icm2 = le_index_real_to_buffer(coords[X]-tc_nhalo+1, -2)+tc_nhalo-1;
      icm1 = le_index_real_to_buffer(coords[X]-tc_nhalo+1, -1)+tc_nhalo-1;
      icp1 = le_index_real_to_buffer(coords[X]-tc_nhalo+1, +1)+tc_nhalo-1;
      icp2 = le_index_real_to_buffer(coords[X]-tc_nhalo+1, +2)+tc_nhalo-1;
#endif

	for (n = 0; n < nf; n++) 
	{


	index1 = targetIndex3D(icm1,coords[Y],coords[Z],tc_Nall);
#ifndef OLD_SHIT
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[addr_hydro(index1, i)];
	}
#else
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[HYADR(tc_nSites,3,index1,i)];
	}
#endif
	u = 0.5*(u0[X] + u1[X]);



	if (u > 0.0) {
	  index2 = targetIndex3D(icm2,coords[Y],coords[Z],tc_Nall);

#ifndef OLD_SHIT
	  flux->fw[addr_rank1(nsites, nf, index0, n)] =
	    u*(a1*field->data[addr_rank1(nsites, nf, index2, n)]
	     + a2*field->data[addr_rank1(nsites, nf, index1, n)]
	     + a3*field->data[addr_rank1(nsites, nf, index0, n)]);
#else
	  flux->fw[ADVADR(tc_nSites,nf,index0,n)] =
	    u*(a1*field->data[FLDADR(tc_nSites,nf,index2,n)]
	       + a2*field->data[FLDADR(tc_nSites,nf,index1,n)]
	       + a3*field->data[FLDADR(tc_nSites,nf,index0,n)]);
#endif
	}
	else {

	index2 = targetIndex3D(icp1,coords[Y],coords[Z],tc_Nall);
#ifndef OLD_SHIT
	flux->fw[addr_rank1(nsites, nf, index0, n)] =
	  u*(a1*field->data[addr_rank1(nsites, nf, index2, n)]
	   + a2*field->data[addr_rank1(nsites, nf, index0, n)]
	   + a3*field->data[addr_rank1(nsites, nf, index1, n)]);
	}
#else
	flux->fw[ADVADR(tc_nSites,nf,index0,n)] =
	  u*(a1*field->data[FLDADR(tc_nSites, nf, index2, n)]
	   + a2*field->data[FLDADR(tc_nSites, nf, index0, n)]
	   + a3*field->data[FLDADR(tc_nSites, nf, index1, n)]);
	}
#endif

	/* east face (ic and icp1) */

	index1 = targetIndex3D(icp1,coords[Y],coords[Z],tc_Nall);
#ifndef OLD_SHIT
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[addr_hydro(index1, i)];
	}
#else
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[HYADR(tc_nSites,3,index1,i)];
	}
#endif
	u = 0.5*(u0[X] + u1[X]);

	if (u < 0.0) {
	index2 = targetIndex3D(icp2,coords[Y],coords[Z],tc_Nall);
#ifndef OLD_SHIT
	flux->fe[addr_rank1(nsites, nf, index0, n)] =
	  u*(a1*field->data[addr_rank1(nsites, nf, index2, n)]
	   + a2*field->data[addr_rank1(nsites, nf, index1, n)]
	   + a3*field->data[addr_rank1(nsites, nf, index0, n)]);
#else
	flux->fe[ADVADR(tc_nSites,nf,index0,n)] =
	  u*(a1*field->data[FLDADR(tc_nSites,nf,index2,n)]
	     + a2*field->data[FLDADR(tc_nSites,nf,index1,n)]
	     + a3*field->data[FLDADR(tc_nSites,nf,index0,n)]);
#endif
	}
	else {
	index2 = targetIndex3D(icm1,coords[Y],coords[Z],tc_Nall);
#ifndef OLD_SHIT
	flux->fe[addr_rank1(nsites, nf, index0, n)] =
	  u*(a1*field->data[addr_rank1(nsites, nf, index2, n)]
	   + a2*field->data[addr_rank1(nsites, nf, index0, n)]
	   + a3*field->data[addr_rank1(nsites, nf, index1, n)]);
#else
	flux->fe[ADVADR(tc_nSites,nf,index0,n)] =
	  u*(a1*field->data[FLDADR(tc_nSites,nf,index2,n)]
	     + a2*field->data[FLDADR(tc_nSites,nf,index0,n)]
	     + a3*field->data[FLDADR(tc_nSites,nf,index1,n)]);
#endif
	}

	/* y direction */

	index1 = targetIndex3D(coords[X],coords[Y]+1,coords[Z],tc_Nall);
#ifndef OLD_SHIT
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[addr_hydro(index1, i)];
	}
#else
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[HYADR(tc_nSites,3,index1,i)];
	}
#endif
	u = 0.5*(u0[Y] + u1[Y]);

	if (u < 0.0) {
	index2 = targetIndex3D(coords[X],coords[Y]+2,coords[Z],tc_Nall);
#ifndef OLD_SHIT
	flux->fy[addr_rank1(nsites, nf, index0, n)] =
	  u*(a1*field->data[addr_rank1(nsites, nf, index2, n)]
	   + a2*field->data[addr_rank1(nsites, nf, index1, n)]
	   + a3*field->data[addr_rank1(nsites, nf, index0, n)]);
#else
	flux->fy[ADVADR(tc_nSites,nf,index0,n)] =
	  u*(a1*field->data[FLDADR(tc_nSites,nf,index2,n)]
	     + a2*field->data[FLDADR(tc_nSites,nf,index1,n)]
	     + a3*field->data[FLDADR(tc_nSites,nf,index0,n)]);
#endif
	}
	else {
	index2 = targetIndex3D(coords[X],coords[Y]-1,coords[Z],tc_Nall);
#ifndef OLD_SHIT
	    flux->fy[addr_rank1(nsites, nf, index0, n)] =
	      u*(a1*field->data[addr_rank1(nsites, nf, index2, n)]
	       + a2*field->data[addr_rank1(nsites, nf, index0, n)]
	       + a3*field->data[addr_rank1(nsites, nf, index1, n)]);
#else
	    flux->fy[ADVADR(tc_nSites,nf,index0,n)] =
	      u*(a1*field->data[FLDADR(tc_nSites,nf,index2,n)]
	       + a2*field->data[FLDADR(tc_nSites,nf,index0,n)]
	       + a3*field->data[FLDADR(tc_nSites,nf,index1,n)]);
#endif
	}

	/* z direction */

	index1 = targetIndex3D(coords[X],coords[Y],coords[Z]+1,tc_Nall);
#ifndef OLD_SHIT
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[addr_hydro(index1, i)];
	}
#else
	for (i = 0; i < 3; i++) {
	  u1[i] = hydro->u[HYADR(tc_nSites,3,index1,i)];
	}
#endif
	u = 0.5*(u0[Z] + u1[Z]);

	if (u < 0.0) {
	index2 = targetIndex3D(coords[X],coords[Y],coords[Z]+2,tc_Nall);
#ifndef OLD_SHIT
	    flux->fz[addr_rank1(nsites, nf, index0, n)] =
	     u*(a1*field->data[addr_rank1(nsites, nf, index2, n)]
	      + a2*field->data[addr_rank1(nsites, nf, index1, n)]
	      + a3*field->data[addr_rank1(nsites, nf, index0, n)]);
#else
	    flux->fz[ADVADR(tc_nSites,nf,index0,n)] =
	     u*(a1*field->data[FLDADR(tc_nSites,nf,index2,n)]
	     + a2*field->data[FLDADR(tc_nSites,nf,index1,n)]
	     + a3*field->data[FLDADR(tc_nSites,nf,index0,n)]);
#endif
	}
	else {
	index2 = targetIndex3D(coords[X],coords[Y],coords[Z]-1,tc_Nall);
#ifndef OLD_SHIT
	flux->fz[addr_rank1(nsites, nf, index0, n)] =
	  u*(a1*field->data[addr_rank1(nsites, nf, index2, n)]
	   + a2*field->data[addr_rank1(nsites, nf, index0, n)]
           + a3*field->data[addr_rank1(nsites, nf, index1, n)]);
#else
	flux->fz[ADVADR(tc_nSites,nf,index0,n)] =
	  u*(a1*field->data[FLDADR(tc_nSites,nf,index2,n)]
	   + a2*field->data[FLDADR(tc_nSites,nf,index0,n)]
           + a3*field->data[FLDADR(tc_nSites,nf,index1,n)]);
#endif
	}


	}
	/* Next site */
      }
    }

  return;
}

/*****************************************************************************
 *
 *  advection_le_3rd
 *
 *  Kernel driver
 *
 *****************************************************************************/

static int advection_le_3rd(advflux_t * flux, hydro_t * hydro, int nf,
			    field_t * field) {
  int nlocal[3];
  int nhalo;
  int nSites;
  int Nall[3];
  double * tmpptr;

  assert(flux);
  assert(hydro);
  assert(field->data);
  assert(coords_nhalo() >= 2);

  coords_nlocal(nlocal);
  nhalo = coords_nhalo();

  Nall[X] = nlocal[X] + 2*nhalo;
  Nall[Y] = nlocal[Y] + 2*nhalo;
  Nall[Z] = nlocal[Z] + 2*nhalo;
  nSites  = Nall[X]*Nall[Y]*Nall[Z];

  /* copy input data to target */

#ifndef KEEPHYDROONTARGET
  assert(0);
  copyFromTarget(&tmpptr, &(hydro->tcopy->u), sizeof(double *)); 
  copyToTarget(tmpptr, hydro->u, 3*le_nsites()*sizeof(double));
#endif

#ifndef KEEPFIELDONTARGET
  copyFromTarget(&tmpptr, &(field->tcopy->data), sizeof(double *)); 
  copyToTarget(tmpptr, field->data, nf*le_nsites()*sizeof(double));
#endif

  /* copy lattice shape constants to target ahead of execution */

  copyConstToTarget(&tc_nSites, &nSites, sizeof(int));
  copyConstToTarget(&tc_nhalo, &nhalo, sizeof(int));
  copyConstToTarget(tc_Nall, Nall, 3*sizeof(int));

  TIMER_start(ADVECTION_X_KERNEL);

  /* execute lattice-based operation on target */
#ifdef __NVCC__
  advection_le_3rd_lattice __targetLaunch__(nSites) (flux->tcopy,hydro->tcopy,nf,field->tcopy);
#else

#ifdef KEEPFIELDONTARGET
  advection_le_3rd_lattice __targetLaunch__(nSites) (flux->tcopy,hydro->tcopy,nf,field->tcopy);
#else
  /*use host copies of input just now, because of LE plane  buffers */
  advection_le_3rd_lattice __targetLaunch__(nSites) (flux->tcopy,hydro,nf,field);
#endif

#endif

  targetSynchronize();

  TIMER_stop(ADVECTION_X_KERNEL);

  /* copy output data from target */

#ifndef KEEPFIELDONTARGET

  copyFromTarget(&tmpptr, &(flux->tcopy->fe), sizeof(double *)); 
  copyFromTarget(flux->fe, tmpptr, nf*le_nsites()*sizeof(double));

  copyFromTarget(&tmpptr, &(flux->tcopy->fw), sizeof(double *)); 
  copyFromTarget(flux->fw, tmpptr, nf*le_nsites()*sizeof(double));

  copyFromTarget(&tmpptr, &(flux->tcopy->fy), sizeof(double*)); 
  copyFromTarget(flux->fy, tmpptr, nf*le_nsites()*sizeof(double));

  copyFromTarget(&tmpptr, &(flux->tcopy->fz), sizeof(double*)); 
  copyFromTarget(flux->fz, tmpptr, nf*le_nsites()*sizeof(double));
#endif

  return 0;
}

/****************************************************************************
 *
 *  advection_le_4th
 *
 *  Advective fluxes, allowing for LE planes.
 *
 *  The stencil is four points.
 *
 ****************************************************************************/

static int advection_le_4th(advflux_t * flux, hydro_t * hydro, int nf,
			    double * f) {
  int nlocal[3];
  int ic, jc, kc;
  int n;
  int index0, index1;
  int icm2, icm1, icp1, icp2;
  double u0[3], u1[3], u;

  const double a1 = (1.0/16.0); /* Interpolation weight */
  const double a2 = (9.0/16.0); /* Interpolation weight */

  assert(flux);
  assert(hydro);
  assert(f);

  coords_nlocal(nlocal);
  assert(coords_nhalo() >= 2);
#ifndef OLD_SHIT
  assert(0);
#endif
  for (ic = 1; ic <= nlocal[X]; ic++) {
    icm2 = le_index_real_to_buffer(ic, -2);
    icm1 = le_index_real_to_buffer(ic, -1);
    icp1 = le_index_real_to_buffer(ic, +1);
    icp2 = le_index_real_to_buffer(ic, +2);

    for (jc = 0; jc <= nlocal[Y]; jc++) {
      for (kc = 0; kc <= nlocal[Z]; kc++) {

	index0 = le_site_index(ic, jc, kc);
	hydro_u(hydro, index0, u0);

	/* west face (icm1 and ic) */

	index1 = le_site_index(icm1, jc, kc);
	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[X] + u1[X]);
	
	for (n = 0; n < nf; n++) {
	  flux->fw[nf*index0 + n] =
	    u*(- a1*f[nf*le_site_index(icm2, jc, kc) + n]
	       + a2*f[nf*index1 + n]
	       + a2*f[nf*index0 + n]
	       - a1*f[nf*le_site_index(icp1, jc, kc) + n]);
	}

	/* east face */

	index1 = le_site_index(icp1, jc, kc);
	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[X] + u1[X]);

	for (n = 0; n < nf; n++) {
	  flux->fe[nf*index0 + n] =
	    u*(- a1*f[nf*le_site_index(icm1, jc, kc) + n]
	       + a2*f[nf*index0 + n]
	       + a2*f[nf*index1 + n]
	       - a1*f[nf*le_site_index(icp2, jc, kc) + n]);
	}

	/* y-direction */

	index1 = le_site_index(ic, jc+1, kc);
	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[Y] + u1[Y]);

	for (n = 0; n < nf; n++) {
	  flux->fy[nf*index0 + n] =
	    u*(- a1*f[nf*le_site_index(ic, jc-1, kc) + n]
	       + a2*f[nf*index0 + n]
	       + a2*f[nf*index1 + n]
	       - a1*f[nf*le_site_index(ic, jc+2, kc) + n]);
	}

	/* z-direction */

	index1 = le_site_index(ic, jc, kc+1);
	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[Z] + u1[Z]);

	for (n = 0; n < nf; n++) {
	  flux->fz[nf*index0 + n] =
	    u*(- a1*f[nf*le_site_index(ic, jc, kc-1) + n]
	       + a2*f[nf*index0 + n]
	       + a2*f[nf*index1 + n]
	       - a1*f[nf*le_site_index(ic, jc, kc+2) + n]);
	}

	/* Next interface. */
      }
    }
  }

  return 0;
}

/****************************************************************************
 *
 *  advection_le_5th
 *
 *  Advective fluxes, allowing for LE planes.
 *
 *  Formally fourth-order accurate wavenumber-extended scheme of
 *  Li, J. Comp. Phys. 133 235-255 (1997).
 *
 *  The stencil is five points, biased in the upwind direction,
 *  with weights a1--a5.
 *
 ****************************************************************************/

static int advection_le_5th(advflux_t * flux, hydro_t * hydro, int nf,
			    double * f) {
  int nlocal[3];
  int ic, jc, kc;
  int n;
  int index0, index1;
  int icm2, icm1, icp1, icp2, icm3, icp3;
  double u0[3], u1[3], u;

  const double a1 =  0.055453;
  const double a2 = -0.305147;
  const double a3 =  0.916054;
  const double a4 =  0.361520;
  const double a5 = -0.027880;

  assert(flux);
  assert(hydro);
  assert(f);

  coords_nlocal(nlocal);
#ifndef OLD_SHIT
  assert(1);
#endif
  for (ic = 1; ic <= nlocal[X]; ic++) {
    icm3 = le_index_real_to_buffer(ic, -3);
    icm2 = le_index_real_to_buffer(ic, -2);
    icm1 = le_index_real_to_buffer(ic, -1);
    icp1 = le_index_real_to_buffer(ic, +1);
    icp2 = le_index_real_to_buffer(ic, +2);
    icp3 = le_index_real_to_buffer(ic, +3);
    for (jc = 0; jc <= nlocal[Y]; jc++) {
      for (kc = 0; kc <= nlocal[Z]; kc++) {

        index0 = le_site_index(ic, jc, kc);
        hydro_u(hydro, index0, u0);

        /* west face (icm1 and ic) */

        index1 = le_site_index(icm1, jc, kc);
        hydro_u(hydro, index1, u1);
        u = 0.5*(u0[X] + u1[X]);

        if (u > 0.0) {
          for (n = 0; n < nf; n++) {
            flux->fw[nf*index0 + n] =
              u*(a1*f[nf*le_site_index(icm3, jc, kc) + n]
	       + a2*f[nf*le_site_index(icm2, jc, kc) + n]
               + a3*f[nf*index1 + n]
               + a4*f[nf*index0 + n]
	       + a5*f[nf*le_site_index(icp1, jc, kc) + n]);
          }
        }
        else {
          for (n = 0; n < nf; n++) {
            flux->fw[nf*index0 + n] =
              u*(a1*f[nf*le_site_index(icp2, jc, kc) + n]
	       + a2*f[nf*le_site_index(icp1, jc, kc) + n]
               + a3*f[nf*index0 + n]
               + a4*f[nf*index1 + n]
	       + a5*f[nf*le_site_index(icm2, jc, kc) + n]);
          }
	}

        /* east face */

        index1 = le_site_index(icp1, jc, kc);
        hydro_u(hydro, index1, u1);
        u = 0.5*(u0[X] + u1[X]);

        if (u < 0.0) {
          for (n = 0; n < nf; n++) {
            flux->fe[nf*index0 + n] =
              u*(a1*f[nf*le_site_index(icp3, jc, kc) + n]
	       + a2*f[nf*le_site_index(icp2, jc, kc) + n]
               + a3*f[nf*index1 + n]
               + a4*f[nf*index0 + n]
	       + a5*f[nf*le_site_index(icm1, jc, kc) + n]);
          }
        }
        else {
          for (n = 0; n < nf; n++) {
            flux->fe[nf*index0 + n] =
              u*(a1*f[nf*le_site_index(icm2, jc, kc) + n]
	       + a2*f[nf*le_site_index(icm1, jc, kc) + n]
               + a3*f[nf*index0 + n]
               + a4*f[nf*index1 + n]
	       + a5*f[nf*le_site_index(icp2, jc, kc) + n]);
          }
        }

        /* y-direction */

        index1 = le_site_index(ic, jc+1, kc);
        hydro_u(hydro, index1, u1);
        u = 0.5*(u0[Y] + u1[Y]);

        if (u < 0.0) {
          for (n = 0; n < nf; n++) {
            flux->fy[nf*index0 + n] =
              u*(a1*f[nf*le_site_index(ic, jc+3, kc) + n]
	       + a2*f[nf*le_site_index(ic, jc+2, kc) + n]
               + a3*f[nf*index1 + n]
               + a4*f[nf*index0 + n]
	       + a5*f[nf*le_site_index(ic, jc-1, kc) + n]);
          }
        }
        else {
          for (n = 0; n < nf; n++) {
            flux->fy[nf*index0 + n] =
              u*(a1*f[nf*le_site_index(ic, jc-2, kc) + n]
	       + a2*f[nf*le_site_index(ic, jc-1, kc) + n]
               + a3*f[nf*index0 + n]
               + a4*f[nf*index1 + n]
	       + a5*f[nf*le_site_index(ic, jc+2, kc) + n]);
          }
        }

        /* z-direction */

        index1 = le_site_index(ic, jc, kc+1);
        hydro_u(hydro, index1, u1);
        u = 0.5*(u0[Z] + u1[Z]);

        if (u < 0.0) {
          for (n = 0; n < nf; n++) {
            flux->fz[nf*index0 + n] =
              u*(a1*f[nf*le_site_index(ic, jc, kc+3) + n]
	       + a2*f[nf*le_site_index(ic, jc, kc+2) + n]
               + a3*f[nf*index1 + n]
               + a4*f[nf*index0 + n]
	       + a5*f[nf*le_site_index(ic, jc, kc-1) + n]);
          }
        }
        else {
          for (n = 0; n < nf; n++) {
            flux->fz[nf*index0 + n] =
              u*(a1*f[nf*le_site_index(ic, jc, kc-2) + n]
	       + a2*f[nf*le_site_index(ic, jc, kc-1) + n]
               + a3*f[nf*index0 + n]
               + a4*f[nf*index1 + n]
	       + a5*f[nf*le_site_index(ic, jc, kc+2) + n]);
          }
        }

        /* Next interface. */
      }
    }
  }

  return 0;
}

/*****************************************************************************
 *
 *  advective_fluxes
 *
 *  General routine for nf fields at starting address f.
 *  No Lees Edwards boundaries.
 *
 *  The storage of the field(s) for all the related routines is
 *  assumed to be f[index][nf], where index is the spatial index.
 *
 *****************************************************************************/

int advective_fluxes(hydro_t * hydro, int nf, double * f, double * fe,
		     double * fy, double * fz) {

  assert(hydro);
  assert(nf > 0);
  assert(f);
  assert(fe);
  assert(fy);
  assert(fz);
  assert(le_get_nplane_total() == 0);

  advective_fluxes_2nd(hydro, nf, f, fe, fy, fz);

  return 0;
}

/*****************************************************************************
 *
 *  advective_fluxes_2nd
 *
 *  'Centred difference' advective fluxes. No LE planes.
 *
 *  Symmetric two-point stencil.
 *
 *****************************************************************************/

int advective_fluxes_2nd(hydro_t * hydro, int nf, double * f, double * fe,
			 double * fy, double * fz) {
  int nlocal[3];
  int ic, jc, kc;
  int n;
  int index0, index1;
  double u0[3], u1[3], u;

  assert(0); /* OLD_SHIT */
  assert(hydro);
  assert(nf > 0);
  assert(f);
  assert(fe);
  assert(fy);
  assert(fz);

  coords_nlocal(nlocal);
  assert(coords_nhalo() >= 1);
  assert(le_get_nplane_total() == 0);
#ifndef OLD_SHIT
  assert(0);
#endif

  for (ic = 0; ic <= nlocal[X]; ic++) {
    for (jc = 0; jc <= nlocal[Y]; jc++) {
      for (kc = 0; kc <= nlocal[Z]; kc++) {

	index0 = coords_index(ic, jc, kc);
	hydro_u(hydro, index0, u0);

	/* east face (ic and icp1) */

	index1 = coords_index(ic+1, jc, kc);

	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[X] + u1[X]);

	for (n = 0; n < nf; n++) {
	  fe[nf*index0 + n] = u*0.5*(f[nf*index1 + n] + f[nf*index0 + n]);
	}

	/* y direction */

	index1 = coords_index(ic, jc+1, kc);

	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[Y] + u1[Y]);

	for (n = 0; n < nf; n++) {
	  fy[nf*index0 + n] = u*0.5*(f[nf*index1 + n] + f[nf*index0 + n]);
	}

	/* z direction */

	index1 = coords_index(ic, jc, kc+1);

	hydro_u(hydro, index1, u1);
	u = 0.5*(u0[Z] + u1[Z]);

	for (n = 0; n < nf; n++) {
	  fz[nf*index0 + n] = u*0.5*(f[nf*index1 + n] + f[nf*index0 + n]);
	}

	/* Next site */
      }
    }
  }

  return 0;
}

/*****************************************************************************
 *
 *  advective_fluxes_d3qx
 *
 *  General routine for nf fields at starting address f.
 *  No Lees Edwards boundaries.
 *
 *  The storage of the field(s) for all the related routines is
 *  assumed to be f[index][nf], where index is the spatial index.
 *
 *****************************************************************************/

int advective_fluxes_d3qx(hydro_t * hydro, int nf, double * f, 
					double ** flx) {

  assert(hydro);
  assert(nf > 0);
  assert(f);
  assert(flx);
  assert(le_get_nplane_total() == 0);

  advective_fluxes_2nd_d3qx(hydro, nf, f, flx);

  return 0;
}

/*****************************************************************************
 *
 *  advective_fluxes_2nd_d3qx
 *
 *  'Centred difference' advective fluxes. No LE planes.
 *
 *  Symmetric two-point stencil.
 *
 *****************************************************************************/

int advective_fluxes_2nd_d3qx(hydro_t * hydro, int nf, double * f, 
					double ** flx) {

  int nsites;
  int nlocal[3];
  int ic, jc, kc, c;
  int n;
  int index0, index1;
  double u0[3], u1[3], u;

  assert(hydro);
  assert(nf > 0);
  assert(f);
  assert(flx);
  assert(le_get_nplane_total() == 0);

#ifndef OLD_SHIT
  assert(1);
#endif
  nsites = coords_nsites();
  coords_nlocal(nlocal);
  assert(coords_nhalo() >= 1);

  for (ic = 1; ic <= nlocal[X]; ic++) {
    for (jc = 1; jc <= nlocal[Y]; jc++) {
      for (kc = 1; kc <= nlocal[Z]; kc++) {

	index0 = coords_index(ic, jc, kc);
	hydro_u(hydro, index0, u0);

        for (c = 1; c < PSI_NGRAD; c++) {

	  index1 = coords_index(ic + psi_gr_cv[c][X], jc + psi_gr_cv[c][Y], kc + psi_gr_cv[c][Z]);
	  hydro_u(hydro, index1, u1);

	  u = 0.5*((u0[X] + u1[X])*psi_gr_cv[c][X] + (u0[Y] + u1[Y])*psi_gr_cv[c][Y] + (u0[Z] + u1[Z])*psi_gr_cv[c][Z]);
#ifndef OLD_SHIT
	  for (n = 0; n < nf; n++) {
	    flx[addr_rank1(nsites, nf, index0, n)][c - 1]
	      = u*0.5*(f[addr_rank1(nsites, nf, index1, n)]
		       + f[addr_rank1(nsites, nf, index0, n)]);
	  }
#else
	  for (n = 0; n < nf; n++) {
	    flx[nf*index0 + n][c - 1] = u*0.5*(f[nf*index1 + n] + f[nf*index0 + n]);
	  }
#endif
	}

	/* Next site */
      }
    }
  }

  return 0;
}