/**
* <Author>        Orlando Chen
* <Email>         seagochen@gmail.com
* <First Time>    Dec 15, 2013
* <Last Time>     Mar 01, 2014
* <File Name>     FluidSimProcKernels.cu
*/

#include <iostream>
#include <utility>
#include "FluidSimulationKernels.h"
#include "CUDATracingKernels.h"

using namespace sge;

__global__ void kernelCopyGrids( double *dst, const double *src )
{
	GetIndex();

	dst[Index(i,j,k)] = src[Index(i,j,k)];
};

__global__ void kernelZeroGrids( double *grid )
{
	GetIndex ();
	grid [ Index(i,j,k) ] = 0.f;
};

__global__ void kernelZeroVolumetric( SGUCHAR *visual )
{
	GetIndex();

	for ( int ii = 0; ii < NODE_X; ii++ )
	{
		for ( int jj = 0; jj < NODE_X; jj++ )
		{
			for ( int kk = 0; kk < NODE_X; kk++ )
			{
				int di = ii * GRID_X + i;
				int dj = jj * GRID_X + j;
				int dk = kk * GRID_X + k;
				
				/* zero data */
				visual[ Index3D(di, dj, dk, VOLUME_X) ] = 0;
			}
		}
	}
};

__global__ void kernelZeroTemporaryBuffers( double *bufs )
{
	GetIndex();

	bufs[threadIdx.x] = 0.f;
};

__global__ void kernelZeroTemporaryBuffers( int *bufs )
{
	bufs[threadIdx.x] = 0;
};

__global__ void kernelPickData
( SGUCHAR *data, const double *bufs, const int offseti, const int offsetj, const int offsetk )
{
	GetIndex();

	int di = offseti + i;
	int dj = offsetj + j;
	int dk = offsetk + k;

	/* zero data first */
	data[ Index3D(di, dj, dk, VOLUME_X) ] = 0;

	/* retrieve data from grid */
	double value = bufs[ Index(i, j, k) ];

	/* append data to volume data */
	int temp = atomicRound( value );
	if ( temp > 0 and temp < 250 )
		data [ Index3D(di, dj, dk, VOLUME_X) ] = (unsigned char) temp;
};

__global__ void kernelSmoothVolumetric (SGUCHAR *visual)
{
	int i = blockIdx.x * blockDim.x + threadIdx.x;
	int j = blockIdx.y * blockDim.y + threadIdx.y;
	int k = 0;
	cudaTrans2DTo3D( i, j, k, 192 );

	if ( i > 0 and i < 191 and  j > 0 and j < 191 and  k > 0 and k < 191 )
	{
		SGUCHAR center = visual[Index3D(i,j,k, 192)];
		SGUCHAR left   = visual[Index3D(i-1,j,k,192)];
		SGUCHAR right  = visual[Index3D(i+1,j,k,192)];
		SGUCHAR up     = visual[Index3D(i,j+1,k,192)];
		SGUCHAR down   = visual[Index3D(i,j-1,k,192)];
		SGUCHAR front  = visual[Index3D(i,j,k+1,192)];
		SGUCHAR back   = visual[Index3D(i,j,k-1,192)];

		visual[Index3D(i,j,k,192)] = ( center + (left + right + up + down + front + back) / 6.f );
	}
	else
		visual[Index3D(i,j,k,192)] = 0;
};

__global__ void kernelUpLoadToSlot
	( double *slot, double const *grid, double const *grid_U, double const *grid_D,
	double const *grid_L, double const *grid_R, double const *grid_F, double const *grid_B )
{
	GetIndex();

	int si = i + 1;
	int sj = j + 1;
	int sk = k + 1;
	const int header = 0;
	const int tailer = SLOT_X - 1;

	slot[ Index3D(si, sj, sk, SLOT_X) ] = grid[ Index(i,j,k) ];

	slot[ Index3D(header, sj, sk, SLOT_X) ] = grid_L[ Index(gst_tailer, j, k) ];
	slot[ Index3D(tailer, sj, sk, SLOT_X) ] = grid_R[ Index(gst_header, j, k) ];
	slot[ Index3D() ]
}

FluidSimProc::FluidSimProc ( FLUIDSPARAM *fluid )
{
	/* initialize FPS */
	InitParams( fluid );

	/* allocate resources */
	if ( !AllocateResource ( fluid ) ) { FreeResource (); exit (1); }

	/* build order */
	BuildOrder();

#if !TESTING_MODE_SWITCH
	/* select node */
	ActiveTheNode( 1, 0, 1 );

	/* clear buffer */
	ZeroBuffers();

	/* set boundary */
	InitBoundary( 1, 0, 1 );
#else
	/* select node */
	ActiveTheNode( 1, 1, 1 );

	/* clear buffer */
	ZeroBuffers();

	/* set boundary */
	InitBoundary( 1, 1, 1 );
#endif

	/* upload buffers */
	UploadBuffers();

	/* finally, print message */
	printf( "fluid simulation ready...\n" );
};

void FluidSimProc::UploadBuffers()
{
	for ( int i = 0; i < NODE_X * NODE_X * NODE_X; i++ )
	{
		cudaMemcpy( dev_density[i], host_density[i], m_node_size, cudaMemcpyHostToDevice );
		cudaMemcpy( dev_velocity_u[i], host_velocity_u[i], m_node_size, cudaMemcpyHostToDevice );
		cudaMemcpy( dev_velocity_v[i], host_velocity_v[i], m_node_size, cudaMemcpyHostToDevice );
		cudaMemcpy( dev_velocity_w[i], host_velocity_w[i], m_node_size, cudaMemcpyHostToDevice );
		cudaMemcpy( dev_obstacle[i], host_obstacle[i], m_node_size, cudaMemcpyHostToDevice );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit(1);
		}
	}
};

void FluidSimProc::InitParams( FLUIDSPARAM *fluid )
{
	fluid->fps.dwCurrentTime = 0;
	fluid->fps.dwElapsedTime = 0;
	fluid->fps.dwFrames = 0;
	fluid->fps.dwLastUpdateTime = 0;
	fluid->fps.uFPS = 0;

	m_node_size = GRID_X * GRID_X * GRID_X * sizeof(double);
	m_volm_size = VOLUME_X * VOLUME_X * VOLUME_X * sizeof(SGUCHAR);
	m_slot_size = SLOT_X * SLOT_X * SLOT_X * sizeof(double);

	increase_times = decrease_times = 0;
	dTimes = 0.f;
};

void FluidSimProc::BuildOrder( void )
{
	for ( int k = 0; k < NODE_X; k++ )
	{
		for ( int j = 0; j < NODE_X; j++ )
		{
			for ( int i = 0; i < NODE_X; i++ )
			{
				/* left */
				if ( i >= 1 )
					host_node[Index3D( i, j, k, NODE_X )]->ptrLeft  = host_node[Index3D( i-1, j, k, NODE_X )];
				/* right */
				if ( i <= NODE_X - 2 )
					host_node[Index3D( i, j, k, NODE_X )]->ptrRight = host_node[Index3D( i+1, j, k, NODE_X )];
				/* down */
				if ( j >= 1 )
					host_node[Index3D( i, j, k, NODE_X )]->ptrDown  = host_node[Index3D( i, j-1, k, NODE_X )];
				/* up */
				if ( j <= NODE_X - 2 )
					host_node[Index3D( i, j, k, NODE_X )]->ptrUp    = host_node[Index3D( i, j+1, k, NODE_X )];
				/* back */
				if ( k >= 1 )
					host_node[Index3D( i, j, k, NODE_X )]->ptrBack  = host_node[Index3D( i, j, k-1, NODE_X )];
				/* front */
				if ( k <= NODE_X - 2 )
					host_node[Index3D( i, j, k, NODE_X )]->ptrFront = host_node[Index3D( i, j, k+1, NODE_X )];

				host_node[Index3D( i, j, k, NODE_X )]->nodeIX.x = i;
				host_node[Index3D( i, j, k, NODE_X )]->nodeIX.y = j;
				host_node[Index3D( i, j, k, NODE_X )]->nodeIX.z = k;
			}
		}
	}

	for ( int i = 0; i < NODE_X; i++ )
	{
		for ( int j = 0; j < NODE_X; j++ )
		{
			for ( int k = 0; k < NODE_X; k++ )
			{
				printf ( "offset: %d %d %d | L: %d | R: %d | U: %d | D: %d | F: %d | B: %d \n",
					host_node[Index3D( i, j, k, NODE_X )]->nodeIX.x, 
					host_node[Index3D( i, j, k, NODE_X )]->nodeIX.y, 
					host_node[Index3D( i, j, k, NODE_X )]->nodeIX.z,
					host_node[Index3D( i, j, k, NODE_X )]->ptrLeft not_eq nullptr,
					host_node[Index3D( i, j, k, NODE_X )]->ptrRight not_eq nullptr,
					host_node[Index3D( i, j, k, NODE_X )]->ptrUp not_eq nullptr,
					host_node[Index3D( i, j, k, NODE_X )]->ptrDown not_eq nullptr,
					host_node[Index3D( i, j, k, NODE_X )]->ptrFront not_eq nullptr,
					host_node[Index3D( i, j, k, NODE_X )]->ptrBack not_eq nullptr );
			}
		}
	}
};

bool FluidSimProc::AllocateResource ( FLUIDSPARAM *fluid )
{
	/* choose which GPU to run on, change this on a multi-GPU system. */
	if ( cudaSetDevice ( 0 ) != cudaSuccess )
	{
		helper.GetCUDALastError ( "cudaSetDevices", __FILE__, __LINE__ );
		return false;
	}

	/* allocate memory on host */
	for ( int i = 0; i < NODE_X * NODE_X * NODE_X; i++ )
	{
		double *ptrDens, *ptrU, *ptrV, *ptrW, *ptrObs;

		if ( helper.CreateHostBuffers( m_node_size, 1, &ptrDens ) not_eq SG_RUNTIME_OK )
			return false;
		if ( helper.CreateHostBuffers( m_node_size, 1, &ptrU ) not_eq SG_RUNTIME_OK )
			return false;
		if ( helper.CreateHostBuffers( m_node_size, 1, &ptrV ) not_eq SG_RUNTIME_OK )
			return false;
		if ( helper.CreateHostBuffers( m_node_size, 1, &ptrW ) not_eq SG_RUNTIME_OK )
			return false;
		if ( helper.CreateHostBuffers( m_node_size, 1, &ptrObs ) not_eq SG_RUNTIME_OK )
			return false;

		/* simulation nodes */
		SimNode *node = (SimNode*)malloc(sizeof(SimNode));
		node->ptrFront = node->ptrBack = nullptr;
		node->ptrLeft = node->ptrRight = nullptr;
		node->ptrDown = node->ptrUp = nullptr;
		host_node.push_back( node );

		node->active = false;

		host_density.push_back( ptrDens );
		host_velocity_u.push_back( ptrU );
		host_velocity_v.push_back( ptrV );
		host_velocity_w.push_back( ptrW );
		host_obstacle.push_back( ptrObs );
	}

	/* allocate memory on GPU */
	for ( int i = 0; i < NODE_X * NODE_X * NODE_X; i++ )
	{
		double *ptrDens, *ptrU, *ptrV, *ptrW, *ptrObs;

		if ( helper.CreateDeviceBuffers( m_node_size, 1, &ptrDens ) not_eq SG_RUNTIME_OK )
			return false;
		if ( helper.CreateDeviceBuffers( m_node_size, 1, &ptrU ) not_eq SG_RUNTIME_OK )
			return false;
		if ( helper.CreateDeviceBuffers( m_node_size, 1, &ptrV ) not_eq SG_RUNTIME_OK )
			return false;
		if ( helper.CreateDeviceBuffers( m_node_size, 1, &ptrW ) not_eq SG_RUNTIME_OK )
			return false;
		if ( helper.CreateDeviceBuffers( m_node_size, 1, &ptrObs ) not_eq SG_RUNTIME_OK )
			return false;

		dev_density.push_back( ptrDens );
		dev_velocity_u.push_back( ptrU );
		dev_velocity_v.push_back( ptrV );
		dev_velocity_w.push_back( ptrW );
		dev_obstacle.push_back( ptrObs );
	}

	/* allocate memory on GPU devices */
	for ( int i = 0; i < dev_buffers_num; i++ )
	{
		double *ptr;
		if ( helper.CreateDeviceBuffers( m_node_size, 1, &ptr ) not_eq SG_RUNTIME_OK )
			return false;

		dev_buffers.push_back(ptr);
	}

	/* allocate slot */
	for ( int i = 0; i < dev_slot_num; i++ )
	{
		double *ptr;
		if ( helper.CreateDeviceBuffers( m_slot_size, 1, &ptr ) not_eq SG_RUNTIME_OK )
			return false;

		dev_slot.push_back(ptr);
	}


	/* allocate visual buffers */
	if ( helper.CreateDeviceBuffers( m_volm_size, 1, &dev_visual ) not_eq SG_RUNTIME_OK )
		return false;
	if ( helper.CreateHostBuffers( m_volm_size, 1, &host_visual ) not_eq SG_RUNTIME_OK )
		return false;

	/* allocate temporary buffers */
	if ( helper.CreateDeviceBuffers( sizeof(double)*TPBUFFER_X, 1, &dev_tpbufs ) not_eq SG_RUNTIME_OK )
		return false;
	if ( helper.CreateHostBuffers(sizeof(double)*TPBUFFER_X, 1, &host_tpbufs ) not_eq SG_RUNTIME_OK )
		return false;

	/* finally */
	return true;
}  

void FluidSimProc::FreeResource ( void )
{
	/* free host resource */
	for ( int i = 0; i < NODE_X * NODE_X * NODE_X; i++ )
	{
		helper.FreeHostBuffers( 5, &host_density[i], &host_velocity_u[i], &host_velocity_v[i], &host_velocity_w[i], &host_obstacle[i] );
		helper.FreeDeviceBuffers( 5, &dev_density[i], &dev_velocity_u[i], &dev_velocity_v[i], &dev_velocity_w[i], &dev_obstacle[i] );
	}

	/* free device resource */
	for ( int i = 0; i < dev_buffers_num; i++ )
	{
		helper.FreeDeviceBuffers( 1, &dev_buffers[i] );
	}

	/* free slot buffers */
	for ( int i = 0; i < dev_slot_num; i++ )
	{
		helper.FreeDeviceBuffers( 1, &dev_slot[i] );
	}

	/* free... */
	helper.FreeHostBuffers( 2, &host_visual, &host_tpbufs );
	helper.FreeDeviceBuffers( 2, &dev_visual, &dev_tpbufs );
}

bool FluidSimProc::ActiveTheNode( int i, int j, int k )
{
	int ix;
	if ( i >= 0 and i < NODE_X and j >= 0 and j < NODE_X and k >= 0 and k < NODE_X )
	{
		ix = Index3D( i, j, k, NODE_X );
		host_node[ix]->active = true;
	}

	return host_node[ix]->active == true;
};

bool FluidSimProc::DeactiveTheNode( int i, int j, int k )
{
	int ix;
	if ( i >= 0 and i < NODE_X and j >= 0 and j < NODE_X and k >= 0 and k < NODE_X )
	{
		ix = Index3D( i, j, k, NODE_X );
		host_node[ix]->active = false;
	}

	return host_node[ix]->active == false;
};

void FluidSimProc::FluidSimSolver( FLUIDSPARAM *fluid )
{
	if ( !fluid->run ) return;

	for ( int i = 0; i < NODE_X; i++ )
	{
		for ( int j = 0; j < NODE_X; j++ )
		{
			for ( int k = 0; k < NODE_X; k++ )
			{
				/* for fluid simulation, copy the data to device */
				NodeToDevice( i, j, k );

				/* tracing */
				TracingTheFlow( i, j, k );
				
				/* Fluid process */
				AddSource();
				VelocitySolver();
				DensitySolver();

				/* retrieve data back to host */
				DeviceToNode( i, j, k );
			}
		}
	}
	/* finally, generate volumetric image */
	GetVolumetric( fluid );
};

void FluidSimProc::GetVolumetric( FLUIDSPARAM *fluid )
{
	/* smooth data */
	cudaDeviceDim3D();

	/* smooth the final image */
	for ( int i = 0; i < NODE_X; i++ ) for ( int j = 0; j < NODE_X; j++ ) for ( int k = 0; k < NODE_X; k++ )
		kernelFloodBound <<<gridDim, blockDim>>> ( dev_visual, i, j, k );
	kernelSmoothVolumetric <<<gridDim, blockDim>>> ( dev_visual );
	
	/* retrieve and rendering data */
	if ( cudaThreadSynchronize() not_eq cudaSuccess )
	{
		printf( "cudaThreadSynchronize failed\n" );
		FreeResource();
		exit( 1 );
	}

	cudaMemcpy( host_visual, dev_visual, m_volm_size, cudaMemcpyDeviceToHost );
	fluid->volume.ptrData = host_visual;
};

void FluidSimProc::NodeToDevice ( int i, int j, int k )
{
	/* navigate the node's position */
	SimNode *ptr = host_node[Index3D( i, j, k, NODE_X )];
	int ix = Index3D( i, j, k, NODE_X );

	/* upload center node */
	cudaDeviceDim3D();
	kernelCopyGrids <<<gridDim, blockDim>>> ( dev_u, dev_velocity_u[ix] );
	kernelCopyGrids <<<gridDim, blockDim>>> ( dev_v, dev_velocity_v[ix] );
	kernelCopyGrids <<<gridDim, blockDim>>> ( dev_w, dev_velocity_w[ix] );
	kernelCopyGrids <<<gridDim, blockDim>>> ( dev_den, dev_density[ix] );
	kernelCopyGrids <<<gridDim, blockDim>>> ( dev_obs, dev_obstacle[ix] );

	if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
	{
		FreeResource();
		exit( 1 );
	}

	/* upload neighbouring buffers to GPU device */
	if ( ptr->ptrLeft )
	{
		ix = Index3D( i-1, j, k, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velu_L, dev_velocity_u[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velv_L, dev_velocity_v[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velw_L, dev_velocity_w[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dens_L, dev_density[ix] );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	if ( ptr->ptrRight )
	{
		ix = Index3D( i+1, j, k, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velu_R, dev_velocity_u[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velv_R, dev_velocity_v[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velw_R, dev_velocity_w[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dens_R, dev_density[ix] );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	if ( ptr->ptrUp )
	{
		ix = Index3D( i, j+1, k, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velu_U, dev_velocity_u[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velv_U, dev_velocity_v[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velw_U, dev_velocity_w[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dens_U, dev_density[ix] );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	if ( ptr->ptrDown )
	{
		ix = Index3D( i, j-1, k, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velu_D, dev_velocity_u[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velv_D, dev_velocity_v[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velw_D, dev_velocity_w[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dens_D, dev_density[ix] );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	if ( ptr->ptrFront )
	{
		ix = Index3D( i, j, k+1, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velu_F, dev_velocity_u[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velv_F, dev_velocity_v[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velw_F, dev_velocity_w[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dens_F, dev_density[ix] );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	if ( ptr->ptrBack )
	{
		ix = Index3D( i, j, k-1, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velu_B, dev_velocity_u[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velv_B, dev_velocity_v[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( velw_B, dev_velocity_w[ix] );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dens_B, dev_density[ix] );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}
};

void FluidSimProc::DeviceToNode ( int i, int j, int k )
{
	/* navigate the node's position */
	SimNode *ptr = host_node[Index3D( i, j, k, NODE_X )];
	int ix = Index3D( i, j, k, NODE_X );

	/* draw data back */
	cudaDeviceDim3D();

	kernelCopyGrids <<<gridDim, blockDim>>> ( dev_density[ix], dev_den );
	kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_u[ix], dev_u );
	kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_v[ix], dev_v );
	kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_w[ix], dev_w );

	if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
	{
		FreeResource();
		exit( 1 );
	}

	/* draw neighbouring buffers back */
	if ( ptr->ptrLeft )
	{
		ix = Index3D( i-1, j, k, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_density[ix], dens_L );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_u[ix], velu_L );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_v[ix], velv_L );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_w[ix], velw_L );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	if ( ptr->ptrRight )
	{
		ix = Index3D( i+1, j, k, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_density[ix], dens_R );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_u[ix], velu_R );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_v[ix], velv_R );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_w[ix], velw_R );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	if ( ptr->ptrUp )
	{
		ix = Index3D( i, j+1, k, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_density[ix], dens_U );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_u[ix], velu_U );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_v[ix], velv_U );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_w[ix], velw_U );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	if ( ptr->ptrDown )
	{
		ix = Index3D( i, j-1, k, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_density[ix], dens_D );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_u[ix], velu_D );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_v[ix], velv_D );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_w[ix], velw_D );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	if ( ptr->ptrFront )
	{
		ix = Index3D( i, j, k+1, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_density[ix], dens_F );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_u[ix], velu_F );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_v[ix], velv_F );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_w[ix], velw_F );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	if ( ptr->ptrBack )
	{
		ix = Index3D( i, j, k-1, NODE_X );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_density[ix], dens_B );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_u[ix], velu_B );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_v[ix], velv_B );
		kernelCopyGrids <<<gridDim, blockDim>>> ( dev_velocity_w[ix], velw_B );

		if ( helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit( 1 );
		}
	}

	/* draw volumetric data back */
	kernelPickData <<<gridDim, blockDim>>>
		( dev_visual, dev_den, i * GRID_X, j * GRID_X, k * GRID_X );

	/* zero buffers */
	for ( int i = 0; i < dev_buffers_num; i++ )
		kernelZeroGrids <<<gridDim, blockDim>>> ( dev_buffers[i] );
};

void FluidSimProc::AddSource( void )
{
	if ( decrease_times eqt 0 )
	{
		if ( (increase_times % 10) eqt 0 ) dTimes += 0.7f;

		cudaDeviceDim3D();
		kernelAddSource<<<gridDim, blockDim>>> ( dev_den, dev_u, dev_v, dev_w, dev_obs, dTimes );
		increase_times++;

		if ( increase_times eqt 200 )
		{
			decrease_times = increase_times;
			increase_times = 0;
		}
	}
	else
	{
		decrease_times--;
		dTimes = 1.f;
	}
};

void FluidSimProc::InitBoundary( int i, int j, int k )
{
	cudaDeviceDim3D();

	/* zero boundary buffers */
	kernelZeroGrids<<<gridDim, blockDim>>>( dev_obs );

	for ( int i = 0; i < host_obstacle.size(); i++ )
	{
		if ( cudaMemcpy( host_obstacle[i], dev_obs,
			m_node_size, cudaMemcpyDeviceToHost ) not_eq cudaSuccess )
		{
			helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ );
			FreeResource();
			exit( 1 );
		}
	}
	
	const int ix = Index3D( i, j, k, NODE_X );

	/* set boundary */
	kernelSetBoundary<<<gridDim, blockDim>>>( dev_obs );
	
	if ( cudaMemcpy( host_obstacle[ix], dev_obs,
		m_node_size, cudaMemcpyDeviceToHost) not_eq cudaSuccess )
	{
		helper.GetCUDALastError( "cudaMemcpy failed", __FILE__, __LINE__ );
		FreeResource();
		exit( 1 );
	}
};

void FluidSimProc::VelocitySolver( void )
{
	// diffuse the velocity field (per axis):
	hostDiffusion( dev_u0, dev_u, VISOCITY, dev_obs, MACRO_VELOCITY_U );
	hostDiffusion( dev_v0, dev_v, VISOCITY, dev_obs, MACRO_VELOCITY_V );
	hostDiffusion( dev_w0, dev_w, VISOCITY, dev_obs, MACRO_VELOCITY_W );
	
	std::swap( dev_u0, dev_u );
	std::swap( dev_v0, dev_v );
	std::swap( dev_w0, dev_w );

	// stabilize it: (vx0, vy0 are whatever, being used as temporaries to store gradient field)
	hostProject( dev_u, dev_v, dev_w, dev_div, dev_p, dev_obs );
	
	// advect the velocity field (per axis):
	hostAdvection( dev_u0, dev_u, dev_obs, MACRO_VELOCITY_U, dev_u, dev_v, dev_w );
	hostAdvection( dev_v0, dev_v, dev_obs, MACRO_VELOCITY_V, dev_u, dev_v, dev_w );
	hostAdvection( dev_w0, dev_w, dev_obs, MACRO_VELOCITY_W, dev_u, dev_v, dev_w );
	std::swap( dev_u0, dev_u );
	std::swap( dev_v0, dev_v );
	std::swap( dev_w0, dev_w );
	
	// stabilize it: (vx0, vy0 are whatever, being used as temporaries to store gradient field)
	hostProject( dev_u, dev_v, dev_w, dev_div, dev_p, dev_obs );
};

void FluidSimProc::DensitySolver( void )
{
	hostDiffusion( dev_den0, dev_den, DIFFUSION, dev_obs, MACRO_DENSITY );
	std::swap( dev_den0, dev_den );
	hostAdvection ( dev_den, dev_den0, dev_obs, MACRO_DENSITY, dev_u, dev_v, dev_w );
};

void FluidSimProc::ZeroBuffers( void )
{
	cudaDeviceDim3D();

	/* zero host buffer */
	for ( int i = 0; i < NODE_X * NODE_X * NODE_X; i++ )
	{
		cudaMemcpy( dev_density[i],    host_density[i],    m_node_size, cudaMemcpyHostToDevice );
		cudaMemcpy( dev_velocity_u[i], host_velocity_u[i], m_node_size, cudaMemcpyHostToDevice );
		cudaMemcpy( dev_velocity_v[i], host_velocity_v[i], m_node_size, cudaMemcpyHostToDevice );
		cudaMemcpy( dev_velocity_w[i], host_velocity_w[i], m_node_size, cudaMemcpyHostToDevice );
		cudaMemcpy( dev_obstacle[i],   host_obstacle[i],   m_node_size, cudaMemcpyHostToDevice );

		if ( helper.GetCUDALastError( "cudaMemcpy failed when zero buffers", __FILE__, __LINE__ ) )
		{
			FreeResource();
			exit(1);
		}
	}
	
	/* zero GPU buffer */
	for ( int i = 0; i < dev_buffers_num; i++ ) 
		kernelZeroGrids <<<gridDim, blockDim>>> ( dev_buffers[i] );

	/* zero visual buffer */
	kernelZeroVolumetric <<< gridDim, blockDim>>> ( dev_visual );
	cudaMemcpy( host_visual, dev_visual, m_volm_size, cudaMemcpyDeviceToHost );
};

void FluidSimProc::TracingTheFlow( int i, int j, int k )
{
	cudaDeviceDim3D();

	/* flooding data */
	kernelFloodingBuffers <<<gridDim, blockDim>>> ( dens_L, dens_R, dens_U, dens_D, dens_F, dens_B, dens_C );
	kernelFloodingBuffers <<<gridDim, blockDim>>> ( velu_L, velu_R, velu_U, velu_D, velu_F, velu_B, velu_C );
	kernelFloodingBuffers <<<gridDim, blockDim>>> ( velv_L, velv_R, velv_U, velv_D, velv_F, velv_B, velv_C );
	kernelFloodingBuffers <<<gridDim, blockDim>>> ( velw_L, velw_R, velw_U, velw_D, velw_F, velw_B, velw_C );

	/* zero buffers if they not exists */
	SimNode *ptr = host_node[Index3D( i, j, k, NODE_X )];

	if ( !ptr->ptrLeft )
	{
		kernelZeroGrids <<<gridDim, blockDim>>> ( dens_L );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velu_L );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velv_L );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velw_L );
	}
	if ( !ptr->ptrRight )
	{
		kernelZeroGrids <<<gridDim, blockDim>>> ( dens_R );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velu_R );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velv_R );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velw_R );
	}
	if ( !ptr->ptrUp )
	{
		kernelZeroGrids <<<gridDim, blockDim>>> ( dens_U );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velu_U );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velv_U );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velw_U );
	}
	if ( !ptr->ptrDown )
	{
		kernelZeroGrids <<<gridDim, blockDim>>> ( dens_D );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velu_D );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velv_D );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velw_D );	
	}
	if ( !ptr->ptrFront )
	{
		kernelZeroGrids <<<gridDim, blockDim>>> ( dens_F );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velu_F );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velv_F );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velw_F );
	}
	if ( !ptr->ptrBack )
	{
		kernelZeroGrids <<<gridDim, blockDim>>> ( dens_B );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velu_B );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velv_B );
		kernelZeroGrids <<<gridDim, blockDim>>> ( velw_B );
	}
};