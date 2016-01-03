#!/bin/bash

if [ "$1" == "" ]; then
  build="baseline"
else
  build="$1"
fi

for suite in "js" "sharding" "jsSlowNightly" "replSets" "aggregation" "tool"; do
  python buildscripts/smoke.py \
    --with-cleanbb --continue-on-failure --smoke-db-prefix=smokedata --quiet ${suite} \
    2>&1 | tee ${build}_${suite}.out
done

