#!/bin/bash

basedir=$(cd $(dirname "$0"); pwd)

# main

OIDS=128
THREADS=128
INCS=8192

# reset 

echo "Reset updtest"

rm mongo_*.out
./mongo --quiet --eval "db.updtest.drop();for(i=0; i<${OIDS}; i++){db.updtest.insert({_id:i,updated:0});}" > /dev/null 2>&1

# spawn threads

echo "Spawning ${THREADS} threads to increcment ids ${INCS} times..."

pidArray=()
for ((t=0; t<${THREADS}; t++)); do
  ./mongo --quiet --eval "for(i=0;i<${INCS};i++){oid=Random.randInt(${OIDS});upd=db.updtest.findOne({_id:oid}).updated;printjson(db.updtest.update({_id:oid,updated:upd},{updated:upd+1}));}" > mongo_${t}.out 2>&1 &
  pidArray+=($!)
done

# wait for processes to end

echo -n "Waiting for jobs to complete"

for p in "${pidArray[@]}"; do
  wait $p
  echo -n '.'
done
echo ""

# results 

dbincs=$(./mongo --quiet --eval 'print(db.updtest.aggregate([{$group:{_id:null,total:{$sum:"$updated"}}}]).next().total)')
recincs=$(grep '{ "nMatched" : 1, "nUpserted" : 0, "nModified" : 1 }' mongo_*.out | wc -l)

echo "dbincs=${dbincs}"
echo "recincs=${recincs}"
[ "${dbincs}" == "${recincs}" ] && echo "SUCCESS" || echo "FAILED"
