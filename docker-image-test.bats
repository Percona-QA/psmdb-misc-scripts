#!/usr/bin/env bats

PSMDB_MAJ_VER="3.2"
PSMDB_PATCH_VER="11"
PSMDB_PERCONA_VER="3.1"
ARCH="x86_64"
DISTRO="xenial"
PSMDB_LINK="https://www.percona.com/downloads/percona-server-mongodb-${PSMDB_MAJ_VER}/LATEST/binary/tarball/percona-server-mongodb-${PSMDB_MAJ_VER}.${PSMDB_PATCH_VER}-${PSMDB_PERCONA_VER}-${DISTRO}-${ARCH}.tar.gz"
PSMDB_TARBALL=$(echo ${PSMDB_LINK}|sed 's:^http.*\/::')
PSMDB_DIR="percona-server-mongodb-${PSMDB_MAJ_VER}.${PSMDB_PATCH_VER}-${PSMDB_PERCONA_VER}"
DOCKER_NAME="psmdb-${PSMDB_MAJ_VER}-image-test"

if [ ${PSMDB_MAJ_VER} = "3.4" ]; then
  DOCKERFILE_DIR="percona-server-mongodb.34"
elif [ ${PSMDB_MAJ_VER} = "3.2" ]; then
  DOCKERFILE_DIR="percona-server-mongodb.32"
elif [ ${PSMDB_MAJ_VER} = "3.0" ]; then
  DOCKERFILE_DIR="percona-server-mongodb"
else
  echo "Unrecognized PSMDB version!"
  exit 1
fi

@test "setup of docker build environment" {
  run git clone https://github.com/percona/percona-docker.git --depth 1
  run wget ${PSMDB_LINK}
  run tar xf ${PSMDB_TARBALL}
  [ $status -eq 0 ]
}

@test "build image" {
  run docker build -t ${DOCKER_NAME} percona-docker/${DOCKERFILE_DIR}
  [ $status -eq 0 ]
}

@test "run container" {
  run docker run -P -d --hostname="psmdb" --name="${DOCKER_NAME}" ${DOCKER_NAME}
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

@test "cleanup" {
  run [ -f ${PSMDB_TARBALL} ] && rm -f ${PSMDB_TARBALL}
  [ $status -eq 0 ]

  run [ -d ${PSMDB_DIR} ] && rm -rf ${PSMDB_DIR}
  [ $status -eq 0 ]
}
