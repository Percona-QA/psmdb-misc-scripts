#!/bin/bash

for i in $(seq 31 100); do
  buildscripts/smoke.py \
    --storageEngine=PerconaFT \
    --mode=files jstests/concurrency/fsm_all_ft.js \
    | tee "smoke_fsm_all_ft_1201_${i}.out"
  grep -q '^failed' "smoke_fsm_all_ft_1201_${i}.out" && exit 1;
done

