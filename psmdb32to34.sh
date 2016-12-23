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
MONGO_START_TIMEOUT=180

# Parameters of parameterized build
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
NODE1_DATA="${BASE_DATADIR}/node1"
NODE2_DATA="${BASE_DATADIR}/node2"
NODE3_DATA="${BASE_DATADIR}/node3"

echo "Workdir: $WORKDIR"
echo "Bindirs: $PSMDB32_BINDIR $PSMDB34_BINDIR"

# Download test database
if [ ! -f primer-dataset.json ]; then
  wget https://raw.githubusercontent.com/mongodb/docs-assets/primer-dataset/primer-dataset.json
fi
TEST_DB_FILE=${WORKDIR}/primer-dataset.json

# Download sysbench-mongodb
if [ ! -f mongo-java-driver-3.2.1.jar ]; then
  wget https://oss.sonatype.org/content/repositories/releases/org/mongodb/mongo-java-driver/3.2.1/mongo-java-driver-3.2.1.jar
fi
export CLASSPATH=$PWD/mongo-java-driver-3.2.1.jar:$CLASSPATH
if [ ! -d sysbench-mongodb ]; then
  git clone https://github.com/Percona-Lab/sysbench-mongodb.git
fi

### COMMON FUNCTIONS
archives() {
  #find data -maxdepth 3 -name "*.log" -name "*.txt" -name "*.tsv" -exec tar -rf ${WORKDIR}/results_${TEST_TYPE}_${STORAGE_ENGINE}.tar {} \;
  find data -maxdepth 3 -type f \( -iname \*.log -o -iname \*.txt -o -iname \*.tsv \) -exec tar -rf ${WORKDIR}/results_${TEST_TYPE}_${STORAGE_ENGINE}.tar {} \;
  #rm -rf ${BASE_DATADIR}
}

trap archives EXIT KILL

start_single()
{
  local FUN_NODE_NR=$1
  local FUN_NODE_VER=$2
  local FUN_NODE_DATA=$3
  local FUN_LOG_ERR=$4
  local FUN_BIN_DIR=$5
  local FUN_NODE_PORT=$6
  local FUN_NODE_SE=$7
  local FUN_REPL_SET="$8"

  local REPL_SET=""
  if [ ! -z $8 ]; then
    local REPL_SET="--replSet "${FUN_REPL_SET}""
  fi

  if [ ! -d ${FUN_NODE_DATA} ]; then
    mkdir -p ${FUN_NODE_DATA}
  fi

  echo "Starting PSMDB-${FUN_NODE_VER} node${FUN_NODE_NR} storage engine: ${FUN_NODE_SE} port ${FUN_NODE_PORT}"

  ${FUN_BIN_DIR}/bin/mongod --dbpath ${FUN_NODE_DATA} --logpath ${FUN_LOG_ERR} --port ${FUN_NODE_PORT} --logappend --fork  --storageEngine ${FUN_NODE_SE} ${REPL_SET} > ${FUN_LOG_ERR} 2>&1 &

  for X in $(seq 0 ${MONGO_START_TIMEOUT}); do
    sleep 1
    if ${FUN_BIN_DIR}/bin/mongo --host=${HOST} --port ${FUN_NODE_PORT} --eval "db.serverStatus()" > /dev/null 2>&1; then
      break
    fi
  done
  if ${FUN_BIN_DIR}/bin/mongo --host=${HOST} --port ${FUN_NODE_PORT} --eval "db.serverStatus()" ping > /dev/null 2>&1; then
    echo "PSMDB node${FUN_NODE_NR} started ok.."
  else
    echo "PSMDB node${FUN_NODE_NR} startup failed.. Please check error log: ${FUN_LOG_ERR}"
  fi
  sleep 10
}

stop_single()
{
  local FUN_NODE_NR=$1
  local FUN_NODE_VER=$2
  local FUN_NODE_DATA=$3
  local FUN_LOG_ERR=$4
  local FUN_BIN_DIR=$5
  local FUN_NODE_PORT=$6

  ${FUN_BIN_DIR}/bin/mongod --dbpath ${FUN_NODE_DATA} --port ${FUN_NODE_PORT} --shutdown > ${FUN_LOG_ERR} 2>&1 &

  echo "Stopping node${FUN_NODE_NR} version ${FUN_NODE_VER} storage engine ${FUN_NODE_SE} port ${FUN_NODE_PORT}"
  for X in $(seq 0 ${MONGO_START_TIMEOUT}); do
    sleep 1
    if [ $(cat ${FUN_NODE_DATA}/mongod.lock|wc -l) -eq "0" ]; then
      break
    fi
  done
  if [ $(cat ${FUN_NODE_DATA}/mongod.lock|wc -l) -eq "0" ]; then
    echo "PSMDB node${FUN_NODE_NR} stopped ok.."
  else
    echo "PSMDB node${FUN_NODE_NR} stop failed.. Please check error log: ${FUN_LOG_ERR}"
  fi
}

start_replica()
{
  start_single 1 3.2 ${NODE1_DATA} ${NODE1_DATA}/node1-3.2-${STORAGE_ENGINE}-first-start.log ${PSMDB32_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE} rs0
  start_single 2 3.2 ${NODE2_DATA} ${NODE2_DATA}/node2-3.2-${STORAGE_ENGINE}-first-start.log ${PSMDB32_BINDIR} ${NODE2_PORT} ${STORAGE_ENGINE} rs0
  start_single 3 3.2 ${NODE3_DATA} ${NODE3_DATA}/node3-3.2-${STORAGE_ENGINE}-first-start.log ${PSMDB32_BINDIR} ${NODE3_PORT} ${STORAGE_ENGINE} rs0
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
  local FUN_NODE_NR=$1
  local FUN_NODE_VER=$2
  local FUN_BIN_DIR=$3
  local FUN_NODE_PORT=$4
  local FUN_NODE_SE=$5
  local FUN_DB=$6
  local FUN_COLLECTION=$7
  local FUN_IMPORT_FILE=$8
  local FUN_LOG_ERR=$9

  echo "Importing test database to node${FUN_NODE_NR} version ${FUN_NODE_VER} storage engine ${FUN_NODE_SE}"
  ${FUN_BIN_DIR}/bin/mongoimport --host=${HOST} --port=${FUN_NODE_PORT} --db ${FUN_DB} --collection ${FUN_COLLECTION} --drop --file ${FUN_IMPORT_FILE} > ${FUN_LOG_ERR} 2>&1
  if [ $? -eq 0 ]; then
    echo "Importing test database was successful."
  else
    echo "Error while importing test database, please check ${FUN_LOG_ERR}"
  fi
}

run_sysbench()
{
  local FUN_NODE=$1
  local FUN_DATABASE=$2
  local FUN_PORT=$3
  local FUN_DROP=$4
  local FUN_PREFIX=$5
  local FUN_DATA=$6

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
  echo "Executing sysbench-mongodb run on node${FUN_NODE_NR} port ${FUN_PORT} database ${FUN_DATABASE}"
  pushd sysbench-mongodb
  ./run.simple.bash
  rename "s/^mongoSysbench/${FUN_PREFIX}_mongoSysbench/" *.txt
  rename "s/^mongoSysbench/${FUN_PREFIX}_mongoSysbench/" *.tsv
  mv *.txt ${FUN_DATA}
  mv *.tsv ${FUN_DATA}
  popd
  echo "Finished with sysbench-mongodb run on node${FUN_NODE_NR} port ${FUN_PORT} database ${FUN_DATABASE}"
}

show_node_info()
{
  local FUN_NODE=$1
  local FUN_PORT=$2
  echo -e "\n\n##### Show server info on node${FUN_NODE} #####\n"
  ${PSMDB32_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --eval "db.serverStatus()"
  echo -e "\n\n##### Show info on sbtest database on node${FUN_NODE} #####\n"
  ${PSMDB32_BINDIR}/bin/mongo ${HOST}:${FUN_PORT}/sbtest --eval "db.stats()"
  echo -e "\n\n##### Show info on test database on node${FUN_NODE} #####\n"
  ${PSMDB32_BINDIR}/bin/mongo ${HOST}:${FUN_PORT}/test --eval "db.stats()"
  echo -e "\n\n##### Show replica set status on node${FUN_NODE} #####\n"
  ${PSMDB32_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --eval "rs.status()"
  echo -e "\n\n##### Show isMaster info on node${FUN_NODE} #####\n"
  ${PSMDB32_BINDIR}/bin/mongo --host=${HOST} --port ${FUN_PORT} --eval "db.isMaster()"
}
### END COMMON FUNCTIONS

if [ ${TEST_TYPE} = "single" ]; then
  start_single 1 3.2 ${NODE1_DATA} ${NODE1_DATA}/node1-3.2-${STORAGE_ENGINE}-first-start.log ${PSMDB32_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE}
  import_test_data 1 3.2 ${PSMDB32_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE} test restaurants ${TEST_DB_FILE} ${NODE1_DATA}/node1-3.2-${STORAGE_ENGINE}-import.log
  run_sysbench 1 sbtest ${NODE1_PORT} FALSE beforeUpgrade ${NODE1_DATA}
  echo -e "\n\n##### Show info of node${FUN_NODE} before upgrade #####\n"
  show_node_info 1 ${NODE1_PORT}
  stop_single 1 3.2 ${NODE1_DATA} ${NODE1_DATA}/node1-3.2-${STORAGE_ENGINE}-upgrade-stop.log ${PSMDB32_BINDIR} ${NODE1_PORT}
  start_single 1 3.4 ${NODE1_DATA} ${NODE1_DATA}/node1-3.4-${STORAGE_ENGINE}-after-upgrade-start.log ${PSMDB34_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE}
  import_test_data 1 3.4 ${PSMDB34_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE} test2 restaurants ${TEST_DB_FILE} ${NODE1_DATA}/node1-3.4-${STORAGE_ENGINE}-import.log
  run_sysbench 1 sbtest2 ${NODE1_PORT} TRUE afterUpgrade ${NODE1_DATA}
  echo -e "\n\n##### Show info of node${FUN_NODE} after upgrade #####\n"
  show_node_info 1 ${NODE1_PORT}
  stop_single 1 3.4 ${NODE1_DATA} ${NODE1_DATA}/node1-3.4-${STORAGE_ENGINE}-final-stop.log ${PSMDB34_BINDIR} ${NODE1_PORT}
elif [ ${TEST_TYPE} = "replicaset" ]; then
  start_replica
  init_replica
  import_test_data 1 3.2 ${PSMDB32_BINDIR} ${NODE1_PORT} ${STORAGE_ENGINE} test restaurants ${TEST_DB_FILE} ${NODE1_DATA}/node1-3.2-${STORAGE_ENGINE}-import.log
  sleep 5
else
  echo "Wrong test type specified!"
  exit 1
fi
