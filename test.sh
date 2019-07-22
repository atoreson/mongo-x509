#! /bin/bash
# Copyright 2018 Kuei-chun Chen. All rights reserved.
source ./certs.env

CERTS_DIR="certs-$(openssl rand -hex 3)"
MASTER_CA_PEM="master-$CERTS_DIR.pem"

if [ -f "$MASTER_CA_PEM" ]; then
    ./create_certs.sh -c "$MASTER_CA_PEM" -o $CERTS_DIR
else
    ./create_certs.sh -o $CERTS_DIR
fi

DB_PATH=$CERTS_DIR/db
mkdir -p $DB_PATH
rm -rf $DB_PATH/*
mongod --port 30097 --dbpath $DB_PATH --logpath $DB_PATH/mongod.log --fork
# create user
login="CN=ken.chen@simagix.com,OU=Users,O=Simagix,L=Atlanta,ST=Georgia,C=US"
echo "create user $login"
mongo "mongodb://localhost:30097/admin" \
    --eval "db.getSisterDB('\$external').createUser({ user: '$login', roles: [ {role: 'root', db: 'admin'} ]})"
mongo "mongodb://localhost:30097/admin" --eval 'db.shutdownServer()' > /dev/null

# start mongo with auth enabled
mongod --port 30097 --dbpath $DB_PATH --logpath $DB_PATH/mongod.log --fork \
    --clusterAuthMode x509 --sslMode requireSSL \
    --sslPEMKeyFile $CERTS_DIR/server.pem --sslCAFile $CERTS_DIR/ca.pem

# connect
mongo "mongodb://localhost:30097/?authSource=\$external&authMechanism=MONGODB-X509" \
    -u $login \
    --ssl --sslPEMKeyFile $CERTS_DIR/client.pem --sslCAFile $CERTS_DIR/ca.pem \
    --eval 'db.runCommand({connectionStatus : 1})'

mongo "mongodb://localhost:30097/?authSource=\$external&authMechanism=MONGODB-X509" \
    -u $login \
    --ssl --sslPEMKeyFile $CERTS_DIR/client.pem --sslCAFile $CERTS_DIR/ca.pem \
    --eval 'db.shutdownServer()' > /dev/null

sleep 2
rm -rf $CERTS_DIR $MASTER_CA_PEM
