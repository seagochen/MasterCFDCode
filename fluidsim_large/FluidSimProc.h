/**
* <Author>        Orlando Chen
* <Email>         seagochen@gmail.com
* <First Time>    Dec 15, 2013
* <Last Time>     Mar 07, 2014
* <File Name>     FluidSimProc.h
*/


#ifndef __fluid_simulation_process_h_
#define __fluid_simulation_process_h_

#include <GL\glew.h>
#include <GL\freeglut.h>
#include <SGE\SGUtils.h>
#include <vector>
#include "FunctionHelper.h"
#include "FrameworkDynamic.h"

using std::vector;

namespace sge
{
	class FluidSimProc
	{
	private:
		struct SimNode
		{
			SGBOOLEAN updated;
			SGINT3 nodeIX;
			SimNode *ptrLeft, *ptrRight, *ptrUp, *ptrDown, *ptrFront, *ptrBack;
		};

	private:
		/* temporary buffers for fluid simulation */
		vector <double*> dev_buffers;

		/* nodes for gpu and host */
		vector <double*> dev_density,    host_density;
		vector <double*> dev_velocity_u, host_velocity_u;
		vector <double*> dev_velocity_v, host_velocity_v;
		vector <double*> dev_velocity_w, host_velocity_w;
		vector <double*> dev_obstacle,   host_obstacle;

		/* local nodes */
		vector <double*> node_density;
		vector <double*> node_velocity_u;
		vector <double*> node_velocity_v;
		vector <double*> node_velocity_w;
		vector <double*> node_obstacle;

		/* topology of nodes on host and device */
		vector <SimNode*> gpu_node, host_node;

		/* visualization */
		SGUCHAR *dev_visual, *host_visual;

		/* temporary buffers for some purpose */
		double *dev_dtpbuf, *host_dtpbuf;
		int    *dev_ntpbuf, *host_ntpbuf;

		/* cursor */
		SGINT3 m_cursor;

		/* CUDA */
		dim3 gridDim, blockDim;

		/* node and volumetric size */
		size_t m_node_size, m_volm_size;

		/* title bar */
		std::string m_sz_title;

		/* etc. */
		int increase_times, decrease_times;

	private:
		FunctionHelper helper;

	public:
		FluidSimProc( FLUIDSPARAM *fluid );

		/* fluid simulation processing function */
		void FluidSimSolver( FLUIDSPARAM *fluid );

		/* when program existed, release resource */
		void FreeResource( void );

		/* zero the buffers for fluid simulation */
		void ZeroBuffers( void );

		/* title bar */
		ptrStr GetTitleBar( void );

		/* print runtime message */
		void PrintMSG( void );

		/* upload buffers */
		void IO_UploadBuffers( void );

		/* download buffers */
		void IO_DownloadBuffers( void );

	private:
		/* IO, host to device */
		void IO_ReadBuffers( void );

		/* IO, device to host */
		void IO_WriteBuffers( void );

		/* loading gpu nodes for fluid simulation */
		void LoadNode( int i, int j, int k );

		/* saving the result of fluid simulation */
		void SaveNode( int i, int j, int k );

		/* solving the Navier-Stokers equations */
		void SolveNavierStokers( void );

		/* flood buffer for multiple nodes */
		void Interaction( int i, int j, int k );

		/* initialize FPS and etc. */
		void InitParams( FLUIDSPARAM *fluid );
			
		/* retrieve the density back and load into volumetric data for rendering */
		void RefreshStatus( FLUIDSPARAM *fluid );
		
		/* create simulation nodes' topological structure */
		void CreateTopology( void );

		/* allocate resource */
		bool AllocateResource( FLUIDSPARAM *fluid );

		/* solving density */
		void DensitySolver( void );

		/* add source */
		void AddSource( void );

		/* initialize boundary condition */
		void InitBoundary( void );

		/* solving velocity */
		void VelocitySolver( void );
	};
};

#endif