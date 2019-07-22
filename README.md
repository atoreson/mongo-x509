# MongoDB Authentication with X509 Certificate
A script, `create_certs.sh` to create x509 certificates.  If a master CA key file (*ca.pem*) is not available, the script will create one.

## Usage
By default, certificates will be created under directory *certs*.

```
create_certs.sh [-c <master_ca] [-o <output_directory] [hostname ...]
```

You should edit the `certs.env` file for your needs and `source` it before executing the `create_certs.sh` script.  Available environment variables are:

```
C           country
ST          state
L           local/city
O           organization/company
OU_SERVER   organization unit/group - server
OU_USER     organization unit/group - client
CN_ADMIN    common name
CN_USER     common name
DAYS        number of days until certificate expired
```

## Demo
Execute the `test.sh` script, which

- Create certificates
- Spin up a *mongo* instance
- Create a user defined in *certs.env*
- Restart the *mongo* instance with authentication enabled
- Login to the *mongo* instance and display connection status

## Use Cases
Here are a few use cases to use this script.
### Case 1: Demo
For a quick demo on your workstation, simply execute it as:

```
source certs.env

./create_certs.sh

certs
├── $(hostname -f).pem
├── ca.pem
├── client.pem
└── server.pem
```

### Case 2: Create for Multiple Hosts
Create certificates for multiple hosts the first time without a master CA pem file:

```
source certs.env

./create_certs.sh -o example.com \
  host1.example.com host2.example.com host3.example.com

example.com/
├── ca.pem
├── client.pem
├── host1.example.com.pem
├── host2.example.com.pem
└── host3.example.com.pem
```

### Case 3: Create Certificates Using a Master CA File
Create certificates to add to the same cluster using the same CA file.

```
source certs.env

./create_certs.sh -o example.com -c master-example.com.pem \
  host4.example.com

example.com/
├── ca.pem
├── client.pem
├── host1.example.com.pem
├── host2.example.com.pem
├── host3.example.com.pem
└── host4.example.com.pem
```
