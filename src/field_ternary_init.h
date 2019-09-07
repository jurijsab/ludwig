/*****************************************************************************
 *
 *  field_ternary_init.h
 *
 *  Edinburgh Soft Matter and Statistical Physics Group and
 *  Edinburgh Parallel Computing Centre
 *
 *  (c) 2019 The University of Edinburgh
 *
 *  Contributing authors:
 *  Shan Chen (shan.chen@epfl.ch)
 *  Kevin Stratford (kevin@epcc.ed.ac.uk)
 *
 *****************************************************************************/

#ifndef LUDWIG_FIELD_TERNARY_INIT_H
#define LUDWIG_FIELD_TERNARY_INIT_H

#include "field.h"

int field_phi_init_ternary_X(field_t * phi);
int field_phi_init_ternary_XY(field_t * phi);
int field_phi_init_ternary_bbb(field_t * phi);
int field_phi_init_ternary_ggg(field_t * phi);

#endif
