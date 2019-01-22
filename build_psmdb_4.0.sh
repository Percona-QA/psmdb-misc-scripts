#!/usr/bin/env bash

# run this script from psmdb source root
NJOBS=""
OPT_TARGETS=""
SCONS_OPTS="--release --opt=on"
CWD=$(pwd)
TARBALL_SUFFIX=""

# Check if we have a functional getopt(1)
if ! getopt --test
then
  go_out="$(getopt --options=dabuj: \
    --longoptions=debug,asan,dbtest,unittests,jobs: \
    --name="$(basename "$0")" -- "$@")"
  test $? -eq 0 || exit 1
  eval set -- $go_out
fi

for arg 
do
  case "$arg" in
  -- ) shift; break;;
  -d | --debug )
    shift
    SCONS_OPTS="${SCONS_OPTS} --disable-warnings-as-errors --dbg=on"
    TARBALL_SUFFIX="${TARBALL_SUFFIX}-dbg"
    echo "Debug build selected..."
    ;;  
  -a | --asan )
    shift
    ASAN_OPTIONS="--allocator=system --sanitize=address"
    TARBALL_SUFFIX="${TARBALL_SUFFIX}-asan"
    echo "ASAN build selected..."
    ;;
  -b | --dbtest )
    shift
    OPT_TARGETS="${OPT_TARGETS} dbtest"
    echo "Building of dbtest enabled..."
    ;;
  -u | --unittests )
    shift
    OPT_TARGETS="${OPT_TARGETS} unittests"
    echo "Building of unittests enabled..."
    ;;
  -j | --jobs )
    shift
    NJOBS="$1"
    shift
    ;;
  esac
done

if [ -z "$NJOBS" ]; then
  NJOBS=$(grep -c processor /proc/cpuinfo)
fi

# prepare source
#
REVISION=$(git rev-parse --short HEAD)
REVISION_LONG=$(git rev-parse HEAD)
PSM_VERSION=$(git tag|grep "psmdb-4.0"|tail -n1|cut -d "-" -f2)
PSM_RELEASE=$(git tag|grep "psmdb-4.0"|tail -n1|cut -d "-" -f3,4)
TARBALL_NAME="percona-server-mongodb-${PSM_VERSION}-${PSM_RELEASE}-${REVISION}${TARBALL_SUFFIX}"
# create a proper version.json
echo "{" > version.json
echo "    \"version\": \"${PSM_VERSION}-${PSM_RELEASE}\"," >> version.json
echo "    \"githash\": \"${REVISION_LONG}\"" >> version.json
echo "}" >> version.json
#
rm -rf mongo-tools
MONGO_TOOLS_TAG="r${PSM_VERSION}"
git clone https://github.com/mongodb/mongo-tools.git
pushd mongo-tools
git checkout $MONGO_TOOLS_TAG
echo "export PSMDB_TOOLS_COMMIT_HASH=\"$(git rev-parse HEAD)\"" > set_tools_revision.sh
echo "export PSMDB_TOOLS_REVISION=\"${PSM_VERSION}-${PSM_RELEASE}\"" >> set_tools_revision.sh
chmod +x set_tools_revision.sh
popd
#
# build binaries
#
if [ -f /opt/percona-devtoolset/enable ]; then
  source /opt/percona-devtoolset/enable
fi
#
export PATH=/usr/local/go/bin:$PATH
#
if [ -f /etc/debian_version ]; then
  export CC=gcc-5
  export CXX=g++-5
else  
  export CC=$(which gcc)
  export CXX=$(which g++)
fi
#
PSM_TARGETS="mongod mongos mongo perconadecrypt mongobridge${OPT_TARGETS}"
ARCH=$(uname -m 2>/dev/null||true)
PSMDIR=$(basename ${CWD})
PSMDIR_ABS=${CWD}
TOOLSDIR="${PSMDIR}/mongo-tools"
TOOLSDIR_ABS="${PSMDIR_ABS}/${TOOLSDIR}"
export TOOLS_TAGS="ssl sasl"

# link PSM dir to /tmp to avoid "argument list too long error"
rm -fr /tmp/${PSMDIR}
ln -fs ${PSMDIR_ABS} /tmp/${PSMDIR}
cd /tmp
#
export CFLAGS="${CFLAGS:-} -fno-omit-frame-pointer"
export CXXFLAGS="${CFLAGS}"
export INSTALLDIR=${PSMDIR_ABS}/install
#
# Finally build Percona Server for MongoDB with SCons
cd ${PSMDIR_ABS}
buildscripts/scons.py CC=${CC} CXX=${CXX} --ssl ${SCONS_OPTS} -j${NJOBS} --use-sasl-client --wiredtiger --audit --inmemory --hotbackup ${ASAN_OPTIONS} CPPPATH=${INSTALLDIR}/include LIBPATH=${INSTALLDIR}/lib ${PSM_TARGETS}
#
# Build mongo tools
cd ${TOOLSDIR_ABS}
mkdir -p build_tools/src/github.com/mongodb/mongo-tools
rm -rf vendor/pkg
[[ ${PATH} == *"/usr/local/go/bin"* && -x /usr/local/go/bin/go ]] || export PATH=/usr/local/go/bin:${PATH}
export GOROOT="/usr/local/go/"
cp -r $(ls | grep -v build_tools) build_tools/src/github.com/mongodb/mongo-tools/
cd build_tools/src/github.com/mongodb/mongo-tools
. ./set_tools_revision.sh
sed -i 's|VersionStr="$(git describe)"|VersionStr="$PSMDB_TOOLS_REVISION"|' set_goenv.sh
sed -i 's|Gitspec="$(git rev-parse HEAD)"|Gitspec="$PSMDB_TOOLS_COMMIT_HASH"|' set_goenv.sh
. ./set_goenv.sh
if [ "${BUILD_TYPE}" == "debug" ]; then
  sed -i 's|go build|go build -a -x|' build.sh
else
  sed -i 's|go build|go build -a |' build.sh
fi
sed -i 's|exit $ec||' build.sh
. ./build.sh
# end build tools
# create psmdb tarball
cd ${PSMDIR_ABS}
mkdir -p ${TARBALL_NAME}/bin
cp mongo* ${TARBALL_NAME}/bin
cp percona* ${TARBALL_NAME}/bin
cp ${TOOLSDIR_ABS}/bin/* ${TARBALL_NAME}/bin
tar --owner=0 --group=0 -czf ${TARBALL_NAME}.tar.gz ${TARBALL_NAME}
rm -rf ${TARBALL_NAME}
# move mongo tools to PSM root dir for running tests
mv ${TOOLSDIR_ABS}/build_tools/src/github.com/mongodb/mongo-tools/bin/* ${PSMDIR_ABS}
