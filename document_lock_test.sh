#!/bin/bash

basedir=$(cd $(dirname "$0"); pwd)

function reset_server {
  cd $basedir
  rm -rf data
  mkdir data

  lse=""
  if ! [[ "$*" == *"storageEngine"* ]]; then
    lse=" --storageEngine=PerconaFT"
  fi

  ./mongod --dbpath=./data ${lse} $@ 2>&1 > mongod.log &
  
  sleep 3
}

# main

THREADS=8
INCS=1000

echo "Starting clean server..."

killall -q mongod
sleep 1
reset_server "$@"

# reset 

echo "Reseting inctest collection to 0..."

./mongo --quiet --eval 'db.inctest.insert({ _id: 1, x: 0});' 2>&1 > /dev/null

# spawn threads

echo "Spawning ${THREADS} threads to increcment document ${INCS} times..."

pidArray=()
for ((t=0; t<${THREADS}; t++)); do
  ./mongo --quiet --eval "for(i=0; i<${INCS}; i++){db.inctest.update({_id:1},{\$inc:{x:1}});}" 2>&1 > /dev/null &
  pidArray+=($!)
done

# wait for processes to end

echo -n "Waiting for jobs to complete"

for p in "${pidArray[@]}"; do
  wait $p
  echo -n '.'
done
echo ""

# reporting increment (should equal threads * incs)

echo "Comparing..."

total=$(./mongo --quiet --eval "db.inctest.findOne({_id:1}).x")

if [ ${total:-0} -eq $(( ${THREADS} * ${INCS} )) ]; then
  echo "Success! ${total} in database is equal to ${THREADS} * ${INCS}"
else
  echo "Failed! ${total} in database is NOT equal to ${THREADS} * ${INCS}"
fi

# kill server

killall -q mongod
sleep 1

