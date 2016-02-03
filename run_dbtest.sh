#!/bin/bash

# build dbtest with
# scons --variant-dir=percona --audit --release --ssl --opt=on -j8 --use-sasl-client --PerconaFT --rocksdb --wiredtiger --tokubackup dbtest

if [ "$1" = "" ]; then
  echo "Usage: ./run_dbtest.sh {trial #}"
  exit
fi

trial=$1

for eng in mmapv1 wiredTiger PerconaFT rocksdb; do
  for test in $(./dbtest --list); do
    ./dbtest --storageEngine=${eng} ${test} 2>&1 | tee dbtest_${test}_${eng}_${trial}.out
  done
done

