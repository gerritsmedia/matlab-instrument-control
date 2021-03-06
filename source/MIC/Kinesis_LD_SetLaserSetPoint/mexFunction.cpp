#include <windows.h>
#pragma comment(lib, "kernel32.lib")

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <mex.h>
#include <conio.h>
#include "C:\Program Files\Thorlabs\Kinesis\Thorlabs.MotionControl.TCube.LaserDiode.h"

#ifndef max
//! not defined in the C standard used by visual studio
#define max(a,b) (((a) > (b)) ? (a) : (b))
#endif
#ifndef min
//! not defined in the C standard used by visual studio
#define min(a,b) (((a) < (b)) ? (a) : (b))
#endif
#define pi 3.141592f


//*******************************************************************************************
void mexFunction(int nlhs, mxArray *plhs[],	int	nrhs, const	mxArray	*prhs[]) {

	// short __cdecl LD_SetLaserSetPoint  ( char const *  serialNo, WORD  laserDiodeCurrent)


	if (nrhs != 2)
		mexErrMsgTxt("Proper Usage: [Err,SetPoint]=LD_SetLaserSetPoint('SerialNoString,Current)");

	if (!mxIsClass(prhs[0], "char"))
		mexErrMsgTxt("Proper Usage: [Err,SetPoint]=LD_SetLaserSetPoint('SerialNoString,Current').  First input must be character array.");

	if (!mxIsClass(prhs[1], "uint32"))
		mexErrMsgTxt("Proper Usage: [Err,SetPoint]=LD_SetLaserSetPoint('SerialNoString,Current').  Second Input must be uint32");

	char * input_buf = mxArrayToString(prhs[0]);
	//mexPrintf("%s\n", input_buf);

	UINT32 Current = (UINT32) mxGetScalar(prhs[1]);

	LD_Enable(input_buf);
	short Err = LD_SetLaserSetPoint(input_buf, Current);
	plhs[0] = mxCreateDoubleScalar(Err);
	plhs[1] = mxCreateDoubleScalar(LD_GetLaserSetPoint(input_buf));

	mxFree(input_buf);
	return;
 }