#pragma semicolon 1
#pragma tabsize 4
#pragma newdecls required

#include <sourcemod>
#include <autoexecconfig>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>
#include <datapack>
#include <morecolors>

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

enum struct PlayerInfo {
	float time_start;
	float time_end;
	char  steam_id[ID_LEN];
}

PlayerInfo	  g_playerInfo[MAXPLAYERS];

int			  g_playerInfo_disconnected_idx;
PlayerInfo	  g_playerInfo_disconnected[MAXDISCONNECTED];

GlobalForward gf_RoundEndEvent;

ConVar		  sr_reset_empty;

float		  g_startTime = 0.0;
float		  g_roundTime;
int			  g_speedrunRound = 0;
bool		  g_isWin		  = false;

public
void OnPluginStart() {
	gf_RoundEndEvent = new GlobalForward("OnSpeedrunEnd", ET_Ignore, Param_Cell);

	AutoExecConfig_SetFile("sm_speedrun");

	sr_reset_empty = AutoExecConfig_CreateConVar("sr_reset_empty", "1", "Auto restart map when no human players remain on the server", FCVAR_NONE, true, 0.0, true, 1.0);

	HookEvent("teamplay_win_panel", OnRoundWinPanel);
	HookEvent("teamplay_round_win", OnRoundWin);
	HookEvent("teamplay_game_over", onTeamplayGameOver);
	HookEvent("tf_game_over", onTeamplayGameOver);
}

public
APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max) {
	RegPluginLibrary("sm_speedrun");

	return APLRes_Success;
}

public
void OnMapStart() {
	g_speedrunRound = 0;
}

public
void onTeamplayGameOver(Handle event, const char[] name, bool dontBroadcast) {
	if (!g_isWin) {
		return;
	}

	float now = GetGameTime();

	for (int i = 1; i <= MaxClients; i++) {
		if (!isValidClient(i)) {
			continue;
		}
		if (g_playerInfo[i].time_start > 0) {
			g_playerInfo[i].time_end = now;
		}
	}

	char reason[12];
	GetEventString(event, "reason", reason, sizeof reason);
	debug("[EVENT] %s (%s)", name, reason);
	if (strcmp(reason, "winlimit") == 0) {
		debug("Templay Game end event ( WINLIMIT )");

		return;
	}

	sendTimes();
}

public
void TF2_OnWaitingForPlayersEnd() {
	reset();
	startSpeedrun();
}

void startSpeedrun() {
	g_speedrunRound++;

	if (g_speedrunRound > 1) {
		return;
	}

	g_startTime = GetGameTime();
	for (int i = 1; i <= MaxClients; i++) {
		if (!isValidClient(i) || !IsClientConnected(i)) {
			continue;
		}

		char sid[ID_LEN];
		GetClientAuthId(i, AuthId_SteamID64, sid, sizeof sid, true);
		g_playerInfo[i].steam_id   = sid;
		g_playerInfo[i].time_start = g_startTime;
		g_playerInfo[i].time_end   = 0.0;

		debug("Init: %s id: %d start: %d", sid, i, g_startTime);
	}

	printSuccess("Run Started");
}

void reset() {
	float now = GetGameTime();

	for (int i = 1; i <= MaxClients; i++) {
		g_playerInfo[i].time_start = now;
		g_playerInfo[i].time_end   = 0.0;
	}

	for (int i = 0; i < sizeof g_playerInfo_disconnected; i++) {
		g_playerInfo_disconnected[i].steam_id	= "";
		g_playerInfo_disconnected[i].time_start = 0.0;
		g_playerInfo_disconnected[i].time_end	= 0.0;
	}

	g_speedrunRound = 0;
	g_isWin			= false;
}

public
void OnClientDisconnect(int clientID) {
	if (!isValidClient(clientID)) {
		return;
	}

	// Copy the players participation info over;
	g_playerInfo_disconnected[g_playerInfo_disconnected_idx].steam_id	= g_playerInfo[clientID].steam_id;
	g_playerInfo_disconnected[g_playerInfo_disconnected_idx].time_start = g_playerInfo[clientID].time_start;
	g_playerInfo_disconnected[g_playerInfo_disconnected_idx].time_end	= GetGameTime();

	g_playerInfo[clientID].steam_id										= "";
	g_playerInfo[clientID].time_start									= 0.0;
	g_playerInfo[clientID].time_end										= 0.0;

	g_playerInfo_disconnected_idx++;
	if (g_playerInfo_disconnected_idx > MAXDISCONNECTED) {
		g_playerInfo_disconnected_idx = 0;
	}

	if (isValidClient(clientID) && getRealClientCount() <= 0 && sr_reset_empty.BoolValue) {
		// reloadMap();

		return;
	}

	CreateTimer(10.0, mapRestarter, _, TIMER_DATA_HNDL_CLOSE);
}

Action mapRestarter(Handle timer) {
	if (getRealClientCount() > 0) {
		return Plugin_Stop;
	}

	debug("Restarting map due to lack of players");

	reloadMap();

	return Plugin_Stop;
}

// https://wiki.alliedmods.net/Team_Fortress_2_Events#teamplay_win_panel
public
void OnRoundWinPanel(Handle event, const char[] name, bool dontBroadcast) {
	debug("[EVENT] %s", name);
	TFTeam team			  = view_as<TFTeam>(GetEventInt(event, "winning_team"));
	int	   winrreason	  = GetEventInt(event, "winrreason");
	int	   flagcaplimit	  = GetEventInt(event, "flagcaplimit");
	bool   round_complete = GetEventBool(event, "round_complete");

	debug("team: %d winrreason: %d flagcaplimit: %d round_complete: %d",
		  team, winrreason, flagcaplimit, round_complete);

	if (!round_complete) {
		return;
	}

	if (team != TFTeam_Blue) /*They got to us???*/ {
		return;
	}

	g_isWin = true;
}

// https://wiki.alliedmods.net/Team_Fortress_2_Events#teamplay_round_win
public
void OnRoundWin(Handle event, const char[] name, bool dontBroadcast) {
	g_roundTime = GetEventFloat(event, "round_time");
	debug("Set round time: %f", g_roundTime);
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
	g_playerInfo[clientID].time_start = g_speedrunRound > 0 ? GetGameTime() : 0.0;
	g_playerInfo[clientID].time_end	  = 0.0;

	debug("Player initialized: %s | %d", steam_id, g_playerInfo[clientID].time_start);
}

void sendTimes() {
	if (g_startTime <= 0) {
		LogError("-- No start time, skipping results submission");

		return;
	}

	printSuccess("Run Ended");

	float duration = GetGameTime() - g_startTime;
	char  mapName[128];
	GetCurrentMap(mapName, sizeof mapName);

	int		   realPlayerCount = getRealClientCount();
	int		   botPlayerCount  = getBotClientCount();
	PlayerInfo players[256];
	int		   total = 0;

	for (int i = 1; i <= MaxClients; i++) {
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

		players[total].steam_id	  = g_playerInfo_disconnected[i].steam_id;
		players[total].time_start = g_playerInfo_disconnected[i].time_start;
		players[total].time_end	  = g_playerInfo_disconnected[i].time_end;

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
		pack.WriteCell(RoundToFloor(players[i].time_start / 60));
		pack.WriteCell(RoundToFloor(players[i].time_end / 60));
		pack.WriteCell(getScore(i));

		debug("sid: %s score: %d duration: %d", players[i].steam_id, getScore(i), players[i].time_end - players[i].time_start);
	}

	pack.Reset();

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
stock int getScore(int client) {
	int entity = GetPlayerResourceEntity();
	int value  = GetEntProp(entity, Prop_Send, "m_iTotalScore", _, client);
	return value;
}

stock int getBotClientCount() {
	int iClients = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (isValidBot(i)) {
			iClients++;
		}
	}

	return iClients;
}

stock bool isValidClient(int client) {
	return !(1 <= client <= MaxClients) || !IsClientInGame(client) || IsFakeClient(client) || IsClientSourceTV(client) || IsClientReplay(client);
}

stock bool isValidBot(int client) {
	return !(1 <= client <= MaxClients) || !IsClientInGame(client) || !IsFakeClient(client) || IsClientSourceTV(client) || IsClientReplay(client);
}

stock void debug(const char[] format, any...) {
#if defined _DEBUG
	char buffer[254];
	VFormat(buffer, sizeof buffer, format, 2);
	PrintToServer("[Speedrun] %s", buffer);
	PrintToChatAll("[Speedrun] %s", buffer);
#endif
}

stock void printSuccess(const char[] format, any...) {
	char buffer[254];
	VFormat(buffer, sizeof buffer, format, 2);
	MC_PrintToChatAll("{green}%s{default}", buffer);
}

stock void gbLog(const char[] format, any...)
{
	char buffer[254];
	VFormat(buffer, sizeof buffer, format, 2);
	PrintToServer("[GB] %s", buffer);
}

publ