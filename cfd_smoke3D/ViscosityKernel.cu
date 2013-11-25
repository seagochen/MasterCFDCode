/**
*
* Copyright (C) <2013> <Orlando Chen>
* Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
* associated documentation files (the "Software"), to deal in the Software without restriction, 
* including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, 
* and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, 
* subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all copies or substantial
* portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT 
* NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
* WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

/**
* <Author>      Orlando Chen
* <First>       Nov 25, 2013
* <Last>		Nov 25, 2013
* <File>        ViscosityKernel.cu
*/

#ifndef __viscosity_kernel_cu_
#define __viscosity_kernel_cu_

#include "cfdHeader.h"

extern void cudaSetBoundary ( float *grid_out, int boundary, dim3 *gridDim, dim3 *blockDim );

/*
-----------------------------------------------------------------------------------------------------------
* @function kernelDiffuse
* @author   Orlando Chen
* @date     Nov 25, 2013
* @input    float *grid_out, float const *grid_in
* @return   NULL
* @bref     To diffuse (smooth) the simulation result
-----------------------------------------------------------------------------------------------------------
*/
__global__ void kernelViscosity ( float *grid_out, float const *grid_in )
{
	// Get index of GPU-thread
	GetIndex ( );

	float ratio = DELETE * VISCOSITY * Grids_X * Grids_X;

	BeginSimArea ( );
	{
		grid_out [ Index(i, j, k) ] = (grid_in [ Index(i, j, k) ] + ratio * ( grid_out [ Index(i-1, j, k) ] +  grid_out [ Index( i+1, j, k) ] +
			grid_out [ Index(i, j-1, k) ] + grid_out [ Index(i, j+1, k) ] )) / ( 1 + 4 * ratio );
	}
	EndSimArea ( );
};


/*
-----------------------------------------------------------------------------------------------------------
* @function cudaViscosity
* @author   Orlando Chen
* @date     Nov 25, 2013
* @input    float *grid_out, float const *grid_in, int boundary, dim3 *gridDim, dim3 *blockDim
* @return   NULL
* @bref     Encapsulation the CUDA routine (diffuse)
-----------------------------------------------------------------------------------------------------------
*/
__host__ void cudaViscosity ( float *grid_out, float const *grid_in, int boundary, dim3 *gridDim, dim3 *blockDim )
{
	for ( int i = 0; i < 20; i++ )
	{
		kernelViscosity cudaDevice(*gridDim, *blockDim) ( grid_out, grid_in );
		cudaSetBoundary  ( grid_out, boundary, gridDim, blockDim );
	}
};

#endif