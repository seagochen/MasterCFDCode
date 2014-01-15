/**
* <Author>      Orlando Chen
* <First>       Oct 16, 2013
* <Last>		Jan 07, 2014
* <File>        LaunchMain.cpp
*/

#include <GL\glew32c.h>
#include <GL\freeglut.h>
#include <SGE\SGUtils.h>
#include <GLM\glm.hpp>
#include <GLM\gtc\matrix_transform.hpp>
#include <GLM\gtx\transform2.hpp>
#include <GLM\gtc\type_ptr.hpp>
#include <iostream>
#include <memory>

#include "FluidSimArea.h"
#include "VolumeRendering.h"
#include "resource.h"

using namespace sge;
using namespace std;

fluidsim      m_fluid;
VolumeHelper  m_vh;
FluidSimProc *m_fs;
MainActivity *activity;

#define K_ON     1
#define ROTATION 0

void initialize ()
{
	m_fluid.ray.fStepsize     = 0.001f;
	m_fluid.ray.nAngle        = 0;
	m_fluid.ray.uCanvasWidth  = 600;
	m_fluid.ray.uCanvasHeight = 600;
	m_fluid.ray.bRun          = true;

#if K_ON
	m_fluid.volume.uWidth    = Area_X;
	m_fluid.volume.uHeight   = Area_X;
	m_fluid.volume.uDepth    = Area_X;
	m_fluid.area.uWidth      = Area_X;
	m_fluid.area.uHeight     = Area_X;
	m_fluid.area.uDepth      = Area_X;
#else
	m_fluid.volume.nVolWidth    = 256;
	m_fluid.volume.nVolHeight   = 256;
	m_fluid.volume.nVolDepth    = 225;
	m_vh.LoadVolumeSource ( ".\\res\\head256.raw", &m_fluid );
#endif

	m_fluid.shader.szCanvasVert = ".\\shader\\backface.vert";
	m_fluid.shader.szCanvasFrag = ".\\shader\\backface.frag";
	m_fluid.shader.szVolumVert  = ".\\shader\\raycasting.vert";
	m_fluid.shader.szVolumFrag  = ".\\shader\\raycasting.frag";

//	m_fluid.volume.ptrData = (GLubyte*) calloc ( constparam::nSim_Size, sizeof(GLubyte) );

	/// Prepare the fluid simulation stage ///
	m_fs = new FluidSimProc ( &m_fluid );

	cout << "initial stage finished" << endl;
};

DWORD WINAPI cudaCFD ( LPVOID lpParam )
{
#if K_ON
	/// Solve the fluid simulation ///
	while ( m_fluid.ray.bRun )
	{
		m_fs->FluidSimSolver ( &m_fluid );
	}
#endif

	return 0;
};

std::string string_format(const std::string fmt_str, ...) {
    int final_n, n = fmt_str.size() * 2; /* reserve 2 times as much as the length of the fmt_str */
    std::string str;
    std::unique_ptr<char[]> formatted;
    va_list ap;
    while(1) {
        formatted.reset(new char[n]); /* wrap the plain char array into the unique_ptr */
        strcpy(&formatted[0], fmt_str.c_str());
        va_start(ap, fmt_str);
        final_n = vsnprintf(&formatted[0], n, fmt_str.c_str(), ap);
        va_end(ap);
        if (final_n < 0 || final_n >= n)
            n += abs(final_n - n + 1);
        else
            break;
    }
    return std::string(formatted.get());
}

#pragma region callback functions

void onCreate ()
{
	/// Initialize glew ///
	GLenum error = glewInit ();
	if ( error != GLEW_OK )
	{
		cout << "glewInit failed: " << glewGetErrorString (error) << endl;
		exit (1);
	}

	/// Create sub-thread function ///
	m_fluid.thread.hThread = CreateThread ( 
            NULL,                   // default security attributes
            0,                      // use default stack size  
            cudaCFD,                // thread function name
            NULL,                   // argument to thread function 
            0,                      // use default creation flags 
			&m_fluid.thread.dwThreadId);   // returns the thread identifier

	 if ( m_fluid.thread.hThread == NULL )
	 {
		 cout << "create sub-thread failed" << endl;
		 exit (1);
	 }

	/// Initialize the shader program and textures ///
	m_vh.CreateShaderProg ( &m_fluid );
	m_fluid.textures.hTexture1D   = m_vh.Create1DTransFunc ( m_vh.DefaultTransFunc () );
	m_fluid.textures.hTexture2D   = m_vh.Create2DCanvas ( &m_fluid );
	m_fluid.textures.hTexture3D   = m_vh.Create3DVolumetric ();
	m_fluid.ray.hCluster          = m_vh.InitVerticesBufferObj ();
	m_fluid.textures.hFramebuffer = m_vh.Create2DFrameBuffer ( &m_fluid );

	cout << "initialize finished, sge will start soon!" << endl;
};

void CountFPS()
{
	// Counting FPS
	m_fluid.fps.dwFrames ++;
	m_fluid.fps.dwCurrentTime = GetTickCount();
	m_fluid.fps.dwElapsedTime = m_fluid.fps.dwCurrentTime - m_fluid.fps.dwLastUpdateTime;

	// 1 second
	if ( m_fluid.fps.dwElapsedTime >= 1000 )
	{
		m_fluid.fps.uFPS     = m_fluid.fps.dwFrames * 1000 / m_fluid.fps.dwElapsedTime;
		m_fluid.fps.dwFrames = 0;
		m_fluid.fps.dwLastUpdateTime = m_fluid.fps.dwCurrentTime;
	}

	const char *szTitle = "Excalibur OTL 1.00.00 alpha test  |  FPS: %d  |  static tracking  |";
	SetWindowText (	activity->GetHWND(), string_format ( szTitle, m_fluid.fps.uFPS ).c_str() );
}

void onDisplay ()
{
	glEnable ( GL_DEPTH_TEST );
	
	/// Bind the vertex buffer object to shader with attribute "vertices" ///
	glBindAttribLocation ( m_fluid.shader.hProgram, 0, "vertices" );

    /// Do Render Now! ///
	glBindFramebuffer ( GL_DRAW_FRAMEBUFFER, m_fluid.textures.hFramebuffer );
	glViewport ( 0, 0, m_fluid.ray.uCanvasWidth, m_fluid.ray.uCanvasHeight );
	m_fluid.shader.ptrShader->LinkShaders 
		( m_fluid.shader.hProgram, 2, m_fluid.shader.hBFVert, m_fluid.shader.hBFFrag );
	m_fluid.shader.ptrShader->ActiveProgram ( m_fluid.shader.hProgram );
	m_vh.RenderingFace ( GL_FRONT, &m_fluid );
	m_fluid.shader.ptrShader->DeactiveProgram ( m_fluid.shader.hProgram );

	/// Do not bind the framebuffer now ///
    glBindFramebuffer ( GL_FRAMEBUFFER, 0 );

	glViewport ( 0, 0, m_fluid.ray.uCanvasWidth, m_fluid.ray.uCanvasHeight );
	m_fluid.shader.ptrShader->LinkShaders 
		( m_fluid.shader.hProgram, 2, m_fluid.shader.hRCVert, m_fluid.shader.hRCFrag );
	m_fluid.shader.ptrShader->ActiveProgram ( m_fluid.shader.hProgram );
	m_vh.SetVolumeInfoUinforms ( &m_fluid );
	m_vh.RenderingFace ( GL_BACK, &m_fluid );
	m_fluid.shader.ptrShader->DeactiveProgram ( m_fluid.shader.hProgram );

#if ROTATION
	m_fluid.drawing.nAngle = (m_fluid.drawing.nAngle + 1) % 360;
#endif
	CountFPS ();
};

void onDestroy ()
{
	m_fluid.ray.bRun = false;
	WaitForSingleObject ( m_fluid.thread.hThread, INFINITE );
	CloseHandle ( m_fluid.thread.hThread );

	m_fs->FreeResourcePtrs();  
	SAFE_FREE_PTR ( m_fs );
	SAFE_FREE_PTR ( m_fluid.shader.ptrShader );

	cout << "memory freed, program exits..." << endl;
	exit(1);
};

void onKeyboard ( SG_KEYS keys, SG_KEY_STATUS status )
{
	if ( status == SG_KEY_STATUS::SG_KEY_DOWN )
	{
		switch (keys)
		{
		case sge::SG_KEY_Q:
		case sge::SG_KEY_ESCAPE:
			onDestroy();
			break;
		
		case sge::SG_KEY_C:
			m_fs->ZeroData();
			break;
		
		default:
			break;
		}
	}
};

void onMouse ( SG_MOUSE mouse, uint x, uint y, int degree )
{
	if ( mouse eqt SG_MOUSE_WHEEL_FORWARD or mouse eqt SG_MOUSE_WHEEL_BACKWARD )
	{
		m_fluid.ray.nAngle = (m_fluid.ray.nAngle + degree) % 360;
	}
};

#pragma endregion

int main()
{
	initialize ();

	activity = new MainActivity ( m_fluid.ray.uCanvasWidth, m_fluid.ray.uCanvasHeight );

	activity->SetAppClientInfo ( IDI_ICON1, IDI_ICON1 );
	activity->RegisterCreateFunc ( onCreate );
	activity->RegisterDisplayFunc ( onDisplay );
	activity->RegisterMouseFunc ( onMouse );
	activity->RegisterDestroyFunc ( onDestroy );
	activity->RegisterKeyboardFunc ( onKeyboard );
	
	activity->SetupRoutine();
}