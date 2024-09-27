#pragma semicolon 1
#pragma tabsize 4
#pragma newdecls required

#include <sourcemod>
#include <autoexecconfig>
#include <tf2>

#define ID_LEN		   18
#define PLUGIN_VERSION "1.0.0"
#define _DEBUG		   false

public
Plugin myinfo = {
	name		= "sm_speedrun",
	author		= "Leigh MacDonald",
	description = "Track and forward how long rounds take for tracking speedruns",
	version		= PLUGIN_VERSION,
	url			= "https://github.com/leighmacdonald/sm_speedrun",
};

int g_startTime = -1;

enum struct PlayerInfo {
	int	 time_connected;
	char steam_id[ID_LEN];
}

enum struct RoundInfo {
	int		  time_elapsed;
	ArrayList players;
}

// ArrayList g_roundInfo;
PlayerInfo	  g_playerInfo[MAXPLAYERS + 1];
GlobalForward gf_RoundEndEvent;
ConVar		  sr_reset_empty;

public
void OnPluginStart() {
	// g_roundInfo = CreateArray(sizeof RoundInfo);
	gf_RoundEndEvent = new GlobalForward("OnRoundEnd", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_Cell);

	AutoExecConfig_SetFile("sm_speedrun");

	sr_reset_empty = AutoExecConfig_CreateConVar("sr_reset_empty", "1", "Auto restart map when no human players remain on the server", FCVAR_NONE, true, 0.0, true, 1.0);

	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
	HookEvent("teamplay_point_captured", OnPointCapture, EventHookMode_PostNoCopy);
	HookEvent("teamplay_round_win", OnRoundWin, EventHookMode_PostNoCopy);
}

public
void OnClientDisconnect_Post(int clientID) {
	if (getRealClientCount() <= 0 && sr_reset_empty.BoolValue) {
		reloadMap();

		return;
	}

	g_playerInfo[clientID].steam_id		  = "";
	g_playerInfo[clientID].time_connected = -1;
}

// https://wiki.alliedmods.net/Team_Fortress_2_Events#teamplay_round_win
public
void OnRoundWin(Handle event, const char[] name, bool dontBroadcast) {
	TFTeam team					= view_as<TFTeam>(GetEventInt(event, "team"));
	int	   winrreason			= GetEventInt(event, "winrreason");
	int	   flagcaplimit			= GetEventInt(event, "flagcaplimit");
	int	   full_round			= GetEventBool(event, "full_round");
	float  round_time			= GetEventFloat(event, "round_time");
	int	   losing_team_num_caps = GetEventInt(event, "losing_team_num_caps");
	int	   was_sudden_death		= GetEventInt(event, "was_sudden_death");

	debug("team: %d winrreason: %d flagcaplimit: %d full_round: %d round_time: %f losing_team_num_caps: %d was_sudden_death: %d",
		  team, winrreason, flagcaplimit, full_round, round_time, losing_team_num_caps, was_sudden_death);

	sendTimes();
}

public
void OnPointCapture(Handle event, const char[] name, bool dontBroadcast) {
	debug("point cap");

	RoundInfo info;
	info.time_elapsed = GetTime() - g_startTime;
	info.players	  = CreateArray(ID_LEN);

	for (int i = 0; i <= MaxClients; i++) {
		if (isValidClient(i) && g_playerInfo[i].time_connected > 0) {
			PushArrayString(info.players, g_playerInfo[i].steam_id);
		}
	}
}

public
void OnRoundStart(Handle event, const char[] name, bool dontBroadcast) {
	g_startTime = GetTime();

	if (GetEventBool(event, "full_reset", false)) {
		debug("Round started full");
	} else {
		debug("Round started");
	}

	int now = GetTime();

	for (int i = 0; i <= MaxClients; i++) {
		if (!isValidClient(i)) {
			continue;
		}

		g_playerInfo[i].time_connected = now;
	}
}

public
void reloadMap() {
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));

	ForceChangeLevel(map, "No more real players");
}

public
void OnClientAuthorized(int clientID) {
	if (!isValidClient(clientID)) {
		return;
	}

	PlayerInfo info;
	info.time_connected = 0;
	if (!GetClientAuthId(clientID, AuthId_SteamID64, info.steam_id, sizeof(info.steam_id), true)) {
		debug("Failed to get client steam id");
		return;
	}

	g_playerInfo[clientID] = info;
}

void sendTimes() {
	if (g_startTime <= 0) {
		debug("-- No times, skipping results submission");

		return;
	}
	int	 playersCount = 0;
	int	 duration	  = GetTime() - g_startTime;
	char mapName[128];
	GetCurrentMap(mapName, sizeof mapName);

	for (int i = 0; i <= sizeof(g_playerInfo); i++) {
		if (g_playerInfo[i].time_connected <= 0) {
			debug("Skipping player with no time recorded");

			continue;
		}

		playersCount++;
	}

	debug("-- sending results");
	debug("Elapsed time: %d", duration);
	debug("Map: %s", mapName);
	debug("Players: %d", playersCount);

	/* Start function call */
	Call_StartForward(gf_RoundEndEvent);

	/* Push parameters one at a time */
	Call_PushCell(duration);
	Call_PushString(mapName);

	/* Finish the call */
	Call_Finish();
}

stock int getRealClientCount() {
	int iClients = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) {
			iClients++;
		}
	}

	return iClients;
}

stock bool isValidClient(int client) {
	return !(1 <= client <= MaxClients) || !IsClientInGame(client) || IsFakeClient(client) || IsClientSourceTV(client) || IsClientReplay(client);
}

stock void	debug(const char[] format, any...) {
#if defined _DEBUG
	char buffer[254];
	VFormat(buffer, sizeof buffer, format, 2);
	PrintToServer("[GB] %s", buffer);
#endif
}
