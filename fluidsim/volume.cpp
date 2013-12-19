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
* <First>       Dec 16, 2013
* <Last>		Dec 18, 2013
* <File>        volume.cpp
*/

#include <GL\glew.h>
#include <GL\freeglut.h>

#include <GLM\glm.hpp>
#include <GLM\gtc\matrix_transform.hpp>
#include <GLM\gtx\transform2.hpp>
#include <GLM\gtc\type_ptr.hpp>

#include "funcdef.h"


bool CheckHandleError ( int nShaderObjs, ... )
{
	if ( nShaderObjs < 1 )
	{
		cout << "call this function must specified the number of shader objects first and then pass the value" << endl;
		return false;
	}
	
	va_list list; int i = 1; bool fin = true;
	va_start ( list, nShaderObjs );
	{
		for ( ; i <= nShaderObjs; i++ )
		{
			GLuint value = va_arg ( list, GLuint );
			if ( value == 0 )
			{
				cout << "Error> the No." << i << " handle is null" << endl;
				fin = false;
			}
		}
		cout << "handle checker is finished" << endl;
	}
	va_end ( list );

	return fin;
};


void CreateShaders ( fluidsim *fluid )
{
	// Temporary ptrs just for convenient
	Shader *shader_out =  fluid->ptrShader;
	GLuint *prog_out   = &fluid->hProgram;
	GLuint *bfVert_out = &fluid->hBFVert;
	GLuint *bfFrag_out = &fluid->hBFFrag;
	GLuint *rcVert_out = &fluid->hRCVert;
	GLuint *rcFrag_out = &fluid->hRCFrag;

	// Create shader helper
	shader_out = new Shader();

	// Create shader objects from source
	shader_out->CreateShaderObj ( ".\\shader\\backface.vert", SG_VERTEX, bfVert_out );
	shader_out->CreateShaderObj ( ".\\shader\\backface.frag", SG_FRAGMENT, bfFrag_out );
	shader_out->CreateShaderObj ( ".\\shader\\raycasting.vert", SG_VERTEX, rcVert_out );
	shader_out->CreateShaderObj ( ".\\shader\\raycasting.frag", SG_FRAGMENT, rcFrag_out );

	// Check error
	if ( !CheckHandleError ( 4, *bfVert_out, *bfFrag_out, *rcVert_out, *rcFrag_out ) )
	{
		cout << "create shaders object failed" << endl;
		exit (1);
	}
	
	// Create shader program object
	shader_out->CreateProgmObj ( prog_out );

	// Check error
	if ( !CheckHandleError ( 1, *prog_out) )
	{
		cout << "create program object failed" << endl;
		exit (1);
	}
}


GLuint Create1DTransFunc ( void )
{
	// Define the transfer function
	GLubyte *tff = (GLubyte*) malloc ( sizeof(GLubyte) * 256 * 4 );
	for ( int i = 0; i < 256; i++ )
	{
		tff [ i * 4 + 0 ] = i;
		tff [ i * 4 + 1 ] = (i * 10) % 256;
		tff [ i * 4 + 2 ] = i;
		tff [ i * 4 + 3 ] = 1;
	}


	GLuint tff1DTex;
	glGenTextures(1, &tff1DTex);
	glBindTexture(GL_TEXTURE_1D, tff1DTex);
	glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_WRAP_S, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	glTexImage1D(GL_TEXTURE_1D, 0, GL_RGBA8, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, tff);

	free(tff);    

	return tff1DTex;
};  


GLuint Create2DBackFace ( fluidsim *fluid )
{
    GLuint backFace2DTex;
    glGenTextures(1, &backFace2DTex);
    glBindTexture(GL_TEXTURE_2D, backFace2DTex);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, fluid->nScrWidth, fluid->nScrHeight, 0, GL_RGBA, GL_FLOAT, NULL);

	cout << "2D backface created" << endl;

	return backFace2DTex;
};


GLuint Create3DVolumetric ( const char *filename, fluidsim *fluid )
{
	// Create temporary value
	size_t width  = fluid->nVolWidth;
	size_t height = fluid->nVolHeight;
	size_t depth  = fluid->nVolDepth;


    FILE *fp;
	size_t size = width * height * depth; // width * length * depth
    GLubyte *data = new GLubyte[size];
	 
	if ( !(fp = fopen ( filename, "rb" )) )
    {
        cout << "Error: opening .raw file failed" << endl;
        exit ( 1 );
    }

    if ( fread(data, sizeof(char), size, fp)!= size) 
    {
        cout << "Error: read .raw file failed" << endl;
        exit ( 1 );
    }

    fclose ( fp );

	// Generate 3D textuer
	GLuint volTex;
    glGenTextures(1, &volTex);
    glBindTexture(GL_TEXTURE_3D, volTex);

    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_REPEAT);

	fluid->ptrData = data;

//    delete []data;

    cout << "3D volume texture created" << endl;

    return volTex;
};


GLuint Create3DVolumetric ( void )
{
	// Generate 3D textuer
	GLuint volTex;
    glGenTextures(1, &volTex);
    glBindTexture(GL_TEXTURE_3D, volTex);

    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);	
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_REPEAT);

    cout << "3D volume texture created" << endl;

    return volTex;
};


GLuint CreateFrameBuffer ( fluidsim *fluid )
{
	// Temp
	GLuint texObj = fluid->hTexture2D;
	GLint width   = fluid->nScrWidth;
	GLint height  = fluid->nScrHeight;

    // Create a depth buffer for framebuffer
    GLuint depthBuffer;
    glGenRenderbuffers ( 1, &depthBuffer );
    glBindRenderbuffer ( GL_RENDERBUFFER, depthBuffer );
    glRenderbufferStorage ( GL_RENDERBUFFER, GL_DEPTH_COMPONENT, width, height );

    // Attach the texture and the depth buffer to the framebuffer
	GLuint framebuffer;
    glGenFramebuffers ( 1, &framebuffer );
    glBindFramebuffer ( GL_FRAMEBUFFER, framebuffer );
    glFramebufferTexture2D ( GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texObj, 0 );
    glFramebufferRenderbuffer ( GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthBuffer );
	
	// Check Framebuffer status
	if ( glCheckFramebufferStatus ( GL_FRAMEBUFFER ) != GL_FRAMEBUFFER_COMPLETE )
    {
		cout << "framebuffer is not complete" << endl;
		exit(EXIT_FAILURE);
    }
    glEnable(GL_DEPTH_TEST);    

	cout << "framebuffer created" << endl;
	
	return framebuffer;
};


void RenderingFace ( GLenum cullFace, fluidsim *fluid )
{
	// Temp
	GLfloat angle  = fluid->nAngle;
	GLuint program = fluid->hProgram;
	GLuint cluster = fluid->hCluster;
	GLint width    = fluid->nScrWidth;
	GLint height   = fluid->nScrHeight;

	using namespace glm;
	
	// Clear background color and depth buffer
    glClearColor ( 0.f, 0.f, 0.f, 0.f );
    glClear ( GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT );
    
	//  Set projection and lookat matrix
    mat4 projection = perspective ( 60.0f, (GLfloat)width/(GLfloat)height, 0.1f, 400.f );
    mat4 view = lookAt (
		vec3(0.0f, 0.0f, 2.0f),
		vec3(0.0f, 0.0f, 0.0f), 
		vec3(0.0f, 1.0f, 0.0f));

	// Set model view matrix
    mat4 model = mat4(1.0f);
	model = model * rotate ( (float)angle, vec3(0.0f, 1.0f, 0.0f) );
    
	// Rotate and translate the view matrix, let object seems to "stand up"
	// Because, original volumetric data is "lying down" on ground.
	model = model * rotate ( 90.0f, vec3(1.0f, 0.0f, 0.0f) );
	model = model * translate ( vec3(-0.5f, -0.5f, -0.5f) ); 
    
	// Finally, we focus on setting the Model View Projection Matrix (MVP matrix)
	// Notice that the matrix multiplication order: reverse order of transform
    mat4 mvp = projection * view * model;

	// Returns an integer that represents the location of a specific uniform variable within a shader program
    GLuint mvpIdx = glGetUniformLocation ( program, "mvp" );
    
	if ( mvpIdx >= 0 )
    {
    	glUniformMatrix4fv ( mvpIdx, 1, GL_FALSE, &mvp[0][0] );
    }
    else
    {
    	cerr << "can't get the MVP" << endl;
    }
	    
	// Draw agent box
	glEnable ( GL_CULL_FACE );
	glCullFace ( cullFace );
	glBindVertexArray ( cluster );
	glDrawElements ( GL_TRIANGLES, 36, GL_UNSIGNED_INT, (GLuint *)NULL );
	glDisable ( GL_CULL_FACE );
}


void SetVolumeInfoUinforms ( fluidsim *fluid )
{
	GLuint program    = fluid->hProgram;
	GLuint Tex1DTrans = fluid->hTexture1D;
	GLuint Tex2DBF    = fluid->hTexture2D;
	GLuint Tex3DVol   = fluid->hTexture3D;
	GLfloat width     = fluid->nScrWidth;
	GLfloat height    = fluid->nScrHeight;
	GLfloat stepsize  = fluid->fStepsize;
	size_t  volWidth  = fluid->nVolWidth;
	size_t  volHeight = fluid->nVolHeight;
	size_t  volDepth  = fluid->nVolDepth;
	GLubyte *data     = fluid->ptrData;

	// Set the uniform of screen size
    GLint screenSizeLoc = glGetUniformLocation ( program, "screensize" );
    if ( screenSizeLoc >= 0 )
    {
		// Incoming two value, width and height
		glUniform2f ( screenSizeLoc, width, height );
    }
    else
    {
		cout << "ScreenSize is not bind to the uniform" << endl;
    }

	// Set the step length
    GLint stepSizeLoc = glGetUniformLocation ( program, "stride" );
	if ( stepSizeLoc >= 0 )
    {
		// Incoming one value, the step size
		glUniform1f ( stepSizeLoc, stepsize );
    }
    else
    {
		cout << "StepSize is not bind to the uniform" << endl;
    }
    
	// Set the transfer function
	GLint transferFuncLoc = glGetUniformLocation ( program, "transfer" );
    if ( transferFuncLoc >= 0 )
	{
		glActiveTexture ( GL_TEXTURE0 );
		glBindTexture ( GL_TEXTURE_1D, Tex1DTrans );
		glUniform1i ( transferFuncLoc, 0 );
    }
    else
    {
		cout << "TransferFunc is not bind to the uniform" << endl;
    }

	// Set the back face as exit point for ray casting
	GLint backFaceLoc = glGetUniformLocation ( program, "stopface" );
	if ( backFaceLoc >= 0 )
    {
		glActiveTexture ( GL_TEXTURE1 );
		glBindTexture(GL_TEXTURE_2D, Tex2DBF);
		glUniform1i(backFaceLoc, 1);
    }
    else
    {
		cout << "ExitPoints is not bind to the uniform" << endl;
    }

	// Set the uniform to hold the data of volumetric data
	GLint volumeLoc = glGetUniformLocation(program, "volumetric");
	if (volumeLoc >= 0)
    {
		glActiveTexture(GL_TEXTURE2);
		glBindTexture(GL_TEXTURE_3D, Tex3DVol);
		// Setting texture quality
		glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_REPEAT);
		glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_REPEAT);
		glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_REPEAT);
		// Pixel transfer happens here from client to OpenGL server
		glPixelStorei(GL_UNPACK_ALIGNMENT,1);
		glTexImage3D(GL_TEXTURE_3D, 0, GL_INTENSITY, volWidth, volHeight, volDepth, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, data);
		glUniform1i(volumeLoc, 2);
    }
    else
    {
		cout << "VolumeTex is not bind to the uniform" << endl;
    }    
};


GLuint InitVerticesBufferObj ( void )
{
#pragma region attributes of vertex
	// How agent cube looks like by specified the coordinate positions of vertices
	GLfloat vertices[24] = 
	{                    // (x, y, z)
		0.0, 0.0, 0.0,   // (0, 0, 0)
		0.0, 0.0, 1.0,   // (0, 0, 1)
		0.0, 1.0, 0.0,   // (0, 1, 0)
		0.0, 1.0, 1.0,   // (0, 1, 1)
		1.0, 0.0, 0.0,   // (1, 0, 0)
		1.0, 0.0, 1.0,   // (1, 0, 1)
		1.0, 1.0, 0.0,   // (1, 1, 0)
		1.0, 1.0, 1.0    // (1, 1, 1)
	};

	// Drawing six faces of agent cube with triangles by counter clockwise
	GLuint indices[36] = 
	{
		/// <front> 1 5 7 3 </front>///
		1,5,7,
		7,3,1,
		/// <back> 0 2 6 4 </back> ///
		0,2,6,
		6,4,0,
		/// <left> 0 1 3 2 </left> ///
		0,1,3,
		3,2,0,
		/// <right> 7 5 4 6 </right> ///
		7,5,4,
		4,6,7,
		/// <up> 2 3 7 6 </up> ///
		2,3,7,
		7,6,2,
		/// <down> 1 0 4 5 </down> ///
		1,0,4,
		4,5,1
	};  
#pragma endregion
	
#pragma region create vertex buffer object
	/// Create Vertex Buffer Object (vbo) ///
	// Generate the buffer indices, and 
	GLuint GenBufferList[2];
	glGenBuffers ( 2, GenBufferList );
	GLuint ArrayBufferData  = GenBufferList [ 0 ];
	GLuint ElementArrayData = GenBufferList [ 1 ];

	// Bind vertex array list
	glBindBuffer ( GL_ARRAY_BUFFER, ArrayBufferData );
	glBufferData ( GL_ARRAY_BUFFER, 24 * sizeof(GLfloat), vertices, GL_STATIC_DRAW );

	// Bind element array list
	glBindBuffer ( GL_ELEMENT_ARRAY_BUFFER, ElementArrayData );
	glBufferData ( GL_ELEMENT_ARRAY_BUFFER, 36 * sizeof(GLuint), indices, GL_STATIC_DRAW );

	/// vbo finished ///

	/// Upload attributes of vertex ///
	// Use a cluster for keeping the attributes of vertex
	GLuint cluster;
	glGenVertexArrays ( 1, &cluster );
	glBindVertexArray ( cluster );

	glEnableVertexAttribArray ( 0 ); // Enable vertex array with index 0
//	glEnableVertexAttribArray ( 1 ); // Enable vertex array with index 1

	// Binding the vbo, and set the vertex location is the same as the vertex color
	// Reserved the null pointer, because we no need to transfer data to shader, vbo was instead.
	// Color will generated by shader
	glBindBuffer ( GL_ARRAY_BUFFER, ArrayBufferData );
	glVertexAttribPointer ( 0, 3, GL_FLOAT, GL_FALSE, 0, (GLfloat *)NULL ); // define the index 0 without any data
//	glVertexAttribPointer ( 1, 3, GL_FLOAT, GL_FALSE, 0, (GLfloat *)NULL ); // define the index 1 without any data
	glBindBuffer ( GL_ELEMENT_ARRAY_BUFFER, ElementArrayData );  
#pragma endregion

	cout << "agent object finished" << endl;

	return cluster;
};