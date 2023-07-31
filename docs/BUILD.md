# Building OpenBMP PostgreSQL Consumer

Dependencies
------------
- Java 11 or greater
- Maven 3.x or greater
- Python psycopg2-binary
- DNS Python

Example install dependencies for consumer:

    sudo apt-get install maven openjdk-17-jdk-headless

Example install dependencies for scripts:

    sudo apt-get install python3-{click,clickhouse-driver,dns,ipaddr,netaddr,pip} whois
    pip install pubdns requests

Build
-----
You can build from source using maven as below:


### (2) Build obmp-psql

    sudo mkdir -p /var/log/obmp-psql && chown www-data. /var/log/obmp-psql
    sudo mkdir -p /var/lib/obmp-psql && chown www-data. /var/log/obmp-psql

    wget -O obmp-psql.tar.gz https://github.com/Catwoolfii/obmp-psql/archive/refs/heads/main.tar.gz
    sudo tar zxvf obmp-psql.tar.gz
    cd obmp-psql-main
    sudo mvn clean package

    cp target/obmp-psql-consumer-0.1.0-SNAPSHOT.jar /var/lib/obmp-psql/
    cp src/main/resources/obmp-psql.yml /var/lib/obmp-psql/
    cp src/main/resources/log4j.yml /var/lib/obmp-psql/
    cp src/main/resources/obmp-psql /etc/default/
    cp src/main/resources/obmp-psql.service /etc/systemd/system/

    sudo systemctl enable obmp-psql.service
