#!/bin/bash

# download and set default g++ toolchain on ubuntu/debian

# Usage: ./g++toolchain.sh {version}

# Example: ./g++toolchain.sh 4.8

[ "$1" == "" ] && {
  echo "download and set default g++ toolchain on ubuntu/debian."
  echo "Usage: ./g++toolchain.sh {version}"
  echo -e "Example: ./g++toolchain.sh 4.8\n"
  exit 1;
}

ver=$1

if apt-get install -y "g++-${ver}"; then
  cd /usr/bin
  ls -l | \
    grep "\-> .*\-${ver}" | \
    grep -v "\-gnu-" | \
    perl -ne 's/^.*[0-9] (.*) ->.*/$1/;print' | \
    xargs -i^ -n1 ln -sf ^-${ver}
else
  echo "Unable to install package: g++-${ver}"
  exit 2;
fi
