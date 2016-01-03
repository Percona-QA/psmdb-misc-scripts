#!/bin/bash

# percona jira PSMDB-28

basedir=$(cd $(dirname "$0"); pwd)
basename=csibwt
storageEngine=wiredTiger

if [ ! -e ${basedir}/mongod ]; then
  echo 'put this script in the same directory as ./mongod and run it again'
  exit 1;
fi

killall mongod > /dev/null 2>&1 

cd ${basedir}

rm -rf ${basename}_data/ ${basename}_mongod.log;
mkdir ${basename}_data;

./mongod --dbpath=./${basename}_data --storageEngine=${storageEngine} > ${basename}_mongod.log 2>&1 &

sleep 3

./mongo --eval "
  for (var i =1; i < 3;i++) { db.foo.save({x: i}) };
  db.foo.ensureIndex({x : 1}, {sparse : true, background : true});
"

killall mongod > /dev/null 2>&1 

grep -q 'Invalid argument' ${basename}_mongod.log && {
  sed -n '/Invalid argument/ { s///; :a; n; p; ba; }' ${basename}_mongod.log
} || echo -e "\nSuccess!"

