/*****************************************************************************
 *
 *  subgrid.h
 *
 *
 *  Edinburgh Soft Matter and Statistical Physics Group and
 *  Edinburgh Parallel Computing Centre
 *
 *  Kevin Stratford (kevin@epcc.ed.ac.uk)
 *  (c) 2010-2020 The University of Edinburgh
 *
 *****************************************************************************/

#ifndef LUDWIG_SUBGRID_H
#define LUDWIG_SUBGRID_H

#include "colloids.h"
#include "hydro.h"

int subgrid_update(colloids_info_t * cinfo, hydro_t * hydro);
int subgrid_force_from_particles(colloids_info_t * cinfo, hydro_t * hydro);
int subgrid_on_set(void);
int subgrid_on(int * flag);

#endif
