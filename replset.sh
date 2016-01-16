#!/bin/bash

basedir=$(cd $(dirname "$0"); pwd)
cd $basedir

killall mongod
sleep 5

tc qdisc del dev lo root
tc qdisc add dev lo root netem rate 40mbps delay 1ms

MONGOD_OPTS='--storageEngine=PerconaFT --PerconaFTCollectionCompression=zlib --PerconaFTIndexCompression=zlib --replSet=rs0'

rm -rf /root/data?; mkdir -p /root/data1 /root/data2
./mongod --dbpath=/root/data1 --bind_ip=127.0.0.1 --port=27017 ${MONGOD_OPTS} > mongod1.out 2>&1 &
./mongod --dbpath=/root/data2 --bind_ip=127.0.0.1 --port=27018 ${MONGOD_OPTS} > mongod2.out 2>&1 &
MONGOD2_PID=$!

# wait until server 2 is listening

tail -f --pid=${MONGOD2_PID} "mongod2.out" | while read LOGLINE
do
  if [[ "${LOGLINE}" == *"waiting for connections"* ]]; then
    pkill -P $$ tail
  fi
done

# prep replset
sleep 5

./mongo --eval 'printjson(rs.initiate( { _id: "rs0", members: [ {_id: 0, host: "127.0.0.1:27017" }, { _id: 1, host: "127.0.0.1:27018" } ] } ))'
sleep 1
./mongo --port 27018 --eval 'rs.slaveOk()'

