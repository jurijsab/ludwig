/*****************************************************************************
 *
 * phi_datamgmt_gpu.cu
 *  
 * Phi data management for GPU adaptation of Ludwig
 * Alan Gray 
 *
 *****************************************************************************/

#include <assert.h>
#include <stdio.h>
#include <math.h>

#include "pe.h"
#include "utilities_gpu.h"
#include "phi_datamgmt_gpu.h"
#include "util.h"
#include "model.h"
#include "timer.h"


/* edge and halo buffers on accelerator */

double * edgeXLOW_d;
double * edgeXHIGH_d;
double * edgeYLOW_d;
double * edgeYHIGH_d;
double * edgeZLOW_d;
double * edgeZHIGH_d;
double * haloXLOW_d;
double * haloXHIGH_d;
double * haloYLOW_d;
double * haloYHIGH_d;
double * haloZLOW_d;
double * haloZHIGH_d;


/* host memory address pointers for temporary staging of data */
double * phi_site_temp;
double * grad_phi_site_temp;
double * delsq_phi_site_temp;


/* edge and  halo buffers on host */

double * edgeXLOW;
double * edgeXHIGH;
double * edgeYLOW;
double * edgeYHIGH;
double * edgeZLOW;
double * edgeZHIGH;
double * haloXLOW;
double * haloXHIGH;
double * haloYLOW;
double * haloYHIGH;
double * haloZLOW;
double * haloZHIGH;


/* pointers to data resident on accelerator */

extern int * N_d;
double * phi_site_d;
double * phi_site_full_d;
double * grad_phi_site_full_d;
float * grad_phi_float_d;
double * h_site_d;
double * stress_site_d;
double * grad_phi_site_d;
double * delsq_phi_site_d;
double * le_index_real_to_buffer_d;

int * le_index_real_to_buffer_temp;

//extern int Nall_cd[3];
//extern int *nsites_cd;


/* data size variables */
static int nhalo;
static int nsites;
static int nop;
static  int N[3];
static  int Nall[3];
static int nlexbuf;

/* handles for CUDA streams (for ovelapping)*/
static cudaStream_t streamX,streamY, streamZ;


void init_phi_gpu(){

  int ic;

  calculate_phi_data_sizes();
  allocate_phi_memory_on_gpu();
  

  /* get le_index_to_real_buffer values */
/*le_index_real_to_buffer holds -1 then +1 translation values */
  for (ic=0; ic<Nall[X]; ic++)
    {

      le_index_real_to_buffer_temp[ic]=
	le_index_real_to_buffer(ic,-1);

      le_index_real_to_buffer_temp[Nall[X]+ic]=
le_index_real_to_buffer(ic,+1);

    }

  cudaMemcpy(le_index_real_to_buffer_d, le_index_real_to_buffer_temp, 
	     nlexbuf*sizeof(int),cudaMemcpyHostToDevice);

  /* create CUDA streams (for ovelapping)*/
  cudaStreamCreate(&streamX);
  cudaStreamCreate(&streamY);
  cudaStreamCreate(&streamZ);


}


void finalise_phi_gpu()
{
  free_phi_memory_on_gpu();

}

/* calculate sizes of data - needed for memory copies to accelerator */
static void calculate_phi_data_sizes()
{
  coords_nlocal(N);  
  nhalo = coords_nhalo();  

  Nall[X]=N[X]+2*nhalo;
  Nall[Y]=N[Y]+2*nhalo;
  Nall[Z]=N[Z]+2*nhalo;

  nsites = Nall[X]*Nall[Y]*Nall[Z];

  nop = phi_nop();



  //nlexbuf = le_get_nxbuffer();
/*for holding le buffer index translation */
/* -1 then +1 values */
  nlexbuf = 2*Nall[X]; 



}





/* Allocate memory on accelerator */
static void allocate_phi_memory_on_gpu()
{

  /* temp arrays for staging data on  host */
  phi_site_temp = (double *) malloc(nsites*nop*sizeof(double));
  grad_phi_site_temp = (double *) malloc(nsites*nop*3*sizeof(double));
  delsq_phi_site_temp = (double *) malloc(nsites*nop*sizeof(double));
  le_index_real_to_buffer_temp = (int *) malloc(nlexbuf*sizeof(int));
  
  cudaMalloc((void **) &phi_site_d, nsites*nop*sizeof(double));
  cudaMalloc((void **) &phi_site_full_d, nsites*9*sizeof(double));
  cudaMalloc((void **) &grad_phi_site_full_d, nsites*27*sizeof(double));
  cudaMalloc((void **) &grad_phi_float_d, nsites*27*sizeof(float)); 
  cudaMalloc((void **) &h_site_d, nsites*9*sizeof(double));
  cudaMalloc((void **) &stress_site_d, nsites*9*sizeof(double));
  cudaMalloc((void **) &delsq_phi_site_d, nsites*nop*sizeof(double));
  cudaMalloc((void **) &grad_phi_site_d, nsites*3*nop*sizeof(double));
  cudaMalloc((void **) &le_index_real_to_buffer_d, nlexbuf*sizeof(int));


     checkCUDAError("allocate_phi_memory_on_gpu");

}


/* Free memory on accelerator */
static void free_phi_memory_on_gpu()
{

  /* free temp memory on host */
  free(phi_site_temp);
  free(grad_phi_site_temp);
  free(delsq_phi_site_temp);
  free(le_index_real_to_buffer_temp);


  cudaFree(phi_site_d);
  cudaFree(phi_site_full_d);
  cudaFree(grad_phi_site_full_d);
  cudaFree(grad_phi_float_d);
  cudaFree(h_site_d);
  cudaFree(stress_site_d);
  cudaFree(delsq_phi_site_d);
  cudaFree(grad_phi_site_d);
  cudaFree(le_index_real_to_buffer_d);

}




/* copy phi from host to accelerator */
void put_phi_on_gpu()
{

  int index, ic, jc, kc, iop;
	      

  /* get temp host copies of arrays */
  for (ic=0; ic<Nall[X]; ic++)
    {
      for (jc=0; jc<Nall[Y]; jc++)
	{
	  for (kc=0; kc<Nall[Z]; kc++)
	    {

	      index = get_linear_index(ic, jc, kc, Nall); 

	      for (iop=0; iop<nop; iop++)
		{

		  phi_site_temp[iop*nsites+index]=phi_op_get_phi_site(index,iop);
		}
	    }
	}
    }


  /* copy data from CPU to accelerator */
  cudaMemcpy(phi_site_d, phi_site_temp, nsites*nop*sizeof(double), \
	     cudaMemcpyHostToDevice);

  checkCUDAError("put_phi_on_gpu");

}

/* copy grad phi from host to accelerator */
void put_grad_phi_on_gpu()
{

  int index, i, ic, jc, kc, iop;
  double grad_phi[3];
	      

  /* get temp host copies of arrays */
  for (ic=0; ic<Nall[X]; ic++)
    {
      for (jc=0; jc<Nall[Y]; jc++)
	{
	  for (kc=0; kc<Nall[Z]; kc++)
	    {

	      index = get_linear_index(ic, jc, kc, Nall); 

	      for (iop=0; iop<nop; iop++)
		{
		  phi_gradients_grad_n(index, iop, grad_phi);

		  for (i=0;i<3;i++)
		    {
		      grad_phi_site_temp[i*nsites*nop+iop*nsites+index]=grad_phi[i];
		    }
		}
	    }
	}
    }


  /* copy data from CPU to accelerator */
  cudaMemcpy(grad_phi_site_d, grad_phi_site_temp, nsites*nop*3*sizeof(double), \
	     cudaMemcpyHostToDevice);


  checkCUDAError("put_grad_phi_on_gpu");

}

/* copy grad phi from accelerator to host*/
void get_grad_phi_from_gpu()
{

  int index, i, ic, jc, kc, iop;
  double grad_phi[3];
	      

  /* copy data from accelerator to CPU */
  cudaMemcpy(grad_phi_site_temp, grad_phi_site_d, nsites*nop*3*sizeof(double), \
	     cudaMemcpyDeviceToHost);


  /* set grad phi */
  for (ic=0; ic<Nall[X]; ic++)
    {
      for (jc=0; jc<Nall[Y]; jc++)
	{
	  for (kc=0; kc<Nall[Z]; kc++)
	    {

	      index = get_linear_index(ic, jc, kc, Nall); 

	      for (iop=0; iop<nop; iop++)
		{

		  for (i=0;i<3;i++)
		    {
		      grad_phi[i]=grad_phi_site_temp[i*nsites*nop+iop*nsites+index];
		    }

		  phi_gradients_set_grad_n(index, iop, grad_phi);

		}
	    }
	}
    }



  checkCUDAError("get_grad_phi_from_gpu");

}

/* copy phi from host to accelerator */
void put_delsq_phi_on_gpu()
{

  int index, ic, jc, kc, iop;

  /* get temp host copies of arrays */
  for (ic=0; ic<Nall[X]; ic++)
    {
      for (jc=0; jc<Nall[Y]; jc++)
	{
	  for (kc=0; kc<Nall[Z]; kc++)
	    {

	      index = get_linear_index(ic, jc, kc, Nall); 

	      for (iop=0; iop<nop; iop++){

		delsq_phi_site_temp[iop*nsites+index] = phi_gradients_delsq_n(index,iop);
	      	      
	      }
	    }
	}
    }


  /* copy data from CPU to accelerator */
  cudaMemcpy(delsq_phi_site_d, delsq_phi_site_temp, nsites*nop*sizeof(double), \
	     cudaMemcpyHostToDevice);

  checkCUDAError("put_delsq_phi_on_gpu");

}

/* copy delsq phi from accelerator to host*/
void get_delsq_phi_from_gpu()
{

  int index, ic, jc, kc, iop;



  /* copy data from CPU to accelerator */
  cudaMemcpy(delsq_phi_site_temp, delsq_phi_site_d, nsites*nop*sizeof(double), \
	     cudaMemcpyDeviceToHost);

  /* get temp host copies of arrays */
  for (ic=0; ic<Nall[X]; ic++)
    {
      for (jc=0; jc<Nall[Y]; jc++)
	{
	  for (kc=0; kc<Nall[Z]; kc++)
	    {

	      index = get_linear_index(ic, jc, kc, Nall); 

	      for (iop=0; iop<nop; iop++){

		phi_gradients_set_delsq_n(index,iop,delsq_phi_site_temp[iop*nsites+index]);
	      	      
	      }
	    }
	}
    }


  checkCUDAError("get_delsq_phi_from_gpu");

}



/* copy phi from accelerator to host */
void get_phi_from_gpu()
{

  int index, ic, jc, kc, iop;
	      

  /* copy data from accelerator to host */
  cudaMemcpy(phi_site_temp, phi_site_d, nsites*nop*sizeof(double),	\
         cudaMemcpyDeviceToHost);

  /* set phi */
  for (ic=0; ic<Nall[X]; ic++)
    {
      for (jc=0; jc<Nall[Y]; jc++)
	{
	  for (kc=0; kc<Nall[Z]; kc++)
	    {

	      index = get_linear_index(ic, jc, kc, Nall); 

	      for (iop=0; iop<nop; iop++)
		{

		
		  phi_op_set_phi_site(index,iop,phi_site_temp[iop*nsites+index]);

		}
	    }
	}
    }

  //checkCUDAError("get_phi_site_from_gpu");

}

__global__ void expand_phi_on_gpu_d(double* phi_site_d,double* phi_site_full_d)
{
  
  int index = blockIdx.x*blockDim.x+threadIdx.x;
  
  /* Avoid going beyond problem domain */
  if (index < Nall_cd[X]*Nall_cd[Y]*Nall_cd[Z])
    {
      
      
      /* calculate index from CUDA thread index */
      
      phi_site_full_d[3*X*nsites_cd+X*nsites_cd+index]
	= phi_site_d[nsites_cd*XX+index];
      phi_site_full_d[3*X*nsites_cd+Y*nsites_cd+index]
	= phi_site_d[nsites_cd*XY+index];
      phi_site_full_d[3*X*nsites_cd+Z*nsites_cd+index]
	= phi_site_d[nsites_cd*XZ+index];
      phi_site_full_d[3*Y*nsites_cd+X*nsites_cd+index]
	=  phi_site_full_d[3*X*nsites_cd+Y*nsites_cd+index];
      phi_site_full_d[3*Y*nsites_cd+Y*nsites_cd+index]
	= phi_site_d[nsites_cd*YY+index];
      phi_site_full_d[3*Y*nsites_cd+Z*nsites_cd+index]
	= phi_site_d[nsites_cd*YZ+index];
      phi_site_full_d[3*Z*nsites_cd+X*nsites_cd+index]
	= phi_site_full_d[3*X*nsites_cd+Z*nsites_cd+index];
      phi_site_full_d[3*Z*nsites_cd+Y*nsites_cd+index]
	= phi_site_full_d[3*Y*nsites_cd+Z*nsites_cd+index];
      phi_site_full_d[3*Z*nsites_cd+Z*nsites_cd+index]
	= 0.0 -  phi_site_full_d[3*X*nsites_cd+X*nsites_cd+index]
	-  phi_site_full_d[3*Y*nsites_cd+Y*nsites_cd+index];


    }

}
void expand_phi_on_gpu()
{
  int N[3],nhalo,Nall[3];
  nhalo = coords_nhalo();
  coords_nlocal(N);
  Nall[X]=N[X]+2*nhalo;
  Nall[Y]=N[Y]+2*nhalo;
  Nall[Z]=N[Z]+2*nhalo;
  int nsites=Nall[X]*Nall[Y]*Nall[Z];
  
  cudaMemcpyToSymbol(N_cd, N, 3*sizeof(int), 0, cudaMemcpyHostToDevice);
  cudaMemcpyToSymbol(Nall_cd, Nall, 3*sizeof(int), 0, cudaMemcpyHostToDevice);
  cudaMemcpyToSymbol(nhalo_cd, &nhalo, sizeof(int), 0, cudaMemcpyHostToDevice);
  cudaMemcpyToSymbol(nsites_cd, &nsites, sizeof(int), 0, cudaMemcpyHostToDevice); 
  
  int nblocks=(Nall[X]*Nall[Y]*Nall[Z]+DEFAULT_TPB-1)/DEFAULT_TPB;
  
  expand_phi_on_gpu_d<<<nblocks,DEFAULT_TPB>>>
    (phi_site_d,phi_site_full_d);
  cudaThreadSynchronize();

checkCUDAError("expand_phi_on_gpu");
 
}

__global__ void expand_grad_phi_on_gpu_d(double* grad_phi_site_d,double* grad_phi_site_full_d, float *grad_phi_float_d)
{
  
  
  int index = blockIdx.x*blockDim.x+threadIdx.x;
  
  /* Avoid going beyond problem domain */
  if (index < Nall_cd[X]*Nall_cd[Y]*Nall_cd[Z])
    {
      
      
      /* /\* calculate index from CUDA thread index *\/ */
      /* int ia; */
      /* for(ia=0;ia<3;ia++){ */
      /* 	grad_phi_site_full_d[ia*nsites_cd*9+3*X*nsites_cd+X*nsites_cd+index] */
      /* 	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*XX+index]; */
      /* 	grad_phi_site_full_d[ia*nsites_cd*9+3*X*nsites_cd+Y*nsites_cd+index] */
      /* 	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*XY+index]; */
      /* 	grad_phi_site_full_d[ia*nsites_cd*9+3*X*nsites_cd+Z*nsites_cd+index] */
      /* 	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*XZ+index]; */
      /* 	grad_phi_site_full_d[ia*nsites_cd*9+3*Y*nsites_cd+X*nsites_cd+index] */
      /* 	  =  grad_phi_site_full_d[ia*nsites_cd*9+3*X*nsites_cd+Y*nsites_cd+index]; */
      /* 	grad_phi_site_full_d[ia*nsites_cd*9+3*Y*nsites_cd+Y*nsites_cd+index] */
      /* 	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*YY+index]; */
      /* 	grad_phi_site_full_d[ia*nsites_cd*9+3*Y*nsites_cd+Z*nsites_cd+index] */
      /* 	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*YZ+index]; */
      /* 	grad_phi_site_full_d[ia*nsites_cd*9+3*Z*nsites_cd+X*nsites_cd+index] */
      /* 	  = grad_phi_site_full_d[ia*nsites_cd*9+3*X*nsites_cd+Z*nsites_cd+index]; */
      /* 	grad_phi_site_full_d[ia*nsites_cd*9+3*Z*nsites_cd+Y*nsites_cd+index] */
      /* 	  = grad_phi_site_full_d[ia*nsites_cd*9+3*Y*nsites_cd+Z*nsites_cd+index]; */
      /* 	grad_phi_site_full_d[ia*nsites_cd*9+3*Z*nsites_cd+Z*nsites_cd+index] */
      /* 	  = 0.0 -  grad_phi_site_full_d[ia*nsites_cd*9+3*X*nsites_cd+X*nsites_cd+index] */
      /* 	  -  grad_phi_site_full_d[ia*nsites_cd*9+3*Y*nsites_cd+Y*nsites_cd+index]; */
      /* } */


      /* /\* calculate index from CUDA thread index *\/ */
      /* int ia; */
      /* for(ia=0;ia<3;ia++){ */
      /* 	grad_phi_site_full_d[index*27+ia*9+3*X+X] */
      /* 	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*XX+index]; */

      /* 	grad_phi_site_full_d[index*27+ia*9+3*X+Y] */
      /* 	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*XY+index]; */

      /* 	grad_phi_site_full_d[index*27+ia*9+3*X+Z] */
      /* 	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*XZ+index]; */

      /* 	grad_phi_site_full_d[index*27+ia*9+3*Y+X] */
      /* 	  =  grad_phi_site_full_d[index*27+ia*9+3*X+Y]; */

      /* 	grad_phi_site_full_d[index*27+ia*9+3*Y+Y] */
      /* 	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*YY+index]; */

      /* 	grad_phi_site_full_d[index*27+ia*9+3*Y+Z] */
      /* 	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*YZ+index]; */

      /* 	grad_phi_site_full_d[index*27+ia*9+3*Z+X] */
      /* 	  = grad_phi_site_full_d[index*27+ia*9+3*X+Z]; */

      /* 	grad_phi_site_full_d[index*27+ia*9+3*Z+Y] */
      /* 	  = grad_phi_site_full_d[index*27+ia*9+3*Y+Z]; */

      /* 	grad_phi_site_full_d[index*27+ia*9+3*Z+Z] */
      /* 	  = 0.0 -  grad_phi_site_full_d[index*27+ia*9+3*X+X] */
      /* 	  -  grad_phi_site_full_d[index*27+ia*9+3*Y+Y]; */
      /* } */


      /* calculate index from CUDA thread index */
      int ia,ib,ic;
      for(ia=0;ia<3;ia++){
	grad_phi_site_full_d[index*27+X*9+3*X+ia]
	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*XX+index];

	grad_phi_site_full_d[index*27+Y*9+3*X+ia]
	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*XY+index];

	grad_phi_site_full_d[index*27+Z*9+3*X+ia]
	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*XZ+index];

	grad_phi_site_full_d[index*27+X*9+3*Y+ia]
	  =  grad_phi_site_full_d[index*27+Y*9+3*X+ia];

	grad_phi_site_full_d[index*27+Y*9+3*Y+ia]
	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*YY+index];

	grad_phi_site_full_d[index*27+Z*9+3*Y+ia]
	  = grad_phi_site_d[ia*nsites_cd*5+nsites_cd*YZ+index];

	grad_phi_site_full_d[index*27+X*9+3*Z+ia]
	  = grad_phi_site_full_d[index*27+Z*9+3*X+ia];

	grad_phi_site_full_d[index*27+Y*9+3*Z+ia]
	  = grad_phi_site_full_d[index*27+Z*9+3*Y+ia];

	grad_phi_site_full_d[index*27+Z*9+3*Z+ia]
	  = 0.0 -  grad_phi_site_full_d[index*27+X*9+3*X+ia]
	  -  grad_phi_site_full_d[index*27+Y*9+3*Y+ia];
      }
      
      for (ia=0;ia<3;ia++)
	for (ib=0;ib<3;ib++)
	  for (ic=0;ic<3;ic++)
	    grad_phi_float_d[index*27+ic*9+3*ib+ia]=grad_phi_site_full_d[index*27+ic*9+3*ib+ia];

    }

}
void expand_grad_phi_on_gpu()
{
  int N[3],nhalo,Nall[3];
  nhalo = coords_nhalo();
  coords_nlocal(N);
  Nall[X]=N[X]+2*nhalo;
  Nall[Y]=N[Y]+2*nhalo;
  Nall[Z]=N[Z]+2*nhalo;
  int nsites=Nall[X]*Nall[Y]*Nall[Z];
  
  cudaMemcpyToSymbol(N_cd, N, 3*sizeof(int), 0, cudaMemcpyHostToDevice);
  cudaMemcpyToSymbol(Nall_cd, Nall, 3*sizeof(int), 0, cudaMemcpyHostToDevice);
  cudaMemcpyToSymbol(nhalo_cd, &nhalo, sizeof(int), 0, cudaMemcpyHostToDevice);
  cudaMemcpyToSymbol(nsites_cd, &nsites, sizeof(int), 0, cudaMemcpyHostToDevice); 
  
  int nblocks=(Nall[X]*Nall[Y]*Nall[Z]+DEFAULT_TPB-1)/DEFAULT_TPB;
  
    expand_grad_phi_on_gpu_d<<<nblocks,DEFAULT_TPB>>>
      (grad_phi_site_d,grad_phi_site_full_d,grad_phi_float_d);

texture<float,1,cudaReadModeElementType> texreference;

checkCUDAError("expand_grad_phi_on_gpu");



 
}


void phi_halo_gpu(){

  halo_gpu(1,nop,0,phi_site_d);

}

extern double * velocity_d;
void velocity_halo_gpu(){

  halo_gpu(1,3,0,velocity_d);

}
