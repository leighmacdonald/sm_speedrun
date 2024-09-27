all: build

build:
	spcomp scripting/sm_speedrun.sp -i scripting/include -o plugins/sm_speedrun.smx 
	
format:
	clang-format -i scripting/*.sp

