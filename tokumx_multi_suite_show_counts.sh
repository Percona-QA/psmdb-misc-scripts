#!/bin/bash

find "$@" -printf "%f\n" \
  -exec /bin/bash -c ' 
    echo -ne "\tok: ";
    grep -c "^ok " {};
    echo -ne "\tnot ok: ";
    grep -c "^not ok " {}' \;
