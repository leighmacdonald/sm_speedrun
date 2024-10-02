#include <sourcemod>

#include <sm_speedrun>

public
Plugin myinfo = {
	name		= "sm_speedrun_example",
	author		= "Leigh MacDonald",
	description = "Track and forward how long rounds take for tracking speedruns",
	version		= "1.0.0",
	url			= "https://github.com/leighmacdonald/sm_speedrun",
};

public
void OnPluginStart() {
}

public void OnSpeedrunEnd(DataPack pack) {
	pack.Reset();
	
	char mapName[128];

	PrintToChatAll("[Speedrun] GOT RESULT!!!");
	int duration = pack.ReadCell();
	pack.ReadString(mapName, sizeof mapName);
	int playerCount = pack.ReadCell();
	int botCount = pack.ReadCell();
	int totalPlayers = pack.ReadCell();

	PrintToChatAll("[Speedrun] Duration: %d Map: %s Players:Bots: %d:%d Participants: %d", duration, mapName, playerCount, botCount, totalPlayers);

	for(int i = 0; i < totalPlayers; i++)
	{
		char sid[18];
		pack.ReadString(sid, sizeof sid);
		int time_start = pack.ReadCell();
		int time_end = pack.ReadCell();
		int score = pack.ReadCell();

		PrintToChatAll("[Speedrun] %s %d %d", sid, time_end - time_start, score)
	}

}
