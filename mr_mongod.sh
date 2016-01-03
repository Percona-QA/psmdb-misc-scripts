#!/bin/bash

rm -rf /data/db/*
mkdir -p /data/db/sconsTests

#gdb -x ft_crud.gdb --args 

#valgrind --tool=callgrind \
#  --separate-threads=yes \
#  --soname-synonyms=somalloc=NONE \

operf -gt \
  ./mongod --port 27999 \
    --dbpath /data/db/sconsTests \
    --setParameter enableTestCommands=1 \
    --httpinterface \
    --storageEngine PerconaFT \
    --setParameter ttlMonitorEnabled=false > mr_mongod.out 2>&1 &

