#if defined _serversys_demos_included
  #endinput
#endif
#define _serversys_demos_included

/**
* Checks if the reports plugin is currently ready
* to begin recording, or if it is already past that
* stage. All this takes is for the ServerID to be
* loaded.
*
* @return               True if ready, false otherwise
*/
native bool Sys_Demos_Ready();

/**
* Checks if the reports plugin is currently recording
* a SourceTV demo.
*
* @return               True if recording, false otherwise.
*/
native bool Sys_Demos_Recording();

/**
* Checks the current recording ID.
*
* @return               Current recording ID or 0.
*/
native int Sys_Demos_GetRecording();

/**
* Checks the current recording ID.
*
* @return               Current recording ID or 0.
*/
native int Sys_Demos_GetRecordingID();


public SharedPlugin __pl_serversys_demos =
{
	name = "serversys-demos",
	file = "serversys-demos.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if defined REQUIRE_PLUGIN
public __pl_serversys_demos_SetNTVOptional(){
    MarkNativeAsOptional("Sys_Demos_Ready");
    MarkNativeAsOptional("Sys_Demos_Recording");
    MarkNativeAsOptional("Sys_Demos_GetRecording");
    MarkNativeAsOptional("Sys_Demos_GetRecordingID");
}
#endif


/* This stays at the bottom
*/
#if defined MAX_MESSAGE_LENGTH
  #endinput
#endif
#define MAX_MESSAGE_LENGTH 256
