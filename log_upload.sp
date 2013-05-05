#pragma semicolon 1
#include <sourcemod>
#include <cURL>
#include <json>

public Plugin:myinfo =
{
	name = "Log auto-uploader",
	author = "Duckeh",
	description = "Auto-upload match logs to logs.tf",
	version = "1.4",
	url = "https://github.com/remydb/LogUploader"
};

new CURL_Default_opt[][2] = {
	{_:CURLOPT_NOSIGNAL,1},
	{_:CURLOPT_NOPROGRESS,1},
	{_:CURLOPT_TIMEOUT,30},
	{_:CURLOPT_CONNECTTIMEOUT,60},
	{_:CURLOPT_USE_SSL,CURLUSESSL_TRY},
	{_:CURLOPT_SSL_VERIFYPEER,0},
	{_:CURLOPT_SSL_VERIFYHOST,0},
	{_:CURLOPT_VERBOSE,0}
};

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

new Handle:g_hCvarAPIKey = INVALID_HANDLE;
new Handle:g_hCvarTitle = INVALID_HANDLE;
new Handle:g_hCvarTournament = INVALID_HANDLE;
new Handle:g_hCvarLogsdir = INVALID_HANDLE;
new Handle:output_file = INVALID_HANDLE;
new Handle:postForm = INVALID_HANDLE;

public OnPluginStart()
{
	// Register CVars
	g_hCvarAPIKey = CreateConVar("sm_logup_apikey", "", "Set the logs.tf API key", FCVAR_PROTECTED);
	g_hCvarTitle = CreateConVar("sm_logup_title", "Auto Uploaded Log", "Title to use on logs.tf", FCVAR_PROTECTED);
	g_hCvarTournament = FindConVar("mp_tournament");
	g_hCvarLogsdir = FindConVar("sv_logsdir");

	// Create config file
	AutoExecConfig(true, "LogUploader");

	// Win conditions met (maxrounds, timelimit)
	HookEvent("teamplay_game_over", GameOverEvent);

	// Win conditions met (windifference)
	HookEvent("tf_game_over", GameOverEvent);
}

public GameOverEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
	new bool:tournament = GetConVarBool(g_hCvarTournament);
	if(!tournament) {
		return;
	}
	ServerCommand("log on");
	CreateTimer(5.0, SearchLog);
}

public Action:SearchLog(Handle:timer)
{
	new count;
	new curTime = GetTime();
	decl String:fileName[32], String:fullPath[64], String:logsDir[64];
	GetConVarString(g_hCvarLogsdir, logsDir, sizeof(logsDir));
	new Handle:dir = OpenDirectory(logsDir);
	while(ReadDirEntry(dir, fileName, sizeof(fileName))) {
		if(StrEqual(fileName, ".")) {
			continue;
		}
		Format(fullPath, sizeof(fullPath), "%s/%s", logsDir, fileName);
		new fileTime = GetFileTime(fullPath, FileTime_LastChange);
		new fileSize = FileSize(fullPath);
		//PrintToChatAll("%s %i", fileName, curTime - fileTime);
		if(curTime - fileTime <= 10 && fileSize >= 10) {
			UploadLog(fullPath);
			count++;
			break;
		}
	}
	CloseHandle(dir);
	checkCount(count);
}


UploadLog(const String:fullPath[])
{
	decl String:APIKey[64];
	GetConVarString(g_hCvarAPIKey, APIKey, sizeof(APIKey));
	decl String:Title[64];
	GetConVarString(g_hCvarTitle, Title, sizeof(Title));
	new String:Map[64];
	GetCurrentMap(Map, sizeof(Map));
	//PrintToChatAll("LogUploader: Found log %s", fullPath);
	//PrintToChatAll("LogUploader: Attempting to upload log");
	new Handle:curl = curl_easy_init();
	CURL_DEFAULT_OPT(curl);
	postForm = curl_httppost();
	curl_formadd(postForm, CURLFORM_COPYNAME, "logfile", CURLFORM_FILE, fullPath, CURLFORM_END);
	curl_formadd(postForm, CURLFORM_COPYNAME, "title", CURLFORM_COPYCONTENTS, Title, CURLFORM_END);
	curl_formadd(postForm, CURLFORM_COPYNAME, "map", CURLFORM_COPYCONTENTS, Map, CURLFORM_END);
	curl_formadd(postForm, CURLFORM_COPYNAME, "key", CURLFORM_COPYCONTENTS, APIKey, CURLFORM_END);
	curl_easy_setopt_handle(curl, CURLOPT_HTTPPOST, postForm);

	output_file = curl_OpenFile("output.json", "w");
	curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, output_file);
	curl_easy_setopt_string(curl, CURLOPT_URL, "http://logs.tf/upload");
	curl_easy_perform_thread(curl, onComplete);
}

public checkCount(count)
{
	if (count == 0)
	{
		PrintToChatAll("LogUploader: Could not locate log, nothing uploaded");
	}
	return;
}

public onComplete(Handle:hndl, CURLcode:code)
{
	if(code != CURLE_OK)
	{
		new String:error_buffer[256];
		curl_easy_strerror(code, error_buffer, sizeof(error_buffer));
		CloseHandle(output_file);
		CloseHandle(hndl);
		PrintToChatAll("cURLCode error");
	}
	else
	{
		CloseHandle(output_file);
		CloseHandle(hndl);
		ParseJSON();
	}
	CloseHandle(postForm);
	return;
}

public ParseJSON()
{
	new Handle:resultFile = OpenFile("output.json", "r");
	new String:resBuff[512];
	ReadFileString(resultFile, resBuff, sizeof(resBuff));
	ReplaceString(resBuff, sizeof(resBuff), "\n", "", false);
	ReplaceString(resBuff, sizeof(resBuff), " ", "", false);
	//PrintToChatAll("Log response: %s", resBuff);
	new JSON:json = json_decode(resBuff);
	new logId = -1;
	new String:logUrl[16];
	if(json_get_cell(json, "log_id", logId)) {
		PrintToChatAll("[LogUploader] Log Id: %i", logId);
	}
	if(json_get_string(json, "url", logUrl, sizeof(logUrl)))
	{
		PrintToChatAll("[LogUploader] Log link: http://logs.tf%s", logUrl);
	}
	json_destroy(json);
	CloseHandle(resultFile);
	return;
}
