/**
* <Author>        Orlando Chen
* <Email>         seagochen@gmail.com
* <First Time>    Dec 15, 2013
* <Last Time>     Apr 03, 2014
* <File Name>     FluidSimProc.cu
*/

#include <time.h>
#include <iostream>
#include <utility>
#include <cuda_runtime_api.h>
#include <device_launch_parameters.h>
#include "MacroDefinition.h"
#include "FluidSimProc.h"
#include "MacroDefinition.h"
#include "Kernels.h"

using namespace sge;
using std::cout;
using std::endl;

static int t_totaltimes = 0;

static clock_t t_start, t_finish;
static double t_duration;

static clock_t t_estart, t_efinish;
static double t_eduration;

FluidSimProc::FluidSimProc( FLUIDSPARAM *fluid )
{
	/* choose which GPU to run on, change this on a multi-GPU system. */
	if ( cudaSetDevice ( 0 ) != cudaSuccess )
	{
		m_scHelper.GetCUDALastError( "cannot set device", __FILE__, __LINE__ );
		exit(1);
	}

	/* initialize FPS */
	InitParams( fluid );

	/* allocate resources */
	AllocateResource();
	
	/* clear buffer */
	ClearBuffers();

	/* create boundary condition */
	InitBoundary();

	/* finally, print message */
	printf( "fluid simulation ready...\n" );
};

void FluidSimProc::InitParams( FLUIDSPARAM *fluid )
{
	fluid->fps.dwCurrentTime = 0;
	fluid->fps.dwElapsedTime = 0;
	fluid->fps.dwFrames = 0;
	fluid->fps.dwLastUpdateTime = 0;
	fluid->fps.uFPS = 0;

	srand(time(NULL));

	m_szTitle = APP_TITLE;

	t_estart = clock();
};

void FluidSimProc::AllocateResource( void )
{
	if ( not m_scHelper.CreateCompNodesForDevice( &m_vectCompBufs, 
		GRIDS_X * GRIDS_Y * GRIDS_Z * sizeof(double), COMP_BUFS ) ) goto Error;

	if ( not m_scHelper.CreateCompNodesForDevice( &m_vectBulletBufs, 
		BULLET_X * BULLET_Y * BULLET_Z * sizeof(double), BUL_BUFS ) ) goto Error;

	m_scHelper.CreateDeviceBuffers( VOLUME_X * VOLUME_Y * VOLUME_Z * sizeof(SGUCHAR),
		1, &m_ptrDeviceVisual );
	m_scHelper.CreateHostBuffers( VOLUME_X * VOLUME_Y * VOLUME_Z * sizeof(SGUCHAR),
		1, &m_ptrHostVisual );

	if ( not m_scHelper.CreateCompNodesForDevice( &m_vectBigBufs,
		VOLUME_X * VOLUME_Y * VOLUME_Z * sizeof(double), BIG_BUFS ) ) goto Error;

	goto Success;

Error:
		cout << "create computation buffers device failed" << endl;
		FreeResource();
		exit(1);

Success:
		cout << "size of m_vectBulletBufs: " << m_vectBulletBufs.size() << endl
			<< "size of m_vectCompBufs: " << m_vectCompBufs.size() << endl;
};

void FluidSimProc::FreeResource( void )
{
	for ( int i = 0; i < m_vectBulletBufs.size(); i++ )
		m_scHelper.FreeDeviceBuffers( 1, &m_vectBulletBufs[i] );

	for ( int i = 0; i < m_vectCompBufs.size(); i++ )
		m_scHelper.FreeDeviceBuffers( 1, &m_vectCompBufs[i] );

	for ( int i = 0; i < m_vectBigBufs.size(); i++ )
		m_scHelper.FreeDeviceBuffers( 1, &m_vectBigBufs[i] );

	m_scHelper.FreeDeviceBuffers( 1, &m_ptrDeviceVisual );
	m_scHelper.FreeHostBuffers( 1, &m_ptrHostVisual );

	t_efinish = clock();
	t_eduration = (double)( t_efinish - t_estart ) / CLOCKS_PER_SEC;

	printf( "total duration: %f\n", t_eduration );
};

void FluidSimProc::RefreshStatus( FLUIDSPARAM *fluid )
{
	/* waiting for all kernels end */
	if ( cudaThreadSynchronize() not_eq cudaSuccess )
	{
		printf( "cudaThreadSynchronize failed\n" );
		FreeResource();
		exit( 1 );
	}

	/* counting FPS */
	fluid->fps.dwFrames ++;
	fluid->fps.dwCurrentTime = GetTickCount();
	fluid->fps.dwElapsedTime = fluid->fps.dwCurrentTime - fluid->fps.dwLastUpdateTime;

	/* 1 second */
	if ( fluid->fps.dwElapsedTime >= 1000 )
	{
		fluid->fps.uFPS     = fluid->fps.dwFrames * 1000 / fluid->fps.dwElapsedTime;
		fluid->fps.dwFrames = 0;
		fluid->fps.dwLastUpdateTime = fluid->fps.dwCurrentTime;
	}

	/* updating image */
	if ( cudaMemcpy( m_ptrHostVisual, m_ptrDeviceVisual, 
		VOLUME_X * VOLUME_Y * VOLUME_Z * sizeof(SGUCHAR), cudaMemcpyDeviceToHost ) not_eq cudaSuccess )
	{
		m_scHelper.GetCUDALastError( "host function: cudaMemcpy failed", __FILE__, __LINE__ );
		FreeResource();
		exit( 1 );
	}
	fluid->volume.ptrData = m_ptrHostVisual;
};

void FluidSimProc::FluidSimSolver( FLUIDSPARAM *fluid )
{
	if ( not fluid->run ) return;

	if( t_totaltimes > TIMES ) 
	{
		FreeResource();
		exit(1);
	}

	t_start = clock();
	SolveNavierStokesEquation( DELTATIME, true, true, true );
	t_finish = clock();
	t_duration = (double)( t_finish - t_start ) / CLOCKS_PER_SEC;
	printf( "%f ", t_duration );

	t_start = clock();
	GenerVolumeImg();
	RefreshStatus( fluid );
	t_finish = clock();
	t_duration = (double)( t_finish - t_start ) / CLOCKS_PER_SEC;
	printf( "%f ", t_duration );

	/* FPS */
	printf( "%d", fluid->fps.uFPS );

	t_totaltimes++;

	printf("\n");
};

void FluidSimProc::GenerVolumeImg( void )
{
	m_scHelper.DeviceParamDim( &gridDim, &blockDim, THREADS_S, TILE_X, TILE_Y, GRIDS_X, GRIDS_X, GRIDS_X );
	kernelExitBullet __device_func__
		( comp_den, dev_den, GRIDS_X, GRIDS_Y, GRIDS_Z, BULLET_X, BULLET_Y, BULLET_Z );

	kernelPickData __device_func__ ( m_ptrDeviceVisual, comp_den, VOLUME_X, VOLUME_Y, VOLUME_Z );
};

void FluidSimProc::ClearBuffers( void )
{
	m_scHelper.DeviceParamDim( &gridDim, &blockDim, THREADS_S, 26, 26, BULLET_X, BULLET_Y, BULLET_Z );
	for ( int i = 0; i < m_vectBulletBufs.size(); i++ )
		kernelZeroBuffers __device_func__ ( m_vectBulletBufs[i], BULLET_X, BULLET_Y, BULLET_Z );

	if ( m_scHelper.GetCUDALastError( "host function failed: ZeroBuffers", __FILE__, __LINE__ ) )
	{
		FreeResource();
		exit( 1 );
	}
};

inline __device__ void _thread( int *i )
{
	*i = blockIdx.x * blockDim.x + threadIdx.x;
};

inline __device__ void _thread( int *i, int *j )
{
	*i = blockIdx.x * blockDim.x + threadIdx.x;
	*j = blockIdx.y * blockDim.y + threadIdx.y;
};

inline __device__ void _thread
	( int *i, int *j, int *k, cint tilex, cint tiley, cint tilez )
{
	_thread( i, j );
	
	*k = *i + *j * tilex;
	*k = *k / ( tilex * tiley );
	*i = *i % tilex;
	*j = *j % tiley;
};

inline __device__ __host__ int ix( cint x, cint tilex)
{
	if ( x >= tilex or x < 0 ) return -1;
	return x;
};

inline __device__ __host__ int ix( cint i, cint j, cint tilex, cint tiley )
{
	if ( i < 0 or j < 0 ) return -1;

	int x; if ( i >= tilex ) x = tilex - 1;
	int y; if ( j >= tiley ) y = tiley - 1;

	x = i; y = j;
	return x + y * tilex;
};

inline __host__ __device__ int ix
	( cint i, cint j, cint k, cint tilex, cint tiley, cint tilez )
{
	if ( i < 0 or i >= tilex ) return -1;
	if ( j < 0 or j >= tiley ) return -1;
	if ( k < 0 or k >= tilez ) return -1;

	return i + j * tilex + k * tilex * tiley;
};

__global__ void kernelSetBound( double *dst, cint tilex, cint tiley, cint tilez )
{
	int i, j, k;
	_thread( &i, &j, &k, tilex, tiley, tilez );

	cint halfx = tilex / 2;
	cint halfz = tilez / 2;

	if ( j < 6 and 
		i >= halfx - 4 and i < halfx + 4 and 
		k >= halfz - 4 and k < halfz + 4 )
	{
		dst[ix(i,j,k,tilex,tiley,tilez)] = MACRO_BOUNDARY_SOURCE;
	}
	else
	{
		dst[ix(i,j,k,tilex,tiley,tilez)] = MACRO_BOUNDARY_BLANK;
	}
};

void FluidSimProc::InitBoundary( void )
{
	m_scHelper.DeviceParamDim( &gridDim, &blockDim, THREADS_S, TILE_X, TILE_Y, GRIDS_X, GRIDS_Y, GRIDS_Z );

	kernelSetBound __device_func__ ( comp_obst, GRIDS_X, GRIDS_Y, GRIDS_Z );

	if ( m_scHelper.GetCUDALastError( "call member function InitBound failed", __FILE__, __LINE__ ) )
	{
		FreeResource();
		exit(1);
	}
};

void FluidSimProc::SaveCurStage( void )
{
};

void FluidSimProc::LoadPreStage( void )
{
};

void FluidSimProc::SolveNavierStokesEquation( cdouble dt, bool add, bool vel, bool dens )
{
	m_scHelper.DeviceParamDim( &gridDim, &blockDim, THREADS_S, TILE_X, TILE_Y, GRIDS_X, GRIDS_Y, GRIDS_Z );

	kernelLoadBullet __device_func__
		( dev_obs, comp_obst,  BULLET_X, BULLET_Y, BULLET_Z, GRIDS_X, GRIDS_Y, GRIDS_Z );

	SolveGlobal( dt, add, vel, dens );
};

void FluidSimProc::SolveGlobal( cdouble dt, bool add, bool vel, bool dens )
{
	printf( "%d   ", t_totaltimes );


	/* duration of adding source */
//	t_start = clock();
	if ( add ) SourceSolverGlobal( dt );
//	t_finish = clock();
//	t_duration = (double)( t_finish - t_start ) / CLOCKS_PER_SEC;
//	printf( "%f ", t_duration );

	/* duration of velocity solver */
//	t_start = clock();
	if ( vel ) VelocitySolverGlobal( dt );
//	t_finish = clock();
//	t_duration = (double)( t_finish - t_start ) / CLOCKS_PER_SEC;
//	printf( "%f ", t_duration );

	/* duration of density solver */
//	t_start = clock();
	if ( dens ) DensitySolverGlobal( dt );
//	t_finish = clock();
//	t_duration = (double)( t_finish - t_start ) / CLOCKS_PER_SEC;
//	printf( "%f ", t_duration );
};