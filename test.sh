#!/bin/bash

set -e

echo "-- Building Sphinx + MySQL Client image"
docker build -t sphinx-test ./sphinx_mysqlclient/

echo
echo "-- Run postgresql container"
docker run --name db-test -d -e 'DB_NAME=db_test' -e 'DB_USER=test' -e 'DB_PASS=pass' romeoz/docker-postgresql; sleep 20
echo
echo "-- Create table"
docker exec -it db-test sudo -u postgres psql db_test -c "CREATE TABLE items (id SERIAL, content TEXT);"

echo
echo "-- Sets a permission on database"
docker exec -it db-test sudo -u postgres psql db_test -c "GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO test;GRANT SELECT ON ALL TABLES IN SCHEMA public TO test;"

echo
echo "-- Insert records"
docker exec -it db-test sudo -u postgres psql db_test -c "INSERT INTO items (content) VALUES ('about dog'),('about cat');"; sleep 5
echo
echo "-- Run sphinx container"
docker run --name sphinx-test -d --link db-test:db-test sphinx-test; sleep 10
echo
echo "-- Indexing records"
docker exec -it sphinx-test indexer --config /etc/sphinxsearch/sphinx.conf --all --rotate; sleep 10
echo
echo "-- Testing"
docker exec -it sphinx-test mysql -P9306 -h127.0.0.1 -e "SELECT id FROM items_index WHERE MATCH('cat');" | grep -wc "2"

echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
docker rmi -f sphinx-test; sleep 5
rm -rf $(pwd)/vo*



echo
echo
echo "-- Building Sphinx image"
docker build -t sphinx-test ./sphinx/

echo
echo "-- Run mysql container"
docker run --name db-test -d -e 'MYSQL_USER=test' -e 'MYSQL_PASS=pass' -e 'MYSQL_CACHE_ENABLED=true' -e 'DB_NAME=db_test' romeoz/docker-mysql; sleep 20

echo
echo "-- Create table"
docker exec -it db-test mysql -uroot -e 'CREATE TABLE db_test.items (id INT NOT NULL AUTO_INCREMENT, content TEXT, PRIMARY KEY(id)) ENGINE = INNODB;'; sleep 5

echo
echo "-- Insert records"
docker exec -it db-test mysql -uroot -e 'INSERT INTO db_test.items (content) VALUES ("about dog"),("about cat");'; sleep 5

echo
echo "-- Run sphinx container"
docker run --name sphinx-test -d --link db-test:db-test sphinx-test; sleep 10
echo
echo "-- Indexing records"
docker exec -it sphinx-test indexer --config /etc/sphinxsearch/sphinx.conf --all --rotate; sleep 10

echo
echo "-- Testing"
docker exec -it db-test mysql -P9306 -h$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' sphinx-test) -e "SELECT * FROM items_index WHERE MATCH('cat');" | grep -wc "2"


echo
echo "-- Testing backup"
#docker exec -it db-test mysql -P9306 -h$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' sphinx-test) -e "FLUSH RTINDEX myrtindex"
docker run -it --rm --volumes-from sphinx-test -e 'SPHINX_MODE=backup' -v $(pwd)/vol/backup:/tmp/backup sphinx-test; sleep 10

echo
echo "-- Clear"
docker rm -f -v sphinx-test; sleep 5
echo
echo "-- Restore from backup"
docker run --name sphinx-restore -d --link db-test:db-test -e 'SPHINX_RESTORE=default' -v $(pwd)/vol/backup:/tmp/backup  sphinx-test; sleep 15

echo
echo "-- Checking backup"
docker exec -it db-test mysql -P9306 -h$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' sphinx-restore) -e "SELECT * FROM items_index WHERE MATCH('cat');" | grep -wc "2"
docker run -it --rm -e 'SPHINX_CHECK=default' -e 'INDEX_NAME=items_index' -v $(pwd)/vol/backup:/tmp/backup  sphinx-test | grep -wc 'Success'; sleep 5

echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
docker rmi -f sphinx-test; sleep 5
rm -rf $(pwd)/vo*

echo
echo "-- Done"