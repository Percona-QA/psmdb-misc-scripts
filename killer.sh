#!/usr/bin/env bash

# This script monitors ps output and if it's the same in some predefined interval
# and the load is not significant on the server it assumes the tests were stuck
# and kills all mongo processes

WORKDIR=$(pwd)
INTERVAL=4500
REGEX='^[0-9]+$'

if [ -z "$1" ]; then
  echo "You can specify check interval in seconds as first parameter."
  echo "Since not specified default will be used."
elif ! [[ $1 =~ ${REGEX} ]]; then
   echo "Specified interval is not a number!" >&2
   exit 1
elif [ "$1" -lt 60 ]; then
  echo "It's not recommended to specify interval lower then 60s."
  INTERVAL=$1
else
  INTERVAL=$1
fi
echo "Using check interval: ${INTERVAL}"

function save_state(){
  ps -e -o cmd|grep -i -E "mongo|resmoke|psmdb|percona-server-mongodb|test"|grep -v grep > ${WORKDIR}/ps-output-new.txt
}

function write_log(){
  echo -e ">>> START OF PROCESS CLEANUP <<<" >> ${WORKDIR}/killer.log
  echo -e "$(date)" >> ${WORKDIR}/killer.log
  echo -e "$(uptime)\n" >> ${WORKDIR}/killer.log
  ps aux|head -n1 >> ${WORKDIR}/killer.log
  ps aux|grep -i -E "mongo|resmoke|psmdb|percona-server-mongodb"|grep -v grep >> ${WORKDIR}/killer.log
  echo -e "\n>>> END OF PROCESS CLEANUP <<<\n\n" >> ${WORKDIR}/killer.log
}

touch ${WORKDIR}/killer.log

if [ ! -f ${WORKDIR}/ps-output-new.txt ]; then
  save_state
fi

while true; do
  sleep ${INTERVAL}
  cp ${WORKDIR}/ps-output-new.txt ${WORKDIR}/ps-output-old.txt
  save_state
  if [ $(grep "resmoke" ${WORKDIR}/ps-output-new.txt|wc -l) -ne 0 ]; then
    if [ "$(md5sum ${WORKDIR}/ps-output-new.txt|cut -f1 -d ' ')" == "$(md5sum ${WORKDIR}/ps-output-old.txt|cut -f1 -d ' ')" ]; then
      LOAD=$(uptime|grep -o "[0-9]*\.[0-9]*$"|cut -f 1 -d '.')
      if [ ${LOAD} -lt 1 ]; then
        write_log
        rm -rf /tmp/mongodb*.sock
        killall -9 mongod mongos mongo mongobridge >/dev/null 2>&1
        sleep 300
        save_state
      fi
    fi
  fi
done
