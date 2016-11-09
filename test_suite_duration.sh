#!/bin/bash
# This script checks all resmoke log output files and writes duration for every test suite

for logfile in *.log; do
  if [[ "${logfile}" != resmoke_summary* ]]; then
    duration=$(grep "resmoke.*Summary" ${logfile} |grep -o "in .* seconds"|grep -o -e "[0-9]*\.[0-9]*")
    suite_name=${logfile#resmoke_}
    suite_name=${suite_name%_*.log}
    echo "${suite_name},${duration}"
  fi
done
