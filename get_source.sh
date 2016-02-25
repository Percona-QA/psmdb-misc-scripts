#
PRODUCT=percona-server-mongodb
echo "PRODUCT=${PRODUCT}" > percona-server-mongodb-3.properties

PRODUCT_FULL=${PRODUCT}-${PSM_VER}-${PSM_RELEASE}
echo "PRODUCT_FULL=${PRODUCT_FULL}" >> percona-server-mongodb-3.properties
echo "VERSION=${PSM_VER}" >> percona-server-mongodb-3.properties
echo "RELEASE=$PSM_RELEASE" >> percona-server-mongodb-3.properties
echo "PSM_BRANCH=${PSM_BRANCH}" >> percona-server-mongodb-3.properties
echo "FTINDEX_TAG=${FTINDEX_TAG}" >> percona-server-mongodb-3.properties
echo "JEMALLOC_TAG=${JEMALLOC_TAG}" >> percona-server-mongodb-3.properties
echo "MONGO_TOOLS_TAG=${MONGO_TOOLS_TAG}" >> percona-server-mongodb-3.properties
echo "BUILD_NUMBER=${BUILD_NUMBER}" >> percona-server-mongodb-3.properties
echo "BUILD_ID=${BUILD_ID}" >> percona-server-mongodb-3.properties
#CHECKOUT_UPLOAD=${TOKUMXSE_MONGO_CHECK/\//_}
#echo "CHECKOUT_UPLOAD=${CHECKOUT_UPLOAD}" >> percona-server-mongodb-3.properties
#
###
git clone https://github.com/percona/percona-server-mongodb-packaging.git
###
git clone https://github.com/percona/percona-server-mongodb.git
#
cd percona-server-mongodb
#
git checkout ${PSM_BRANCH}
REVISION=$(git rev-parse --short HEAD)
# create a proper version.json
REVISION_LONG=$(git rev-parse HEAD)
echo "{" > version.json
echo "    \"version\": \"${PSM_VER}-${PSM_RELEASE}\"," >> version.json
echo "    \"githash\": \"${REVISION_LONG}\"" >> version.json
echo "}" >> version.json
#
echo "REVISION=${REVISION}" >> ../percona-server-mongodb-3.properties
rm -fr debian rpm
cp -a ${WORKSPACE}/percona-server-mongodb-packaging/manpages .
cp -a ${WORKSPACE}/percona-server-mongodb-packaging/docs/* .
#
# submodules
git submodule init
git submodule update
#
pushd src/third_party
git clone https://github.com/percona/Percona-TokuBackup.git
(cd Percona-TokuBackup && git checkout ${TOKUBACKUP_BRANCH})
popd
#
pushd src/third_party/PerconaFT
git checkout ${FTINDEX_TAG}
popd
#
pushd src/third_party/jemalloc
git checkout ${JEMALLOC_TAG}
popd
#
pushd src/third_party/rocksdb
git checkout ${ROCKSDB_TAG}
popd
#
git clone https://github.com/mongodb/mongo-tools.git
pushd mongo-tools
git checkout $MONGO_TOOLS_TAG
popd
#
cd ${WORKSPACE}
#
source percona-server-mongodb-3.properties
#
mv percona-server-mongodb ${PRODUCT}-${PSM_VER}-${PSM_RELEASE}
tar --owner=0 --group=0 --exclude=.* -czf ${PRODUCT}-${PSM_VER}-${PSM_RELEASE}.tar.gz ${PRODUCT}-${PSM_VER}-${PSM_RELEASE}
echo "UPLOAD=UPLOAD/experimental/BUILDS/${PRODUCT}/${PRODUCT}-${PSM_VER}-${PSM_RELEASE}/${PSM_BRANCH}/${REVISION}/${BUILD_ID}" >> percona-server-mongodb-3.properties
