#!/bin/sh

set | grep -q TMUX= || {
  echo "Run this script in a tmux window"
  exit;
}

base_directory=$(cd $(dirname "$0"); pwd)
base_script_name=$(basename "$0")
full_script_name="${base_directory}/${base_script_name}"
prog_match=$1

while true; do
  prog_pids=$(pgrep "${prog_match}")
  for prog_pid in ${prog_pids}; do
    has_gdb=$(ps -eo '%a' | grep -c "[g]db .* -p ${prog_pid}")
    if [ "${has_gdb}" -eq "0" ]; then
      tmux set-option remain-on-exit on
      tmux splitw -h "${full_script_name} $*" &
      tmux select-layout even-horizontal
      gdb -ex "set pagination off" -ex "break $2" -ex continue -p ${prog_pid}
      exit
    fi
  done
done
