#!/usr/bin/env bash
# This script is used to test upgrade of PSMDB.
# It can test single instances or replicasets with different SE's.
# Created by Tomislav Plavcic

set -e

if [ "$#" -ne 5 ]; then
  echo "This script requires absolute workdir, test type, storage engine and directories for old and new binaries as parameters!";
  echo "Example: ./psmdb_upgrade.sh /tmp/psmdb-upgrade single rocksdb /mongo-old-bindir /mongo-new-bindir"
  echo "         ./psmdb_upgrade.sh /tmp/psmdb-upgrade replicaset wiredTiger /mongo-old-bindir /mongo-new-bindir"
  exit 1
fi

ulimit -c unlimited

#Kill mongod and mongos processes
killall -9 mongod > /dev/null 2>&1 || true
killall -9 mongos > /dev/null 2>&1 || true
sleep 5

SCRIPT_PWD=$(cd `dirname $0` && pwd)
WORKDIR=$1
LAYOUT_TYPE=$2
STORAGE_ENGINE=$3
PSMDB_OLD_BINDIR=$4
PSMDB_NEW_BINDIR=$5
BASE_DATADIR="${WORKDIR}/data"
MONGO_START_TIMEOUT=600
YCSB_VER="0.15.0"
CIPHER_MODE="${CIPHER_MODE:-AES256-CBC}"
ENCRYPTION="${ENCRYPTION:-no}"
MONGO_JAVA_DRIVER="${MONGO_JAVA_DRIVER:-3.6.3}"
MONGOD_EXTRA="${MONGOD_EXTRA:-}"
LEAVE_RUNNING=${LEAVE_RUNNING:-false}
BENCH_TOOL="${BENCH_TOOL:-sysbench}"
Y_OPERATIONS=${Y_OPERATIONS:-1000000}
S_DURATION=${S_DURATION:-5}
S_COLLECTIONS=${S_COLLECTIONS:-1}
B_DOCSPERCOL=${B_DOCSPERCOL:-1000000}
S_WRITE_CONCERN="${S_WRITE_CONCERN:-SAFE}"
B_LOADER_THREADS=${B_LOADER_THREADS:-8}
B_WRITER_THREADS=${B_WRITER_THREADS:-8}

cd ${WORKDIR}

if [ -z ${PSMDB_OLD_BINDIR} ]; then
  echo "PSMDB old binary directory is mandatory!"
  exit 1
fi
if [ -z ${PSMDB_NEW_BINDIR} ]; then
  echo "PSMDB new binary directory is mandatory!"
  exit 1
fi
if [ "${STORAGE_ENGINE}" != "wiredTiger" -a "${ENCRYPTION}" != "no" ]; then
  echo "ERROR: Data at rest encryption is possible only with wiredTiger storage engine!"
  exit 1
fi

rm -rf ${BASE_DATADIR}
rm -f ${WORKDIR}/results_${LAYOUT_TYPE}_${STORAGE_ENGINE}.tar

HOST="localhost"
NODE1_PORT=27017
NODE2_PORT=27018
NODE3_PORT=27019
PRIMARY_PORT=""
PRIMARY_DATA=""
UPGRADE_PORT=""
UPGRADE_DATA=""
NODE1_DATA="${BASE_DATADIR}/${NODE1_PORT}"
NODE2_DATA="${BASE_DATADIR}/${NODE2_PORT}"
NODE3_DATA="${BASE_DATADIR}/${NODE3_PORT}"

check_version() {
  PSMDBDIR=$1
  echo "$(${PSMDBDIR}/bin/mongod --version|head -n1|sed 's/db version v//')"
}

OLD_VER=$(check_version ${PSMDB_OLD_BINDIR})
NEW_VER=$(check_version ${PSMDB_NEW_BINDIR})
UPSTREAM_OLD_VER=$(echo "${OLD_VER}"|sed 's/-.*$//')
UPSTREAM_NEW_VER=$(echo "${NEW_VER}"|sed 's/-.*$//')

COMPATIBILITY=$(echo ${UPSTREAM_NEW_VER}|grep -oE "[0-9]+\.[0-9]+")

GT_VERSION=$(echo -e "${UPSTREAM_NEW_VER}\n${UPSTREAM_OLD_VER}" | sort -t. -k1,1nr -k2,2nr -k3,3nr | head -1)
if [ "${GT_VERSION}" = "${UPSTREAM_OLD_VER}" ]; then
  TEST_TYPE="downgrade"
else
  TEST_TYPE="upgrade"
fi

echo "Workdir: ${WORKDIR}"
echo "Datadir: ${BASE_DATADIR}"
echo "Version ${OLD_VER} bindir: ${PSMDB_OLD_BINDIR}"
echo "Version ${NEW_VER} bindir: ${PSMDB_NEW_BINDIR}"

# Download test database
if [ ! -f primer-dataset.json ]; then
  wget --no-verbose https://raw.githubusercontent.com/mongodb/docs-assets/primer-dataset/primer-dataset.json
fi
TEST_DB_FILE=${WORKDIR}/primer-dataset.json

# Download benchmarking tool
if [ "${BENCH_TOOL}" = "sysbench" ]; then
  if [ ! -f mongo-java-driver-${MONGO_JAVA_DRIVER}.jar ]; then
    wget --no-verbose https://oss.sonatype.org/content/repositories/releases/org/mongodb/mongo-java-driver/${MONGO_JAVA_DRIVER}/mongo-java-driver-${MONGO_JAVA_DRIVER}.jar
  fi
  export CLASSPATH=$PWD/mongo-java-driver-${MONGO_JAVA_DRIVER}.jar:$CLASSPATH
  if [ ! -d sysbench-mongodb ]; then
    git clone https://github.com/Percona-Lab/sysbench-mongodb.git
  fi
elif [ "${BENCH_TOOL}" = "ycsb" ]; then
  if [ ! -d ycsb-${YCSB_VER} ]; then
    rm -f ycsb-${YCSB_VER}.tar.gz
    wget --no-verbose https://github.com/brianfrankcooper/YCSB/releases/download/${YCSB_VER}/ycsb-${YCSB_VER}.tar.gz
    tar xf ycsb-${YCSB_VER}.tar.gz
    rm -f ycsb-${YCSB_VER}.tar.gz
  fi
elif [ "${BENCH_TOOL}" != "none" ]; then
  echo "Unknown benchmarking tool selected. Please use \"export BENCH_TOOL=sysbench|ycsb|none\" !"
  exit 1
fi

###
### COMMON FUNCTIONS
###
archives() {
  rm -rf ${WORKDIR}/results_${LAYOUT_TYPE}_${STORAGE_ENGINE}_${OLD_VER}_${NEW_VER}
  mkdir ${WORKDIR}/results_${LAYOUT_TYPE}_${STORAGE_ENGINE}_${OLD_VER}_${NEW_VER}
  find data -maxdepth 3 -type f \( -iname \*.log -o -iname \*.txt -o -iname \*.tsv \) -exec cp {} ${WORKDIR}/results_${LAYOUT_TYPE}_${STORAGE_ENGINE}_${OLD_VER}_${NEW_VER} \;
  tar czf ${WORKDIR}/results_${LAYOUT_TYPE}_${STORAGE_ENGINE}_${OLD_VER}_${NEW_VER}.tar.gz -C ${WORKDIR} results_${LAYOUT_TYPE}_${STORAGE_ENGINE}_${OLD_VER}_${NEW_VER}
}

trap archives EXIT KILL

start_single()
{
  local FUN_NODE_VER=$1
  local FUN_NODE_DATA=$2
  local FUN_LOG_ERR=$3
  local FUN_BIN_DIR=$4
  local FUN_NODE_PORT=$5
  local FUN_NODE_SE=$6
  local FUN_REPL_SET="$7"

  local REPL_SET=""
  local FUN_MONGOD_EXTRA=""
  if [ ! -z $7 ]; then
    local REPL_SET="--replSet "${FUN_REPL_SET}""
  fi

  if [ ! -d ${FUN_NODE_DATA} ]; then
    mkdir -p ${FUN_NODE_DATA}
  fi

  echo "Starting node on port ${FUN_NODE_PORT} storage engine: ${FUN_NODE_SE}"

  if [ "${FUN_NODE_VER:0:3}" == "3.6" -a "${FUN_NODE_SE}" == "rocksdb" ]; then
    FUN_MONGOD_EXTRA="${MONGOD_EXTRA} --useDeprecatedMongoRocks"
  fi
  if [ "${FUN_NODE_SE}" == "wiredTiger" -a "${ENCRYPTION}" == "keyfile" ]; then
    if [ ! -f ${FUN_NODE_DATA}/mongodb-keyfile ]; then
      openssl rand -base64 32 > ${FUN_NODE_DATA}/mongodb-keyfile
      chmod 600 ${FUN_NODE_DATA}/mongodb-keyfile
    fi
    FUN_MONGOD_EXTRA="${MONGOD_EXTRA} --enableEncryption --encryptionKeyFile ${FUN_NODE_DATA}/mongodb-keyfile --encryptionCipherMode ${CIPHER_MODE}"
  fi
  ${FUN_BIN_DIR}/bin/mongod --dbpath ${FUN_NODE_DATA} --logpath ${FUN_LOG_ERR} --port ${FUN_NODE_PORT} --logappend --fork --storageEngine ${FUN_NODE_SE} ${REPL_SET} ${FUN_MONGOD_EXTRA} > ${FUN_LOG_ERR} 2>&1 &

  for X in $(seq 0 ${MONGO_START_TIMEOUT}); do
    sleep 1
    if ${FUN_BIN_DIR}/bin/mongo --host=${HOST} --port ${FUN_NODE_PORT} --eval "db.serverStatus()" > /dev/null 2>&1; then
      break
    fi
  done
  if ${FUN_BIN_DIR}/bin/mongo --host=${HOST} --port ${FUN_NODE_PORT} --eval "db.serverStatus()" ping > /dev/null 2>&1; then
    echo "PSMDB on port ${FUN_NODE_PORT} started ok.."
  else
    echo "PSMDB on port ${FUN_NODE_PORT} startup failed.. Please check error log: ${FUN_LOG_ERR}"
  fi
  sleep 10
}

stop_single()
{
  local FUN_NODE_VER=$1
  local FUN_NODE_DATA=$2
  local FUN_LOG_ERR=$3
  local FUN_BIN_DIR=$4
  local FUN_NODE_PORT=$5

  ${FUN_BIN_DIR}/bin/mongod --dbpath ${FUN_NODE_DATA} --port ${FUN_NODE_PORT} --shutdown > ${FUN_LOG_ERR} 2>&1 &

  echo "Stopping node ${FUN_NODE_PORT} version ${FUN_NODE_VER} storage engine ${FUN_NODE_SE}"
  for X in $(seq 0 ${MONGO_START_TIMEOUT}); do
    sleep 1
    if [ $(cat ${FUN_NODE_DATA}/mongod.lock|wc -l) -eq "0" ]; then
      break
    fi
  done
  if [ $(cat ${FUN_NODE_DATA}/mongod.lock|wc -l) -eq "0" ]; then
    echo "PSMDB on port ${FUN_NODE_PORT} stopped ok.."
  else
    echo "PSMDB on port ${FUN_NODE_PORT} stop failed.. Please check error log: ${FUN_LOG_ERR}"
  fi
}

start_replica()
{
  start_single ${OLD_VER} ${NODE1_DATA} ${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-first-start.log ${PSMDB_OLD_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE} rs0
  start_single ${OLD_VER} ${NODE2_DATA} ${NODE2_DATA}/${NODE2_PORT}-${OLD_VER}-${STORAGE_ENGINE}-first-start.log ${PSMDB_OLD_BINDIR} ${NODE2_PORT} ${STORAGE_ENGINE} rs0
  start_single ${OLD_VER} ${NODE3_DATA} ${NODE3_DATA}/${NODE3_PORT}-${OLD_VER}-${STORAGE_ENGINE}-first-start.log ${PSMDB_OLD_BINDIR} ${NODE3_PORT} ${STORAGE_ENGINE} rs0
}

init_replica()
{
  ${PSMDB_OLD_BINDIR}/bin/mongo --host=${HOST} --port ${NODE1_PORT} --eval "rs.initiate({ _id: \"rs0\", members: [ { _id: 0, host: \"${HOST}:${NODE1_PORT}\" } ] })"
  sleep 30
  ${PSMDB_OLD_BINDIR}/bin/mongo --host=${HOST} --port ${NODE1_PORT} --eval "rs.add(\"${HOST}:${NODE2_PORT}\")"
  ${PSMDB_OLD_BINDIR}/bin/mongo --host=${HOST} --port ${NODE1_PORT} --eval "rs.add(\"${HOST}:${NODE3_PORT}\")"
}

import_test_data()
{
  local FUN_NODE_VER=$1
  local FUN_BIN_DIR=$2
  local FUN_NODE_PORT=$3
  local FUN_NODE_SE=$4
  local FUN_DB=$5
  local FUN_COLLECTION=$6
  local FUN_IMPORT_FILE=$7
  local FUN_LOG_ERR=$8

  echo "Importing test database to node ${FUN_NODE_PORT} version ${FUN_NODE_VER} storage engine ${FUN_NODE_SE}"
  ${FUN_BIN_DIR}/bin/mongoimport --host=${HOST} --port=${FUN_NODE_PORT} --db ${FUN_DB} --collection ${FUN_COLLECTION} --drop --file ${FUN_IMPORT_FILE} > ${FUN_LOG_ERR} 2>&1
  if [ $? -eq 0 ]; then
    echo "Importing test database was successful."
  else
    echo "Error while importing test database, please check ${FUN_LOG_ERR}"
  fi
}

run_bench()
{
  local FUN_DATABASE=$1
  local FUN_PORT=$2
  local FUN_DROP=$3
  local FUN_PREFIX=$4
  local FUN_DATA=$5
  local FUN_OPERATION=$6

  # Execute sysbench-mongodb
  echo "Executing ${BENCH_TOOL} run on node ${FUN_PORT} database ${FUN_DATABASE}"
  if [ "${BENCH_TOOL}" = "sysbench" ]; then
    # Set run parameters
    sed -i "/export DB_NAME=/c\export DB_NAME=${FUN_DATABASE}" sysbench-mongodb/config.bash
    sed -i "/export USERNAME=/c\export USERNAME=none" sysbench-mongodb/config.bash
    sed -i "/export MONGO_SERVER=/c\export MONGO_SERVER=${HOST}" sysbench-mongodb/config.bash
    sed -i "/export MONGO_PORT=/c\export MONGO_PORT=${FUN_PORT}" sysbench-mongodb/config.bash
    sed -i "/export NUM_COLLECTIONS=/c\export NUM_COLLECTIONS=${S_COLLECTIONS}" sysbench-mongodb/config.bash
    sed -i "/export NUM_DOCUMENTS_PER_COLLECTION=/c\export NUM_DOCUMENTS_PER_COLLECTION=${B_DOCSPERCOL}" sysbench-mongodb/config.bash
    sed -i "/export RUN_TIME_MINUTES=/c\export RUN_TIME_MINUTES=${S_DURATION}" sysbench-mongodb/config.bash
    sed -i "/export DROP_COLLECTIONS=/c\export DROP_COLLECTIONS=${FUN_DROP}" sysbench-mongodb/config.bash
    sed -i "/export NUM_WRITER_THREADS=/c\export NUM_WRITER_THREADS=${B_WRITER_THREADS}" sysbench-mongodb/config.bash
    sed -i "/export NUM_LOADER_THREADS=/c\export NUM_LOADER_THREADS=${B_LOADER_THREADS}" sysbench-mongodb/config.bash
    sed -i "/export WRITE_CONCERN=/c\export WRITE_CONCERN=${S_WRITE_CONCERN}" sysbench-mongodb/config.bash

    pushd sysbench-mongodb
    ./run.simple.bash
    rename "s/^mongoSysbench/${FUN_PREFIX}_mongoSysbench/" *.txt
    rename "s/^mongoSysbench/${FUN_PREFIX}_mongoSysbench/" *.tsv
    mv *.txt ${FUN_DATA}
    mv *.tsv ${FUN_DATA}
    popd
  elif [ "${BENCH_TOOL}" = "ycsb" ]; then
    pushd ycsb-${YCSB_VER}
    if [ "${FUN_OPERATION}" == "load" -o "${FUN_OPERATION}" == "load-update" ]; then
      ./bin/ycsb load mongodb -s -P workloads/workloadb -p recordcount=${B_DOCSPERCOL} -threads ${B_LOADER_THREADS} -p mongodb.url="mongodb://localhost:${FUN_PORT}/${FUN_DATABASE}" -p mongodb.auth="false" > ${FUN_DATA}/${FUN_PREFIX}_${FUN_DATABASE}_ycsb-load.txt
    fi
    if [ "${FUN_OPERATION}" == "update" -o "${FUN_OPERATION}" == "load-update" ]; then
      ./bin/ycsb.sh run mongodb -s -P workloads/workloadb -p recordcount=${B_DOCSPERCOL} -p operationcount=${Y_OPERATIONS} -threads ${B_WRITER_THREADS} -p mongodb.url="mongodb://localhost:${FUN_PORT}/${FUN_DATABASE}" -p mongodb.auth="false" > ${FUN_DATA}/${FUN_PREFIX}_${FUN_DATABASE}_ycsb-run.txt
    fi
    popd
  fi
  echo "Finished with ${BENCH_TOOL} run on node ${FUN_PORT} database ${FUN_DATABASE}"
}

show_node_info()
{
  local FUN_PORT=$1
  local FUN_TEXT=$2
  echo -e "\n\n##### Show databases info on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB_NEW_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --quiet --eval "rs.slaveOk(); db.adminCommand('listDatabases')"
  echo -e "\n\n##### Show server info on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB_NEW_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --quiet --eval "db.serverStatus({ rocksdb: 0, metrics: 0, locks: 0, tcmalloc: 0 })"
  echo -e "\n\n##### Show info on bench_test database on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${FUN_PORT}/bench_test --quiet --eval "db.stats()"
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${FUN_PORT}/bench_test --quiet --eval "db.runCommand({ dbHash: 1 })"
  echo -e "\n\n##### Show info on test database on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${FUN_PORT}/test --quiet --eval "db.stats()"
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${FUN_PORT}/test --quiet --eval "db.runCommand({ dbHash: 1 })"
  echo -e "\n\n##### Show replica set status on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB_NEW_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --quiet --eval "rs.status()"
  echo -e "\n\n##### Show isMaster info on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB_NEW_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --quiet --eval "db.isMaster()"
  echo -e "\n\n##### Show featureCompatibilityVersion on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB_NEW_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --quiet --eval "db.adminCommand( { getParameter: 1, featureCompatibilityVersion: 1 } );"
  echo -e "\n\n##### Show encryption startup options on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB_NEW_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --quiet --eval "db.serverCmdLineOpts().parsed.security;"
  echo -e "\n"
}

update_primary_info()
{
  PRIMARY_PORT=""
  PRIMARY_DATA=""
  for node_port in ${NODE1_PORT} ${NODE2_PORT} ${NODE3_PORT}; do
    if [ $(${PSMDB_OLD_BINDIR}/bin/mongo --host=${HOST} --port ${node_port} --quiet --eval 'db.isMaster().ismaster') = "true" ]; then
      PRIMARY_PORT=$node_port
      PRIMARY_DATA=$(${PSMDB_OLD_BINDIR}/bin/mongo --host=${HOST} --port ${node_port} --quiet --eval 'db.serverCmdLineOpts().parsed.storage.dbPath')
      break;
    fi
  done
}

choose_rs_node_upgrade()
{
  local NODE_TYPE=$1
  UPGRADE_PORT=""
  UPGRADE_DATA=""
  for node_port in ${NODE3_PORT} ${NODE2_PORT} ${NODE1_PORT}; do
    if [ $(${PSMDB_OLD_BINDIR}/bin/mongo --host=${HOST} --port ${node_port} --quiet --eval 'db.isMaster().ismaster') = "true" ]; then
      CUR_NODE_TYPE="PRIMARY"
    else
      CUR_NODE_TYPE="SECONDARY"
    fi
    CUR_NODE_VER="$(${PSMDB_OLD_BINDIR}/bin/mongo --host=${HOST} --port ${node_port} --quiet --eval 'db.serverBuildInfo().version')"
    if [ "${CUR_NODE_VER}" = "${OLD_VER}" -a "${CUR_NODE_TYPE}" = "${NODE_TYPE}" ]; then
      UPGRADE_PORT=$node_port
      UPGRADE_DATA=$(${PSMDB_OLD_BINDIR}/bin/mongo --host=${HOST} --port ${node_port} --quiet --eval 'db.serverCmdLineOpts().parsed.storage.dbPath')
      break;
    fi
  done
}

upgrade_next_rs_node()
{
  local NODE_TYPE=$1
  choose_rs_node_upgrade ${NODE_TYPE}
  if [ "${NODE_TYPE}" == "PRIMARY" ]; then
    ${PSMDB_OLD_BINDIR}/bin/mongo --host=${HOST} --port ${UPGRADE_PORT} --quiet --eval 'rs.stepDown();' || true
  fi
  echo -e "\n\n##### Upgrading ${HOST}:${UPGRADE_PORT} - ${UPGRADE_DATA} #####\n"
  stop_single ${OLD_VER} ${UPGRADE_DATA} ${UPGRADE_DATA}/${UPGRADE_PORT}-${OLD_VER}-${STORAGE_ENGINE}-upgrade-stop.log ${PSMDB_OLD_BINDIR} ${UPGRADE_PORT}
  start_single ${NEW_VER} ${UPGRADE_DATA} ${UPGRADE_DATA}/${UPGRADE_PORT}-${NEW_VER}-${STORAGE_ENGINE}-after-upgrade-start.log ${PSMDB_NEW_BINDIR} ${UPGRADE_PORT} ${STORAGE_ENGINE} rs0
}
###
### END COMMON FUNCTIONS
###

if [ "${LAYOUT_TYPE}" == "single" ]; then
  start_single ${OLD_VER} ${NODE1_DATA} ${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-first-start.log ${PSMDB_OLD_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE}
  import_test_data ${OLD_VER} ${PSMDB_OLD_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE} test restaurants ${TEST_DB_FILE} ${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-import.log
  if [ "${BENCH_TOOL}" != "none" ]; then
    run_bench bench_test ${NODE1_PORT} FALSE beforeUpgrade ${NODE1_DATA} load
    run_bench bench_test2 ${NODE1_PORT} FALSE beforeUpgrade ${NODE1_DATA} load
  fi
  # create db hashes
  ${PSMDB_OLD_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet > ${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node1-dbhash-before.log
  ${PSMDB_OLD_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/bench_test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet >> ${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node1-dbhash-before.log

  # downgrade featureCompatibilityVersion to lower version
  if [ "${TEST_TYPE}" == "downgrade" ]; then
    ${PSMDB_OLD_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/admin --eval "db.adminCommand( { setFeatureCompatibilityVersion: \"${COMPATIBILITY}\" } );"
  fi
  #
  echo -e "\n\n##### Show info of node ${NODE1_PORT} before upgrade #####\n"
  show_node_info ${NODE1_PORT} "beforeUpgrade" | tee ${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-nodeInfo-beforeUpgrade.log
  stop_single ${OLD_VER} ${NODE1_DATA} ${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-upgrade-stop.log ${PSMDB_OLD_BINDIR} ${NODE1_PORT}
  sleep 10
  start_single ${NEW_VER} ${NODE1_DATA} ${NODE1_DATA}/${NODE1_PORT}-${NEW_VER}-${STORAGE_ENGINE}-after-upgrade-start.log ${PSMDB_NEW_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE}

  # upgrade featureCompatibilityVersion to higher version
  if [ "${TEST_TYPE}" == "upgrade" ]; then
		if [ "${STORAGE_ENGINE}" != "rocksdb" -o "${COMPATIBILITY}" != "3.6" ]; then
			${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/admin --eval "db.adminCommand( { setFeatureCompatibilityVersion: \"${COMPATIBILITY}\" } );"
		else
			COMPATIBILITY="3.4"
		fi
  fi

  import_test_data ${NEW_VER} ${PSMDB_NEW_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE} test2 restaurants ${TEST_DB_FILE} ${NODE1_DATA}/${NODE1_PORT}-${NEW_VER}-${STORAGE_ENGINE}-import.log
  if [ "${BENCH_TOOL}" != "none" ]; then
    run_bench bench_test2 ${NODE1_PORT} TRUE afterUpgrade ${NODE1_DATA} update
  fi
  # create db hashes
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet > ${NODE1_DATA}/${NODE1_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node1-dbhash-after.log
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/bench_test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet >> ${NODE1_DATA}/${NODE1_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node1-dbhash-after.log
  #
  echo -e "\n\n##### Show info of node ${NODE1_PORT} after upgrade #####\n"
  show_node_info ${NODE1_PORT} "afterUpgrade" | tee ${NODE1_DATA}/${NODE1_PORT}-${NEW_VER}-${STORAGE_ENGINE}-nodeInfo-afterUpgrade.log
  NODE1_COMP=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/test --quiet --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 }).featureCompatibilityVersion.version")
  if [ -z "${NODE1_COMP}" ]; then
    NODE1_COMP=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/test --quiet --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 }).featureCompatibilityVersion")
  fi
  if [ "${NODE1_COMP}" != "${COMPATIBILITY}" ]; then
    echo "ERROR: Compatibility version is not ${COMPATIBILITY} on all nodes!"
    exit 1
  else
    echo "OK: Compatibility version is ${COMPATIBILITY} on all nodes!"
  fi
  if [ "${LEAVE_RUNNING}" = "false" ]; then
    stop_single ${NEW_VER} ${NODE1_DATA} ${NODE1_DATA}/${NODE1_PORT}-${NEW_VER}-${STORAGE_ENGINE}-final-stop.log ${PSMDB_NEW_BINDIR} ${NODE1_PORT}
  fi

  diff ${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node1-dbhash-before.log ${NODE1_DATA}/${NODE1_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node1-dbhash-after.log
  RESULT=$?
  if [ ${RESULT} -ne 0 ]; then
    echo "### ERROR: Data after upgrade seems to have different dbhash then it had before upgrade! ###"
  else
    echo "### SUCCESS: Data after upgrade seems to have the same dbhash as before upgrade! ###"
  fi
  exit $RESULT

elif [ "${LAYOUT_TYPE}" == "replicaset" ]; then
  start_replica
  init_replica
  update_primary_info
  import_test_data ${OLD_VER} ${PSMDB_OLD_BINDIR} ${PRIMARY_PORT} ${STORAGE_ENGINE} test restaurants ${TEST_DB_FILE} ${PRIMARY_DATA}/${PRIMARY_PORT}-${OLD_VER}-${STORAGE_ENGINE}-import.log
  if [ "${BENCH_TOOL}" != "none" ]; then
    update_primary_info
    echo "PRIMARY_PORT: ${PRIMARY_PORT}"
    echo "PRIMARY_DATA: ${PRIMARY_DATA}"
    run_bench bench_test ${PRIMARY_PORT} FALSE "beforeUpgrade-${PRIMARY_PORT}" ${PRIMARY_DATA} load
    run_bench bench_test2 ${PRIMARY_PORT} FALSE "beforeUpgrade-${PRIMARY_PORT}" ${PRIMARY_DATA} load
  fi
  sleep 10
  # create db hashes
  ${PSMDB_OLD_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet > ${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node1-dbhash-before.log
  ${PSMDB_OLD_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/bench_test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet >> ${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node1-dbhash-before.log
  ${PSMDB_OLD_BINDIR}/bin/mongo ${HOST}:${NODE2_PORT}/test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet > ${NODE2_DATA}/${NODE2_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node2-dbhash-before.log
  ${PSMDB_OLD_BINDIR}/bin/mongo ${HOST}:${NODE2_PORT}/bench_test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet >> ${NODE2_DATA}/${NODE2_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node2-dbhash-before.log
  ${PSMDB_OLD_BINDIR}/bin/mongo ${HOST}:${NODE3_PORT}/test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet > ${NODE3_DATA}/${NODE3_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node3-dbhash-before.log
  ${PSMDB_OLD_BINDIR}/bin/mongo ${HOST}:${NODE3_PORT}/bench_test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet >> ${NODE3_DATA}/${NODE3_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node3-dbhash-before.log
  #
  # downgrade featureCompatibilityVersion to lower version before RS downgrade
  update_primary_info
  if [ "${TEST_TYPE}" == "downgrade" ]; then
    ${PSMDB_OLD_BINDIR}/bin/mongo ${HOST}:${PRIMARY_PORT}/test --eval "db.adminCommand( { setFeatureCompatibilityVersion: \"${COMPATIBILITY}\" } );"
  fi
  #
  echo -e "\n\n##### Show info of node ${PRIMARY_PORT} after sysbench and before any upgrades #####\n"
  show_node_info ${PRIMARY_PORT} "beforeUpgrade"
  upgrade_next_rs_node "SECONDARY"
  echo -e "\n\n##### Show info of node ${UPGRADE_PORT} after upgrade #####\n"
  show_node_info ${UPGRADE_PORT} "afterUpgrade"
  upgrade_next_rs_node "SECONDARY"
  if [ "${BENCH_TOOL}" != "none" ]; then
    update_primary_info
    echo "PRIMARY_PORT: ${PRIMARY_PORT}"
    echo "PRIMARY_DATA: ${PRIMARY_DATA}"
    run_bench bench_test2 ${PRIMARY_PORT} FALSE "afterTwoUpgrade-${PRIMARY_PORT}" ${PRIMARY_DATA} update
  fi
  echo -e "\n\n##### Show info of node ${UPGRADE_PORT} after upgrade #####\n"
  show_node_info ${UPGRADE_PORT} "afterUpgrade"
  upgrade_next_rs_node "PRIMARY"
  update_primary_info
  if [ "${TEST_TYPE}" == "upgrade" ]; then
		if [ "${STORAGE_ENGINE}" != "rocksdb" -o "${COMPATIBILITY}" != "3.6" ]; then
			${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${PRIMARY_PORT}/test --eval "db.adminCommand( { setFeatureCompatibilityVersion: \"${COMPATIBILITY}\" } );"
		else
			COMPATIBILITY="3.4"
		fi
  fi
  sleep 10
  if [ "${BENCH_TOOL}" != "none" ]; then
    echo "PRIMARY_PORT: ${PRIMARY_PORT}"
    echo "PRIMARY_DATA: ${PRIMARY_DATA}"
    run_bench bench_test2 ${PRIMARY_PORT} FALSE "afterAllUpgrade-${PRIMARY_PORT}" ${PRIMARY_DATA} update
  fi
  # create db hashes
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet > ${NODE1_DATA}/${NODE1_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node1-dbhash-after.log
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/bench_test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet >> ${NODE1_DATA}/${NODE1_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node1-dbhash-after.log
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE2_PORT}/test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet > ${NODE2_DATA}/${NODE2_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node2-dbhash-after.log
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE2_PORT}/bench_test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet >> ${NODE2_DATA}/${NODE2_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node2-dbhash-after.log
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE3_PORT}/test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet > ${NODE3_DATA}/${NODE3_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node3-dbhash-after.log
  ${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE3_PORT}/bench_test --eval "db.runCommand({ dbHash: 1 }).md5" --quiet >> ${NODE3_DATA}/${NODE3_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node3-dbhash-after.log
  #
  echo -e "\n\n##### Show info of node ${UPGRADE_PORT} after upgrade #####\n"
  show_node_info ${UPGRADE_PORT} "afterUpgrade"

  NODE1_COMP=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/test --quiet --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 }).featureCompatibilityVersion.version")
  if [ -z "${NODE1_COMP}" ]; then
    NODE1_COMP=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/test --quiet --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 }).featureCompatibilityVersion")
  fi
  NODE2_COMP=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE2_PORT}/test --quiet --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 }).featureCompatibilityVersion.version")
  if [ -z "${NODE2_COMP}" ]; then
    NODE2_COMP=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE2_PORT}/test --quiet --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 }).featureCompatibilityVersion")
  fi
  NODE3_COMP=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE3_PORT}/test --quiet --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 }).featureCompatibilityVersion.version")
  if [ -z "${NODE3_COMP}" ]; then
    NODE3_COMP=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE3_PORT}/test --quiet --eval "db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 }).featureCompatibilityVersion")
  fi
  if [ "${NODE1_COMP}" != "${COMPATIBILITY}" -o "${NODE2_COMP}" != "${COMPATIBILITY}" -o "${NODE3_COMP}" != "${COMPATIBILITY}" ]; then
    echo "ERROR: Compatibility version is not ${COMPATIBILITY} on all nodes!"
    exit 1
  else
    echo "OK: Compatibility version is ${COMPATIBILITY} on all nodes!"
  fi

  NODE1_VER=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE1_PORT}/test --quiet --eval "db.serverStatus().version")
  NODE2_VER=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE2_PORT}/test --quiet --eval "db.serverStatus().version")
  NODE3_VER=$(${PSMDB_NEW_BINDIR}/bin/mongo ${HOST}:${NODE3_PORT}/test --quiet --eval "db.serverStatus().version")
  if [ "${NODE1_VER}" != "${NODE2_VER}" -o "${NODE2_VER}" != "${NODE3_VER}" ]; then
    echo "ERROR: Version is not the same on all nodes!"
    exit 1
  else
    echo "OK: Version is the same on all nodes: ${NODE1_VER}"
  fi

  if [ "${LEAVE_RUNNING}" = "false" ]; then
    killall mongod
  fi

  diff --from-file=${NODE1_DATA}/${NODE1_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node1-dbhash-before.log ${NODE2_DATA}/${NODE2_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node2-dbhash-before.log ${NODE3_DATA}/${NODE3_PORT}-${OLD_VER}-${STORAGE_ENGINE}-node3-dbhash-before.log ${NODE1_DATA}/${NODE1_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node1-dbhash-after.log ${NODE2_DATA}/${NODE2_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node2-dbhash-after.log ${NODE3_DATA}/${NODE3_PORT}-${NEW_VER}-${STORAGE_ENGINE}-node3-dbhash-after.log
  RESULT=$?
  if [ ${RESULT} -ne 0 ]; then
    echo "### ERROR: Data after upgrade seems to have different dbhash then it had before upgrade! ###"
  else
    echo "### SUCCESS: Data after upgrade seems to have the same dbhash as before upgrade! ###"
  fi
  exit $RESULT
else
  echo "Wrong test type specified!"
  exit 1
fi
