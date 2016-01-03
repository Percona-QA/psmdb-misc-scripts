#!/bin/bash

if [ "$1" == "" ]; then
  echo "Usage ./run_smoke.sh {trial #}"                                                                               
  exit 1;                                                                                                             
fi                                                                                                                    
                                                                                                                      
trial=$1                                                                                                              
                                                                                                                      
suites="all"                                                                                                          
if [ ! "$2" == "" ]; then                                                                                             
  shift                                                                                                               
  suites="$@"                                                                                                         
fi                                                                                                                    
fn_suites=$(echo "${suites}" | sed 's/ /_/g')                                                                         
                                                                                                                      
chmod 400 jstests/libs/key*                                                                                           
                                                                                                                      
for eng in mmapv1 wiredTiger rocksdb PerconaFT; do                                                                    
  /bin/rm -rf /data/db/*                                                                                              
  buildscripts/smoke.py \
    --continue-on-failure \
    --storageEngine=${eng} \
    ${suites} 2>&1 | tee smoke_${fn_suites}_${eng}_${trial}.out
done  
