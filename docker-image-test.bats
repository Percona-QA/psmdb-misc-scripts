#!/usr/bin/env bats

TAG="3.4.7"
REPO="perconalab/percona-server-mongodb"
DOCKER_NAME="psmdb-${TAG}-image-test"

@test "run container" {
  run docker run -P -d --hostname="psmdb" --name="${DOCKER_NAME}" ${REPO}:${TAG}
  [ $status -eq 0 ]
}

@test "insert data into PSMDB" {
  sleep 15
  export PORT=$(docker inspect ${DOCKER_NAME}|grep HostPort|head -n 1|sed -rn 's/.*"([0-9]+)"$/\1/p')
  run ${PSMDB_DIR}/bin/mongo --eval 'db.users.insert({ id: 1, name: "John Doe" })' localhost:${PORT}/test
  [ $status -eq 0 ]
}

@test "stop container" {
  run docker stop ${DOCKER_NAME}
  [ $status -eq 0 ]
}

@test "start container again" {
  run docker start ${DOCKER_NAME}
  [ $status -eq 0 ]
}

@test "insert more data into PSMDB" {
  sleep 15
  export PORT=$(docker inspect ${DOCKER_NAME}|grep HostPort|head -n 1|sed -rn 's/.*"([0-9]+)"$/\1/p')
  run ${PSMDB_DIR}/bin/mongo --eval 'db.users.insert({ id: 2, name: "Jane Doe" })' localhost:${PORT}/test
  [ $status -eq 0 ]
}

@test "mongod version check" {
  MONGOD_VER=$(docker exec -it ${DOCKER_NAME} /usr/bin/mongod --version|head -n1)
  run bash -c "echo ${MONGOD_VER}|grep '${PSMDB_MAJ_VER}.${PSMDB_PATCH_VER}-${PSMDB_PERCONA_VER}'"
  [ $status -eq 0 ]
}

@test "mongos version check" {
  MONGOS_VER=$(docker exec -it ${DOCKER_NAME} /usr/bin/mongos --version|head -n1|sed -r 's/:.*$//')
  run bash -c "echo ${MONGOS_VER}|grep '${PSMDB_MAJ_VER}.${PSMDB_PATCH_VER}-${PSMDB_PERCONA_VER}'"
  [ $status -eq 0 ]
}

@test "check that all data is stored" {
  export PORT=$(docker inspect ${DOCKER_NAME}|grep HostPort|head -n 1|sed -rn 's/.*"([0-9]+)"$/\1/p')
  run bash -c "${PSMDB_DIR}/bin/mongo --eval 'db.users.find().forEach(printjson)' localhost:${PORT}/test|grep 'John Doe'"
  [ $status -eq 0 ]

  run bash -c "${PSMDB_DIR}/bin/mongo --eval 'db.users.find().forEach(printjson)' localhost:${PORT}/test|grep 'Jane Doe'"
  [ $status -eq 0 ]
}

@test "stop container" {
  run docker stop ${DOCKER_NAME}
  [ $status -eq 0 ]
}

@test "remove docker container" {
  run docker rm ${DOCKER_NAME}
  [ $status -eq 0 ]
}

@test "remove docker image" {
  run docker rmi ${DOCKER_NAME}
  [ $status -eq 0 ]
}

