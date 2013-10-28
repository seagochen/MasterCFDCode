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
* <First>       Oct 12, 2013
* <Last>		Oct 25, 2013
* <File>        cfd_2DKernel.cu
*/

#ifndef __cfd_2DKernel_cu_
#define __cfd_2DKernel_cu_

#include "macro_def.h"

using namespace std;

__global__ void add_source_kernel ( float *ptr_out, float *ptr_in )
{
	// Get index of GPU-thread
	int i = blockIdx.x * blockDim.x + threadIdx.x;
	int j = blockIdx.y * blockDim.y + threadIdx.y;
	int ind = Index(i, j);

	// Yield value
	ptr_out[ind] += DELTA_TIME * ptr_in[ind];
};


__global__ void set_bnd_kernel ( float *grid_out, int boundary )
{
#define is ==
	// Get index of GPU-thread
	int i = blockIdx.x * blockDim.x + threadIdx.x;
	int j = blockIdx.y * blockDim.y + threadIdx.y;

	// Boundary condition
	if ( i >= 1 && i <= SimArea_X && j >= 1 && j <= SimArea_X )
	{
		// Slove line (0, y)
		grid_out[Index(0, j)]  = boundary is 1 ? -grid_out[Index(1, j)] : grid_out[Index(1, j)];
		// Slove line (65, y)
		grid_out[Index(65, j)] = boundary is 1 ? -grid_out[Index(64,j)] : grid_out[Index(64,j)];
		// Slove line (x, 0)
		grid_out[Index(i, 0)]  = boundary is 2 ? -grid_out[Index(i, 1)] : grid_out[Index(i, 1)];
		// Slove line (x, 65)
		grid_out[Index(i, 65)] = boundary is 2 ? -grid_out[Index(i,64)] : grid_out[Index(i,64)];
	}
	// Slove ghost cell (0, 0)
	grid_out[Index(0, 0)] = 0.5f * ( grid_out[Index(1, 0)]  + grid_out[Index(0, 1)] );
	// Slove ghost cell (0, 65)
	grid_out[Index(0, 65)] = 0.5f * ( grid_out[Index(1, 65)] + grid_out[Index(0, 64)] );
	// Slove ghost cell (65, 0)
	grid_out[Index(65, 0)] = 0.5f * ( grid_out[Index(64, 0)] + grid_out[Index(65, 1)] );
	// Slove ghost cell (65, 65)
	grid_out[Index(65, 65)] = 0.5f * ( grid_out[Index(64, 65)] + grid_out[Index(65, 64)]);

#undef is
}


__global__ void lin_solve_kernel ( float *grid_inout, float *grid0_in, int boundary, float a, float c )
{
	// Get index of GPU-thread
	int i = blockIdx.x * blockDim.x + threadIdx.x;
	int j = blockIdx.y * blockDim.y + threadIdx.y;

	if ( i >= 1 && i <= SimArea_X && j >= 1 && j <= SimArea_X )
	{	
		grid_inout[Index(i,j)] = (grid0_in[Index(i,j)] + a * ( grid_inout[Index(i-1,j)] + 
			grid_inout[Index(i+1,j)] + grid_inout[Index(i,j-1)] + grid_inout[Index(i,j+1)] ) ) / c;	
	}
}


__global__ void advect_kernel(float *density_out, float *density0_in, float *u_in, float *v_in, float dt0)
{
	// Get index of GPU-thread
	int i = blockIdx.x * blockDim.x + threadIdx.x;
	int j = blockIdx.y * blockDim.y + threadIdx.y;

	int i0, j0, i1, j1;
	float x, y, s0, t0, s1, t1;

	if ( i >= 1 && i <= SimArea_X && j >= 1 && j <= SimArea_X )
	{
		x = i - dt0 * u_in[Index(i,j)];
		y = j - dt0 * v_in[Index(i,j)];
		if (x < 0.5f) x = 0.5f;
		if (x > SimArea_X + 0.5f) x = SimArea_X+0.5f;

		i0 = (int)x; 
		i1 = i0+1;
		
		if (y < 0.5f) y=0.5f;
		if (y > SimArea_X+0.5f) y = SimArea_X+0.5f;
		
		j0 = (int)y;
		j1 = j0 + 1;
		s1 = x - i0;
		s0 = 1 - s1;
		t1 = y - j0;
		t0 = 1 - t1;

		density_out[Index(i,j)] = s0 * ( t0 * density0_in[Index(i0,j0)] +
			t1 * density0_in[Index(i0,j1)]) + s1 * ( t0 * density0_in[Index(i1,j0)] + 
			t1 * density0_in[Index(i1,j1)]);
	}
};


__global__ void project_kernel_pt1(float * u, float * v, float * p, float * div)
{
	// Get index of GPU-thread
	int i = blockIdx.x * blockDim.x + threadIdx.x;
	int j = blockIdx.y * blockDim.y + threadIdx.y;
	
	if ( i >= 1 && i <= SimArea_X && j >= 1 && j <= SimArea_X )
	{
		div[Index(i,j)] = -0.5f*(u[Index(i+1,j)]-u[Index(i-1,j)]+v[Index(i,j+1)]-v[Index(i,j-1)])/SimArea_X;
		p[Index(i,j)] = 0;
	}
}


__global__ void project_kernel_pt2(float * u, float * v, float * p, float * div)
{
	// Get index of GPU-thread
	int i = blockIdx.x * blockDim.x + threadIdx.x;
	int j = blockIdx.y * blockDim.y + threadIdx.y;
	
	if ( i >= 1 && i <= SimArea_X && j >= 1 && j <= SimArea_X )
	{
			u[Index(i,j)] -= 0.5f*SimArea_X*(p[Index(i+1,j)]-p[Index(i-1,j)]);
			v[Index(i,j)] -= 0.5f*SimArea_X*(p[Index(i,j+1)]-p[Index(i,j-1)]);
	}
}


void cuda_add_source ( float *grid, float *grid0, dim3 *grid_size, dim3 *block_size )
{
    // Launch a kernel on the GPU with one thread for each element.
	add_source_kernel cuda_device(*grid_size,  *block_size) (grid, grid0);
};


void cuda_lin_solve (float *grid, float *grid0, int boundary, float a, float c, dim3 *grid_size, dim3 *block_size)
{
    // Launch a kernel on the GPU with one thread for each element.
	for (int i=0; i<20; i++)
	{
		lin_solve_kernel cuda_device(*grid_size,  *block_size) (grid, grid0, boundary, a, c);
	}
	set_bnd_kernel cuda_device(*grid_size,  *block_size)  (grid, boundary);
}


void cuda_diffuse ( float *grid, float *grid0, int boundary, float diff, dim3 *grid_size, dim3 *block_size )
{
	float a=DELTA_TIME*diff*SimArea_X*SimArea_X;
	cuda_lin_solve ( grid, grid0, boundary, a, 1+4*a, grid_size, block_size );
}


void cuda_advect( float *density, float *density0, float *u, float *v,  int boundary, dim3 *grid_size, dim3 *block_size )
{
    // Launch a kernel on the GPU with one thread for each element.
	float dt0 = DELTA_TIME*SimArea_X;
	advect_kernel cuda_device(*grid_size,  *block_size) (density, density0, u, v, dt0);
	set_bnd_kernel cuda_device(*grid_size,  *block_size) (density, boundary);
}


void cuda_project ( float * u, float * v, float * p, float * div, dim3 *grid_size, dim3 *block_size )
{
	project_kernel_pt1  cuda_device(*grid_size,  *block_size)  (u, v, p, div);
	set_bnd_kernel  cuda_device(*grid_size,  *block_size)  (div, 0); 
	set_bnd_kernel  cuda_device(*grid_size,  *block_size)  (p, 0);
	lin_solve_kernel  cuda_device(*grid_size,  *block_size)  (p, div, 0, 1, 4);
	project_kernel_pt2  cuda_device(*grid_size,  *block_size)  (u, v, p, div);
	set_bnd_kernel  cuda_device(*grid_size,  *block_size)  ( u, 1 );
	set_bnd_kernel  cuda_device(*grid_size,  *block_size)  ( v, 2 );
}


void dens_step ( float *grid, float *grid0, float *u, float *v )
{
	// Define the computing unit size
	dim3 block_size;
	dim3 grid_size;
	block_size.x = Tile_X;
	block_size.y = Tile_X;
	grid_size.x  = Grids_X / Tile_X;
	grid_size.y  = Grids_X / Tile_X;

	size_t size = Grids_X * Grids_X;

    // Copy input vectors from host memory to GPU buffers.
    cudaStatus = cudaMemcpy(dev_grid, grid, size * sizeof(float), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }

	cudaStatus = cudaMemcpy(dev_grid0, grid0, size * sizeof(float), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }

	cudaStatus = cudaMemcpy(dev_u, u, size * sizeof(float), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);    
	}

	cudaStatus = cudaMemcpy(dev_v, v, size * sizeof(float), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }


	cuda_add_source(dev_grid, dev_grid0, &grid_size, &block_size);
	swap ( dev_grid0, dev_grid ); cuda_diffuse ( dev_grid, dev_grid0, 0, DIFFUSION, &grid_size, &block_size );
	swap ( dev_grid0, dev_grid ); cuda_advect ( dev_grid, dev_grid0, dev_u, dev_v, 0, &grid_size, &block_size );
	
	
	// Check for any errors launching the kernel
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "CUDA encountered an error, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }
    
    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaStatus = cudaDeviceSynchronize();
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaDeviceSynchronize was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }

    // Copy output vector from GPU buffer to host memory.
    cudaStatus = cudaMemcpy(grid, dev_grid, size * sizeof(int), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }

	cudaStatus = cudaMemcpy(grid0, dev_grid0, size * sizeof(int), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
	}
	
	cudaStatus = cudaMemcpy(u, dev_u, size * sizeof(int), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
	}

	cudaStatus = cudaMemcpy(v, dev_v, size * sizeof(int), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
	}
}


void vel_step ( float * u, float * v, float * u0, float * v0 )
{
	// Define the computing unit size
	dim3 block_size;
	dim3 grid_size;
	block_size.x = Tile_X;
	block_size.y = Tile_X;
	grid_size.x  = Grids_X / Tile_X;
	grid_size.y  = Grids_X / Tile_X;

	size_t size = Grids_X * Grids_X;

    // Copy input vectors from host memory to GPU buffers.
    cudaStatus = cudaMemcpy(dev_u0, u0, size * sizeof(float), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }

	cudaStatus = cudaMemcpy(dev_v0, v0, size * sizeof(float), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }

	cudaStatus = cudaMemcpy(dev_u, u, size * sizeof(float), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }

	cudaStatus = cudaMemcpy(dev_v, v, size * sizeof(float), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }


	cuda_add_source ( dev_u, dev_u0, &grid_size, &block_size ); cuda_add_source ( dev_v, dev_v0, &grid_size, &block_size );
	swap ( dev_u0, dev_u ); cuda_diffuse ( dev_u, dev_u0, 1, VISCOSITY, &grid_size, &block_size );
	swap ( dev_v0, dev_v ); cuda_diffuse ( dev_v, dev_v0, 2, VISCOSITY, &grid_size, &block_size );
	cuda_project ( dev_u, dev_v, dev_u0, dev_v0, &grid_size, &block_size );
	swap ( dev_u0, dev_u ); swap ( dev_v0, dev_v );
	cuda_advect ( dev_u, dev_u0, dev_u0, dev_v0, 1, &grid_size, &block_size );
	cuda_advect ( dev_v, dev_v0, dev_u0, dev_v0, 2, &grid_size, &block_size );
	cuda_project ( dev_u, dev_v, dev_u0, dev_v0, &grid_size, &block_size );


	// Check for any errors launching the kernel
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "CUDA encountered an error, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }
    
    // cudaDeviceSynchronize waits for the kernel to finish, and returns
    // any errors encountered during the launch.
    cudaStatus = cudaDeviceSynchronize();
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaDeviceSynchronize was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }

    // Copy output vector from GPU buffer to host memory.
    cudaStatus = cudaMemcpy(u0, dev_u0, size * sizeof(int), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }

	cudaStatus = cudaMemcpy(v0, dev_v0, size * sizeof(int), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }
	
	cudaStatus = cudaMemcpy(u, dev_u, size * sizeof(int), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }

	cudaStatus = cudaMemcpy(v, dev_v, size * sizeof(int), cudaMemcpyDeviceToHost);
    if (cudaStatus != cudaSuccess) {
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, "cudaMemcpy was failed, at line: %d of file %s", __LINE__, __FILE__);
		Logfile.SaveStringToFile("errormsg.log", sge::SG_FILE_OPEN_APPEND, ">>>> Error Message: %s", cudaGetErrorString(cudaStatus));
		exit(0);
    }
}

#endif