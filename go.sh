#!/bin/bash
MD=data/master
MP=5433
RD=data/replica
RP=5434
RSN=replica1

REPLICATION_USER=replicator
REPLICATION_PASSWORD=letmereplicate

start_master() {
  export PGDATA=${MD}
  rm -rf ${PGDATA}
  mkdir -p ${PGDATA}
  initdb
  cat >> "${MD}/postgresql.conf" <<EOF
port=${MP}
wal_level = hot_standby
max_replication_slots = 10
max_wal_senders = 3
checkpoint_segments = 8
wal_keep_segments = 8
EOF
  echo "host replication     replicator      0.0.0.0/0            md5" >> "${MD}/pg_hba.conf"
  sleep 1
  # Start master
  postgres&
  MPID=$!
  echo "${MPID}" > master.pid
  sleep 5
  psql -p ${MP} -c "CREATE USER ${REPLICATION_USER} REPLICATION LOGIN ENCRYPTED PASSWORD '${REPLICATION_PASSWORD}';" template1

}

start_replica() {
  # Create replication slot
  psql -p ${MP} template1 -c "SELECT * FROM pg_create_physical_replication_slot('${RSN}');"

  export PGDATA=${RD}
  rm -rf ${PGDATA}
  mkdir -p ${PGDATA}
  chmod 700 ${PGDATA}
  #initdb
  PGPASSWORD=${REPLICATION_PASSWORD} pg_basebackup -h localhost -p ${MP} -D ${PGDATA} -U ${REPLICATION_USER} -X stream -v

  cat > "${RD}/postgresql.conf" <<EOF
port=${RP}
wal_level = hot_standby
max_replication_slots = 10
max_wal_senders = 3
checkpoint_segments = 8
wal_keep_segments = 8
hot_standby = on
EOF

cat >> "${RD}/recovery.conf" <<EOF
standby_mode = 'on'
primary_conninfo = 'host=127.0.0.1 port=${MP} user=${REPLICATION_USER} password=${REPLICATION_PASSWORD}'
trigger_file = '/tmp/postgresql.trigger'
primary_slot_name = '${RSN}'
EOF
  # Start replica
  postgres&
  RPID=$!
  echo "${RPID}" > replica.pid
}

start_master
start_replica

# Write sample data to master
psql -p ${MP} template1 -c "CREATE DATABASE fawad;"
psql -p ${MP} fawad -c "CREATE TABLE foo (id INT, name VARCHAR(255))"
psql -p ${MP} fawad -c "INSERT INTO foo (id, name) VALUES (1, 'jimbob')"
# Read back sample data from replica
psql -p ${RP} fawad -c "\d"
psql -p ${RP} fawad -c "SELECT * FROM foo"

kill `cat *.pid`
