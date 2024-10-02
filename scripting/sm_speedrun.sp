#pragma semicolon 1
#pragma tabsize 4
#pragma newdecls required

#include <sourcemod>
#include <autoexecconfig>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>

#define ID_LEN			18
#define MAXROUNDS		10
#define MAXDISCONNECTED MAXPLAYERS * 2
#define PLUGIN_VERSION	"1.0.0"
#define _DEBUG			false

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
	int	 time_start;
	int	 time_end;
	char steam_id[ID_LEN];
}

PlayerInfo	  g_playerInfo[MAXPLAYERS];

int			  g_playerInfo_disconnected_idx;
PlayerInfo	  g_playerInfo_disconnected[MAXDISCONNECTED];

GlobalForward gf_RoundEndEvent;
ConVar		  sr_reset_empty;

float g_roundTime;

int g_setupCompleted = false;

// L 09/29/2024 - 20:29:25: "ุ<3><[U:1:123868297]><Blue>" changed role to "soldier"
// L 09/29/2024 - 20:29:31: World triggered "Round_Start"
// L 09/29/2024 - 20:29:31: World triggered "Round_Setup_Begin"
// L 09/29/2024 - 20:29:31: World triggered "Mini_Round_Selected" (round "eotl_round_1")
// L 09/29/2024 - 20:29:31: World triggered "Mini_Round_Start"
// L 09/29/2024 - 20:29:44: World triggered "Round_Setup_End"
// miniround_win

public
void OnPluginStart() {
	gf_RoundEndEvent = new GlobalForward("OnSpeedrunEnd", ET_Ignore, Param_Cell);

	AutoExecConfig_SetFile("sm_speedrun");

	sr_reset_empty = AutoExecConfig_CreateConVar("sr_reset_empty", "1", "Auto restart map when no human players remain on the server", FCVAR_NONE, true, 0.0, true, 1.0);

	// Mini_Round_Start?
	HookEvent("teamplay_setup_finished", OnTeamplaySetupFinished);
	HookEvent("teamplay_win_panel", OnRoundWinPanel);
	// HookEvent("round_start", OnRoundStart);
	HookEvent("teamplay_point_captured", OnPointCapture);
	HookEvent("teamplay_round_win", OnRoundWin);
	//HookEvent("teamplay_round_start", OnRoundStart);
	HookEvent("teamplay_game_over", onTeamplayGameOver);
	HookEvent("tf_game_over", OnGameOver);
	// HookEvent("teamplay_round_active");
}

public
APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max) {
	RegPluginLibrary("sm_speedrun");

	return APLRes_Success;
}

public
void OnMapEnd() {
	debug("[EVENT] Map End");
}

public
void onTeamplayGameOver(Handle event, const char[] name, bool dontBroadcast) {
	debug("[EVENT] %s", name);
	char reason[12];
	GetEventString(event, "reason", reason, sizeof reason);
	if (strcmp(reason, "winlimit") == 0) {
		debug("Templay Game end event ( WINLIMIT )");
		return;
	}

	debug("Templay Game end event");
}

public
void OnGameOver(Handle event, const char[] name, bool dontBroadcast) {
	debug("[EVENT] %s", name);

	char reason[12];
	GetEventString(event, "reason", reason, sizeof reason);
	if (strcmp(reason, "winlimit") == 0) {
		debug("Game end event ( WINLIMIT )");
		return;
	}
}

public
void OnTeamplaySetupFinished(Handle event, const char[] name, bool dontBroadcast) {
	if (GetEventBool(event, "full_round", false) || g_setupCompleted == 0) {
		debug("Resetting round data due to full restart");
		restart();
	}

	g_setupCompleted++;

	debug("Speedrun Round #%d", g_setupCompleted);

	if ((g_setupCompleted - 1) > 0) {
		return;
	}

	int now		= GetTime();
	g_startTime = now;

	for (int i = 0; i < MaxClients; i++) {
		if (!isValidClient(i)){
			continue;
		}

		char sid[ID_LEN];
		GetClientAuthId(GetClientOfUserId(i), AuthId_SteamID64, sid, sizeof sid);
		g_playerInfo[i].steam_id = sid;
		g_playerInfo[i].time_start = now;
		g_playerInfo[i].time_end   = -1;
	}
}

void restart() {
	int now = GetTime();

	for (int i = 0; i < sizeof g_playerInfo; i++) {
		g_playerInfo[i].time_start = now;
		g_playerInfo[i].time_end   = -1;
	}

	for (int i = 0; i < sizeof g_playerInfo_disconnected; i++) {
		g_playerInfo_disconnected[i].steam_id	= "";
		g_playerInfo_disconnected[i].time_start = -1;
		g_playerInfo_disconnected[i].time_end	= -1;
	}

	g_setupCompleted = 0;
}

public
void OnClientDisconnect_Post(int clientID) {
	// Copy the players participation info over;
	g_playerInfo_disconnected[g_playerInfo_disconnected_idx].steam_id	= g_playerInfo[clientID].steam_id;
	g_playerInfo_disconnected[g_playerInfo_disconnected_idx].time_start = g_playerInfo[clientID].time_start;
	g_playerInfo_disconnected[g_playerInfo_disconnected_idx].time_end	= GetTime();

	g_playerInfo[clientID].steam_id										= "";
	g_playerInfo[clientID].time_start									= -1;
	g_playerInfo[clientID].time_end										= -1;

	g_playerInfo_disconnected_idx++;
	if (g_playerInfo_disconnected_idx > MAXDISCONNECTED) {
		g_playerInfo_disconnected_idx = 0;
	}

	if (isValidClient(clientID) && getRealClientCount() <= 0 && sr_reset_empty.BoolValue) {
		// reloadMap();

		return;
	}
}

// https://wiki.alliedmods.net/Team_Fortress_2_Events#teamplay_win_panel
public
void OnRoundWinPanel(Handle event, const char[] name, bool dontBroadcast) {
	debug("[EVENT] %s", name);
	TFTeam team			= view_as<TFTeam>(GetEventInt(event, "winning_team"));
	int	   winrreason	= GetEventInt(event, "winrreason");
	int	   flagcaplimit = GetEventInt(event, "flagcaplimit");
	bool   round_complete	= GetEventBool(event, "round_complete");


	debug("team: %d winrreason: %d flagcaplimit: %d round_complete: %d",
		  team, winrreason, flagcaplimit, round_complete);
	
	if (!round_complete) {
		return;
	}

	if (team != TFTeam_Blue) {
		return;
	}

	int now = GetTime();

	for (int i = 0; i < sizeof g_playerInfo; i++) {
		if (!isValidClient(i)) {
			continue;
		}
		if (g_playerInfo[i].time_start > 0) {
			g_playerInfo[i].time_end = now;
		}
	}

	sendTimes();

}


// https://wiki.alliedmods.net/Team_Fortress_2_Events#teamplay_round_win
public
void OnRoundWin(Handle event, const char[] name, bool dontBroadcast) {
	debug("[EVENT] %s", name);
	g_roundTime	= GetEventFloat(event, "round_time");
	debug("Set round time: %f", g_roundTime);
}

public
void OnPointCapture(Handle event, const char[] name, bool dontBroadcast) {
	debug("[EVENT] %s", name);
	int	 cp = GetEventInt(event, "cp");
	char cpName[128];
	GetEventString(event, "cpname", cpName, sizeof cpName);
	TFTeam team = view_as<TFTeam>(GetEventInt(event, "team"));

	char   cappers[32];
	GetEventString(event, "cappers", cappers, MAXPLAYERS);

	char message[200];
	int	 client_index;
	int	 cappers_count	= strlen(cappers);
	int[] cappers_array = new int[cappers_count];

	for (int i = 0; i < cappers_count; i++) {
		client_index = view_as<int>(cappers[i]);

		Format(message, sizeof(message), "%s, %N", message, client_index);
		cappers_array[i] = client_index;

		char s64[18];
		if (!GetClientAuthId(client_index, AuthId_SteamID64, s64, sizeof s64, true)) {
			continue;
		}

		debug("%N: %s", client_index, s64);
	}

	debug("point: %d cpname: %s team: %d cappers: %s", cp, cpName, team, cappers);
}

public
void reloadMap() {
	debug("Reloading map");
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));

	ForceChangeLevel(map, "No more real players");
}

public
void OnClientAuthorized(int clientID) {
	if (!isValidClient(clientID)) {
		return;
	}

	char steam_id[ID_LEN];
	if (!GetClientAuthId(clientID, AuthId_SteamID64, steam_id, sizeof(steam_id), true)) {
		debug("Failed to get client steam id");
		return;
	}

	g_playerInfo[clientID].steam_id	  = steam_id;
	g_playerInfo[clientID].time_start = g_setupCompleted ? GetTime() : -1;
	g_playerInfo[clientID].time_end = -1;

	debug("Player initialized: %s | %d", steam_id, g_playerInfo[clientID].time_start);
}

void sendTimes() {
	if (g_startTime <= 0) {
		LogError("-- No start time, skipping results submission");

		return;
	}

	int	 duration = GetTime() - g_startTime;
	char mapName[128];
	GetCurrentMap(mapName, sizeof mapName);

	int		   realPlayerCount = getRealClientCount();
	int		   botPlayerCount  = getBotClientCount();
	PlayerInfo players[256];
	int		   total = 0;

	for (int i = 0; i < sizeof g_playerInfo; i++) {
		if (!isValidClient(i)) {
			continue;
		}
		if (g_playerInfo[i].time_start <= 0 || strcmp(g_playerInfo[i].steam_id, "") == 0) {
			continue;
		}

		players[total].steam_id	  = g_playerInfo[i].steam_id;
		players[total].time_start = g_playerInfo[i].time_start;
		players[total].time_end	  = g_playerInfo[i].time_end;

		total++;
	}

	for (int i = 0; i < sizeof g_playerInfo_disconnected; i++) {
		if (g_playerInfo_disconnected[i].time_start <= 0 || strcmp(g_playerInfo[i].steam_id, "") == 0) {
			continue;
		}

		players[total].steam_id	  = g_playerInfo[i].steam_id;
		players[total].time_start = g_playerInfo[i].time_start;
		players[total].time_end	  = g_playerInfo[i].time_end;

		total++;
	}

	debug("-- sending results");
	debug("Elapsed time: %d", duration);
	debug("Map: %s", mapName);
	debug("Players: %d", total);

	DataPack pack = new DataPack();
	pack.WriteCell(duration);
	pack.WriteString(mapName);
	pack.WriteCell(realPlayerCount);
	pack.WriteCell(botPlayerCount);
	pack.WriteCell(total);

	for (int i = 0; i < total; i++) {
		pack.WriteString(players[i].steam_id);
		pack.WriteCell(players[i].time_start);
		pack.WriteCell(players[i].time_end);
		pack.WriteCell(getScore(i));

		debug("sid: %s score: %d duration: %d", players[i].steam_id, getScore(i), players[i].time_end - players[i].time_start);
	}

	Call_StartForward(gf_RoundEndEvent);
	Call_PushCell(pack);
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

// Get player's score
stock int getScore(int client)
{	
	int entity = GetPlayerResourceEntity();
	int value = GetEntProp(entity, Prop_Send, "m_iTotalScore", _, client);
	return value;

	//entity = new GetPlayerResourceEntity();
	// return GetEntProp(client, Prop_Send, "m_iTotalScore", _, client);
	// return TF2_GetPlayerResourceData(client, TFResource_TotalScore);
}

stock int getBotClientCount() {
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

stock void debug(const char[] format, any...) {
#if defined _DEBUG
	char buffer[254];
	VFormat(buffer, sizeof buffer, format, 2);
	PrintToServer("[Speedrun] %s", buffer);
	PrintToChatAll("[Speedrun] %s", buffer);
#endif
}
