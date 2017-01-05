#!/bin/bash
# This script is used to test upgrade of PSMDB from 3.2 to 3.4
# and it can test single instances or replicasets with different
# storage engines
# Created by Tomislav Plavcic

if [ "$#" -ne 3 ]; then
  echo "This script requires absolute workdir, test type and storage engine as parameters!";
  echo "Example: ./psmdb32to34.sh /tmp/psmdb-upgrade single rocksdb"
  echo "         ./psmdb32to34.sh /tmp/psmdb-upgrade replicaset wiredTiger"
  exit 1
fi

ulimit -c unlimited

set -e

#Kill mongod and mongos processes
killall -9 mongod > /dev/null 2>&1 || true
killall -9 mongos > /dev/null 2>&1 || true
sleep 5

SCRIPT_PWD=$(cd `dirname $0` && pwd)
WORKDIR=$1
TEST_TYPE=$2
STORAGE_ENGINE=$3
BASE_DATADIR="${WORKDIR}/data"
MONGO_START_TIMEOUT=600

# Parameters of parameterized build
if [ -z $MONGOD_EXTRA ]; then
  MONGOD_EXTRA=""
fi
if [ -z $LEAVE_RUNNING ]; then
  LEAVE_RUNNING=false
fi
if [ -z $SKIP_SYSBENCH ]; then
  SKIP_SYSBENCH=false
fi
if [ -z $SDURATION ]; then
  SDURATION=5
fi
if [ -z $SCOLLECTIONS ]; then
  SCOLLECTIONS=10
fi
if [ -z $SDOCSPERCOL ]; then
  SDOCSPERCOL=1000000
fi
if [ -z $SWRITE_CONCERN ]; then
  SWRITE_CONCERN="SAFE"
fi
if [ -z $SLOADER_THREADS ]; then
  SLOADER_THREADS=8
fi
if [ -z $SWRITER_THREADS ]; then
  SWRITER_THREADS=64
fi

cd ${WORKDIR}

PSMDB32_TAR=$(find . -maxdepth 1|grep -o percona-server-mongodb-3.2*.tar.gz)
PSMDB32_DIR=$(echo ${PSMDB32_TAR%.tar.gz}|cut --delimiter=- -f1-5)
PSMDB34_TAR=$(find . -maxdepth 1|grep -o percona-server-mongodb-3.4*.tar.gz)
PSMDB34_DIR=$(echo ${PSMDB34_TAR%.tar.gz}|cut --delimiter=- -f1-5)
PSMDB32_BINDIR="${WORKDIR}/${PSMDB32_DIR}"
PSMDB34_BINDIR="${WORKDIR}/${PSMDB34_DIR}"

if [ -z ${PSMDB32_TAR} ]; then
  echo "PSMDB 3.2 tarball not found!"
  exit 1
fi
if [ -z ${PSMDB34_TAR} ]; then
  echo "PSMDB 3.4 tarball not found!"
  exit 1
fi

rm -rf ${BASE_DATADIR}
rm -f ${WORKDIR}/results_${TEST_TYPE}_${STORAGE_ENGINE}.tar

if [ ! -d ${PSMDB32_DIR} ]; then
  tar xf ${PSMDB32_TAR}
fi
if [ ! -d ${PSMDB34_DIR} ]; then
  tar xf ${PSMDB34_TAR}
fi

HOST=$(hostname)
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

echo "Workdir: $WORKDIR"
echo "Bindirs: $PSMDB32_BINDIR $PSMDB34_BINDIR"

# Download test database
if [ ! -f primer-dataset.json ]; then
  wget https://raw.githubusercontent.com/mongodb/docs-assets/primer-dataset/primer-dataset.json
fi
TEST_DB_FILE=${WORKDIR}/primer-dataset.json

# Download sysbench-mongodb
if [ "${SKIP_SYSBENCH}" = "false" ]; then
  if [ ! -f mongo-java-driver-3.2.1.jar ]; then
    wget https://oss.sonatype.org/content/repositories/releases/org/mongodb/mongo-java-driver/3.2.1/mongo-java-driver-3.2.1.jar
  fi
  export CLASSPATH=$PWD/mongo-java-driver-3.2.1.jar:$CLASSPATH
  if [ ! -d sysbench-mongodb ]; then
    git clone https://github.com/Percona-Lab/sysbench-mongodb.git
  fi
fi

### COMMON FUNCTIONS
archives() {
  rm -rf ${WORKDIR}/results_${TEST_TYPE}_${STORAGE_ENGINE}
  mkdir ${WORKDIR}/results_${TEST_TYPE}_${STORAGE_ENGINE}
  find data -maxdepth 3 -type f \( -iname \*.log -o -iname \*.txt -o -iname \*.tsv \) -exec cp {} ${WORKDIR}/results_${TEST_TYPE}_${STORAGE_ENGINE} \;
  tar czf ${WORKDIR}/results_${TEST_TYPE}_${STORAGE_ENGINE}.tar.gz -C ${WORKDIR} results_${TEST_TYPE}_${STORAGE_ENGINE}
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
  if [ ! -z $7 ]; then
    local REPL_SET="--replSet "${FUN_REPL_SET}""
  fi

  if [ ! -d ${FUN_NODE_DATA} ]; then
    mkdir -p ${FUN_NODE_DATA}
  fi

  echo "Starting node on port ${FUN_NODE_PORT} storage engine: ${FUN_NODE_SE}"

  ${FUN_BIN_DIR}/bin/mongod --dbpath ${FUN_NODE_DATA} --logpath ${FUN_LOG_ERR} --port ${FUN_NODE_PORT} --logappend --fork  --storageEngine ${FUN_NODE_SE} ${REPL_SET} ${MONGOD_EXTRA} > ${FUN_LOG_ERR} 2>&1 &

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
  start_single 3.2 ${NODE1_DATA} ${NODE1_DATA}/${NODE1_PORT}-3.2-${STORAGE_ENGINE}-first-start.log ${PSMDB32_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE} rs0
  start_single 3.2 ${NODE2_DATA} ${NODE2_DATA}/${NODE2_PORT}-3.2-${STORAGE_ENGINE}-first-start.log ${PSMDB32_BINDIR} ${NODE2_PORT} ${STORAGE_ENGINE} rs0
  start_single 3.2 ${NODE3_DATA} ${NODE3_DATA}/${NODE3_PORT}-3.2-${STORAGE_ENGINE}-first-start.log ${PSMDB32_BINDIR} ${NODE3_PORT} ${STORAGE_ENGINE} rs0
}

init_replica()
{
  ${PSMDB32_BINDIR}/bin/mongo --host=${HOST} --port ${NODE1_PORT} --eval "rs.initiate()"
  ${PSMDB32_BINDIR}/bin/mongo --host=${HOST} --port ${NODE1_PORT} --eval "rs.add(\"${HOST}:${NODE2_PORT}\")"
  ${PSMDB32_BINDIR}/bin/mongo --host=${HOST} --port ${NODE1_PORT} --eval "rs.add(\"${HOST}:${NODE3_PORT}\")"
  sleep 3
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

run_sysbench()
{
  local FUN_DATABASE=$1
  local FUN_PORT=$2
  local FUN_DROP=$3
  local FUN_PREFIX=$4
  local FUN_DATA=$5

  # Set run parameters
  sed -i "/export DB_NAME=/c\export DB_NAME=${FUN_DATABASE}" sysbench-mongodb/config.bash
  sed -i "/export USERNAME=/c\export USERNAME=none" sysbench-mongodb/config.bash
  sed -i "/export MONGO_SERVER=/c\export MONGO_SERVER=${HOST}" sysbench-mongodb/config.bash
  sed -i "/export MONGO_PORT=/c\export MONGO_PORT=${FUN_PORT}" sysbench-mongodb/config.bash
  sed -i "/export NUM_COLLECTIONS=/c\export NUM_COLLECTIONS=${SCOLLECTIONS}" sysbench-mongodb/config.bash
  sed -i "/export NUM_DOCUMENTS_PER_COLLECTION=/c\export NUM_DOCUMENTS_PER_COLLECTION=${SDOCSPERCOL}" sysbench-mongodb/config.bash
  sed -i "/export RUN_TIME_MINUTES=/c\export RUN_TIME_MINUTES=${SDURATION}" sysbench-mongodb/config.bash
  sed -i "/export DROP_COLLECTIONS=/c\export DROP_COLLECTIONS=${FUN_DROP}" sysbench-mongodb/config.bash
  sed -i "/export NUM_WRITER_THREADS=/c\export NUM_WRITER_THREADS=${SWRITER_THREADS}" sysbench-mongodb/config.bash
  sed -i "/export NUM_LOADER_THREADS=/c\export NUM_LOADER_THREADS=${SLOADER_THREADS}" sysbench-mongodb/config.bash
  sed -i "/export WRITE_CONCERN=/c\export WRITE_CONCERN=${SWRITE_CONCERN}" sysbench-mongodb/config.bash

  # Execute sysbench-mongodb
  echo "Executing sysbench-mongodb run on node ${FUN_PORT} database ${FUN_DATABASE}"
  pushd sysbench-mongodb
  ./run.simple.bash
  rename "s/^mongoSysbench/${FUN_PREFIX}_mongoSysbench/" *.txt
  rename "s/^mongoSysbench/${FUN_PREFIX}_mongoSysbench/" *.tsv
  mv *.txt ${FUN_DATA}
  mv *.tsv ${FUN_DATA}
  popd
  echo "Finished with sysbench-mongodb run on node ${FUN_PORT} database ${FUN_DATABASE}"
}

show_node_info()
{
  local FUN_PORT=$1
  local FUN_TEXT=$2
  echo -e "\n\n##### Show databases info on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB34_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --eval "rs.slaveOk(); db.adminCommand('listDatabases')"
  echo -e "\n\n##### Show server info on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB34_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --eval "db.serverStatus()"
  echo -e "\n\n##### Show info on sbtest database on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB34_BINDIR}/bin/mongo ${HOST}:${FUN_PORT}/sbtest --eval "db.stats()"
  echo -e "\n\n##### Show info on test database on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB34_BINDIR}/bin/mongo ${HOST}:${FUN_PORT}/test --eval "db.stats()"
  echo -e "\n\n##### Show replica set status on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB34_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --eval "rs.status()"
  echo -e "\n\n##### Show isMaster info on node ${FUN_PORT} ${FUN_TEXT} #####\n"
  ${PSMDB34_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --eval "db.isMaster()"
}

update_primary_info()
{
  PRIMARY_PORT=""
  PRIMARY_DATA=""
  for node_port in $NODE1_PORT $NODE2_PORT $NODE3_PORT; do
    if [ $(${PSMDB32_BINDIR}/bin/mongo --host=${HOST} --port ${node_port} --eval 'db.isMaster().ismaster' | tail -n1) = "true" ]; then
      PRIMARY_PORT=$node_port
      PRIMARY_DATA=$(${PSMDB32_BINDIR}/bin/mongo --host=${HOST} --port ${node_port} --eval 'db.serverCmdLineOpts().parsed.storage.dbPath' | tail -n1)
      break;
    fi
  done
}

choose_rs_node_upgrade()
{
  UPGRADE_PORT=""
  UPGRADE_DATA=""
  for node_port in $NODE3_PORT $NODE2_PORT $NODE1_PORT; do
    if [ $(${PSMDB32_BINDIR}/bin/mongo --host=${HOST} --port ${node_port} --eval 'db.serverBuildInfo().version'|tail -n1|cut -d '.' -f 1,2) = "3.2" ]; then
      UPGRADE_PORT=$node_port
      UPGRADE_DATA=$(${PSMDB32_BINDIR}/bin/mongo --host=${HOST} --port ${node_port} --eval 'db.serverCmdLineOpts().parsed.storage.dbPath' | tail -n1)
      break;
    fi
  done
}

upgrade_next_rs_node()
{
  choose_rs_node_upgrade
  echo -e "\n\n##### Upgrading ${HOST}:${UPGRADE_PORT} - ${UPGRADE_DATA} #####\n"
  stop_single 3.2 ${UPGRADE_DATA} ${UPGRADE_DATA}/${UPGRADE_PORT}-3.2-${STORAGE_ENGINE}-upgrade-stop.log ${PSMDB32_BINDIR} ${UPGRADE_PORT}
  start_single 3.4 ${UPGRADE_DATA} ${UPGRADE_DATA}/${UPGRADE_PORT}-3.4-${STORAGE_ENGINE}-after-upgrade-start.log ${PSMDB34_BINDIR} ${UPGRADE_PORT} ${STORAGE_ENGINE} rs0
}
### END COMMON FUNCTIONS

if [ ${TEST_TYPE} = "single" ]; then
  start_single 3.2 ${NODE1_DATA} ${NODE1_DATA}/${NODE1_PORT}-3.2-${STORAGE_ENGINE}-first-start.log ${PSMDB32_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE}
  import_test_data 3.2 ${PSMDB32_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE} test restaurants ${TEST_DB_FILE} ${NODE1_DATA}/${NODE1_PORT}-3.2-${STORAGE_ENGINE}-import.log
  if [ "${SKIP_SYSBENCH}" = "false" ]; then
    run_sysbench sbtest ${NODE1_PORT} TRUE beforeUpgrade ${NODE1_DATA}
  fi
  echo -e "\n\n##### Show info of node ${NODE1_PORT} before upgrade #####\n"
  show_node_info ${NODE1_PORT} "beforeUpgrade"
  stop_single 3.2 ${NODE1_DATA} ${NODE1_DATA}/${NODE1_PORT}-3.2-${STORAGE_ENGINE}-upgrade-stop.log ${PSMDB32_BINDIR} ${NODE1_PORT}
  start_single 3.4 ${NODE1_DATA} ${NODE1_DATA}/${NODE1_PORT}-3.4-${STORAGE_ENGINE}-after-upgrade-start.log ${PSMDB34_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE}
  import_test_data 3.4 ${PSMDB34_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE} test2 restaurants ${TEST_DB_FILE} ${NODE1_DATA}/${NODE1_PORT}-3.4-${STORAGE_ENGINE}-import.log
  if [ "${SKIP_SYSBENCH}" = "false" ]; then
    run_sysbench sbtest2 ${NODE1_PORT} TRUE afterUpgrade ${NODE1_DATA}
  fi
  echo -e "\n\n##### Show info of node ${NODE1_PORT} after upgrade #####\n"
  show_node_info ${NODE1_PORT} "afterUpgrade"
  if [ "${LEAVE_RUNNING}" = "false" ]; then
    stop_single 3.4 ${NODE1_DATA} ${NODE1_DATA}/${NODE1_PORT}-3.4-${STORAGE_ENGINE}-final-stop.log ${PSMDB34_BINDIR} ${NODE1_PORT}
  fi
elif [ ${TEST_TYPE} = "replicaset" ]; then
  start_replica
  init_replica
  update_primary_info
  import_test_data 3.2 ${PSMDB32_BINDIR} ${PRIMARY_PORT} ${STORAGE_ENGINE} test restaurants ${TEST_DB_FILE} ${PRIMARY_DATA}/${PRIMARY_PORT}-3.2-${STORAGE_ENGINE}-import.log
  if [ "${SKIP_SYSBENCH}" = "false" ]; then
    update_primary_info
    echo "PRIMARY_PORT: ${PRIMARY_PORT}"
    echo "PRIMARY_DATA: ${PRIMARY_DATA}"
    run_sysbench sbtest ${PRIMARY_PORT} TRUE "beforeUpgrade-${PRIMARY_PORT}" ${PRIMARY_DATA}
  fi
  echo -e "\n\n##### Show info of node ${PRIMARY_PORT} after sysbench and before any upgrades #####\n"
  show_node_info ${PRIMARY_PORT} "beforeUpgrade"
  upgrade_next_rs_node
  echo -e "\n\n##### Show info of node ${UPGRADE_PORT} after upgrade #####\n"
  show_node_info ${UPGRADE_PORT} "afterUpgrade"
  upgrade_next_rs_node
  if [ "${SKIP_SYSBENCH}" = "false" ]; then
    update_primary_info
    echo "PRIMARY_PORT: ${PRIMARY_PORT}"
    echo "PRIMARY_DATA: ${PRIMARY_DATA}"
    run_sysbench sbtest ${PRIMARY_PORT} TRUE "afterTwoUpgrade-${PRIMARY_PORT}" ${PRIMARY_DATA}
  fi
  echo -e "\n\n##### Show info of node ${UPGRADE_PORT} after upgrade #####\n"
  show_node_info ${UPGRADE_PORT} "afterUpgrade"
  upgrade_next_rs_node
  if [ "${SKIP_SYSBENCH}" = "false" ]; then
    update_primary_info
    echo "PRIMARY_PORT: ${PRIMARY_PORT}"
    echo "PRIMARY_DATA: ${PRIMARY_DATA}"
    run_sysbench sbtest ${PRIMARY_PORT} TRUE "afterAllUpgrade-${PRIMARY_PORT}" ${PRIMARY_DATA}
  fi
  echo -e "\n\n##### Show info of node ${UPGRADE_PORT} after upgrade #####\n"
  show_node_info ${UPGRADE_PORT} "afterUpgrade"
  if [ "${LEAVE_RUNNING}" = "false" ]; then
    killall mongod
  fi
else
  echo "Wrong test type specified!"
  exit 1
fi
