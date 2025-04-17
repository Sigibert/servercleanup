/**
 * ==================================================================================
 *  Server Clean Up Change Log
 * ==================================================================================
 * 
 * 1.0
 * - Initial release.
 *
 * 1.1
 * - Added full translation support to convars.
 * - Added new cvar to control what type of logs to delete (normal logs, normal + 
 *   error logs, all logs).
 * - Added a command to manually execute clean up "sm_srvcln_now" (set to root only).
 * - Added a convar to control whether server clean up automatically cleans up on map
 *   start or not (enabled by default).
 * - Detection code totally rewritten.
 *
 * 1.1.1
 * - Fixed a small memory leak.
 *
 * 1.1.2
 * - Added support to clean up sprays.
 *
 * 1.1.3
 * - Added cvar "sm_srvcln_demos_path" so users can point to an optional location to
 *   their demo files.
 * - Added proper directory detection.
 * - Fixed translation errors.
 *
 * 1.1.4
 * - Fixed issue if you installed the plugin on a fresh server it would complain
 *   about the downloads directory being missing.
 *
 * 1.1.5
 * - Removed warnings about directories, only confuses users.
 *
 * 1.1.6
 * - Fixed return on "clean now" command.
 * - Removed an old check for the spray folder.
 *
 * 1.1.7
 * - Added WarMod support.
 *
 * 1.1.8
 * - Added round backup clean up for csgo in default form.
 * - New minimum time of 12 hours is now allowed, also added a super clean mode for 
 *   all time cvars using -1 which just keeps the current days files.
 * - Added a cvar to optionally log what gets deleted.
 *
 * 1.1.9
 * - Fixed round backup clean up for csgo to use the proper cvar for setting the 
 *   round backup file name prefix, thanks SanKen!
 *
 * 1.2.0
 * - Added support for replay cleaning and steampipe spray cleaning.
 * - Added cvar to control whether to check for archives too when cleaning replays.
 *
 * 1.2.1
 * - Added a more thorough check on the round backup files to prevent the deletion
 *   of important text files in the case of the mp_backup_round_file being empty.
 *
 * 1.2.2
 * - Fixed memory leaks and optimised some code (thanks 11530!)
 *
 * 1.3.0
 * - Added daily run option, writing file to preserve last run
 * - Changed to newdecls
 * - smlogs_type 0 & 1: Made the StrContains case sensitive with "L" to retain other logfiles starting with l
 * ==================================================================================
 */
 
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.3.0"

#define DEBUG 1

const LOG = 0;
const SML = 1;
const DEM = 2;
const SPR = 3;
const RND = 4;
const RPY = 5;
const MAX = 6;

ConVar cvar_type[MAX],
	cvar_time[MAX],
	cvar_arch_demos,
	cvar_arch_replays,
	cvar_enable,
	cvar_logtype,
	cvar_demopath,
	cvar_logging,
	cvar_run_hour;

Handle g_warpath,
	g_logsdir,
	g_backuproundprefix;

char s_backuproundprefix[PLATFORM_MAX_PATH],
    g_sLastRunFile[PLATFORM_MAX_PATH];

bool b_usewarmod;

#if DEBUG
char LogFilePath[PLATFORM_MAX_PATH];
#endif

public Plugin myinfo = 
{
	name = "Server Clean Up _Xnet CS:GO",
	author = "Jamster, forked by MeroWinger",
	description = "Cleans up logs and demo files automatically",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net/"
};

public void OnPluginStart()
{
	LoadTranslations("servercleanup.phrases");
	char desc[256];
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_version");
	CreateConVar("sm_srvcln_version", PLUGIN_VERSION, desc, FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_enable");
	cvar_enable = CreateConVar("sm_srvcln_enable", "1", desc, FCVAR_NONE, true, 0.0, true, 1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_logging_mode");
	cvar_logging = CreateConVar("sm_srvcln_logging_mode", "0", desc, FCVAR_NONE, true, 0.0, true, 1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_logs");
	cvar_type[LOG] = CreateConVar("sm_srvcln_logs", "0", desc, FCVAR_NONE, true, 0.0, true, 1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_smlogs");
	cvar_type[SML] = CreateConVar("sm_srvcln_smlogs", "1", desc, FCVAR_NONE, true, 0.0, true, 1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_demos");
	cvar_type[DEM] = CreateConVar("sm_srvcln_demos", "0", desc, FCVAR_NONE, true, 0.0, true, 1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_replays");
	cvar_type[RPY] = CreateConVar("sm_srvcln_replays", "0", desc, FCVAR_NONE, true, 0.0, true, 1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_replays_archives");
	cvar_arch_replays = CreateConVar("sm_srvcln_replays_archives", "0", desc, FCVAR_NONE, true, 0.0, true, 1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_roundbackups");
	cvar_type[RND] = CreateConVar("sm_srvcln_roundbackups", "0", desc, FCVAR_NONE, true, 0.0, true, 1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_demos_path");
	cvar_demopath = CreateConVar("sm_srvcln_demos_path", ".", desc, FCVAR_NONE);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_sprays");
	cvar_type[SPR] = CreateConVar("sm_srvcln_sprays", "0", desc, FCVAR_NONE, true, 0.0, true, 1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_demos_archives");
	cvar_arch_demos = CreateConVar("sm_srvcln_demos_archives", "0", desc, FCVAR_NONE, true, 0.0, true, 1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_smlogs_type");
	cvar_logtype = CreateConVar("sm_srvcln_smlogs_type", "1", desc, FCVAR_NONE, true, 0.0, true, 2.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_logs_time");
	cvar_time[LOG] = CreateConVar("sm_srvcln_logs_time", "168", desc, FCVAR_NONE, true, -1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_sprays_time");
	cvar_time[SPR] = CreateConVar("sm_srvcln_sprays_time", "168", desc, FCVAR_NONE, true, -1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_smlogs_time");
	cvar_time[SML] = CreateConVar("sm_srvcln_smlogs_time", "168", desc, FCVAR_NONE, true, -1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_demos_time");
	cvar_time[DEM] = CreateConVar("sm_srvcln_demos_time", "168", desc, FCVAR_NONE, true, -1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_replays_time");
	cvar_time[RPY] = CreateConVar("sm_srvcln_replays_time", "168", desc, FCVAR_NONE, true, -1.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_roundbackups_time");
	cvar_time[RND] = CreateConVar("sm_srvcln_roundbackups_time", "168", desc, FCVAR_NONE, true, -1.0);

	FormatEx(desc, sizeof(desc), "%t", "srvcln_run_hour");
	cvar_run_hour = CreateConVar("sm_srvcln_run_hour", "12", desc, FCVAR_NONE, true, -1.0, true, 24.0);
	
	FormatEx(desc, sizeof(desc), "%t", "srvcln_now");
	RegAdminCmd("sm_srvcln_now", CommandCleanNow, ADMFLAG_ROOT, desc);
	
	g_logsdir = FindConVar("sv_logsdir");
	g_backuproundprefix = FindConVar("mp_backup_round_file");

	
    BuildPath(Path_SM, g_sLastRunFile, sizeof(g_sLastRunFile), "data/%s.txt", "servercleanup");

	AutoExecConfig(true, "plugin.servercleanup");
}

public void OnAllPluginsLoaded()
{
	g_warpath = FindConVar("wm_save_dir");
	if (g_warpath != INVALID_HANDLE)
		b_usewarmod = true;
	else
		b_usewarmod = false;
}

public void OnConfigsExecuted()
{
	#if DEBUG
	BuildPath(Path_SM, LogFilePath, sizeof(LogFilePath), "logs/srvcln_debug.log");
	PrintToServer(LogFilePath);
	#endif

	char lastRunDate[16];
    bool ranToday = false;
	char hourBuffer[4];
    FormatTime(hourBuffer, sizeof(hourBuffer), "%H");
	int runHour = GetConVarInt(cvar_run_hour) % 24;
    int currentHour = StringToInt(hourBuffer);
    char today[16];
    FormatTime(today, sizeof(today), "%Y-%m-%d");

    if (FileExists(g_sLastRunFile))
    {
        File hFile = OpenFile(g_sLastRunFile, "r");
        if (hFile != null)
        {
            hFile.ReadString(lastRunDate, sizeof(lastRunDate));
            TrimString(lastRunDate);
            hFile.Close();
        }
        ranToday = StrEqual(today, lastRunDate);
    }
	
	if (GetConVarInt(cvar_enable) && (!ranToday || runHour < 0) && currentHour >= runHour)
	{
		#if DEBUG
		LogToFileEx(LogFilePath, "Running daily action!");
		#endif

		for (int i; i < MAX; i++)
			if (GetConVarInt(cvar_type[i]))
				CleanServer(i);

		File hFile = OpenFile(g_sLastRunFile, "w");
        if (hFile != null)
        {
            WriteFileLine(hFile, "%s", today);
            hFile.Close();
        }
	}
}

public Action CommandCleanNow(int client, int args)
{
	ReplyToCommand(client, "%t", "Command Now Start");
	for (int i; i < MAX; i++)
		if (GetConVarInt(cvar_type[i]))
			CleanServer(i);
	ReplyToCommand(client, "%t", "Command Now End");
	LogMessage("\"%L\" %t", client, "Command Now Log");
	return Plugin_Handled;
}

void CleanServer(int type)
{	
	int Time32;
	int TimeType = GetConVarInt(cvar_time[type]);
	if (TimeType != -1)
	{
		Time32 = GetTime() / 3600 - TimeType;
	}
	else
	{
		char day[10];
		FormatTime(day, sizeof(day), "%Y%j");
		Time32 = StringToInt(day);
	}
	
	char filename[256];
	char dir[PLATFORM_MAX_PATH];
	
	int logging = GetConVarInt(cvar_logging);
	
	switch (type)
	{
		case LOG:
			GetConVarString(g_logsdir, dir, sizeof(dir));
		case SML:
			BuildPath(Path_SM, dir, sizeof(dir), "logs");
		case DEM:
			GetConVarString(cvar_demopath, dir, sizeof(dir));
		case SPR:
			FormatEx(dir, sizeof(dir), "downloads");
		case RND:
			FormatEx(dir, sizeof(dir), "");
	}
	
	if (b_usewarmod && type == DEM)
		GetConVarString(g_warpath, dir, sizeof(dir));
	
	Handle h_dir = INVALID_HANDLE;
	
	#if DEBUG
	switch (type)
	{
		case LOG:
			LogToFileEx(LogFilePath, "~~ Regular logs dir files ~~");
		case SML:
			LogToFileEx(LogFilePath, "~~ SourceMod logs dir files ~~");
		case DEM:
			LogToFileEx(LogFilePath, "~~ Demo files ~~");
		case SPR:
			LogToFileEx(LogFilePath, "~~ Spray files ~~");
		case RND:
			LogToFileEx(LogFilePath, "~~ Round backup files ~~");
		case RPY:
			LogToFileEx(LogFilePath, "~~ Replay files ~~");
	}
	#endif
	
	if (type == RND && g_backuproundprefix != INVALID_HANDLE)
	{
		char cvar[PLATFORM_MAX_PATH];
		GetConVarString(g_backuproundprefix, cvar, sizeof(cvar));
		TrimString(cvar);
		if (!cvar[0])
		{
			FormatEx(s_backuproundprefix, sizeof(s_backuproundprefix), "round");
		}
		else
		{
			FormatEx(s_backuproundprefix, sizeof(s_backuproundprefix), "%s_round", cvar);
		}
	}
//	else if (type == RND)
//	{
//		return false;
//	}
		
	
	int strLength;
	int DelArchDemos = GetConVarInt(cvar_arch_demos);
	int DelArchReplays = GetConVarInt(cvar_arch_replays);
	int LogType = GetConVarInt(cvar_logtype);
	
	if (type == RPY)
	{
		for (int i=0;i<=2;i++)
		{
			switch (i)
			{
				case 0:
					FormatEx(dir, sizeof(dir), "replay/server/blocks");
				case 1:
					FormatEx(dir, sizeof(dir), "replay/server/sessions");
				case 2:
					FormatEx(dir, sizeof(dir), "replay/server/tmp");
			}
			
			if (DirExists(dir))
			{
				#if DEBUG
				LogToFileEx(LogFilePath, "[Under: %s]", dir);
				#endif 
				
				h_dir = OpenDirectory(dir);
				
				while (ReadDirEntry(h_dir, filename, sizeof(filename)))
				{
					if (StrEqual(filename, ".") || StrEqual(filename, ".."))
						continue;
						
					#if DEBUG
					LogToFileEx(LogFilePath, "%s/%s", dir, filename);
					#endif 
						
					strLength = strlen(filename);
					
					if (StrContains(filename, ".dmx", false) == strLength-4 || StrContains(filename, ".block", false) == strLength-6)
					{
						CanDelete(Time32, TimeType, dir, filename, type, logging);
						continue;
					}
					else if (DelArchReplays && (StrContains(filename, ".zip", false) == strLength-4 || StrContains(filename, ".bz2", false) == strLength-4 || StrContains(filename, ".rar", false) == strLength-4 || StrContains(filename, ".7z", false) == strLength-3))
					{
						CanDelete(Time32, TimeType, dir, filename, type, logging);
						continue;
					}
				}
				
				CloseHandle(h_dir);
				h_dir = INVALID_HANDLE;
				
			}
		}
	}
	else if (type == SPR)
	{
		if (DirExists(dir))
		{
			#if DEBUG
			LogToFileEx(LogFilePath, "[Under: %s]", dir);
			#endif 
		
			h_dir = OpenDirectory(dir);
			while (ReadDirEntry(h_dir, filename, sizeof(filename)))
			{
				
				if (StrEqual(filename, ".") || StrEqual(filename, ".."))
					continue;
					
				#if DEBUG
				LogToFileEx(LogFilePath, "%s/%s", dir, filename);
				#endif 
					
				strLength = strlen(filename);
				
				if (StrContains(filename, ".dat", false) == strLength-4 || StrContains(filename, ".ztmp", false) == strLength-5)
				{
					CanDelete(Time32, TimeType, dir, filename, type, logging);
					continue;
				} 
			}
			
			CloseHandle(h_dir);
			h_dir = INVALID_HANDLE;
			
		}
			
		FormatEx(dir, sizeof(dir), "download/user_custom");
		
		if (DirExists(dir))
		{
			h_dir = OpenDirectory(dir);
			char subdir[PLATFORM_MAX_PATH];
			char fullpath[PLATFORM_MAX_PATH]; 
			Handle h_subdir = INVALID_HANDLE;
			
			while (ReadDirEntry(h_dir, subdir, sizeof(subdir)))
			{
				if (StrEqual(subdir, ".") || StrEqual(subdir, ".."))
					continue;
					
				FormatEx(fullpath, sizeof(fullpath), "%s/%s", dir, subdir);
				
				#if DEBUG
				LogToFileEx(LogFilePath, "[Under: %s]", fullpath);
				#endif 
				
				if (DirExists(fullpath))
				{
					h_subdir = OpenDirectory(fullpath);
					bool emptyfolder = true;
					while (ReadDirEntry(h_subdir, filename, sizeof(filename)))
					{
						if (StrEqual(filename, ".") || StrEqual(filename, ".."))
							continue;
							
						emptyfolder = false;
							
						#if DEBUG
						LogToFileEx(LogFilePath, "%s/%s", fullpath, filename);
						#endif 
						
						strLength = strlen(filename);
						
						if (StrContains(filename, ".dat", false) == strLength-4 || StrContains(filename, ".ztmp", false) == strLength-5)
						{
							CanDelete(Time32, TimeType, fullpath, filename, type, logging);
							continue;
						}
					}
					
					CloseHandle(h_subdir);
					h_subdir = INVALID_HANDLE;
					
					if (emptyfolder)
						CanDelete(Time32, TimeType, dir, subdir, type, logging, true, true);
				}
				
			}
			
			CloseHandle(h_dir);
			h_dir = INVALID_HANDLE;
			
		}
	}
	else
	{
		if (!StrEqual(dir, "") && DirExists(dir))
		{
			h_dir = OpenDirectory(dir);
			
			while (ReadDirEntry(h_dir, filename, sizeof(filename)))
			{
				
				if (StrEqual(filename, ".") || StrEqual(filename, ".."))
					continue;
					
				#if DEBUG
				LogToFileEx(LogFilePath, "%s/%s", dir, filename);
				#endif 
					
				strLength = strlen(filename);
				
				if (type == LOG)
				{
					if (StrContains(filename, ".log", false) == strLength-4)
					{
							CanDelete(Time32, TimeType, dir, filename, type, logging);
							continue;
					}
				}
				else if (type == SML)
				{
					if (!LogType)
					{
						if (StrContains(filename, "L") == 0 && StrContains(filename, ".log", false) == strLength-4)
						{
							CanDelete(Time32, TimeType, dir, filename, type, logging);
							continue;
						}
					}
					else if (LogType == 1)
					{
						if ((StrContains(filename, "L") == 0 || StrContains(filename, "errors_", false) == 0) && StrContains(filename, ".log", false) == strLength-4)
						{
							CanDelete(Time32, TimeType, dir, filename, type, logging);
							continue;
						}
					}
					else if (LogType == 2 && StrContains(filename, ".log", false) == strLength-4)
					{
						CanDelete(Time32, TimeType, dir, filename, type, logging);
						continue;
					}
				}
				else if (type == DEM)
				{
					if ((StrContains(filename, "auto-", false) == 0 || b_usewarmod) && StrContains(filename, ".dem", false) == strLength-4)
					{
						CanDelete(Time32, TimeType, dir, filename, type, logging);
						continue;
					} 
					else if (((DelArchDemos && StrContains(filename, "auto-", false) == 0) || b_usewarmod) && (StrContains(filename, ".zip", false) == strLength-4 || StrContains(filename, ".bz2", false) == strLength-4 || StrContains(filename, ".rar", false) == strLength-4 || StrContains(filename, ".7z", false) == strLength-3))
					{
						CanDelete(Time32, TimeType, dir, filename, type, logging);
						continue;
					}
				}
				else if (type == RND)
				{
					if (StrContains(filename, s_backuproundprefix, false) == 0 && StrContains(filename, ".txt", false) == strLength-4 && IsCharNumeric(filename[strLength-5]) && IsCharNumeric(filename[strLength-6]))
					{
						CanDelete(Time32, TimeType, dir, filename, type, logging);
						continue;
					}
				}
			}
			
			CloseHandle(h_dir);
			h_dir = INVALID_HANDLE;
				
		}
	}

	#if DEBUG
	switch (type)
	{
		case LOG:
			LogToFileEx(LogFilePath, "~~ Regular logs dir files handled ~~");
		case SML:
			LogToFileEx(LogFilePath, "~~ SourceMod logs dir files handled ~~");
		case DEM:
			LogToFileEx(LogFilePath, "~~ Demo files handled ~~");
		case SPR:
			LogToFileEx(LogFilePath, "~~ Spray files handled ~~");
		case RND:
			LogToFileEx(LogFilePath, "~~ Round backup files handled ~~");
		case RPY:
			LogToFileEx(LogFilePath, "~~ Replay files handled ~~");
	}
	#endif
	
//	return true;
}

void CanDelete(const int Time32, const int TimeType, const char[] dir, const char[] filename, const int type, const int logging, const bool force=false, const bool folder=false)
{
	#if DEBUG
	LogToFileEx(LogFilePath, "[Checking] %s/%s", dir, filename);
	#endif
	
	int TimeStamp;
	char file[PLATFORM_MAX_PATH];
	FormatEx(file, sizeof(file), "%s/%s", dir, filename);
	if (type == SPR)
	{
		// Sprays are done on last access due to players requesting them.
		TimeStamp = GetFileTime(file, FileTime_LastAccess);
		if (TimeStamp == -1)
		{
			TimeStamp = GetFileTime(file, FileTime_LastChange);
		}
	}
	else
	{
		TimeStamp = GetFileTime(file, FileTime_LastChange);
	}
	
	if (TimeType != -1)
	{
		TimeStamp /= 3600;
	}
	else
	{
		char day[10];
		FormatTime(day, sizeof(day), "%Y%j", TimeStamp);
		TimeStamp = StringToInt(day);
	}
	
	if (TimeStamp == -1)
	{
		LogError("%t", "CL Error TS", file);
	}
	
	if (Time32 > TimeStamp || force)
	{
		if (folder ? !RemoveDir(file) : !DeleteFile(file))
		{
			LogError("%t", "CL Error Del", file);
			#if DEBUG
			LogToFileEx(LogFilePath, "[DENIED] %s/%s", dir, filename);
			#endif
		}
		else if (logging)
		{
			switch (folder)
			{
				case false:
					LogMessage("%t", "CL Deleted File", file);
				case true:
					LogMessage("%t", "CL Deleted Folder", file);
			}
		}
		
		#if DEBUG
		if (folder ? !DirExists(file) : !FileExists(file))
		{
			LogToFileEx(LogFilePath, "[Deleted] %s/%s", dir, filename);
		}
		#endif
	}
}
