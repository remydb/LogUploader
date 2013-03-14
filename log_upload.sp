#pragma semicolon 1
#include <sourcemod>
#include <cURL>

public Plugin:myinfo =
{
        name = "Log auto-uploader",
        author = "Duckeh",
        description = "Auto-upload match logs to logs.tf",
        version = "1.2",
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

new Handle:g_APIKey = INVALID_HANDLE;
new Handle:output_file = INVALID_HANDLE;
new Handle:dir = INVALID_HANDLE;
new Handle:postForm = INVALID_HANDLE;
new Handle:curl = INVALID_HANDLE;
new Handle:resultFile = INVALID_HANDLE;
new Int:count;

public OnPluginStart()
{
                // Register 'sm_log' command
                RegConsoleCmd("sm_log", Command_LOG, "Displays info on log plugin.");

		// Register CVar for API-Key
		g_APIKey = CreateConVar("sm_logup_apikey", "", "Set the logs.tf API key", FCVAR_PROTECTED);

		// Create config file
		AutoExecConfig(true, "LogUploader");

                // Win conditions met (maxrounds, timelimit)
                HookEvent("teamplay_game_over", GameOverEvent);

                // Win conditions met (windifference)
                HookEvent("tf_game_over", GameOverEvent);
}

public Action:Command_LOG(client, args)
{
        ReplyToCommand(client, "This server will try to automatically upload logs.");

	return Plugin_Handled;
}

public GameOverEvent(Handle:event, const String:name[], bool:dontBroadcast)
{
        PrintToChatAll("LogUploader: End of game detected.");
        PrintToChatAll("LogUploader: Searching for log..");

        new String:path[40] = "logs/";
        new String:buff[] = "";
        dir = OpenDirectory(path);
	count = Int:0;
	decl String:APIKey[128];
	GetConVarString(g_APIKey, APIKey, sizeof(APIKey));
        while(ReadDirEntry(dir, buff, 15))
        {
                new String:fullPath[50] = "logs/";
                StrCat(fullPath, 50, buff);
                new fileTime = GetFileTime(fullPath, FileTime_LastChange);
                new Int:timeDiff = Int:GetTime() - Int:fileTime;
                if (timeDiff <= Int:60 && StrEqual(fullPath, "logs/.", false) == false)
                {
                        new String:map[40];
                        GetCurrentMap(map, 40);
                        PrintToChatAll("LogUploader: Found log %s", fullPath);
                        PrintToChatAll("LogUploader: Attempting to upload log");
                        curl = curl_easy_init();
                        CURL_DEFAULT_OPT(curl);
                        postForm = curl_httppost();
                        curl_formadd(postForm, CURLFORM_COPYNAME, "logfile", CURLFORM_FILE, fullPath, CURLFORM_END);
                        curl_formadd(postForm, CURLFORM_COPYNAME, "map", CURLFORM_COPYCONTENTS, map, CURLFORM_END);
                        curl_formadd(postForm, CURLFORM_COPYNAME, "key", CURLFORM_COPYCONTENTS, APIKey, CURLFORM_END);
                        curl_easy_setopt_handle(curl, CURLOPT_HTTPPOST, postForm);

                        output_file = curl_OpenFile("output.json", "w");
                        curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, output_file);
                        curl_easy_setopt_string(curl, CURLOPT_URL, "http://logs.tf/upload");
       	                curl_easy_perform_thread(curl, onComplete);
			count++;
                }
        }
	checkCount();
}

public checkCount()
{
	if (count == Int:0)
	{
		PrintToChatAll("LogUploader: Could not locate log, nothing uploaded");
		return;
	}
	else
	{
		return;
	}
}

public onComplete(Handle:hndl, CURLcode:code)
{
        if(code != CURLE_OK)
        {
                new String:error_buffer[256];
                curl_easy_strerror(code, error_buffer, sizeof(error_buffer));
                CloseHandle(hndl);
		PrintToChatAll("cURLCode error");
        }
	else
	{
		CloseHandle(output_file);
	        CloseHandle(hndl);
                resultFile = OpenFile("output.json", "r");
		new String:resBuff[256];
	        while(ReadFileLine(resultFile, resBuff, sizeof(resBuff)))
	        {
	        	PrintToChatAll("LogUploader: %s", resBuff);
                }
                CloseHandle(resultFile);
	}
	CloseHandle(postForm);
        CloseHandle(dir);
	return;
}
