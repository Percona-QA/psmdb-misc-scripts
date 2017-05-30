#!/usr/bin/env bash
wget http://ftp.gnu.org/gnu/bash/bash-4.4.tar.gz
tar xf bash-4.4.tar.gz
rm -f bash-4.4.tar.gz
cd bash-4.4
./configure
make
make install
cd ..
rm -rf bash-4.4
