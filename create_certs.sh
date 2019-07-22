#! /bin/bash
# Copyright 2018 Kuei-chun Chen. All rights reserved.
#
# author: Ken Chen
# create certificates with alternative names
#
usage() {
    echo "Usage: $0 [-c <ca.pem>] [-o <output dir>] [host ...]" 1>&2

cat << EOF

Environment variables
    C           country
    ST          state
    L           local/city
    O           organization/company
    OU_SERVER   organization unit/group - server
    OU_USER     organization unit/group - client
    CN_ADMIN    common name
    CN_USER     common name
    DAYS        number of days until certificate expired
EOF
    exit 1
}

CERTS_DIR="certs"

while getopts ":c:o:" o; do
    case "${o}" in
        c)
            CA=${OPTARG}
            ;;
        o)
            CERTS_DIR=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "$*" ]; then
    IFS=', ' read -r -a hostnames <<< $(hostname -f)
else
    hostnames=$@
fi

if [ -d "$CERTS_DIR" ]; then
    echo -n "* Warning: files under directory $CERTS_DIR exists, override [y/N]? "
    read y
    if [ "$y" != "y" ]; then
        exit
    fi
    if [ -f "$CERTS_DIR/certs.env" ]; then
        echo "* Warning: environment file $CERTS_DIR/certs.env found, source it"
        source $CERTS_DIR/certs.env
    fi
else
    mkdir -p $CERTS_DIR
fi

if [ "$CA" != "" ]; then
    cp $CA $CERTS_DIR/ca.pem || exit
elif [ -f "ca-$(hostname -f).pem" ]; then
    echo -n "* Warning: master ca pem file ca-$(hostname -f).pem exists, override [y/N]? "
    read y
    if [ "$y" == "y" ]; then
        rm -f ca-$(hostname -f).pem
    else
        CA="ca-$(hostname -f).pem"
        cp $CA $CERTS_DIR/ca.pem || exit
    fi
fi

OPWD=$(pwd)
cd $CERTS_DIR
echo "Files are created in $CERTS_DIR"

DAYS="${DAYS:-30}"
C="${C:-US}"
ST="${ST:-Georgia}"
L="${L:-Atlanta}"
O="${O:-Example}"
OU_SERVER="${OU_SERVER:-Servers}"
OU_USER="${OU_USER:-Users}"
CN_ADMIN="${CN_ADMIN:-admin@example.com}"
CN_USER="${CN_USER:-admin@example.com}"

read -r -d '' DN <<-EOF
C=$C
ST=$ST
L=$L
O=$O
EOF

read -r -d '' CADATA <<-EOF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
default_md = x509
x509_extensions = v3_req
[dn]
$DN
OU=Root
CN=$(hostname -f)
[v3_req]
subjectAltName = @alt_names
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:TRUE

[alt_names]
DNS.1=localhost
IP.1=127.0.0.1
EOF

read -r -d '' PEMDATA <<-EOF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
default_md = x509
req_extensions = v3_req
[v3_req]
[dn]
$DN
OU=$OU_SERVER
EOF

read -r -d '' CLIENT_PEMDATA <<-EOF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
default_md = x509
req_extensions = v3_req
[dn]
C=$C
ST=$ST
L=$L
O=$O
OU=$OU_USER
CN=$CN_USER
[v3_req]
EOF

# CA certificates
# echo "Creating server certificate and key file: ca.crt and ca.key"
if [ "$CA" == "" ]; then
	openssl req -nodes -x509 -days ${DAYS} -newkey rsa:2048 -keyout ca.key -out ca.crt -config <(
	cat <<-EOF
	$CADATA
	EOF
	)
	cat ca.crt ca.key > ca.pem
    rm -f ca.key
else
    echo "extracting ca.crt"
    openssl crl2pkcs7 -nocrl -certfile ca.pem | openssl pkcs7 -print_certs -out ca.crt || exit
fi

# Server certificates
for hostname in $hostnames
do
	openssl req -nodes -newkey rsa:2048 -keyout server.key -out server.csr -config <(
	cat <<-EOF
	$PEMDATA
    CN=$hostname
	EOF
	)

	openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.pem -CAcreateserial -days ${DAYS} -out server.crt -extfile <(
	cat <<-EOF
	basicConstraints = CA:FALSE
	keyUsage = nonRepudiation, digitalSignature, keyEncipherment
	subjectAltName = @alt_names
	[alt_names]
	DNS.1=localhost
	DNS.2=127.0.0.1
	DNS.3=$hostname
	EOF
	)

    if [ "${hostname:0:2}" == "*." ]; then
        cat server.key server.crt > ${hostname:2}.pem
    else
  	    cat server.key server.crt > ${hostname}.pem
    fi
    rm -f server.csr server.crt server.key

    if [ "$hostname" == "$(hostname -f)" ]; then
  	    cp ${hostname}.pem server.pem
    fi
done

# Client certificates
if [ ! -f client.pem ]; then
	# echo "Creating client certificate and key file: client.crt and client.key"
	openssl req -nodes -newkey rsa:2048 -keyout client.key -out client.csr -config <(
	cat <<-EOF
	$CLIENT_PEMDATA
	EOF
	)
	openssl x509 -req -in client.csr -CA ca.pem -CAkey ca.pem -CAserial ca.srl -days ${DAYS} -out client.crt -extfile <(
	cat <<-EOF
	basicConstraints = CA:FALSE
	keyUsage = nonRepudiation, digitalSignature, keyEncipherment
	extendedKeyUsage = TLS Web Server Authentication, TLS Web Client Authentication
	EOF
	)
	cat client.key client.crt > client.pem
	rm -f client.csr client.crt client.key
fi
rm -f ca.srl
echo; echo; echo
echo "certificates created"

if [ "$CA" != "" ]; then
    rm -f ca.pem
else
    nm=$(basename $CERTS_DIR)
    echo "Master master-$nm.pem created.  Keep it for future use."
    mv -f ca.pem $OPWD/master-$nm.pem
fi

echo "rename $CERTS_DIR/ca.crt to $CERTS_DIR/ca.pem"
mv ca.crt ca.pem
cat > certs.env <<EOF
export C=$C
export ST=$ST
export L=$L
export O=$O
export OU_SERVER=$OU_SERVER
export OU_USER=$OU_USER
export CN_ADMIN=$CN_ADMIN
export CN_USER=$CN_USER
export DAYS=$DAYS
EOF

cd $OPWD
tree=$(which tree)

if [ "tree" != "" ]; then
    tree $CERTS_DIR
else
    ls -l $CERTS_DIR
fi
