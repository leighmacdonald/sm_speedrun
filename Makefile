all: build

build:
	spcomp scripting/sm_speedrun.sp -i scripting/include -o plugins/sm_speedrun.smx 

check:
	clang-format --dry-run --Werror -i scripting/*.sp

format:
	clang-format -i scripting/*.sp

