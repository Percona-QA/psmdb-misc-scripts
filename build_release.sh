if [ -f /opt/percona-devtoolset/enable ]; then
  source /opt/percona-devtoolset/enable
fi
#
if [ -f /etc/debian_version ]; then
  	export CC=gcc-4.8
  	export CXX=g++-4.8
else  
	export CC=$(which gcc)
	export CXX=$(which g++)
fi
#
export BUILD_TOOLS=yes
#
PSM_TARGETS="mongod mongos mongo"
TARBALL_SUFFIX=""
if [ -f /etc/debian_version ]; then
  export OS_RELEASE="$(lsb_release -sc)"
  
fi
#
if [ -f /etc/redhat-release ]; then
  export OS_RELEASE="centos$(lsb_release -sr | awk -F'.' '{print $1}')"
  RHEL=$(rpm --eval %rhel)
  if [ ${RHEL} = 5 ]; then
    export BUILD_TOOLS=no
  fi
fi
#
ARCH=$(uname -m 2>/dev/null||true)
TARFILE=$(basename $(find . -name 'percona-server-mongodb-*.tar.gz' | sort | grep -v "tools" | tail -n1))
PSMDIR=${TARFILE%.tar.gz}
PSMDIR_ABS=${WORKSPACE}/${PSMDIR}
#TOOLS_TARFILE=$(basename $(find . -name 'percona-server-mongodb-tools-*.tar.gz' | sort | tail -n1))
TOOLSDIR=${PSMDIR}/mongo-tools
TOOLSDIR_ABS=${WORKSPACE}/${TOOLSDIR}
TOOLS_TAGS="ssl sasl"

# NJOBS=$(grep -c processor /proc/cpuinfo)
NJOBS=4

tar xzf $TARFILE
rm -f $TARFILE

# link PSM dir to /tmp to avoid "argument list too long error"
rm -fr /tmp/${PSMDIR}
ln -fs ${PSMDIR_ABS} /tmp/${PSMDIR}
cd /tmp
#
export CFLAGS="${CFLAGS:-} -fno-omit-frame-pointer"
export CXXFLAGS="${CFLAGS}"
export INSTALLDIR=${WORKSPACE}/install
export PORTABLE=1
#
# TokuBackup
pushd $PSMDIR/src/third_party/Percona-TokuBackup/backup 
cmake . -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/ -DBUILD_STATIC_LIBRARY=ON
make -j4
make install DESTDIR=${INSTALLDIR}
popd
# PerconaFT
pushd $PSMDIR/src/third_party/PerconaFT
cmake . -DCMAKE_BUILD_TYPE=Release -DUSE_VALGRIND=OFF -DTOKU_DEBUG_PARANOID=OFF -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX=/ -DJEMALLOC_SOURCE_DIR=${PSMDIR_ABS}/src/third_party/jemalloc
make -j$NJOBS VERBOSE=1
make install DESTDIR=${INSTALLDIR}
popd
#
# RocksDB
pushd ${PSMDIR}/src/third_party/rocksdb
make -j$NJOBS static_lib
make install-static INSTALL_PATH=${INSTALLDIR}
popd
#
# Finally build Percona Server for MongoDB with SCons
cd ${PSMDIR_ABS}
scons --variant-dir=percona --audit --release --ssl --opt=on --cc=${CC} --cxx=${CXX} -j4 --use-sasl-client \
CPPPATH=${INSTALLDIR}/include LIBPATH=${INSTALLDIR}/lib --PerconaFT --rocksdb --wiredtiger --tokubackup ${PSM_TARGETS}
# scons install doesn't work - it installs the binaries not linked with fractal tree
#scons --prefix=$PWD/$PSMDIR install
#
mkdir -p ${PSMDIR}/bin
for target in ${PSM_TARGETS[@]}; do
  cp -f $target ${PSMDIR}/bin
  strip --strip-debug ${PSMDIR}/bin/${target}
done
#
cd ${WORKSPACE}
#
# Build mongo tools
if [ ${BUILD_TOOLS} = yes ]; then
cd ${TOOLSDIR}
rm -rf vendor/pkg
. ./set_gopath.sh
mkdir -p bin
for i in bsondump mongostat mongofiles mongoexport mongoimport mongorestore mongodump mongotop mongooplog; do
  echo "Building ${i}..."
  go build -a -o "bin/$i" -tags "${TOOLS_TAGS}" "$i/main/$i.go"
done
# move mongo tools to PSM installation dir
mv bin/* ${PSMDIR_ABS}/${PSMDIR}/bin
# end build tools
else
  cd ${WORKSPACE}
  wget http://jenkins.percona.com/downloads/mongo-tools-ce5.tar.gz
  tar xzf mongo-tools-ce5.tar.gz
  cp -a mongo-tools-ce5/* ${PSMDIR_ABS}/${PSMDIR}/bin/
fi 
#
cd ${PSMDIR_ABS}
tar --owner=0 --group=0 -czf ${WORKSPACE}/${PSMDIR}-${OS_RELEASE}-${ARCH}${TARBALL_SUFFIX}.tar.gz ${PSMDIR}
