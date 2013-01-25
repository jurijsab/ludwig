/*****************************************************************************
 *
 *  phi_force_gpu.cu
 *
 *  Alan Gray
 *
 *****************************************************************************/

#include <assert.h>
#include <stdlib.h>
#include <math.h>
#include <stdio.h> 

#define INCLUDING_FROM_GPU_SOURCE
#include "phi_force_gpu.h"

#include "pe.h"
//#include "coords.h"
#include "lattice.h"
#include "phi.h"
#include "site_map.h"
#include "leesedwards.h"
#include "free_energy.h"
#include "wall.h"
#include "phi_force_stress.h"
#include "colloids_Q_tensor.h"
// FROM util.c
#include "util.h"
//static const double r3_ = (1.0/3.0);


dim3 nblocks, threadsperblock;


/*****************************************************************************
 *
 *  phi_force_calculation
 *
 *  Driver routine to compute the body force on fluid from phi sector.
 *
 *****************************************************************************/

void phi_force_calculation_gpu(void) {

  int N[3],nhalo,Nall[3];
  nhalo = coords_nhalo();
  coords_nlocal(N); 
  Nall[X]=N[X]+2*nhalo;
  Nall[Y]=N[Y]+2*nhalo;
  Nall[Z]=N[Z]+2*nhalo;
  int nsites=Nall[X]*Nall[Y]*Nall[Z];

  //TO DO
  //if (force_required_ == 0) return;

  //if (le_get_nplane_total() > 0 || wall_present()) {
    /* Must use the flux method for LE planes */
    /* Also convenient for plane walls */
    //phi_force_flux();
  //}
  //else {
  //if (force_divergence_) {

  put_phi_force_constants_on_gpu();

  cudaFuncSetCacheConfig(phi_force_calculation_fluid_gpu_d,cudaFuncCachePreferL1);

  /* compute q2 and eq */
  threadsperblock.x=DEFAULT_TPB_Z;
  threadsperblock.y=DEFAULT_TPB_Y;
  threadsperblock.z=DEFAULT_TPB_X;

  nblocks.x=(Nall[Z]+DEFAULT_TPB_Z-1)/DEFAULT_TPB_Z;
  nblocks.y=(Nall[Y]+DEFAULT_TPB_Y-1)/DEFAULT_TPB_Y;
  nblocks.z=(Nall[X]+DEFAULT_TPB_X-1)/DEFAULT_TPB_X;

  blue_phase_compute_q2_eq_all_gpu_d<<<nblocks,threadsperblock>>>(phi_site_d,phi_site_full_d,grad_phi_site_d,delsq_phi_site_d,h_site_d,tmpscal1_d,tmpscal2_d);


  /* /\* compute h *\/ */
  /* #define TPSITE 9 */
  /* threadsperblock.x=DEFAULT_TPB; */
  /* threadsperblock.y=1; */
  /* threadsperblock.z=1; */

  /* nblocks.x=(TPSITE*Nall[X]*Nall[Y]*Nall[Z]+DEFAULT_TPB-1)/DEFAULT_TPB,1,1; */
  /* nblocks.y=1; */
  /* nblocks.z=1; */

  /* blue_phase_compute_h_all_gpu_d<<<nblocks,threadsperblock>>>(phi_site_d,phi_site_full_d,grad_phi_site_d,delsq_phi_site_d,h_site_d, tmpscal1_d, tmpscal2_d); */


  /* /\* compute stress *\/ */
  /* threadsperblock.x=DEFAULT_TPB_Z; */
  /* threadsperblock.y=DEFAULT_TPB_Y; */
  /* threadsperblock.z=DEFAULT_TPB_X; */

  /* nblocks.x=(Nall[Z]+DEFAULT_TPB_Z-1)/DEFAULT_TPB_Z; */
  /* nblocks.y=(Nall[Y]+DEFAULT_TPB_Y-1)/DEFAULT_TPB_Y; */
  /* nblocks.z=(Nall[X]+DEFAULT_TPB_X-1)/DEFAULT_TPB_X; */


  blue_phase_compute_h_all_gpu_d<<<nblocks,threadsperblock>>>(phi_site_d,phi_site_full_d,grad_phi_site_d,delsq_phi_site_d,h_site_d, tmpscal1_d, tmpscal2_d);

  blue_phase_compute_stress1_all_gpu_d<<<nblocks,threadsperblock>>>(phi_site_d,phi_site_full_d,grad_phi_site_d,grad_phi_site_full_d,delsq_phi_site_d,h_site_d, stress_site_d);

  blue_phase_compute_stress2_all_gpu_d<<<nblocks,threadsperblock>>>(phi_site_d,phi_site_full_d,grad_phi_site_d,grad_phi_site_full_d,grad_phi_float_d,delsq_phi_site_d,h_site_d, stress_site_d);



  /* compute force */
  threadsperblock.x=DEFAULT_TPB_Z;
  threadsperblock.y=DEFAULT_TPB_Y;
  threadsperblock.z=DEFAULT_TPB_X;

  nblocks.x=(N[Z]+DEFAULT_TPB_Z-1)/DEFAULT_TPB_Z;
  nblocks.y=(N[Y]+DEFAULT_TPB_Y-1)/DEFAULT_TPB_Y;
  nblocks.z=(N[X]+DEFAULT_TPB_X-1)/DEFAULT_TPB_X;


  phi_force_calculation_fluid_gpu_d<<<nblocks,threadsperblock>>>
    (le_index_real_to_buffer_d,phi_site_d,phi_site_full_d,grad_phi_site_d,delsq_phi_site_d,h_site_d,stress_site_d,force_d);
      
      cudaThreadSynchronize();
      checkCUDAError("phi_force_calculation_fluid_gpu_d");

      //}
      //else {
     //hi_force_fluid_phi_gradmu();
      //}
      //}

  return;
}

texture<float,1,cudaReadModeElementType> texreference;

void phi_force_colloid_gpu(void) {

  int N[3],nhalo,Nall[3];
  nhalo = coords_nhalo();
  coords_nlocal(N); 
  Nall[X]=N[X]+2*nhalo;
  Nall[Y]=N[Y]+2*nhalo;
  Nall[Z]=N[Z]+2*nhalo;
  int nsites=Nall[X]*Nall[Y]*Nall[Z];
   

  // TODO
  /* if (colloids_q_anchoring_method() == ANCHORING_METHOD_ONE) { */
  /*   phi_force_interpolation1(); */
  /* } */
  /* else { */
  /*   phi_force_interpolation2(); */
  /* } */


  put_phi_force_constants_on_gpu();

  expand_grad_phi_on_gpu();

  cudaFuncSetCacheConfig(phi_force_colloid_gpu_d,cudaFuncCachePreferL1);

  cudaFuncSetCacheConfig( blue_phase_compute_h_all_gpu_d,cudaFuncCachePreferShared);

  /* compute q2 and eq */
  threadsperblock.x=DEFAULT_TPB_Z;
  threadsperblock.y=DEFAULT_TPB_Y;
  threadsperblock.z=DEFAULT_TPB_X;

  nblocks.x=(Nall[Z]+DEFAULT_TPB_Z-1)/DEFAULT_TPB_Z;
  nblocks.y=(Nall[Y]+DEFAULT_TPB_Y-1)/DEFAULT_TPB_Y;
  nblocks.z=(Nall[X]+DEFAULT_TPB_X-1)/DEFAULT_TPB_X;

  blue_phase_compute_q2_eq_all_gpu_d<<<nblocks,threadsperblock>>>(phi_site_d,phi_site_full_d,grad_phi_site_d,delsq_phi_site_d,h_site_d,tmpscal1_d,tmpscal2_d);


  /* /\* compute h *\/ */
  /* #define TPSITE 9 */
  /* threadsperblock.x=DEFAULT_TPB; */
  /* threadsperblock.y=1; */
  /* threadsperblock.z=1; */

  /* nblocks.x=(TPSITE*Nall[X]*Nall[Y]*Nall[Z]+DEFAULT_TPB-1)/DEFAULT_TPB,1,1; */
  /* nblocks.y=1; */
  /* nblocks.z=1; */

  /* blue_phase_compute_h_all_gpu_d<<<nblocks,threadsperblock>>>(phi_site_d,phi_site_full_d,grad_phi_site_d,delsq_phi_site_d,h_site_d, tmpscal1_d, tmpscal2_d); */


  /* /\* compute stress *\/ */
  /* threadsperblock.x=DEFAULT_TPB_Z; */
  /* threadsperblock.y=DEFAULT_TPB_Y; */
  /* threadsperblock.z=DEFAULT_TPB_X; */

  /* nblocks.x=(Nall[Z]+DEFAULT_TPB_Z-1)/DEFAULT_TPB_Z; */
  /* nblocks.y=(Nall[Y]+DEFAULT_TPB_Y-1)/DEFAULT_TPB_Y; */
  /* nblocks.z=(Nall[X]+DEFAULT_TPB_X-1)/DEFAULT_TPB_X; */


  blue_phase_compute_h_all_gpu_d<<<nblocks,threadsperblock>>>(phi_site_d,phi_site_full_d,grad_phi_site_d,delsq_phi_site_d,h_site_d, tmpscal1_d, tmpscal2_d);


  blue_phase_compute_stress1_all_gpu_d<<<nblocks,threadsperblock>>>(phi_site_d,phi_site_full_d,grad_phi_site_d,grad_phi_site_full_d,delsq_phi_site_d,h_site_d, stress_site_d);



  threadsperblock.x=DEFAULT_TPB;
  threadsperblock.y=1;
  threadsperblock.z=1;

  nblocks.x=(9*Nall[X]*Nall[Y]*Nall[Z]+DEFAULT_TPB-1)/DEFAULT_TPB,1,1;
  nblocks.y=1;
  nblocks.z=1;




cudaBindTexture(0,texreference,grad_phi_float_d,sizeof(float)*nsites*27); 

 blue_phase_compute_stress2_all_gpu_d<<<nblocks,threadsperblock>>>(phi_site_d,phi_site_full_d,grad_phi_site_d,grad_phi_site_full_d,grad_phi_float_d,delsq_phi_site_d,h_site_d, stress_site_d);


//unbind texture reference to free resource
cudaUnbindTexture(texreference);





  /* compute force */
  threadsperblock.x=DEFAULT_TPB_Z;
  threadsperblock.y=DEFAULT_TPB_Y;
  threadsperblock.z=DEFAULT_TPB_X;

  nblocks.x=(N[Z]+DEFAULT_TPB_Z-1)/DEFAULT_TPB_Z;
  nblocks.y=(N[Y]+DEFAULT_TPB_Y-1)/DEFAULT_TPB_Y;
  nblocks.z=(N[X]+DEFAULT_TPB_X-1)/DEFAULT_TPB_X;


  phi_force_colloid_gpu_d<<<nblocks,threadsperblock>>>
    (le_index_real_to_buffer_d,site_map_status_d,phi_site_d,phi_site_full_d,grad_phi_site_d,delsq_phi_site_d,h_site_d,stress_site_d,force_d,colloid_force_d);
      
      cudaThreadSynchronize();
      checkCUDAError("phi_force_colloid_gpu_d");

  return;
}



void blue_phase_be_update_gpu(void) {

  int N[3],nhalo,Nall[3];
  
  nhalo = coords_nhalo();
  coords_nlocal(N); 


  Nall[X]=N[X]+2*nhalo;
  Nall[Y]=N[Y]+2*nhalo;
  Nall[Z]=N[Z]+2*nhalo;
  
  int nsites=Nall[X]*Nall[Y]*Nall[Z];
 

  put_phi_force_constants_on_gpu();  

  cudaFuncSetCacheConfig(phi_force_calculation_fluid_gpu_d,cudaFuncCachePreferL1);

  threadsperblock.x=DEFAULT_TPB_Z;
  threadsperblock.y=DEFAULT_TPB_Y;
  threadsperblock.z=DEFAULT_TPB_X;

  nblocks.x=(N[Z]+DEFAULT_TPB_Z-1)/DEFAULT_TPB_Z;
  nblocks.y=(N[Y]+DEFAULT_TPB_Y-1)/DEFAULT_TPB_Y;
  nblocks.z=(N[X]+DEFAULT_TPB_X-1)/DEFAULT_TPB_X;

  blue_phase_be_update_gpu_d<<<nblocks,threadsperblock>>>
    (le_index_real_to_buffer_d,phi_site_d,phi_site_full_d,grad_phi_site_d,delsq_phi_site_d,h_site_d,force_d,velocity_d,site_map_status_d, fluxe_d, fluxw_d, fluxy_d, fluxz_d);
      
  cudaThreadSynchronize();
  checkCUDAError("blue_phase_be_update_gpu_d");


  return;
}

void advection_upwind_gpu(void) {

  int N[3],nhalo,Nall[3];
  
  nhalo = coords_nhalo();
  coords_nlocal(N); 


  Nall[X]=N[X]+2*nhalo;
  Nall[Y]=N[Y]+2*nhalo;
  Nall[Z]=N[Z]+2*nhalo;
  
  int nsites=Nall[X]*Nall[Y]*Nall[Z];
 

  


 cudaFuncSetCacheConfig(advection_upwind_gpu_d,cudaFuncCachePreferL1);

  threadsperblock.x=DEFAULT_TPB_Z;
  threadsperblock.y=DEFAULT_TPB_Y;
  threadsperblock.z=DEFAULT_TPB_X;

 /* two fastest moving dimensions have cover a single lower width-one halo here */

  nblocks.x=(N[Z]+1+DEFAULT_TPB_Z-1)/DEFAULT_TPB_Z;
  nblocks.y=(N[Y]+1+DEFAULT_TPB_Y-1)/DEFAULT_TPB_Y;
  nblocks.z=(N[X]+DEFAULT_TPB_X-1)/DEFAULT_TPB_X;


  advection_upwind_gpu_d<<<nblocks,threadsperblock>>>
    (le_index_real_to_buffer_d,phi_site_d,phi_site_full_d,grad_phi_site_d,delsq_phi_site_d,force_d,velocity_d,site_map_status_d, fluxe_d, fluxw_d, fluxy_d, fluxz_d);
      
  cudaThreadSynchronize();
  checkCUDAError("advection_upwind_gpu_d");


  return;
}

__global__ void advection_bcs_no_normal_flux_gpu_d(const int nop,
					   char *site_map_status_d,
					   double *fluxe_d,
					   double *fluxw_d,
					   double *fluxy_d,
					   double *fluxz_d
						   );


void advection_bcs_no_normal_flux_gpu(void){

  int N[3],nhalo,Nall[3];
  
  nhalo = coords_nhalo();
  coords_nlocal(N); 


  Nall[X]=N[X]+2*nhalo;
  Nall[Y]=N[Y]+2*nhalo;
  Nall[Z]=N[Z]+2*nhalo;
  
  int nsites=Nall[X]*Nall[Y]*Nall[Z];


  int nop = phi_nop();
  
  cudaFuncSetCacheConfig(advection_upwind_gpu_d,cudaFuncCachePreferL1);
  
#define TPBX 4 
#define TPBY 4
#define TPBZ 8
  
  /* two sfastest moving dimensions have cover a single lower width-one halo here */
  dim3 nblocks(((N[Z]+1)+TPBZ-1)/TPBZ,((N[Y]+1)+TPBY-1)/TPBY,(N[X]+TPBX-1)/TPBX);
  dim3 threadsperblock(TPBZ,TPBY,TPBX);
  
  advection_bcs_no_normal_flux_gpu_d<<<nblocks,threadsperblock>>>
    (nop, site_map_status_d, fluxe_d, fluxw_d, fluxy_d, fluxz_d);
  
  cudaThreadSynchronize();
  checkCUDAError("advection_bcs_no_normal_flux_gpu");
  
  return;

}


/*****************************************************************************
 *
 *  blue_phase_compute_fed
 *
 *  Compute the free energy density as a function of q and the q gradient
 *  tensor dq.
 *
 *****************************************************************************/

__device__ double blue_phase_compute_fed_gpu_d(double q[3][3], double dq[3][3][3], double *grad_phi_site_full_d, int index){

  int ia, ib, ic, id;
  double q2, q3;
  double dq0, dq1;
  double sum;
  double efield;
 
  q2 = 0.0;

  /* Q_ab^2 */

  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {
      q2 += q[ia][ib]*q[ia][ib];
    }
  }

  /* Q_ab Q_bc Q_ca */

  q3 = 0.0;

  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {
      for (ic = 0; ic < 3; ic++) {
	/* We use here the fact that q[ic][ia] = q[ia][ic] */
	q3 += q[ia][ib]*q[ib][ic]*q[ia][ic];
      }
    }
  }

  /* (d_b Q_ab)^2 */

  dq0 = 0.0;

  for (ia = 0; ia < 3; ia++) {
    sum = 0.0;
    for (ib = 0; ib < 3; ib++) {
      sum += dq[ib][ia][ib];
      //sum += grad_phi_site_full_d[ib*nsites_cd*9 + ia*nsites_cd*3+ ib*nsites_cd + index];
    }
    dq0 += sum*sum;
  }

  /* (e_acd d_c Q_db + 2q_0 Q_ab)^2 */
  /* With symmetric Q_db write Q_bd */

  dq1 = 0.0;

  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {
      sum = 0.0;
      for (ic = 0; ic < 3; ic++) {
	for (id = 0; id < 3; id++) {
	  sum += e_cd[ia][ic][id]*dq[ic][ib][id];
	  //sum += e_cd[ia][ic][id]*grad_phi_site_full_d[ic*nsites_cd*9 + ib*nsites_cd*3+ id*nsites_cd + index];
	}
      }
      sum += 2.0*q0shift_cd*q[ia][ib];
      dq1 += sum*sum;
    }
  }

  /* Electric field term (epsilon_ includes the factor 1/12pi) */

  efield = 0.0;
  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {
      efield += electric_cd[ia]*q[ia][ib]*electric_cd[ib];
    }
  }

  sum = 0.5*a0_cd*(1.0 - r3_cd*gamma_cd)*q2 - r3_cd*a0_cd*gamma_cd*q3 +
    0.25*a0_cd*gamma_cd*q2*q2 + 0.5*kappa0shift_cd*dq0 + 0.5*kappa1shift_cd*dq1 - epsilon_cd*efield;;

  return sum;
}


/*****************************************************************************
 *
 *  blue_phase_compute_stress
 *
 *  Compute the stress as a function of the q tensor, the q tensor
 *  gradient and the molecular field.
 *
 *  Note the definition here has a minus sign included to allow
 *  computation of the force as minus the divergence (which often
 *  appears as plus in the liquid crystal literature). This is a
 *  separate operation at the end to avoid confusion.
 *
 *****************************************************************************/

__device__ void blue_phase_compute_stress1_gpu_d(double q[3][3], double dq[3][3][3], double sth[3][3], double *grad_phi_site_full_d, double *h_site_d, int index){
  int ia, ib, ic, id, ie;

  double tmpdbl,tmpdbl2;

  double h[3][3];

  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {
      h[ia][ib]=h_site_d[3*nsites_cd*ia+nsites_cd*ib+index];
    }
  }

  
  /* We have ignored the rho T term at the moment, assumed to be zero
   * (in particular, it has no divergence if rho = const). */

  tmpdbl = 0.0 - blue_phase_compute_fed_gpu_d(q, dq,grad_phi_site_full_d, index);

  /* The contraction Q_ab H_ab */

  tmpdbl2 = 0.0;

  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {
      tmpdbl2 += q[ia][ib]*h[ia][ib];
    }
  }

  /* The term in the isotropic pressure, plus that in qh */
  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {
      sth[ia][ib] = -tmpdbl*d_cd[ia][ib] + 2.0*xi_cd*(q[ia][ib] + r3_cd*d_cd[ia][ib])*tmpdbl2;
    }
  }

  /* Remaining two terms in xi and molecular field */

  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {
      tmpdbl=0.;
      for (ic = 0; ic < 3; ic++) {
	tmpdbl+=
  	  -xi_cd*h[ia][ic]*(q[ib][ic] + r3_cd*d_cd[ib][ic])
  	  -xi_cd*(q[ia][ic] + r3_cd*d_cd[ia][ic])*h[ib][ic];
      }
      sth[ia][ib] += tmpdbl;
    }
  }

  /* The antisymmetric piece q_ac h_cb - h_ac q_cb. We can
   * rewrite it as q_ac h_bc - h_ac q_bc. */

  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {
      tmpdbl=0.;
      for (ic = 0; ic < 3; ic++) {
  	 tmpdbl += q[ia][ic]*h[ib][ic] - h[ia][ic]*q[ib][ic];
      }
      sth[ia][ib]+=tmpdbl;
      /* This is the minus sign. */
      //sth[ia][ib] = -sth[ia][ib];
    }
  }






  return;
}



/*****************************************************************************
 *
 *  phi_force_calculation_fluid
 *
 *  Compute force from thermodynamic sector via
 *    F_alpha = nalba_beta Pth_alphabeta
 *  using a simple six-point stencil.
 *
 *  Side effect: increments the force at each local lattice site in
 *  preparation for the collision stage.
 *
 *****************************************************************************/


__global__ void phi_force_calculation_fluid_gpu_d(int * le_index_real_to_buffer_d,
						  double *phi_site_d,
						  double *phi_site_full_d,
						  double *grad_phi_site_d,
						  double *delsq_phi_site_d,
						  double *h_site_d,
						  double *stress_site_d,
						  double *force_d
					    ) {

  int ia, ib, icm1, icp1;
  int index, index1;
  double pth0[3][3];
  double pth1[3][3];
  double force[3];
  int ii, jj, kk;

 /* CUDA thread index */
  kk = blockIdx.x*blockDim.x+threadIdx.x;
  jj = blockIdx.y*blockDim.y+threadIdx.y;
  ii = blockIdx.z*blockDim.z+threadIdx.z;
 
 /* Avoid going beyond problem domain */
  if (ii < N_cd[X] && jj < N_cd[Y] && kk < N_cd[Z] )
    {


      /* calculate index from CUDA thread index */

      index = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);      
      icm1=le_index_real_to_buffer_d[ii+nhalo_cd];
      icp1=le_index_real_to_buffer_d[Nall_cd[X]+ii+nhalo_cd];      
      

	/* Compute pth at current point */
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth0[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index];
      	}
      }

	/* Compute differences */
	index1 = get_linear_index_gpu_d(icp1,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }
	for (ia = 0; ia < 3; ia++) {
	  force[ia] = -0.5*(pth1[ia][X] + pth0[ia][X]);
	}

	index1 = get_linear_index_gpu_d(icm1,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }
	for (ia = 0; ia < 3; ia++) {
	  force[ia] += 0.5*(pth1[ia][X] + pth0[ia][X]);
	}

	
	index1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd+1,kk+nhalo_cd,Nall_cd);
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }
	for (ia = 0; ia < 3; ia++) {
	  force[ia] -= 0.5*(pth1[ia][Y] + pth0[ia][Y]);
	}

	index1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd-1,kk+nhalo_cd,Nall_cd);
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }
	for (ia = 0; ia < 3; ia++) {
	  force[ia] += 0.5*(pth1[ia][Y] + pth0[ia][Y]);
	}
	

	index1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd+1,Nall_cd);
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }
	for (ia = 0; ia < 3; ia++) {
	  force[ia] -= 0.5*(pth1[ia][Z] + pth0[ia][Z]);
	}

	index1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd-1,Nall_cd);
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }
	for (ia = 0; ia < 3; ia++) {
	  force[ia] += 0.5*(pth1[ia][Z] + pth0[ia][Z]);
	}

	/* Store the force on lattice */
	for (ia=0;ia<3;ia++)
	  force_d[ia*nsites_cd+index]+=force[ia];

    }


  return;
}



__global__ void phi_force_colloid_gpu_d(int * le_index_real_to_buffer_d,
					char * site_map_status_d,
						  double *phi_site_d,
						  double *phi_site_full_d,
						  double *grad_phi_site_d,
						  double *delsq_phi_site_d,
						  double *h_site_d,
						  double *stress_site_d,
					double *force_d,
						  double *colloid_force_d
					    ) {

  int ia, ib, icm1, icp1;
  int index, index1;
  double pth0[3][3];
  double pth1[3][3];
  double force[3];
  int ii, jj, kk;

 /* CUDA thread index */
  kk = blockIdx.x*blockDim.x+threadIdx.x;
  jj = blockIdx.y*blockDim.y+threadIdx.y;
  ii = blockIdx.z*blockDim.z+threadIdx.z;
 
 /* Avoid going beyond problem domain */

  if (ii < N_cd[X] && jj < N_cd[Y] && kk < N_cd[Z] )
    {


      /* calculate index from CUDA thread index */
      index = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);      

      if (site_map_status_d[index1] != COLLOID){
	/* If this is solid, then there's no contribution here. */
      
	/* Compute pth at current point */
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth0[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index];
      	}
      }

	/* Compute differences */
	index1 = get_linear_index_gpu_d(ii+nhalo_cd+1,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);

	if (site_map_status_d[index1] == COLLOID){
	  /* Compute the fluxes at solid/fluid boundary */
	  for (ia = 0; ia < 3; ia++) {
	    force[ia] = -pth0[ia][X];
	    colloid_force_d[0*nsites_cd*3+nsites_cd*ia+index]+=pth0[ia][X];
	  }
	}
	else
	  {
	  /* This flux is fluid-fluid */ 
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }


	    for (ia = 0; ia < 3; ia++) {
	      force[ia] = -0.5*(pth1[ia][X] + pth0[ia][X]);
	    }

	  }



	index1 = get_linear_index_gpu_d(ii+nhalo_cd-1,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);

	if (site_map_status_d[index1] == COLLOID){
	  /* Solid-fluid */
	  for (ia = 0; ia < 3; ia++) {
	    force[ia] += pth0[ia][X];
	    colloid_force_d[1*nsites_cd*3+nsites_cd*ia+index]-=pth0[ia][X];
	  }
	}
	else
	  {
	    /* Fluid - fluid */
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }


	    for (ia = 0; ia < 3; ia++) {
	      force[ia] += 0.5*(pth1[ia][X] + pth0[ia][X]);
	    }
	  }

	
	index1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd+1,kk+nhalo_cd,Nall_cd);
	
	if (site_map_status_d[index1] == COLLOID){
	  /* Solid-fluid */
	  for (ia = 0; ia < 3; ia++) {
	    force[ia] -= pth0[ia][Y];
	    colloid_force_d[2*nsites_cd*3+nsites_cd*ia+index]+=pth0[ia][Y];
	  }
	}
	else
	  {
	    /* Fluid - fluid */
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }


	    for (ia = 0; ia < 3; ia++) {
	      force[ia] -= 0.5*(pth1[ia][Y] + pth0[ia][Y]);
	    }
	  }
	
	
	index1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd-1,kk+nhalo_cd,Nall_cd);
	
	if (site_map_status_d[index1] == COLLOID){
	  /* Solid-fluid */
	  for (ia = 0; ia < 3; ia++) {
	    force[ia] += pth0[ia][Y];
	    colloid_force_d[3*nsites_cd*3+nsites_cd*ia+index]-=pth0[ia][Y];
	  }
	}
	else
	  {
	    /* Fluid - fluid */
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }


	    for (ia = 0; ia < 3; ia++) {
	      force[ia] += 0.5*(pth1[ia][Y] + pth0[ia][Y]);
	    }
	  }	
	
	index1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd+1,Nall_cd);
	
	if (site_map_status_d[index1] == COLLOID){
	  /* Solid-fluid */
	  for (ia = 0; ia < 3; ia++) {
	    force[ia] -= pth0[ia][Z];
	    colloid_force_d[4*nsites_cd*3+nsites_cd*ia+index]+=pth0[ia][Z];
	  }
	}
	else
	  {
	    /* Fluid - fluid */
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }


	    for (ia = 0; ia < 3; ia++) {
	      force[ia] -= 0.5*(pth1[ia][Z] + pth0[ia][Z]);
	    }
	    
	  }
	
	index1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd-1,Nall_cd);
	if (site_map_status_d[index1] == COLLOID){
	  /* Solid-fluid */
	  for (ia = 0; ia < 3; ia++) {
	    force[ia] += pth0[ia][Z];
	    colloid_force_d[5*nsites_cd*3+nsites_cd*ia+index]-=pth0[ia][Z];
	  }
	}
	else
	  {
	    /* Fluid - fluid */
      for (ia = 0; ia < 3; ia++) {
      	for (ib = 0; ib < 3; ib++) {
      	  pth1[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index1];
      	}
      }


	    for (ia = 0; ia < 3; ia++) {
	      force[ia] += 0.5*(pth1[ia][Z] + pth0[ia][Z]);
	    }
	    
	  }

	/* Store the force on lattice */
	for (ia=0;ia<3;ia++)
	  force_d[ia*nsites_cd+index]+=force[ia];
	
      }
    }
  
  
  return;
}


__global__ void blue_phase_be_update_gpu_d(int * le_index_real_to_buffer_d,
						  double *phi_site_d,
						  double *phi_site_full_d,
						  double *grad_phi_site_d,
						  double *delsq_phi_site_d,
						  double *h_site_d,
					   double *force_d,
					   double *velocity_d,
					   char *site_map_status_d,
					   double *fluxe_d,
					   double *fluxw_d,
					   double *fluxy_d,
					   double *fluxz_d
					    ) {

  int ia, icm1, icp1;
  int index, index1, indexm1, indexp1;
  double pth0[3][3];
  double pth1[3][3];
  double force[3];
  int ii, jj, kk;

 /* CUDA thread index */
  kk = blockIdx.x*blockDim.x+threadIdx.x;
  jj = blockIdx.y*blockDim.y+threadIdx.y;
  ii = blockIdx.z*blockDim.z+threadIdx.z;
 
 /* Avoid going beyond problem domain */
  if (ii < N_cd[X] && jj < N_cd[Y] && kk < N_cd[Z] )
    {


      /* calculate index from CUDA thread index */

      index = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);      

      icm1=le_index_real_to_buffer_d[ii+nhalo_cd];
      icp1=le_index_real_to_buffer_d[Nall_cd[X]+ii+nhalo_cd];      

      indexm1 = get_linear_index_gpu_d(icm1,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);
      indexp1 = get_linear_index_gpu_d(icp1,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);



      int ia, ib, ic, id;

  double q[3][3];
  double d[3][3];
  double h[3][3];
  double s[3][3];
  double dq[3][3][3];
  double dsq[3][3];
  double w[3][3];
  double omega[3][3];
  double trace_qw;

  /* load phi */

  q[X][X] = phi_site_d[nsites_cd*XX+index];
  q[X][Y] = phi_site_d[nsites_cd*XY+index];
  q[X][Z] = phi_site_d[nsites_cd*XZ+index];
  q[Y][X] = q[X][Y];
  q[Y][Y] = phi_site_d[nsites_cd*YY+index];
  q[Y][Z] = phi_site_d[nsites_cd*YZ+index];
  q[Z][X] = q[X][Z];
  q[Z][Y] = q[Y][Z];
  q[Z][Z] = 0.0 - q[X][X] - q[Y][Y];

  /* load grad phi */
  for (ia = 0; ia < 3; ia++) {
    dq[ia][X][X] = grad_phi_site_d[ia*nsites_cd*5 + XX*nsites_cd + index];
    dq[ia][X][Y] = grad_phi_site_d[ia*nsites_cd*5 + XY*nsites_cd + index];
    dq[ia][X][Z] = grad_phi_site_d[ia*nsites_cd*5 + XZ*nsites_cd + index];
    dq[ia][Y][X] = dq[ia][X][Y];
    dq[ia][Y][Y] = grad_phi_site_d[ia*nsites_cd*5 + YY*nsites_cd + index];
    dq[ia][Y][Z] = grad_phi_site_d[ia*nsites_cd*5 + YZ*nsites_cd + index];
    dq[ia][Z][X] = dq[ia][X][Z];
    dq[ia][Z][Y] = dq[ia][Y][Z];
    dq[ia][Z][Z] = 0.0 - dq[ia][X][X] - dq[ia][Y][Y];
  }

    /* load delsq phi */
  dsq[X][X] = delsq_phi_site_d[XX*nsites_cd+index];
  dsq[X][Y] = delsq_phi_site_d[XY*nsites_cd+index];
  dsq[X][Z] = delsq_phi_site_d[XZ*nsites_cd+index];
  dsq[Y][X] = dsq[X][Y];
  dsq[Y][Y] = delsq_phi_site_d[YY*nsites_cd+index];
  dsq[Y][Z] = delsq_phi_site_d[YZ*nsites_cd+index];
  dsq[Z][X] = dsq[X][Z];
  dsq[Z][Y] = dsq[Y][Z];
  dsq[Z][Z] = 0.0 - dsq[X][X] - dsq[Y][Y];


  //blue_phase_compute_h_gpu_d(h, dq, dsq, phi_site_full_d, index);


   if (site_map_status_d[index] != FLUID) {
     
     q[X][X] += dt_solid_cd*Gamma_cd*h_site_d[3*nsites_cd*X+nsites_cd*X+index];
     q[X][Y] += dt_solid_cd*Gamma_cd*h_site_d[3*nsites_cd*X+nsites_cd*Y+index];
     q[X][Z] += dt_solid_cd*Gamma_cd*h_site_d[3*nsites_cd*X+nsites_cd*Z+index];
     q[Y][Y] += dt_solid_cd*Gamma_cd*h_site_d[3*nsites_cd*Y+nsites_cd*Y+index];
     q[Y][Z] += dt_solid_cd*Gamma_cd*h_site_d[3*nsites_cd*Y+nsites_cd*Z+index];
     
   }
   else {
     

	  /* Velocity gradient tensor, symmetric and antisymmetric parts */

       w[X][X] = 0.5*(velocity_d[X*nsites_cd+indexp1] - velocity_d[X*nsites_cd+indexm1]);
       w[Y][X] = 0.5*(velocity_d[Y*nsites_cd+indexp1] - velocity_d[Y*nsites_cd+indexm1]);
       w[Z][X] = 0.5*(velocity_d[Z*nsites_cd+indexp1] - velocity_d[Z*nsites_cd+indexm1]);
       
       indexm1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd-1,kk+nhalo_cd,Nall_cd);
       indexp1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd+1,kk+nhalo_cd,Nall_cd);

       w[X][Y] = 0.5*(velocity_d[X*nsites_cd+indexp1] - velocity_d[X*nsites_cd+indexm1]);
       w[Y][Y] = 0.5*(velocity_d[Y*nsites_cd+indexp1] - velocity_d[Y*nsites_cd+indexm1]);
       w[Z][Y] = 0.5*(velocity_d[Z*nsites_cd+indexp1] - velocity_d[Z*nsites_cd+indexm1]);

       indexm1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd-1,Nall_cd);
       indexp1 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd+1,Nall_cd);

       w[X][Z] = 0.5*(velocity_d[X*nsites_cd+indexp1] - velocity_d[X*nsites_cd+indexm1]);
       w[Y][Z] = 0.5*(velocity_d[Y*nsites_cd+indexp1] - velocity_d[Y*nsites_cd+indexm1]);
       w[Z][Z] = 0.5*(velocity_d[Z*nsites_cd+indexp1] - velocity_d[Z*nsites_cd+indexm1]);
       
     //end  hydrodynamics_velocity_gradient_tensor(ic, jc, kc, w);
	  trace_qw = 0.0;

	  for (ia = 0; ia < 3; ia++) {
	    trace_qw += q[ia][ia]*w[ia][ia];
	    for (ib = 0; ib < 3; ib++) {
	      d[ia][ib]     = 0.5*(w[ia][ib] + w[ib][ia]);
	      omega[ia][ib] = 0.5*(w[ia][ib] - w[ib][ia]);
	    }
	  }
	  
	  for (ia = 0; ia < 3; ia++) {
	    for (ib = 0; ib < 3; ib++) {
	      s[ia][ib] = -2.0*xi_cd*(q[ia][ib] + r3_cd*d_cd[ia][ib])*trace_qw;
	      for (id = 0; id < 3; id++) {
		s[ia][ib] +=
		  (xi_cd*d[ia][id] + omega[ia][id])*(q[id][ib] + r3_cd*d_cd[id][ib])
		  + (q[ia][id] + r3_cd*d_cd[ia][id])*(xi_cd*d[id][ib] - omega[id][ib]);
	      }
	    }
	  }
	     
	  /* Here's the full hydrodynamic update. */

	  int indexj, indexk;
	  indexj = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd-1,kk+nhalo_cd,Nall_cd);      
	  indexk = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd-1,Nall_cd);      

	  q[X][X] += dt_cd*(s[X][X] + Gamma_cd*(h_site_d[3*nsites_cd*X+nsites_cd*X+index])
	  		 - fluxe_d[XX*nsites_cd+index] + fluxw_d[XX*nsites_cd+index]
	  		 - fluxy_d[XX*nsites_cd+index] + fluxy_d[XX*nsites_cd+indexj]
	  		 - fluxz_d[XX*nsites_cd+index] + fluxz_d[XX*nsites_cd+indexk]);

	  q[X][Y] += dt_cd*(s[X][Y] + Gamma_cd*(h_site_d[3*nsites_cd*X+nsites_cd*Y+index])
	  		 - fluxe_d[XY*nsites_cd+index] + fluxw_d[XY*nsites_cd+index]
	  		 - fluxy_d[XY*nsites_cd+index] + fluxy_d[XY*nsites_cd+indexj]
	  		 - fluxz_d[XY*nsites_cd+index] + fluxz_d[XY*nsites_cd+indexk]);

	  q[X][Z] += dt_cd*(s[X][Z] + Gamma_cd*(h_site_d[3*nsites_cd*X+nsites_cd*Z+index])
	  		 - fluxe_d[XZ*nsites_cd+index] + fluxw_d[XZ*nsites_cd+index]
	  		 - fluxy_d[XZ*nsites_cd+index] + fluxy_d[XZ*nsites_cd+indexj]
	  		 - fluxz_d[XZ*nsites_cd+index] + fluxz_d[XZ*nsites_cd+indexk]);

	  q[Y][Y] += dt_cd*(s[Y][Y] + Gamma_cd*(h_site_d[3*nsites_cd*Y+nsites_cd*Y+index])
	  		 - fluxe_d[YY*nsites_cd+index] + fluxw_d[YY*nsites_cd+index]
	  		 - fluxy_d[YY*nsites_cd+index] + fluxy_d[YY*nsites_cd+indexj]
	  		 - fluxz_d[YY*nsites_cd+index] + fluxz_d[YY*nsites_cd+indexk]);

	  q[Y][Z] += dt_cd*(s[Y][Z] + Gamma_cd*(h_site_d[3*nsites_cd*Y+nsites_cd*Z+index])
	  		 - fluxe_d[YZ*nsites_cd+index] + fluxw_d[YZ*nsites_cd+index]
	  		 - fluxy_d[YZ*nsites_cd+index] + fluxy_d[YZ*nsites_cd+indexj]
	  		 - fluxz_d[YZ*nsites_cd+index] + fluxz_d[YZ*nsites_cd+indexk]);
	

	   }
	 phi_site_d[nsites_cd*XX+index] = q[X][X];
	 phi_site_d[nsites_cd*XY+index] = q[X][Y];
	 phi_site_d[nsites_cd*XZ+index] = q[X][Z];
	 phi_site_d[nsites_cd*YY+index] = q[Y][Y];
	 phi_site_d[nsites_cd*YZ+index] = q[Y][Z];


    }


  return;
}


__global__ void advection_upwind_gpu_d(int * le_index_real_to_buffer_d,
						  double *phi_site_d,
						  double *phi_site_full_d,
						  double *grad_phi_site_d,
						  double *delsq_phi_site_d,
					   double *force_d,
					   double *velocity_d,
					   char *site_map_status_d,
					   double *fluxe_d,
					   double *fluxw_d,
					   double *fluxy_d,
					   double *fluxz_d
					    ) {

  int ia, icm1, icp1;
  int index, index1, index0;
  int ii, jj, kk, n;
  double u, phi0;
  //int threadIndex,ii, jj, kk;



 /* CUDA thread index */
  //threadIndex = blockIdx.x*blockDim.x+threadIdx.x;
  kk = blockIdx.x*blockDim.x+threadIdx.x;
  jj = blockIdx.y*blockDim.y+threadIdx.y;
  ii = blockIdx.z*blockDim.z+threadIdx.z;
 
 /* Avoid going beyond problem domain */
  // if (threadIndex < N_cd[X]*N_cd[Y]*N_cd[Z])

  if (ii < N_cd[X] && jj < (N_cd[Y]+1) && kk < (N_cd[Z]+1) )
    {


      /* calculate index from CUDA thread index */

      //get_coords_from_index_gpu_d(&ii,&jj,&kk,threadIndex,N_cd);
      index0 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd-1,kk+nhalo_cd-1,Nall_cd);      
      icm1=le_index_real_to_buffer_d[ii+nhalo_cd];
      icp1=le_index_real_to_buffer_d[Nall_cd[X]+ii+nhalo_cd];      


      
      for (n = 0; n < nop_cd; n++) {

	phi0 = phi_site_d[nsites_cd*n+index0];
	index1=get_linear_index_gpu_d(icm1,jj+nhalo_cd-1,kk+nhalo_cd-1,Nall_cd);
	u = 0.5*(velocity_d[X*nsites_cd+index0] + velocity_d[X*nsites_cd+index1]);
	
	if (u > 0.0) {
	  fluxw_d[n*nsites_cd+index0] = u*phi_site_d[nsites_cd*n+index1];
	}
	else {
	  fluxw_d[n*nsites_cd+index0] = u*phi0;
	}

	  /* east face (ic and icp1) */

	index1=get_linear_index_gpu_d(icp1,jj+nhalo_cd-1,kk+nhalo_cd-1,Nall_cd);
	  u = 0.5*(velocity_d[X*nsites_cd+index0] + velocity_d[X*nsites_cd+index1]);

	  if (u < 0.0) {
	    fluxe_d[n*nsites_cd+index0] = u*phi_site_d[nsites_cd*n+index1];
	  }
	  else {
	    fluxe_d[n*nsites_cd+index0] = u*phi0;
	  }


	  /* y direction */

	index1=get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd-1,Nall_cd);
	  u = 0.5*(velocity_d[Y*nsites_cd+index0] + velocity_d[Y*nsites_cd+index1]);


	  if (u < 0.0) {
	    fluxy_d[n*nsites_cd+index0] = u*phi_site_d[nsites_cd*n+index1];
	  }
	  else {
	    fluxy_d[n*nsites_cd+index0] = u*phi0;
	  }


	  /* z direction */


      index1=get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd-1,kk+nhalo_cd,Nall_cd);
      u = 0.5*(velocity_d[Z*nsites_cd+index0] + velocity_d[Z*nsites_cd+index1]);

      if (u < 0.0) {
	fluxz_d[n*nsites_cd+index0] = u*phi_site_d[nsites_cd*n+index1];
      }
      else {
	fluxz_d[n*nsites_cd+index0] = u*phi0;
      }



      }
    }

  return;
}


__global__ void advection_bcs_no_normal_flux_gpu_d(const int nop,
					   char *site_map_status_d,
					   double *fluxe_d,
					   double *fluxw_d,
					   double *fluxy_d,
					   double *fluxz_d
					    ) {

  int ia, icm1, icp1;
  int index, index1, index0;
  int ii, jj, kk, n;
  double u, phi0;
  //int threadIndex,ii, jj, kk;
  double mask, maske, maskw, masky, maskz;


 /* CUDA thread index */
  //threadIndex = blockIdx.x*blockDim.x+threadIdx.x;
  kk = blockIdx.x*blockDim.x+threadIdx.x;
  jj = blockIdx.y*blockDim.y+threadIdx.y;
  ii = blockIdx.z*blockDim.z+threadIdx.z;
 
 /* Avoid going beyond problem domain */
  // if (threadIndex < N_cd[X]*N_cd[Y]*N_cd[Z])

  if (ii < N_cd[X] && jj < (N_cd[Y]+1) && kk < (N_cd[Z]+1) )
    {


      /* calculate index from CUDA thread index */


      /* mask  = (site_map_get_status_index(index)  == FLUID); */
      /* maske = (site_map_get_status(ic+1, jc, kc) == FLUID); */
      /* maskw = (site_map_get_status(ic-1, jc, kc) == FLUID); */
      /* masky = (site_map_get_status(ic, jc+1, kc) == FLUID); */
      /* maskz = (site_map_get_status(ic, jc, kc+1) == FLUID); */
      
      
      index = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd-1,kk+nhalo_cd-1,Nall_cd);      
      mask  = (site_map_status_d[index]  == FLUID); 

      index0 = get_linear_index_gpu_d(ii+nhalo_cd+1,jj+nhalo_cd-1,kk+nhalo_cd-1,Nall_cd);      
      maske  = (site_map_status_d[index0]  == FLUID); 

      index0 = get_linear_index_gpu_d(ii+nhalo_cd-1,jj+nhalo_cd-1,kk+nhalo_cd-1,Nall_cd);      
      maskw  = (site_map_status_d[index0]  == FLUID); 

      index0 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd-1,Nall_cd);      
      masky  = (site_map_status_d[index0]  == FLUID); 

      index0 = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd-1,kk+nhalo_cd,Nall_cd);      
      maskz  = (site_map_status_d[index0]  == FLUID); 





	for (n = 0;  n < nop; n++) { 
	   fluxw_d[n*nsites_cd+index] *= mask*maskw; 
	   fluxe_d[n*nsites_cd+index] *= mask*maske;
	   fluxy_d[n*nsites_cd+index] *= mask*masky; 
	   fluxz_d[n*nsites_cd+index] *= mask*maskz; 
	 } 
      
      


    }
}

__global__ void blue_phase_compute_q2_eq_all_gpu_d(  double *phi_site_d,
						 double *phi_site_full_d,
						 double *grad_phi_site_d,
						 double *delsq_phi_site_d,
						 double *h_site_d,
						 double *q2_site_d,
						 double *eq_site_d
						 ){

  int ia, ib, ic, id;
  int index;
  double q[3][3];
  double h[3][3];
  double dq[3][3][3];
  double dsq[3][3];

  int ii, jj, kk;
 
 /* CUDA thread index */
  kk = blockIdx.x*blockDim.x+threadIdx.x;
  jj = blockIdx.y*blockDim.y+threadIdx.y;
  ii = blockIdx.z*blockDim.z+threadIdx.z;
 
  if (ii < Nall_cd[X] && jj < Nall_cd[Y] && kk < Nall_cd[Z] )
    {


      /* calculate index from CUDA thread index */
      //index = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);
      index = get_linear_index_gpu_d(ii,jj,kk,Nall_cd);
      
      /* load phi */
      
      q[X][X] = phi_site_d[nsites_cd*XX+index];
      q[X][Y] = phi_site_d[nsites_cd*XY+index];
      q[X][Z] = phi_site_d[nsites_cd*XZ+index];
      q[Y][X] = q[X][Y];
      q[Y][Y] = phi_site_d[nsites_cd*YY+index];
      q[Y][Z] = phi_site_d[nsites_cd*YZ+index];
      q[Z][X] = q[X][Z];
      q[Z][Y] = q[Y][Z];
      q[Z][Z] = 0.0 - q[X][X] - q[Y][Y];
      
      
      /* load grad phi */
      for (ia = 0; ia < 3; ia++) {
	dq[ia][X][X] = grad_phi_site_d[ia*nsites_cd*5 + XX*nsites_cd + index];
	dq[ia][X][Y] = grad_phi_site_d[ia*nsites_cd*5 + XY*nsites_cd + index];
	dq[ia][X][Z] = grad_phi_site_d[ia*nsites_cd*5 + XZ*nsites_cd + index];
	dq[ia][Y][X] = dq[ia][X][Y];
	dq[ia][Y][Y] = grad_phi_site_d[ia*nsites_cd*5 + YY*nsites_cd + index];
	dq[ia][Y][Z] = grad_phi_site_d[ia*nsites_cd*5 + YZ*nsites_cd + index];
	dq[ia][Z][X] = dq[ia][X][Z];
	dq[ia][Z][Y] = dq[ia][Y][Z];
	dq[ia][Z][Z] = 0.0 - dq[ia][X][X] - dq[ia][Y][Y];
      }
      
      /* load delsq phi */
      dsq[X][X] = delsq_phi_site_d[XX*nsites_cd+index];
      dsq[X][Y] = delsq_phi_site_d[XY*nsites_cd+index];
      dsq[X][Z] = delsq_phi_site_d[XZ*nsites_cd+index];
      dsq[Y][X] = dsq[X][Y];
      dsq[Y][Y] = delsq_phi_site_d[YY*nsites_cd+index];
      dsq[Y][Z] = delsq_phi_site_d[YZ*nsites_cd+index];
      dsq[Z][X] = dsq[X][Z];
      dsq[Z][Y] = dsq[Y][Z];
      dsq[Z][Z] = 0.0 - dsq[X][X] - dsq[Y][Y];
                  
  double q2;
  double e2;
  double eq;
  double sum, sum1;


  /* From the bulk terms in the free energy... */

  q2 = 0.0;
  eq = 0.0;
  
  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {

      q2 += phi_site_full_d[3*nsites_cd*ia+nsites_cd*ib+index]*phi_site_full_d[3*nsites_cd*ia+nsites_cd*ib+index];
      
      for (ic = 0; ic < 3; ic++) {
	eq += e_cd[ia][ib][ic]*dq[ia][ib][ic];
      }
      
    }
  }

  q2_site_d[index]=q2;
  eq_site_d[index]=eq;
    }
  return;
}


__global__ void blue_phase_compute_h_all_gpu_d(  double *phi_site_d,
						 double *phi_site_full_d,
						 double *grad_phi_site_d,
						 double *delsq_phi_site_d,
						 double *h_site_d,
						 double *q2_site_d,
						 double *eq_site_d
						 ){

  int ia, ib, ic, id;
  int index;
  double q[3][3];
  double h[3][3];
  double dq[3][3][3];
  double dsq[3][3];

  int ii, jj, kk;
 
 /* CUDA thread index */
  kk = blockIdx.x*blockDim.x+threadIdx.x;
  jj = blockIdx.y*blockDim.y+threadIdx.y;
  ii = blockIdx.z*blockDim.z+threadIdx.z;
 
  if (ii < Nall_cd[X] && jj < Nall_cd[Y] && kk < Nall_cd[Z] )
    {


      /* calculate index from CUDA thread index */
      //index = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);
      index = get_linear_index_gpu_d(ii,jj,kk,Nall_cd);
      
      /* load phi */
      
      q[X][X] = phi_site_d[nsites_cd*XX+index];
      q[X][Y] = phi_site_d[nsites_cd*XY+index];
      q[X][Z] = phi_site_d[nsites_cd*XZ+index];
      q[Y][X] = q[X][Y];
      q[Y][Y] = phi_site_d[nsites_cd*YY+index];
      q[Y][Z] = phi_site_d[nsites_cd*YZ+index];
      q[Z][X] = q[X][Z];
      q[Z][Y] = q[Y][Z];
      q[Z][Z] = 0.0 - q[X][X] - q[Y][Y];
      
      
      /* load grad phi */
      for (ia = 0; ia < 3; ia++) {
	dq[ia][X][X] = grad_phi_site_d[ia*nsites_cd*5 + XX*nsites_cd + index];
	dq[ia][X][Y] = grad_phi_site_d[ia*nsites_cd*5 + XY*nsites_cd + index];
	dq[ia][X][Z] = grad_phi_site_d[ia*nsites_cd*5 + XZ*nsites_cd + index];
	dq[ia][Y][X] = dq[ia][X][Y];
	dq[ia][Y][Y] = grad_phi_site_d[ia*nsites_cd*5 + YY*nsites_cd + index];
	dq[ia][Y][Z] = grad_phi_site_d[ia*nsites_cd*5 + YZ*nsites_cd + index];
	dq[ia][Z][X] = dq[ia][X][Z];
	dq[ia][Z][Y] = dq[ia][Y][Z];
	dq[ia][Z][Z] = 0.0 - dq[ia][X][X] - dq[ia][Y][Y];
      }
      
      /* load delsq phi */
      dsq[X][X] = delsq_phi_site_d[XX*nsites_cd+index];
      dsq[X][Y] = delsq_phi_site_d[XY*nsites_cd+index];
      dsq[X][Z] = delsq_phi_site_d[XZ*nsites_cd+index];
      dsq[Y][X] = dsq[X][Y];
      dsq[Y][Y] = delsq_phi_site_d[YY*nsites_cd+index];
      dsq[Y][Z] = delsq_phi_site_d[YZ*nsites_cd+index];
      dsq[Z][X] = dsq[X][Z];
      dsq[Z][Y] = dsq[Y][Z];
      dsq[Z][Z] = 0.0 - dsq[X][X] - dsq[Y][Y];
                  
  double e2;
  double sum, sum1;

  double q2=q2_site_d[index];
  double eq=eq_site_d[index];


  double cd1=-a0_cd*(1.0 - r3_cd*gamma_cd);
  double cd2=a0_cd*gamma_cd;
  double cd3=2.0*kappa1shift_cd*q0shift_cd;
  
  /* d_c Q_db written as d_c Q_bd etc */
  for (ia = 0; ia < 3; ia++) {
    for (ib = 0; ib < 3; ib++) {
      sum = 0.0;
      sum1 = 0.0;
      for (ic = 0; ic < 3; ic++) {

  	sum +=  phi_site_full_d[3*nsites_cd*ia+nsites_cd*ic+index]* phi_site_full_d[3*nsites_cd*ib+nsites_cd*ic+index];

	for (id = 0; id < 3; id++) {
	  sum1 +=
	    (e_cd[ia][ic][id]*dq[ic][ib][id] + e_cd[ib][ic][id]*dq[ic][ia][id]);
	}
      }

      h[ia][ib] = cd1* phi_site_full_d[3*nsites_cd*ia+nsites_cd*ib+index]
  	+ cd2*(sum - r3_cd*q2*d_cd[ia][ib]) - cd2*q2*phi_site_full_d[3*nsites_cd*ia+nsites_cd*ib+index];

      h[ia][ib] += kappa0shift_cd*dsq[ia][ib]
	- cd3*sum1 + 4.0*r3_cd*kappa1shift_cd*q0shift_cd*eq*d_cd[ia][ib]
	- 4.0*kappa1shift_cd*q0shift_cd*q0shift_cd*phi_site_full_d[3*nsites_cd*ia+nsites_cd*ib+index];

      h[ia][ib] +=  epsilon_cd*(electric_cd[ia]*electric_cd[ib] - r3_cd*d_cd[ia][ib]*e2_cd);
      h_site_d[3*nsites_cd*ia+nsites_cd*ib+index]=h[ia][ib];

    }
  }
  
    }

  return;
}

/* __global__ void blue_phase_compute_h_all_gpu_d(  double *phi_site_d, */
/* 						 double *phi_site_full_d, */
/* 						 double *grad_phi_site_d, */
/* 						 double *delsq_phi_site_d, */
/* 						 double *h_site_d, */
/* 						 double *q2_site_d, */
/* 						 double *eq_site_d */
/* 						 ){ */

/*   int ic, id; */
/*   int index; */

                        
/*   double e2; */
/*   double sum, sum1,htmp; */

 
/*   int threadIndex=blockIdx.x*blockDim.x+threadIdx.x;  */


/*   int i=threadIndex/(Nall_cd[Y]*Nall_cd[Z]*TPSITE); */
/*   int j=(threadIndex-i*Nall_cd[Y]*Nall_cd[Z]*TPSITE)/(Nall_cd[Y]*TPSITE); */
/*   int k=(threadIndex-i*Nall_cd[Y]*Nall_cd[Z]*TPSITE-j*Nall_cd[Y]*TPSITE)/TPSITE; */
/*   int iw=threadIndex-i*Nall_cd[Y]*Nall_cd[Z]*TPSITE-j*Nall_cd[Y]*TPSITE-k*TPSITE; */

/*   int ia=iw/3; */
/*   int ib=iw-ia*3; */

/*   int threadIndexStart=blockIdx.x*blockDim.x;  */


/*   int iStart=threadIndexStart/(Nall_cd[Y]*Nall_cd[Z]*TPSITE); */
/*   int jStart=(threadIndexStart-iStart*Nall_cd[Y]*Nall_cd[Z]*TPSITE)/(Nall_cd[Y]*TPSITE); */
/*   int kStart=(threadIndexStart-iStart*Nall_cd[Y]*Nall_cd[Z]*TPSITE-jStart*Nall_cd[Y]*TPSITE)/TPSITE; */



/*   index=get_linear_index_gpu_d(i,j,k,Nall_cd); */

/*   int indexStart=get_linear_index_gpu_d(iStart,jStart,kStart,Nall_cd); */

/* #define SPB (((DEFAULT_TPB+TPSITE-1)/TPSITE)+1) */

/*   __shared__ double q_sm[3][3][SPB]; */
/*   __shared__ double dsq_sm[3][3][SPB]; */
/*   __shared__ double dq_sm[3][3][3][SPB]; */
  
/*   __shared__ double q2_sm[SPB]; */
/*   __shared__ double eq_sm[SPB]; */
 
/*   if ((threadIdx.x < SPB) && (threadIdx.x < nsites_cd)){ */
/*     q_sm[X][X][threadIdx.x] = phi_site_d[nsites_cd*XX+(indexStart+threadIdx.x)]; */
/*       q_sm[X][Y][threadIdx.x] = phi_site_d[nsites_cd*XY+(indexStart+threadIdx.x)]; */
/*       q_sm[X][Z][threadIdx.x] = phi_site_d[nsites_cd*XZ+(indexStart+threadIdx.x)]; */
/*       q_sm[Y][X][threadIdx.x] = q_sm[X][Y][threadIdx.x]; */
/*       q_sm[Y][Y][threadIdx.x] = phi_site_d[nsites_cd*YY+(indexStart+threadIdx.x)]; */
/*       q_sm[Y][Z][threadIdx.x] = phi_site_d[nsites_cd*YZ+(indexStart+threadIdx.x)]; */
/*       q_sm[Z][X][threadIdx.x] = q_sm[X][Z][threadIdx.x]; */
/*       q_sm[Z][Y][threadIdx.x] = q_sm[Y][Z][threadIdx.x]; */
/*       q_sm[Z][Z][threadIdx.x] = 0.0 - q_sm[X][X][threadIdx.x] - q_sm[Y][Y][threadIdx.x]; */
/*       /\* load grad phi *\/ */
/*       for (ic = 0; ic < 3; ic++) { */
/*       	dq_sm[ic][X][X][threadIdx.x] = grad_phi_site_d[ic*nsites_cd*5 + XX*nsites_cd + indexStart+threadIdx.x]; */
/*       	dq_sm[ic][X][Y][threadIdx.x] = grad_phi_site_d[ic*nsites_cd*5 + XY*nsites_cd + indexStart+threadIdx.x]; */
/*       	dq_sm[ic][X][Z][threadIdx.x] = grad_phi_site_d[ic*nsites_cd*5 + XZ*nsites_cd + indexStart+threadIdx.x]; */
/*       	dq_sm[ic][Y][X][threadIdx.x] = dq_sm[ic][X][Y][threadIdx.x]; */
/*       	dq_sm[ic][Y][Y][threadIdx.x] = grad_phi_site_d[ic*nsites_cd*5 + YY*nsites_cd + indexStart+threadIdx.x]; */
/*       	dq_sm[ic][Y][Z][threadIdx.x] = grad_phi_site_d[ic*nsites_cd*5 + YZ*nsites_cd + indexStart+threadIdx.x]; */
/*       	dq_sm[ic][Z][X][threadIdx.x] = dq_sm[ic][X][Z][threadIdx.x]; */
/*       	dq_sm[ic][Z][Y][threadIdx.x] = dq_sm[ic][Y][Z][threadIdx.x]; */
/*       	dq_sm[ic][Z][Z][threadIdx.x] = 0.0 - dq_sm[ic][X][X][threadIdx.x] - dq_sm[ic][Y][Y][threadIdx.x]; */
/*       } */
/*       //load delsq phi */
/*     dsq_sm[X][X][threadIdx.x] = delsq_phi_site_d[nsites_cd*XX+(indexStart+threadIdx.x)]; */
/*       dsq_sm[X][Y][threadIdx.x] = delsq_phi_site_d[nsites_cd*XY+(indexStart+threadIdx.x)]; */
/*       dsq_sm[X][Z][threadIdx.x] = delsq_phi_site_d[nsites_cd*XZ+(indexStart+threadIdx.x)]; */
/*       dsq_sm[Y][X][threadIdx.x] = dsq_sm[X][Y][threadIdx.x]; */
/*       dsq_sm[Y][Y][threadIdx.x] = delsq_phi_site_d[nsites_cd*YY+(indexStart+threadIdx.x)]; */
/*       dsq_sm[Y][Z][threadIdx.x] = delsq_phi_site_d[nsites_cd*YZ+(indexStart+threadIdx.x)]; */
/*       dsq_sm[Z][X][threadIdx.x] = dsq_sm[X][Z][threadIdx.x]; */
/*       dsq_sm[Z][Y][threadIdx.x] = dsq_sm[Y][Z][threadIdx.x]; */
/*       dsq_sm[Z][Z][threadIdx.x] = 0.0 - dsq_sm[X][X][threadIdx.x] - dsq_sm[Y][Y][threadIdx.x]; */


/*     q2_sm[threadIdx.x] = q2_site_d[indexStart+threadIdx.x]; */
/*     eq_sm[threadIdx.x] = eq_site_d[indexStart+threadIdx.x]; */

/*   } */

/*       syncthreads(); */


/*   if (index < Nall_cd[X]*Nall_cd[Y]*Nall_cd[Y] && ia<3 && ib <3) */
/*     { */
            
/*       int index_sm=index-indexStart; */
      

/*   /\* d_c Q_db written as d_c Q_bd etc *\/ */
/*       sum = 0.0; */
/*       sum1 = 0.0; */
/*       for (ic = 0; ic < 3; ic++) { */

/*   	sum +=  q_sm[ia][ic][index_sm]*q_sm[ib][ic][index_sm]; */

/* 	for (id = 0; id < 3; id++) { */
/* 	  sum1 += */
/* 	    (e_cd[ia][ic][id]*dq_sm[ic][ib][id][index_sm] + e_cd[ib][ic][id]*dq_sm[ic][ia][id][index_sm]); */
/* 	} */
/*       } */

/*       htmp = cd1*q_sm[ia][ib][index_sm] */
/*   	+ cd2*(sum - r3_cd*q2_sm[index_sm]*d_cd[ia][ib])  */
/* 	- cd2*q2_sm[index_sm]*q_sm[ia][ib][index_sm]; */

/*       htmp += kappa0shift_cd*dsq_sm[ia][ib][index_sm] */
/* 	- cd3*sum1 + 4.0*cd4*eq_sm[index_sm]*d_cd[ia][ib] */
/* 	- cd5*q_sm[ia][ib][index_sm]; */

/*       htmp +=  epsilon_cd*(electric_cd[ia]*electric_cd[ib]  */
/* 				- cd6*d_cd[ia][ib]); */

/*       h_site_d[3*nsites_cd*ia+nsites_cd*ib+index]=htmp; */

/*       //h_site_d[index*3*3+3*ia+ib]=htmp; */

/*     } */




   

/*   return; */
/* } */

__global__ void blue_phase_compute_stress1_all_gpu_d(  double *phi_site_d,
						 double *phi_site_full_d,
						 double *grad_phi_site_d,
						 double *grad_phi_site_full_d,
						 double *delsq_phi_site_d,
						 double *h_site_d,
						 double *stress_site_d){

  int ia, ib, ic;
  int index;
  double q[3][3];
  double sth[3][3];
  double dq[3][3][3];
  double dsq[3][3];

  int ii, jj, kk;
 
 /* CUDA thread index */
  kk = blockIdx.x*blockDim.x+threadIdx.x;
  jj = blockIdx.y*blockDim.y+threadIdx.y;
  ii = blockIdx.z*blockDim.z+threadIdx.z;
 
  if (ii < Nall_cd[X] && jj < Nall_cd[Y] && kk < Nall_cd[Z] )
    {


      /* calculate index from CUDA thread index */
      //index = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);
      index = get_linear_index_gpu_d(ii,jj,kk,Nall_cd);
      
      /* load phi */
      
      q[X][X] = phi_site_d[nsites_cd*XX+index];
      q[X][Y] = phi_site_d[nsites_cd*XY+index];
      q[X][Z] = phi_site_d[nsites_cd*XZ+index];
      q[Y][X] = q[X][Y];
      q[Y][Y] = phi_site_d[nsites_cd*YY+index];
      q[Y][Z] = phi_site_d[nsites_cd*YZ+index];
      q[Z][X] = q[X][Z];
      q[Z][Y] = q[Y][Z];
      q[Z][Z] = 0.0 - q[X][X] - q[Y][Y];
      
      
      /* load grad phi */
            for (ia = 0; ia < 3; ia++) {
      //for (ib = 0; ib <3; ib++){
      //  for (ic = 0; ic <3; ic++){
      //    dq[ia][ib][ic] = grad_phi_site_full_d[ia*nsites_cd*9 + ib*nsites_cd*3+ ic*nsites_cd + index];
      //  }
      //}

	dq[ia][X][X] = grad_phi_site_d[ia*nsites_cd*5 + XX*nsites_cd + index];
	dq[ia][X][Y] = grad_phi_site_d[ia*nsites_cd*5 + XY*nsites_cd + index];
	dq[ia][X][Z] = grad_phi_site_d[ia*nsites_cd*5 + XZ*nsites_cd + index];
	dq[ia][Y][X] = dq[ia][X][Y];
	dq[ia][Y][Y] = grad_phi_site_d[ia*nsites_cd*5 + YY*nsites_cd + index];
	dq[ia][Y][Z] = grad_phi_site_d[ia*nsites_cd*5 + YZ*nsites_cd + index];
	dq[ia][Z][X] = dq[ia][X][Z];
	dq[ia][Z][Y] = dq[ia][Y][Z];
	dq[ia][Z][Z] = 0.0 - dq[ia][X][X] - dq[ia][Y][Y];
           }
      
      /* load delsq phi */
      dsq[X][X] = delsq_phi_site_d[XX*nsites_cd+index];
      dsq[X][Y] = delsq_phi_site_d[XY*nsites_cd+index];
      dsq[X][Z] = delsq_phi_site_d[XZ*nsites_cd+index];
      dsq[Y][X] = dsq[X][Y];
      dsq[Y][Y] = delsq_phi_site_d[YY*nsites_cd+index];
      dsq[Y][Z] = delsq_phi_site_d[YZ*nsites_cd+index];
      dsq[Z][X] = dsq[X][Z];
      dsq[Z][Y] = dsq[Y][Z];
      dsq[Z][Z] = 0.0 - dsq[X][X] - dsq[Y][Y];
                  
      
      blue_phase_compute_stress1_gpu_d(q, dq, sth, grad_phi_site_full_d,h_site_d, index);

      for (ia = 0; ia < 3; ia++) {
	for (ib = 0; ib < 3; ib++) {
	  stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index]=sth[ia][ib];
	}
      }
    }

  return;
}
 __global__ void blue_phase_compute_stress2_all_gpu_d(  double *phi_site_d,
						 double *phi_site_full_d,
						 double *grad_phi_site_d,
						 double *grad_phi_site_full_d,
						 float *grad_phi_float_d,
						 double *delsq_phi_site_d,
						 double *h_site_d,
						 double *stress_site_d){

   //int ia, ib, ic;
   int ic;
  int index;
  double q[3][3];
  double sth[3][3];
  double dq[3][3][3];
  double dsq[3][3];

  int ii, jj, kk;
 
 /* CUDA thread index */
  kk = blockIdx.x*blockDim.x+threadIdx.x;
  jj = blockIdx.y*blockDim.y+threadIdx.y;
  ii = blockIdx.z*blockDim.z+threadIdx.z;

  
  int threadIndex = blockIdx.x*blockDim.x+threadIdx.x;
  int i=threadIndex/(Nall_cd[Y]*Nall_cd[Z]*9);
  int j=(threadIndex-i*Nall_cd[Y]*Nall_cd[Z]*9)/(Nall_cd[Y]*9);
  int k=(threadIndex-i*Nall_cd[Y]*Nall_cd[Z]*9-j*Nall_cd[Y]*9)/9;
  int iw=threadIndex-i*Nall_cd[Y]*Nall_cd[Z]*9-j*Nall_cd[Y]*9-k*9;
  int ib=iw/3;
  int ia=iw-ib*3;

 
  if (i < Nall_cd[X] && j < Nall_cd[Y] && k < Nall_cd[Z] && ia<3 && ib <3)
    {


      /* calculate index from CUDA thread index */
      //index = get_linear_index_gpu_d(ii+nhalo_cd,jj+nhalo_cd,kk+nhalo_cd,Nall_cd);
      index = get_linear_index_gpu_d(i,j,k,Nall_cd);
      
      /* load phi */
      
      q[X][X] = phi_site_d[nsites_cd*XX+index];
      q[X][Y] = phi_site_d[nsites_cd*XY+index];
      q[X][Z] = phi_site_d[nsites_cd*XZ+index];
      q[Y][X] = q[X][Y];
      q[Y][Y] = phi_site_d[nsites_cd*YY+index];
      q[Y][Z] = phi_site_d[nsites_cd*YZ+index];
      q[Z][X] = q[X][Z];
      q[Z][Y] = q[Y][Z];
      q[Z][Z] = 0.0 - q[X][X] - q[Y][Y];
      
      
      /* load grad phi */
      //      for (ia = 0; ia < 3; ia++) {
      //for (ib = 0; ib <3; ib++){
      //  for (ic = 0; ic <3; ic++){
      //    dq[ia][ib][ic] = grad_phi_site_full_d[ia*nsites_cd*9 + ib*nsites_cd*3+ ic*nsites_cd + index];
      //  }
      //}

	/* dq[ia][X][X] = grad_phi_site_d[ia*nsites_cd*5 + XX*nsites_cd + index]; */
	/* dq[ia][X][Y] = grad_phi_site_d[ia*nsites_cd*5 + XY*nsites_cd + index]; */
	/* dq[ia][X][Z] = grad_phi_site_d[ia*nsites_cd*5 + XZ*nsites_cd + index]; */
	/* dq[ia][Y][X] = dq[ia][X][Y]; */
	/* dq[ia][Y][Y] = grad_phi_site_d[ia*nsites_cd*5 + YY*nsites_cd + index]; */
	/* dq[ia][Y][Z] = grad_phi_site_d[ia*nsites_cd*5 + YZ*nsites_cd + index]; */
	/* dq[ia][Z][X] = dq[ia][X][Z]; */
	/* dq[ia][Z][Y] = dq[ia][Y][Z]; */
	/* dq[ia][Z][Z] = 0.0 - dq[ia][X][X] - dq[ia][Y][Y]; */
      //      }
      

      //for (ia = 0; ia < 3; ia++) {
      //for (ib = 0; ib < 3; ib++) {
	  sth[ia][ib]=stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index];
	  //}
	  //}


  int ic, id, ie;

  double tmpdbl,tmpdbl2;

  /* Dot product term d_a Q_cd . dF/dQ_cd,b */

  //for (ia = 0; ia < 3; ia++) {
  //for (ib = 0; ib < 3; ib++) {
      tmpdbl=0.;
      for (ic = 0; ic < 3; ic++) {
	for (id = 0; id < 3; id++) {
	  /* tmpdbl += */
	  /*   - kappa0shift_cd*dq[ia][ib][ic]*dq[id][ic][id] */
	  /*   - kappa1shift_cd*dq[ia][ic][id]*dq[ib][ic][id] */
	  /*   + kappa1shift_cd*dq[ia][ic][id]*dq[ic][ib][id]; */
	  
	  /* tmpdbl2= -2.0*kappa1shift_cd*q0shift_cd*dq[ia][ic][id]; */
	  /* for (ie = 0; ie < 3; ie++) { */
	  /*   tmpdbl += */
	  /*    tmpdbl2*e_cd[ib][ic][ie]*q[id][ie]; */
	  /* } */

	  /* tmpdbl += */
	  /*   - kappa0shift_cd*grad_phi_site_full_d[ia*nsites_cd*9 + ib*nsites_cd*3+ ic*nsites_cd + index]* */
	  /*   grad_phi_site_full_d[id*nsites_cd*9 + ic*nsites_cd*3+ id*nsites_cd + index] */
	  /*   - kappa1shift_cd*grad_phi_site_full_d[ia*nsites_cd*9 + ic*nsites_cd*3+ id*nsites_cd + index]* */
	  /*   grad_phi_site_full_d[ib*nsites_cd*9 + ic*nsites_cd*3+ id*nsites_cd + index] */
	  /*   + kappa1shift_cd*grad_phi_site_full_d[ia*nsites_cd*9 + ic*nsites_cd*3+ id*nsites_cd + index]* */
	  /*   grad_phi_site_full_d[ic*nsites_cd*9 + ib*nsites_cd*3+ id*nsites_cd + index]; */
	  
	  /* tmpdbl2= -2.0*kappa1shift_cd*q0shift_cd */
	  /*   *grad_phi_site_full_d[ia*nsites_cd*9 + ic*nsites_cd*3+ id*nsites_cd + index]; */
	  /* for (ie = 0; ie < 3; ie++) { */
	  /*   tmpdbl += */
	  /*    tmpdbl2*e_cd[ib][ic][ie]*q[id][ie]; */
	  /* } */

	  /* tmpdbl += */
	  /*   - kappa0shift_cd*grad_phi_site_full_d[index*27+ia*9 + ib*3+ ic]* */
	  /*   grad_phi_site_full_d[index*27+id*9 + ic*3+ id] */
	  /*   - kappa1shift_cd*grad_phi_site_full_d[index*27+ia*9 + ic*3+ id]* */
	  /*   grad_phi_site_full_d[index*27+ib*9 + ic*3+ id] */
	  /*   + kappa1shift_cd*grad_phi_site_full_d[index*27+ia*9 + ic*3+ id]* */
	  /*   grad_phi_site_full_d[index*27+ic*9 + ib*3+ id]; */
	  
	  /* tmpdbl2= -2.0*kappa1shift_cd*q0shift_cd */
	  /*   *grad_phi_site_full_d[index*27+ia*9 + ic*3+ id]; */
	  /* for (ie = 0; ie < 3; ie++) { */
	  /*   tmpdbl += */
	  /*    tmpdbl2*e_cd[ib][ic][ie]*q[id][ie]; */
	  /* } */



	  /* tmpdbl += */
	  /*   - kappa0shift_cd*grad_phi_site_full_d[index*27+ic*9 + ib*3+ ia]* */
	  /*   grad_phi_site_full_d[index*27+id*9 + ic*3+ id] */
	  /*   - kappa1shift_cd*grad_phi_site_full_d[index*27+id*9 + ic*3+ ia]* */
	  /*   grad_phi_site_full_d[index*27+id*9 + ic*3+ ib] */
	  /*   + kappa1shift_cd*grad_phi_site_full_d[index*27+id*9 + ic*3+ ia]* */
	  /*   grad_phi_site_full_d[index*27+id*9 + ib*3+ ic]; */
	  
	  /* tmpdbl2= -2.0*kappa1shift_cd*q0shift_cd */
	  /*   *grad_phi_site_full_d[index*27+id*9 + ic*3+ ia]; */
	  /* for (ie = 0; ie < 3; ie++) { */
	  /* tmpdbl += */
	  /*  tmpdbl2*e_cd[ib][ic][ie]*q[id][ie]; */
	  /* } */


	  //doarray[index]=tex1Dfetch(texreference,index);

	  /* tmpdbl += */
	  /*   - kappa0shift_cd*grad_phi_float_d[index*27+ic*9 + ib*3+ ia]* */
	  /*   grad_phi_float_d[index*27+id*9 + ic*3+ id] */
	  /*   - kappa1shift_cd*grad_phi_float_d[index*27+id*9 + ic*3+ ia]* */
	  /*   grad_phi_float_d[index*27+id*9 + ic*3+ ib] */
	  /*   + kappa1shift_cd*grad_phi_float_d[index*27+id*9 + ic*3+ ia]* */
	  /*   grad_phi_float_d[index*27+id*9 + ib*3+ ic]; */
	  
	  /* tmpdbl2= -2.0*kappa1shift_cd*q0shift_cd */
	  /*   *grad_phi_float_d[index*27+id*9 + ic*3+ ia]; */
	  /* for (ie = 0; ie < 3; ie++) { */
	  /* tmpdbl += */
	  /*  tmpdbl2*e_cd[ib][ic][ie]*q[id][ie]; */
	  /* } */


	  tmpdbl +=
	    - kappa0shift_cd*tex1Dfetch(texreference,index*27+ic*9 + ib*3+ ia)*
	    tex1Dfetch(texreference,index*27+id*9 + ic*3+ id)
	    - kappa1shift_cd*tex1Dfetch(texreference,index*27+id*9 + ic*3+ ia)*
	    tex1Dfetch(texreference,index*27+id*9 + ic*3+ ib)
	    + kappa1shift_cd*tex1Dfetch(texreference,index*27+id*9 + ic*3+ ia)*
	    tex1Dfetch(texreference,index*27+id*9 + ib*3+ ic);
	  
	  tmpdbl2= -2.0*kappa1shift_cd*q0shift_cd
	    *tex1Dfetch(texreference,index*27+id*9 + ic*3+ ia);
	  for (ie = 0; ie < 3; ie++) {
	  tmpdbl +=
	   tmpdbl2*e_cd[ib][ic][ie]*q[id][ie];
	  }




	}
      }
      sth[ia][ib]+=tmpdbl;

      sth[ia][ib]=-sth[ia][ib];

      //}
      //}

      //for (ia = 0; ia < 3; ia++) {
      //for (ib = 0; ib < 3; ib++) {
      stress_site_d[3*nsites_cd*ia+nsites_cd*ib+index]=sth[ia][ib];
	  //	}
  //}
    }

  return;
}

void put_phi_force_constants_on_gpu(){


  int N[3],nhalo,Nall[3];
  
  nhalo = coords_nhalo();
  coords_nlocal(N); 


  Nall[X]=N[X]+2*nhalo;
  Nall[Y]=N[Y]+2*nhalo;
  Nall[Z]=N[Z]+2*nhalo;
  
  int nsites=Nall[X]*Nall[Y]*Nall[Z];
  int nop = phi_nop();


  double redshift_ = blue_phase_redshift(); 
  double rredshift_ = blue_phase_rredshift(); 
  double q0_=blue_phase_q0();
  q0_ = q0_*rredshift_;

  double a0_=blue_phase_a0();
  double kappa0_=blue_phase_kappa0();
  double kappa1_=blue_phase_kappa1();
  kappa0_ = kappa0_*redshift_*redshift_;
  kappa1_ = kappa1_*redshift_*redshift_;

  double xi_=blue_phase_get_xi();
  double zeta_=blue_phase_get_zeta();
  double gamma_=blue_phase_gamma();
  double epsilon_=blue_phase_get_dielectric_anisotropy();
  double Gamma_=blue_phase_be_get_rotational_diffusion();

  double electric_[3];
  blue_phase_get_electric_field(electric_);  
  int ia;
  double e2=0;
  for (ia = 0; ia < 3; ia++) 
    e2 += electric_[ia]*electric_[ia];   /* Electric field term */

  /* For first anchoring method (only) have evolution at solid sites. */
  const double dt = 1.0;
  double dt_solid;
  dt_solid = 0;
  if (colloids_q_anchoring_method() == ANCHORING_METHOD_ONE) dt_solid = dt;


  double cd1_=-a0_*(1.0 - r3_*gamma_);
  double cd2_=a0_*gamma_;
  double cd3_=2.0*kappa1_*q0_;
  double cd4_=r3_*kappa1_*q0_;
  double cd5_=4.0*kappa1_*q0_*q0_;
  double cd6_=r3_*e2;

  /* copy to constant memory on device */
  cudaMemcpyToSymbol(N_cd, N, 3*sizeof(int), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(Nall_cd, Nall, 3*sizeof(int), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(nhalo_cd, &nhalo, sizeof(int), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(nsites_cd, &nsites, sizeof(int), 0, cudaMemcpyHostToDevice); 
  
  cudaMemcpyToSymbol(electric_cd, electric_, 3*sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(redshift_cd, &redshift_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(rredshift_cd, &rredshift_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(q0shift_cd, &q0_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(a0_cd, &a0_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(kappa0shift_cd, &kappa0_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(kappa1shift_cd, &kappa1_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(xi_cd, &xi_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(zeta_cd, &zeta_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(gamma_cd, &gamma_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(epsilon_cd, &epsilon_, sizeof(double), 0, cudaMemcpyHostToDevice);
  cudaMemcpyToSymbol(r3_cd, &r3_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(e2_cd, &e2, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(d_cd, d_, 3*3*sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(e_cd, e_, 3*3*3*sizeof(double), 0, cudaMemcpyHostToDevice);
  		
  cudaMemcpyToSymbol(cd1, &cd1_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(cd2, &cd2_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(cd3, &cd3_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(cd4, &cd4_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(cd5, &cd5_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(cd6, &cd6_, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(nop_cd, &nop, sizeof(int), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(dt_solid_cd, &dt_solid, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(dt_cd, &dt, sizeof(double), 0, cudaMemcpyHostToDevice); 
  cudaMemcpyToSymbol(Gamma_cd, &Gamma_, sizeof(double), 0, cudaMemcpyHostToDevice); 

 
  checkCUDAError("phi_force cudaMemcpyToSymbol");


}


/* get linear index from 3d coordinates */
 __device__ static int get_linear_index_gpu_d(int ii,int jj,int kk,int N_d[3])
{
  
  int yfac = N_d[Z];
  int xfac = N_d[Y]*yfac;

  return ii*xfac + jj*yfac + kk;

}

/* get 3d coordinates from the index on the accelerator */
__device__ static void get_coords_from_index_gpu_d(int *ii,int *jj,int *kk,int index,int N_d[3])

{
  
  int yfac = N_d[Z];
  int xfac = N_d[Y]*yfac;
  
  *ii = index/xfac;
  *jj = ((index-xfac*(*ii))/yfac);
  *kk = (index-(*ii)*xfac-(*jj)*yfac);

  return;

}
