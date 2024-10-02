#!/bin/env bash

/home/leigh/sdks/sourcemod/addons/sourcemod/scripting/spcomp scripting/sm_speedrun.sp -i scripting/include -o plugins/sm_speedrun.smx  && \
scp plugins/sm_speedrun.smx tf2server@192.168.0.203:srcds-srcds-1/tf/addons/sourcemod/plugins/sm_speedrun.smx && \
rcon -H 192.168.0.203:27015 -p testtest sm plugins unload sm_speedrun &&\
rcon -H 192.168.0.203:27015 -p testtest sm plugins load sm_speedrun.smx
# rcon -H 192.168.0.203:27015 -p testtest sm plugins list

/home/leigh/sdks/sourcemod/addons/sourcemod/scripting/spcomp scripting/sm_speedrun_example.sp -i scripting/include -o plugins/sm_speedrun_example.smx  && \
scp plugins/sm_speedrun_example.smx tf2server@192.168.0.203:srcds-srcds-1/tf/addons/sourcemod/plugins/sm_speedrun_example.smx && \
rcon -H 192.168.0.203:27015 -p testtest sm plugins unload sm_speedrun_example &&\
rcon -H 192.168.0.203:27015 -p testtest sm plugins load sm_speedrun_example.smx