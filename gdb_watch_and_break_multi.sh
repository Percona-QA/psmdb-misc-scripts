#!/bin/sh

if [ $# -lt 2 ]; then
    echo 'Usage: gdb_watch_and_break_multi.sh PROGNAME BREAK_GDB_FORMAT...'
    echo 'Ex: gdb_watch_and_break_multi.sh mongod src/mongo/db/s/move_chunk_command.cpp:345'
    exit 1
fi

set | grep -q TMUX= || {
  echo "Run this script in a tmux window"
  exit;
}

prog_match=$1
brks=''
shift
for brk; do
    brks="$brks -ex \"break $brk\""
done

base_directory=$(cd $(dirname "$0"); pwd)
base_script_name=$(basename "$0")
full_script_name="${base_directory}/${base_script_name}"

while true; do
  prog_pids=$(pgrep "${prog_match}")
  for prog_pid in ${prog_pids}; do
    has_gdb=$(ps -eo '%a' | grep -c "[g]db .* -p ${prog_pid}")
    if [ "${has_gdb}" -eq "0" ]; then
      tmux set-option remain-on-exit on
      tmux splitw -h "${full_script_name} ${prog_match} $*" &
      tmux select-layout even-horizontal
      eval gdb -ex "set pagination off" $brks -ex continue -p ${prog_pid}
      exit
    fi
  done
done
