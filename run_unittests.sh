#!/bin/bash

# build unittests with
# scons --variant-dir=percona --audit --release --ssl --opt=on -j8 --use-sasl-client --PerconaFT --rocksdb --wiredtiger --tokubackup unittests

basedir=$(pwd)

if [ "$1" = "" ]; then
  echo "Usage: ./run_unittests.sh {trial #}"
  exit
fi

trial=$1

for test in $(cat ${basedir}/build/unittests.txt); do
  ./${test} 2>&1 | tee unittests_${test//\//_}_${trial}.out
done

