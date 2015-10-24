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
char g_Settings_CommandString[128];


int  g_iServerID = 0;
bool g_bRecording;
int  g_iRecording;

bool g_bListening[MAXPLAYERS + 1];
int  g_iListeningTarget[MAXPLAYERS + 1];
int  g_iListeningTime[MAXPLAYERS + 1];

void LoadConfig(){
	Handle kv = CreateKeyValues("Reports");
	char Config_Path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, Config_Path, sizeof(Config_Path), "configs/serversys/reports.cfg");

	if(!(FileExists(Config_Path)) || !(FileToKeyValues(kv, Config_Path))){
		Sys_KillHandle(kv);
		SetFailState("[serversys] reports :: Cannot read from configuration file: %s", Config_Path);
	}

	KvGetString(kv, "report-command", g_Settings_CommandString, sizeof(g_Settings_CommandString), "!report /report");

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

	LoadTranslations("serversys.reports.phrases");

	if(g_bLateLoad && Sys_InMap())
		StartRecording();
}

public void OnAllPluginsLoaded(){
	Sys_RegisterChatCommand(g_Settings_CommandString, Command_ReportPlayer);
}

public void OnMapStart(){
	StartRecording();

	for(int i = 1; i <= MaxClients; i++){
		if(IsClientConnected(i) && !IsFakeClient(i) && !IsClientSourceTV(i)){
			g_bListening[i] = false;
			g_iListeningTarget[i] = 0;
			g_iListeningTime[i] = 0;
		}
	}
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

public void OnClientPutInServer(int client){
	g_bListening[client] = false;
	g_iListeningTarget[client] = 0;
	g_iListeningTime[client] = 0;
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
		DataPack pack = new DataPack();
		pack.WriteCell(g_iRecording);
		pack.WriteCell(GetTime());
		CreateTimer(1.0, FTPUpload_Timer, pack);
	}
	g_bRecording = false;
	g_iRecording = 0;
}

public Action FTPUpload_Timer(Handle timer, DataPack data){
	int recording = data.ReadCell();
	data.Position = data.Position - 1;

	char temp_path_local[PLATFORM_MAX_PATH];
	Format(temp_path_local, sizeof(temp_path_local), "%s/%d.dem", g_Settings_LocalPath, recording);

	char temp_path_remote[PLATFORM_MAX_PATH];
	Format(temp_path_remote, sizeof(temp_path_remote), "%s/%d/%d.dem", g_Settings_FTPPath, g_iServerID, recording);

	System2_UploadFTPFile(view_as<TransferUpdated>(FTPUpload_Callback),
		temp_path_local,
		temp_path_remote,
		g_Settings_FTPHost,
		g_Settings_FTPUser,
		g_Settings_FTPPass,
		g_Settings_FTPPort,
		data);
}

public void FTPUpload_Callback(bool finished, const char[] error, float dltotal, float dlnow, float uptotal, float upnow, DataPack data){
	// System2 spams random errors, unknown
	//if(strlen(error) > 1){
	//	LogError("[server-sys] reports :: Error on FTP upload: %s", error);
	//	return;
	//}else


	if(finished == true){
		int recording = data.ReadCell();
		int finish = data.ReadCell();
		data.Position = data.Position - 2;

		char query[1024];
		Format(query, sizeof(query), "INSERT INTO reports_demos (sid, timestamp, timestamp_end, integrity) VALUES(%d, %d, %d, %.2f);", g_iServerID, recording, finish, ((upnow / uptotal)*100.0));


		Sys_DB_TQuery(Sys_Reports_DemoInsertCB, query, data, DBPrio_High);
	}
}

public void Sys_Reports_DemoInsertCB(Handle owner, Handle hndl, const char[] error, DataPack data){
	int recording = data.ReadCell();
	int finished = data.ReadCell();
	CloseHandle(data);

	if(hndl == INVALID_HANDLE){
		LogError("[serversys] reports :: Error inserting demo (%d.dem, finished on %d) to database: %s", recording, finished, error);
		return;
	}

	PrintToServer("[serversys] reports :: Demo uploading complete and inserted into table. %d to %d (%d.dem)", recording, finished, recording);
}

public void Command_ReportPlayer(int client, const char[] command, const char[] args){
	if(Sys_PlayerCount(_, true) > 1){
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
	}else{
		PrintToChat(client, "%t", "No Players");
	}
}

public int MenuHandler_ReportPlayer(Menu menu, MenuAction action, int client, int itemidx){
	if(client <= 0 || !IsClientConnected(client)){
		#if defined DEBUG
		PrintToServer("[server-sys] reports :: Weird error in report menu.");
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
				PrintToChat(client, "%t", "Type Reason Against", name);
			}else{
				PrintToChat(client, "%t", "Type Reason");
			}
		}
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] args){
	if(client != 0 && g_bListening[client] && (g_iListeningTarget[client] > 0)){
		// string magik
		char desc[MAX_MESSAGE_LENGTH];
		int safelen = (2*(MAX_MESSAGE_LENGTH)+1);
		char[] safedesc = new char[safelen];
		strcopy(desc, sizeof(desc), args);

		Sys_DB_EscapeString(desc, sizeof(desc), safedesc, safelen);

		char query[1024];
		Format(query, sizeof(query), "INSERT INTO reports (reporter, reportee, description, demo, timestamp) VALUES(%d, %d, '%s', %d, %d);",
			Sys_GetPlayerID(client),
			g_iListeningTarget[client],
			safedesc,
			g_iRecording,
			g_iListeningTime[client]);
		Sys_DB_TQuery(Sys_Reports_ReportInsertCB, query, client);
	}
}

public void Sys_Reports_ReportInsertCB(Handle owner, Handle hndl, const char[] error, int client){
	if(hndl == INVALID_HANDLE){
		LogError("[serversys] reports :: Error inserting report from %N: %s", client, error);
		return;
	}

	PrintToChat(client, "%t", "Report Success", SQL_GetInsertId(hndl));
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("serversys-reports");

	CreateNative("Sys_Reports_Ready", Native_Reports_Ready);
	CreateNative("Sys_Reports_Recording", Native_Reports_Recording);
	CreateNative("Sys_Reports_GetRecording", Native_Reports_GetRecording);
	CreateNative("Sys_Reports_GetRecordingID", Native_Reports_GetRecording);


	g_bLateLoad = late;
}

public int Native_Reports_GetRecording(Handle plugin, int numParams){
	if(Sys_Reports_Recording() && g_iRecording != 0)
		return g_iRecording;

	return 0;
}

public int Native_Reports_Ready(Handle plugin, int numParams){
	if(g_iServerID == 0)
		return false;

	return true;
}

public int Native_Reports_Recording(Handle plugin, int numParams){
	return g_bRecording;
}
