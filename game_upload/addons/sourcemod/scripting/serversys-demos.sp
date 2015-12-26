#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <smlib>

#include <serversys>
#include <serversys-demos>

#undef REQUIRE_EXTENSIONS
#include <cURL>
#define REQUIRE_EXTENSIONS

#define CURL_LOADED() (GetFeatureStatus(FeatureType_Native, "curl_easy_init") == FeatureStatus_Available)

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
	name = "[Server-Sys] Demos",
	description = "Server-Sys reports and auto-demo implementation.",
	author = "cam",
	version = SERVERSYS_VERSION,
	url = SERVERSYS_URL
}

bool g_bLateLoad;
bool g_Settings_Reports = true;
bool g_Settings_UploadDemos = true;

char g_Settings_LocalPath[PLATFORM_MAX_PATH];
char g_Settings_FTPHost[64];
char g_Settings_FTPPass[64];
char g_Settings_FTPUser[64];
char g_Settings_FTPPath[64];
int  g_Settings_FTPPort;
char g_Settings_CommandString[128];
char g_Settings_TVName[64];
int  g_Settings_TVDelay;

bool g_Settings_NotifyUploads;


bool g_bRecording;
bool g_bUploading;
int  g_iRecording;

bool g_bListening[MAXPLAYERS + 1];
int  g_iListeningTarget[MAXPLAYERS + 1];
int  g_iListeningTime[MAXPLAYERS + 1];

Handle g_hProccessingFile;

ConVar cv_Enable;
ConVar cv_Record;
ConVar cv_Delay;
ConVar cv_Name;
ConVar cv_TransmitAll;
ConVar cv_AllowCameraMan;

public void OnPluginStart(){
	cv_Name = FindConVar("tv_name");
	cv_Enable = FindConVar("tv_enable");
	cv_Record = FindConVar("tv_autorecord");
	cv_Delay = FindConVar("tv_delay");
	cv_TransmitAll = FindConVar("tv_transmitall");
	cv_AllowCameraMan = FindConVar("tv_allow_camera_man");

	LoadConfig();

	LoadTranslations("serversys.demos.phrases");

	if(g_bLateLoad && Sys_InMap())
		StartRecording();

	cv_Enable.BoolValue = true;
	cv_Record.BoolValue = false;
	cv_TransmitAll.BoolValue = true;
	// This one isn't in CS:GO
	if(cv_AllowCameraMan != INVALID_HANDLE)
		cv_AllowCameraMan.BoolValue = false;

	cv_Enable.AddChangeHook(Hook_ConVarChange);
	cv_Record.AddChangeHook(Hook_ConVarChange);
	cv_Delay.AddChangeHook(Hook_ConVarChange);
}

void LoadConfig(){
	Handle kv = CreateKeyValues("Demos");
	char Config_Path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, Config_Path, sizeof(Config_Path), "configs/serversys/demos.cfg");

	if(!(FileExists(Config_Path)) || !(FileToKeyValues(kv, Config_Path))){
		Sys_KillHandle(kv);
		SetFailState("[serversys] demos :: Cannot read from configuration file: %s", Config_Path);
	}

	if(KvJumpToKey(kv, "recording")){
		char local_path[128];
		KvGetString(kv, "path", local_path, sizeof(local_path), "data");
		BuildPath(Path_SM, g_Settings_LocalPath, sizeof(g_Settings_LocalPath), "%s", local_path);

		KvGetString(kv, "name", g_Settings_TVName, sizeof(g_Settings_TVName), "SourceTV");
		cv_Name.SetString(g_Settings_TVName, true, true);

		g_Settings_TVDelay = KvGetNum(kv, "delay", 10);
		cv_Delay.IntValue = g_Settings_TVDelay;

		KvGoBack(kv);
	}else{
		BuildPath(Path_SM, g_Settings_LocalPath, sizeof(g_Settings_LocalPath), "%s", "data/demos");
	}

	if(KvJumpToKey(kv, "reporting")){
		g_Settings_Reports = view_as<bool>(KvGetNum(kv, "enabled", 1));

		KvGetString(kv, "command", g_Settings_CommandString, sizeof(g_Settings_CommandString), "!report /report");

		KvGoBack(kv);
	}else{
		g_Settings_Reports = false;
		strcopy(g_Settings_CommandString, sizeof(g_Settings_CommandString), "!report /report");
	}

	if(KvJumpToKey(kv, "uploading")){
		g_Settings_UploadDemos = view_as<bool>(KvGetNum(kv, "enabled", 1));

		g_Settings_NotifyUploads = view_as<bool>(KvGetNum(kv, "notify", 1));

		KvGetString(kv, "host", g_Settings_FTPHost, sizeof(g_Settings_FTPHost), "127.0.0.1");
		KvGetString(kv, "user", g_Settings_FTPUser, sizeof(g_Settings_FTPUser), "root");
		KvGetString(kv, "pass", g_Settings_FTPPass, sizeof(g_Settings_FTPPass), "password");
		g_Settings_FTPPort = KvGetNum(kv, "port", 21);

		KvGetString(kv, "path", g_Settings_FTPPath, sizeof(g_Settings_FTPPath), "var/www/servers/demos/");

		KvGoBack(kv);
	}else{
		g_Settings_UploadDemos = false;
	}

	Sys_KillHandle(kv);
}

public void Hook_ConVarChange(ConVar cv, const char[] value1, const char[] value2){
	if(cv == cv_Enable)
		cv.BoolValue = true;

	if(cv == cv_Delay)
		cv.IntValue = g_Settings_TVDelay;

	if(cv == cv_Record)
		cv.BoolValue = false;
}

public void OnAllPluginsLoaded(){
	Sys_RegisterChatCommand(g_Settings_CommandString, Command_ReportPlayer);
}

public void OnClientPutInServer(int client){
	if(!Sys_Demos_Recording())
		StartRecording();

	g_bListening[client] = false;
	g_iListeningTarget[client] = 0;
	g_iListeningTime[client] = 0;
}

public void OnClientDisconnect_Post(int client){
	if(Sys_Demos_Recording() && (Sys_GetPlayerCount(-2001, true) < 2))
		StopRecording();
}

public void OnMapStart(){
	StartRecording();

	for(int i = 1; i <= MaxClients; i++){
		g_bListening[i] = false;
		g_iListeningTarget[i] = 0;
		g_iListeningTime[i] = 0;
	}
}

public void OnMapEnd(){
	if(Sys_Demos_Recording())
		StopRecording();
}

public void OnPluginEnd(){
	StopRecording();
}

void StartRecording(){
	if(Sys_Demos_Recording())
		SetFailState("[server-sys] demos :: ERROR! Cannot double record!");

	if(Sys_GetPlayerCount(-2001, true) < 1){
		LogMessage("[server-sys] demos :: No players are in-game! Skipping recording.");
		return;
	}

	if(strlen(g_Settings_TVName) > 0){
		char name[128];
		Format(name, sizeof(name), "%s [ RECORDING ]", g_Settings_TVName);
		cv_Name.SetString(name, true, true);
	}

	g_iRecording = GetTime();

	cv_TransmitAll.BoolValue = true;
	if(cv_AllowCameraMan != INVALID_HANDLE)
		cv_AllowCameraMan.BoolValue = false;

	ServerCommand("tv_record %s/%d.dem", g_Settings_LocalPath, g_iRecording);

	g_bRecording = true;
}

void StopRecording(){
	if(!Sys_Demos_Recording())
		SetFailState("[server-sys] demos :: ERROR! Attempting to stop unknown recording!");

	if(strlen(g_Settings_TVName) > 0){
		cv_Name.SetString(g_Settings_TVName, true, true);
	}

	ServerCommand("tv_stoprecord");

	if(g_Settings_UploadDemos && CURL_LOADED()){
		DataPack pack = new DataPack();
		pack.WriteCell(g_iRecording);
		pack.WriteCell(GetTime());
		pack.WriteCell(Sys_GetMapID());
		pack.WriteFloat((GetEngineTime() + 10.0));
		CreateTimer(10.0, FTPUpload_Timer, pack);
	}else{
		LogMessage("[serversys] demos :: Finished recording %d.dem", g_iRecording);
	}

	g_bRecording = false;
	g_iRecording = 0;
}

public Action FTPUpload_Timer(Handle timer, DataPack data){
	data.Reset();
	int recording = data.ReadCell();

	Handle curl = curl_easy_init();

	if(curl == INVALID_HANDLE){
		LogMessage("[serversys] demos :: Unable to initalize curl!");
		return Plugin_Stop;
	}


	g_bUploading = true;
	curl_easy_setopt_int(curl, CURLOPT_NOSIGNAL, 1);
	curl_easy_setopt_int(curl, CURLOPT_NOPROGRESS, 1);
	curl_easy_setopt_int(curl, CURLOPT_TIMEOUT, 90);
	curl_easy_setopt_int(curl, CURLOPT_CONNECTTIMEOUT, 45);
	curl_easy_setopt_int(curl, CURLOPT_VERBOSE, 0);

	curl_easy_setopt_int(curl, CURLOPT_UPLOAD, 1);
	curl_easy_setopt_function(curl, CURLOPT_READFUNCTION, FTP_ReadFunction);

	curl_easy_setopt_int(curl, CURLOPT_FTP_CREATE_MISSING_DIRS, CURLFTP_CREATE_DIR);

	char path_local[PLATFORM_MAX_PATH];
	Format(path_local, sizeof(path_local), "%s/%d.dem", g_Settings_LocalPath, recording);

	if(!FileExists(path_local)){
		LogError("[serversys] demos :: Demo doesn't exist to upload! Uh oh!");
	}

	if(g_hProccessingFile != INVALID_HANDLE){
		delete g_hProccessingFile;
		g_hProccessingFile = INVALID_HANDLE;
	}

	g_hProccessingFile = OpenFile(path_local, "rb");

	char ftp_url[PLATFORM_MAX_PATH];
	Format(ftp_url, sizeof(ftp_url), "ftp://%s:%s@%s:%d/%s/%d/%d.dem",
		g_Settings_FTPUser,
		g_Settings_FTPPass,
		g_Settings_FTPHost,
		g_Settings_FTPPort,
		g_Settings_FTPPath,
		Sys_GetServerID(),
		recording);

	curl_easy_setopt_string(curl, CURLOPT_URL, ftp_url);
	curl_easy_perform_thread(curl, FTPUpload_Finished, data);

	if(g_Settings_NotifyUploads){
		CPrintToChatAll("%t", "Notify of upload start");
	}

	return Plugin_Stop;
}

public int FTP_ReadFunction(Handle curl, const int bytes, const int nmemb){
	if((bytes*nmemb) < 1)
		return 0;

	if(IsEndOfFile(g_hProccessingFile)){
		delete g_hProccessingFile;
		g_hProccessingFile = INVALID_HANDLE;
		return 0;
	}

	int iBytesToRead = (bytes * nmemb);

	// This is slow as hell, but ReadFile always read 4 byte blocks, even though
	// it was told explicitely to read 'bytes' * 'nmemb' bytes.
	// XXX: Revisit this and try to do it right...
	char[] items = new char[iBytesToRead];
	int pos = 0;
	int cell = 0;
	for(; pos < iBytesToRead && ReadFileCell(g_hProccessingFile, cell, 1) == 1; pos++) {
		items[pos] = cell;
	}

	curl_set_send_buffer(curl, items, pos);

	return pos;
}

public int FTPUpload_Finished(Handle curl, CURLcode code, DataPack data){
	if(code == CURLE_OK){
		data.Reset();
		int recording = data.ReadCell();
		int finish = data.ReadCell();
		int mid = data.ReadCell();
		float took = (GetEngineTime() - data.ReadFloat());

		if(g_Settings_NotifyUploads){
			CPrintToChatAll("%t", "Notify of upload end", took);
		}

		char query[1024];
		Format(query, sizeof(query), "INSERT INTO demos (sid, mid, timestamp, timestamp_end, upload_time) VALUES(%d, %d, %d, %d, %.2f);", Sys_GetServerID(), mid, recording, finish, took);

		Sys_DB_TQuery(Sys_Demos_DemoInsertCB, query, data, DBPrio_High);
	}else{
		char error[256];
		curl_easy_strerror(code, error, sizeof(error));

		LogMessage("[serversys] demos :: Error CURL uploading: %", error);
		return 0;
	}

	Sys_KillHandle(g_hProccessingFile);
	g_bUploading = false;

	return 0;
}

public void Sys_Demos_DemoInsertCB(Handle owner, Handle hndl, const char[] error, DataPack data){
	data.Reset();
	int recording = data.ReadCell();
	int finished = data.ReadCell();
	CloseHandle(data);

	if(hndl == INVALID_HANDLE){
		LogError("[serversys] demos :: Error inserting demo (%d.dem, finished on %d) to database: %s", recording, finished, error);
		return;
	}

	PrintToServer("[serversys] demos :: Demo uploading complete and inserted into table. %d to %d (%d.dem)", recording, finished, recording);
}

public void Command_ReportPlayer(int client, const char[] command, const char[] args){
	if(!g_Settings_Reports)
		return;

	if(Sys_GetPlayerCount(-2001, false, false, false) > 1){
		if(strlen(args) > 0){
			int target = FindTarget(client, args, true);

			if((0 < target <= MaxClients) && IsClientInGame(target)){
				if(Sys_GetPlayerID(target) > 0){
					g_bListening[client] = true;
					g_iListeningTarget[client] = Sys_GetPlayerID(target);
					g_iListeningTime[client] = GetTime();

					char name[MAX_NAME_LENGTH];
					GetClientName(target, name, MAX_NAME_LENGTH);
					CPrintToChat(client, "%t", "Type Reason Against", name);
				}
			}else{
				CPrintToChat(client, "%t", "Invalid report command usage");
			}
		}else{
			Menu menu = new Menu(MenuHandler_ReportPlayer);
			menu.SetTitle("%t", "Report Menu Header");
			menu.ExitButton = true;
			char tauth[32];
			char tname[32];
			for(int i = 1; i <= MaxClients; i++){
				if(IsClientConnected(i) && (i != client) && !IsFakeClient(i) && !IsClientSourceTV(i)){
					Format(tauth, sizeof(tauth), "%d", Sys_GetPlayerID(i));
					Format(tname, sizeof(tname), "%N", i);
					menu.AddItem(tauth, tname);
				}
			}
			menu.Display(client, 30);
		}
	}else{
		CPrintToChat(client, "%t", "No Players");
	}

	return;
}

public int MenuHandler_ReportPlayer(Menu menu, MenuAction action, int client, int itemidx){
	if(client <= 0 || !IsClientConnected(client)){
		#if defined DEBUG
		PrintToServer("[server-sys] demos :: Weird error in report menu.");
		#endif
		return;
	}

	if(action == MenuAction_Select){
		char info[32];
		menu.GetItem(itemidx, info, sizeof(info));

		int playerid = StringToInt(info);
		int reportee = Sys_GetClientOfPlayerID(playerid);

		if(playerid > 0){
			g_bListening[client] = true;
			g_iListeningTarget[client] = playerid;
			g_iListeningTime[client] = GetTime();

			if(reportee != 0){
				char name[32];
				GetClientName(reportee, name, sizeof(name));
				CPrintToChat(client, "%t", "Type Reason Against", name);
			}else{
				CPrintToChat(client, "%t", "Type Reason");
			}
		}
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] args){
	if(client != 0 && g_bListening[client] && (g_iListeningTarget[client] > 0)){

		if(((GetTime() - g_iListeningTime[client]) >= 90) || StrEqual(args, "no", false) || StrEqual(args, "cancel", false) || StrEqual(args, "abort", false) || StrEqual(args, "nevermind", false)){
			g_bListening[client] = false;
			g_iListeningTarget[client] = 0;
			g_iListeningTime[client] = 0;

			return Plugin_Continue;
		}

		// string magik
		char desc[MAX_MESSAGE_LENGTH];
		int safelen = (2*(MAX_MESSAGE_LENGTH)+1);
		char[] safedesc = new char[safelen];
		strcopy(desc, sizeof(desc), args);

		Sys_DB_EscapeString(desc, sizeof(desc), safedesc, safelen);

		char query[1024];
		Format(query, sizeof(query), "INSERT INTO reports (sid, reporter, reportee, description, demo, timestamp) VALUES(%d, %d, %d, '%s', %d, %d);",
			Sys_GetServerID(),
			Sys_GetPlayerID(client),
			g_iListeningTarget[client],
			safedesc,
			g_iRecording,
			g_iListeningTime[client]);
		Sys_DB_TQuery(Sys_Demos_ReportInsertCB, query, client);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void Sys_Demos_ReportInsertCB(Handle owner, Handle hndl, const char[] error, int client){
	if(hndl == INVALID_HANDLE){
		LogError("[serversys] demos :: Error inserting report from %N: %s", client, error);
		return;
	}

	CPrintToChat(client, "%t", "Report Success", SQL_GetInsertId(hndl));
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("serversys-demos");

	CreateNative("Sys_Demos_Ready", Native_Demos_Ready);
	CreateNative("Sys_Demos_Recording", Native_Demos_Recording);
	CreateNative("Sys_Demos_GetRecording", Native_Demos_GetRecording);
	CreateNative("Sys_Demos_GetRecordingID", Native_Demos_GetRecording);


	g_bLateLoad = late;
}

public int Native_Demos_GetRecording(Handle plugin, int numParams){
	if(Sys_Demos_Recording() && g_iRecording != 0)
		return g_iRecording;

	return 0;
}

public int Native_Demos_Ready(Handle plugin, int numParams){
	if(Sys_GetServerID() == 0)
		return false;

	return true;
}

public int Native_Demos_Recording(Handle plugin, int numParams){
	return g_bRecording;
}
