#if defined _serversys_reports_included
  #endinput
#endif
#define _serversys_reports_included

/**
* Checks if the reports plugin is currently ready
* to begin recording, or if it is already past that
* stage. All this takes is for the ServerID to be
* loaded.
*
* @return               True if ready, false otherwise
*/
native bool Sys_Reports_Ready();

/**
* Checks if the reports plugin is currently recording
* a SourceTV demo.
*
* @return               True if recording, false otherwise.
*/
native bool Sys_Reports_Recording();


public SharedPlugin __pl_serversys_core =
{
	name = "serversys-reports",
	file = "serversys-reports.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if defined REQUIRE_PLUGIN
public __pl_serversys_core_SetNTVOptional(){
    MarkNativeAsOptional("Sys_Reports_Ready");
    MarkNativeAsOptional("Sys_Reports_Recording");
}
#endif
