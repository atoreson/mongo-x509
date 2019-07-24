#! /bin/bash
# Copyright 2019 Kuei-chun Chen. All rights reserved.
source ./certs.env

WS_DIR="ws-$(openssl rand -hex 3)"
echo "* generate x509 certificates..."
./create_certs.sh -o $WS_DIR/certs > /dev/null 2>&1

for port in 30097 30098 30099
do
  mkdir -p $WS_DIR/${port}/db
  cat > $WS_DIR/${port}/mongod.conf <<EOF
  systemLog:
    destination: file
    path: $WS_DIR/${port}/mongod.log
  storage:
    dbPath: $WS_DIR/${port}/db
  processManagement:
    fork: true
  net:
    port: ${port}
    ssl:
      mode: requireSSL
      PEMKeyFile: $WS_DIR/certs/server.pem
      clusterFile: $WS_DIR/certs/server.pem
      CAFile: $WS_DIR/certs/ca.pem
  replication:
    replSetName: "x509"
  security:
    authorization: enabled
    clusterAuthMode: x509
EOF
  echo "* spin up mongod at port ${port}"
  mongod -f "$WS_DIR/${port}/mongod.conf" > /dev/null 2>&1
  sleep 1
done

echo "* initiate replica..."
mongo mongodb://localhost:30097/admin \
  --ssl --sslCAFile $WS_DIR/certs/ca.pem --sslPEMKeyFile $WS_DIR/certs/client.pem \
  --eval "rs.initiate({_id:'x509',members:[{_id:0,host:'localhost:30097'},{_id:1,host:'localhost:30098'},{_id:2,host:'localhost:30099'}]})" \
  > /dev/null 2>&1

ret=0
while [[ $ret -eq 0 ]]; do
  ret=$(mongo "mongodb://localhost:30097/admin?replicaSet=x509" \
        --ssl --sslCAFile $WS_DIR/certs/ca.pem --sslPEMKeyFile $WS_DIR/certs/client.pem \
        --eval 'rs.isMaster()' | grep '"ok" : 1' | wc -l)
  echo "* wait for primary to be ready..."
  sleep 2
done

login="CN=ken.chen@simagix.com,OU=Users,O=Simagix,L=Atlanta,ST=Georgia,C=US"
echo "* create admin user..."
mongo "mongodb://localhost:30097/admin?replicaSet=x509" \
        --ssl --sslCAFile $WS_DIR/certs/ca.pem --sslPEMKeyFile $WS_DIR/certs/client.pem \
        --eval "db.getSisterDB('\$external').createUser({ user: '$login', roles: [ {role: 'root', db: 'admin'} ]})" > /dev/null 2>&1

# connect
echo "* connect and validate connection status..."
mongo --quiet "mongodb://localhost:30097,localhost:30098,localhost:30099/?replicaSet=x509&authSource=\$external&authMechanism=MONGODB-X509" \
    -u $login \
    --ssl --sslPEMKeyFile $WS_DIR/certs/client.pem --sslCAFile $WS_DIR/certs/ca.pem \
    --eval 'rs.status()'
mongo --quiet "mongodb://localhost:30097,localhost:30098,localhost:30099/?replicaSet=x509&authSource=\$external&authMechanism=MONGODB-X509" \
    -u $login \
    --ssl --sslPEMKeyFile $WS_DIR/certs/client.pem --sslCAFile $WS_DIR/certs/ca.pem \
    --eval 'db.runCommand({connectionStatus : 1})'

echo "* cleanup..."
for port in 30097 30098 30099
do
  mongo "mongodb://localhost:${port}/?authSource=\$external&authMechanism=MONGODB-X509" \
      --ssl --sslCAFile $WS_DIR/certs/ca.pem --sslPEMKeyFile $WS_DIR/certs/client.pem \
      -u $login \
      --eval 'db.getSiblingDB("admin").shutdownServer()' > /dev/null
done

rm -rf $WS_DIR master-certs.pem
