#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <smlib>

#include <serversys>
#include <serversys-reports>
#include <system2>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name = "[Server-Sys] Reports System",
	description = "Server-Sys reports and auto-demo implementation.",
	author = "cam",
	version = SERVERSYS_VERSION,
	url = SERVERSYS_URL
}

bool g_bLateLoad;

char g_Settings_LocalPath[PLATFORM_MAX_PATH];
char g_Settings_FTPHost[64];
char g_Settings_FTPPass[64];
char g_Settings_FTPUser[64];
char g_Settings_FTPPath[64];
int  g_Settings_FTPPort;


int  g_iServerID = 0;
bool g_bRecording;
int  g_iRecording;

void LoadConfig(){
	Handle kv = CreateKeyValues("Reports");
	char Config_Path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, Config_Path, sizeof(Config_Path), "configs/serversys/reports.cfg");

	if(!(FileExists(Config_Path)) || !(FileToKeyValues(kv, Config_Path))){
		Sys_KillHandle(kv);
		SetFailState("[serversys] reports :: Cannot read from configuration file: %s", Config_Path);
	}

	char local_path[128];
	KvGetString(kv, "local-path", local_path, sizeof(local_path), "data");
	BuildPath(Path_SM, g_Settings_LocalPath, sizeof(g_Settings_LocalPath), "%s", local_path);

	KvGetString(kv, "ftp-host", g_Settings_FTPHost, sizeof(g_Settings_FTPHost), "127.0.0.1");
	KvGetString(kv, "ftp-user", g_Settings_FTPUser, sizeof(g_Settings_FTPUser), "root");
	KvGetString(kv, "ftp-pass", g_Settings_FTPPass, sizeof(g_Settings_FTPPass), "");
	g_Settings_FTPPort = KvGetNum(kv, "ftp-port", 21);

	KvGetString(kv, "ftp-path", g_Settings_FTPPath, sizeof(g_Settings_FTPPath), "/var/www/servers/demos/");

	Sys_KillHandle(kv);
}

public void OnPluginStart(){
	LoadConfig();

	if(g_bLateLoad)
		StartRecording();
}

public void OnMapStart(){
	StartRecording();
}

public void OnMapEnd(){
	StopRecording();
}

public void OnPluginEnd(){
	StopRecording();
}

public void OnServerIDLoaded(int ServerID){
	g_iServerID = ServerID;
}

void StartRecording(){
	if(Sys_Reports_Recording())
		SetFailState("[server-sys] reports :: ERROR! Cannot double record!");

	g_iRecording = GetTime();

	ServerCommand("tv_record %s/%d.dem", g_Settings_LocalPath, g_iRecording);

	g_bRecording = true;
}

void StopRecording(){
	if(!Sys_Reports_Recording())
		SetFailState("[server-sys] reports :: ERROR! Attempting to stop unknown recording!");

	ServerCommand("tv_stoprecord");

	if(Sys_Reports_Ready()){
		char temp_path_local[PLATFORM_MAX_PATH];
		Format(temp_path_local, sizeof(temp_path_local), "%s/%d.dem", g_Settings_LocalPath, g_iRecording);

		char temp_path_remote[PLATFORM_MAX_PATH];
		Format(temp_path_remote, sizeof(temp_path_remote), "%s/%d/%d.dem", g_Settings_FTPPath, g_iServerID, g_iRecording);

		System2_UploadFTPFile(Upload_Update,
			temp_path_local,
			temp_path_remote,
			g_Settings_FTPHost,
			g_Settings_FTPUser,
			g_Settings_FTPPass,
			g_Settings_FTPPort,
			g_iRecording);
	}
	g_bRecording = false;
}

public void Upload_Update(bool finished, const char[] error, float dltotal, float dlnow, float uptotal, float upnow, any recording){
	if(strlen(error) > 1){
		LogError("[server-sys] reports :: Error on FTP upload: %s", error);
		return;
	}
	if(finished == true){
		char query[1024];
		Format(query, sizeof(query), "INSERT INTO reports_demos (sid, timestamp) VALUES(%d, %d)", g_iServerID, recording);

		Sys_DB_TQuery(Sys_Reports_DemoInsertCB, query, recording, DBPrio_High);
	}
}

public void Sys_Reports_DemoInsertCB(Handle owner, Handle hndl, const char[] error, any recording){
	if(hndl == INVALID_HANDLE){
		LogError("[serversys] reports :: Error inserting demo to database: %d", recording, error);
		return;
	}

}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("serversys-reports");

	CreateNative("Sys_Reports_Ready", Native_Reports_Ready);
	CreateNative("Sys_Reports_Recording", Native_Reports_Recording);

	g_bLateLoad = late;
}


public int Native_Reports_Ready(Handle plugin, int numParams){
	if(g_iServerID == 0)
		return false;

	return true;
}

public int Native_Reports_Recording(Handle plugin, int numParams){
	return g_bRecording;
}
