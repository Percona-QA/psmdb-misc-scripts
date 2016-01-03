#!/bin/bash

rm -rf /data/db/*
mkdir -p /data/db/sconsTests

#gdb -x ft_crud.gdb --args 
./mongod --port 27999 \
  --dbpath /data/db/sconsTests \
  --setParameter enableTestCommands=1 \
  --httpinterface \
  --storageEngine mmapv1 \
  --setParameter ttlMonitorEnabled=false > mr_mongod.out 2>&1 &

