/*****************************************************************************
 *
 *  test_bond_fene.c
 *
 *  Edinburgh Soft Matter and Statistical Physics Group and
 *  Edinburgh Parallel Computing Centre
 *
 *  (c) 2014-2017 The University of Edinburgh
 *
 *  Contributing authors:
 *  Kevin Stratford (kevin@epcc.ed.ac.uk)
 *
 *****************************************************************************/

#include <assert.h>
#include <float.h>
#include <math.h>
#include <stdlib.h>

#include "pe.h"
#include "coords.h"
#include "colloids_halo.h"
#include "bond_fene.h"
#include "tests.h"

#define BOND_K    3.0
#define BOND_R0   7.0

int test_bond_fene1(pe_t * pe, cs_t * cs);
int test_bond_fene2(pe_t * pe, cs_t * cs);
int test_create_dimer(colloids_info_t * cinfo, double a, double r1[3],
		      double r2[3], colloid_t * pc[2]);

/*****************************************************************************
 *
 *  test_bond_fene_suite
 *
 *****************************************************************************/

int test_bond_fene_suite(void) {

  pe_t * pe = NULL;
  cs_t * cs = NULL;

  pe_create(MPI_COMM_WORLD, PE_QUIET, &pe);
  cs_create(pe, &cs);
  cs_init(cs);

  test_bond_fene1(pe, cs);
  test_bond_fene2(pe, cs);

  cs_free(cs);
  pe_info(pe, "PASS     ./unit/test_bond_fene\n");
  pe_free(pe);

  return 0;
}

/*****************************************************************************
 *
 *  test_bond_fene1
 *
 *****************************************************************************/

int test_bond_fene1(pe_t * pe, cs_t * cs) {

  bond_fene_t * bond = NULL;

  double r = 1.0;
  double v, f;

  assert(pe);
  assert(cs);

  bond_fene_create(pe, cs, &bond);
  assert(bond);

  bond_fene_param_set(bond, BOND_K, BOND_R0);

  bond_fene_single(bond, r, &v, &f);

  assert(fabs(v -  1.5155176) < FLT_EPSILON);
  assert(fabs(f - -3.0625000) < FLT_EPSILON);

  bond_fene_free(bond);

  return 0;
}

/*****************************************************************************
 *
 *  test_bond_fene2
 *
 *****************************************************************************/

int test_bond_fene2(pe_t * pe, cs_t * cs) {

  int ncell[3] = {2, 2, 2};

  double r1[3], r2[3];
  double v, f, dr;
  double r12[3];
  double ltot[3];
  double stats_local[INTERACT_STAT_MAX];
  double stats[INTERACT_STAT_MAX];

  colloids_info_t * cinfo = NULL;
  interact_t * interact = NULL;
  bond_fene_t * bond = NULL;
  colloid_t * pc[2];
  MPI_Comm comm;

  assert(pe);
  assert(cs);

  cs_ltot(cs, ltot);
  cs_cart_comm(cs, &comm);

  colloids_info_create(pe, cs, ncell, &cinfo);
  interact_create(pe, cs, &interact);

  assert(cinfo);
  assert(interact);

  bond_fene_create(pe, cs, &bond);
  bond_fene_param_set(bond, BOND_K, BOND_R0);
  bond_fene_register(bond, interact);

  dr = 1.0/sqrt(3.0); /* Set separation 1.0 */
  r1[X] = 0.5*(ltot[X] - dr);
  r1[Y] = 0.5*(ltot[Y] - dr);
  r1[Z] = 0.5*(ltot[Z] - dr);
  r2[X] = 0.5*(ltot[X] + dr);
  r2[Y] = 0.5*(ltot[Y] + dr);
  r2[Z] = 0.5*(ltot[Z] + dr);

  test_create_dimer(cinfo, dr, r1, r2, pc);

  /* Go through the interaction */

  interact_find_bonds(interact, cinfo);
  interact_bonds(interact, cinfo);

  cs_minimum_distance(cs, r1, r2, r12);
  dr = sqrt(r12[X]*r12[X] + r12[Y]*r12[Y] + r12[Z]*r12[Z]);
  bond_fene_single(bond, dr, &v, &f);

  if (pc[0]) {
    assert(fabs(pc[0]->force[X] - -f*r12[X]/dr) < FLT_EPSILON);
    assert(fabs(pc[0]->force[Y] - -f*r12[Y]/dr) < FLT_EPSILON);
    assert(fabs(pc[0]->force[Z] - -f*r12[Z]/dr) < FLT_EPSILON);
  }

  if (pc[1]) {
    assert(fabs(pc[1]->force[X] -  f*r12[X]/dr) < FLT_EPSILON);
    assert(fabs(pc[1]->force[Y] -  f*r12[Y]/dr) < FLT_EPSILON);
    assert(fabs(pc[1]->force[Z] -  f*r12[Z]/dr) < FLT_EPSILON);
  }

  /* Get stats (just do whole INTERACT_STAT_MAX for each operation) */

  bond_fene_stats(bond, stats_local);

  MPI_Allreduce(stats_local, stats, INTERACT_STAT_MAX, MPI_DOUBLE, MPI_SUM,
		comm);
  assert(fabs(stats[INTERACT_STAT_VLOCAL] - v) < FLT_EPSILON);

  MPI_Allreduce(stats_local, stats, INTERACT_STAT_MAX, MPI_DOUBLE, MPI_MIN,
		comm);
  assert(fabs(stats[INTERACT_STAT_RMINLOCAL] - dr) < FLT_EPSILON);

  MPI_Allreduce(stats_local, stats, INTERACT_STAT_MAX, MPI_DOUBLE, MPI_MAX,
		comm);
  assert(fabs(stats[INTERACT_STAT_RMAXLOCAL] - dr) < FLT_EPSILON);

  /* Finish */

  bond_fene_free(bond);
  interact_free(interact);
  colloids_info_free(cinfo);

  return 0;
}

/*****************************************************************************
 *
 *  test_create_dimer
 *
 *****************************************************************************/

int test_create_dimer(colloids_info_t * cinfo, double a, double r1[3],
		      double r2[3], colloid_t * pc[2]) {

  int nc = 0;

  assert(cinfo);
  assert(pc);

  colloids_info_add_local(cinfo, 1, r1, pc);
  if (pc[0]) {
    pc[0]->s.a0 = a;
    pc[0]->s.ah = a;
    pc[0]->s.nbonds = 1;
    pc[0]->s.bond[0] = 2;
  }

  colloids_info_add_local(cinfo, 2, r2, pc + 1);
  if (pc[1]) {
    pc[1]->s.a0 = a;
    pc[1]->s.ah = a;
    pc[1]->s.nbonds = 1;
    pc[1]->s.bond[0] = 1;
  }

  colloids_info_ntotal_set(cinfo);
  colloids_info_ntotal(cinfo, &nc);
  assert(nc == 2);

  colloids_halo_state(cinfo);
  colloids_info_list_local_build(cinfo);

  return 0;
}
