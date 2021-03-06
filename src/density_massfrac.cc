/*
 * density_massfrac.cc
 *
 *  Created on: Feb 24, 2015
 *      Author: zhixuanc
 */

// Function for density and mass fraction updating

#include <vector>
#include <cassert>
#include <iostream>
using namespace std;

#include <thashtab.h>

#include "particler.h"
#include "constant.h"
#include "sph_header.h"

#ifdef DEBUG
#  include <debug_header.h>
#endif

void
smooth_density(THashTable * P_table)
{
  int i, j, k, no_of_neighs;
  //unsigned jkey[TKEYLENGTH];
  double xi[DIMENSION], ds[DIMENSION], s[DIMENSION];
  double wght, density=0.0;
  TKey tmpkey;
  int phs_i;
  double tmprho[PHASE_NUM]={0.0}, phaserho[PHASE_NUM]={0.0}, mssfrc;
  double wnorm[PHASE_NUM];
  // create a Hash Table iterator instance
  THTIterator * itr = new THTIterator (P_table);
  Particle * pi = NULL;

#ifdef DEBUG
   bool check_den = false;
   bool do_search = false;
   bool check_mssfrac = false;
   bool find;
   unsigned keycheck[TKEYLENGTH] =  {69674717, 3383906357, 0};
   unsigned keytemp[TKEYLENGTH] ;
#endif

  // iterate over the table
  while ((pi = (Particle *) itr->next ()))
  {
    if (pi->need_neigh())
    {

#ifdef DEBUG
		if (do_search)
		{
		    for (i = 0; i < TKEYLENGTH; i++)
			    keytemp[i] = pi->getKey ().key[i];

		    if (find_particle (keytemp, keycheck))
			    cout << "The particle found!" << endl;
		}
#endif

      for (i = 0; i < DIMENSION; i++)
        xi[i] = (*(pi->get_coords () + i));

      double hi = pi->get_smlen ();
      double supp = 3.0 * hi;
      TKey ki = pi->getKey ();

      for (i = 1; i <= PHASE_NUM; i++)
    	  tmprho[i-1] = 0.;

      for (i = 1; i <= PHASE_NUM; i++)
    	  phaserho[i-1] = 0.;

      for (i = 1; i <= PHASE_NUM; i++)
    	  wnorm [i-1] = 0.;

      vector <TKey> neighs = pi->get_neighs ();
      vector <TKey> :: iterator p_itr;

      //go through all neighbors
      for (p_itr = neighs.begin (); p_itr != neighs.end (); p_itr++)
      {
          // Transfer key into particle #
          Particle *pj = (Particle *) P_table->lookup (*p_itr);
          assert (pj);
          //update density for each phase
          //Probably, a switch case is better than for loop in terms of efficiency!
          for (phs_i = 1; phs_i<= PHASE_NUM; phs_i++)
          {
              //for each phase
      	      if (pj->which_phase()==phs_i)
      	      {
      		    // guests are included ghosts are not,
      	    	// the wall effect is handled by wnorm!
      		    if (pj->contr_dens())
      		    {
      		        for (i = 0; i < DIMENSION; i++)
      		            ds[i] = xi[i] - *(pj->get_coords() + i);

      		        if (in_support(ds, supp))
      		        {
      		            for (k = 0; k < DIMENSION; k++)
      		            s[k] = ds[k] / hi;
      		            wght = weight(s, hi);
      		            tmprho[phs_i-1] += wght * (pj->get_mass());
      		            wnorm[phs_i-1] += wght * (pj->get_mass()) / (pj->get_density());
      		         }
      		     }
      	      }//end of if

          }//end of loop for phase

      }//end of go through all neighbors

      for (phs_i = 2; phs_i<= PHASE_NUM; phs_i++) //add wnorm up, so start from second phase.
      {
    	  wnorm[0] += wnorm [phs_i-1];
      }

      density=0.0;
      for (phs_i = 1; phs_i<= PHASE_NUM; phs_i++)
      {
           assert (wnorm[0] > 0);
    	   phaserho[phs_i-1]= tmprho[phs_i-1] / wnorm[0];
    	   density +=phaserho[phs_i-1];
      }

#ifdef DEBUG
      if (check_den)
      {
         if (!(density > 0))
        	 cout << "density is invalid" << endl;
      }
#endif

	  assert(density > 0);
      pi->put_density(density);
      mssfrc=phaserho[1]/density;

#ifdef DEBUG
      if (check_mssfrac)
      {
         if (!(mssfrc <=1))
        	 cout << "mass fraction larger than 1" << endl;
      }
#endif
      assert(mssfrc <= 1);
      pi->put_mass_frac(mssfrc);

    }//end of if --> if the density of that particle need to be updated based summation
  }//end of loop -->go through all particle

  // clean up stuff
  delete itr;

  return;
}

