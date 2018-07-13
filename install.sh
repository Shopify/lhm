set -e

echo "Checking if dbdeployer is installed"
if ! [ -x "$(command -v dbdeployer)" ]; then
  echo "Not installed...starting install"
  VERSION=1.8.0
  OS=osx
  origin=https://github.com/datacharmer/dbdeployer/releases/download/$VERSION
  filename=dbdeployer-$VERSION.$OS
  wget -q $origin/$filename.tar.gz
  tar -xzf $filename.tar.gz
  chmod +x $filename
  sudo mv $filename /usr/local/bin/dbdeployer
  rm $filename.tar.gz
else
  echo "Installation found!"
fi


echo "Checking if mysql 5.7.22 is available for dbdeployer"
if [ -z "$(dbdeployer available | grep 5.7.22)" ]; then
  echo "Not found..."
  mkdir -p $HOME/opt/mysql

  MYSQL_FILE=mysql-5.7.22-macos10.13-x86_64.tar.gz
  rm -f $MYSQL_FILE*
  echo "Downloading $MYSQL_FILE...(this may take a while)"
  wget -q "https://dev.mysql.com/get/Downloads/MySQL-5.7/$MYSQL_FILE"

  echo "Setting up..."
  dbdeployer unpack $MYSQL_FILE --verbosity 0
  rm $MYSQL_FILE
else
  echo "mysql 5.7.22 found!"
fi

echo "Forcing new replication setup..."
dbdeployer deploy replication 5.7.22 --nodes 2 --force
dbdeployer global status

echo "Setting up database.yml"
DATABASE_YML=spec/integration/database.yml
echo "master:" > $DATABASE_YML
cat ~/sandboxes/rsandbox_5_7_22/master/my.sandbox.cnf | grep -A 4 client | tail -n 4 | awk $'{print "  " $1 ": " $3}' >> $DATABASE_YML

echo "slave:" >> $DATABASE_YML
cat ~/sandboxes/rsandbox_5_7_22/node1/my.sandbox.cnf | grep -A 4 client | tail -n 4 | awk $'{print "  " $1 ": " $3}' >> $DATABASE_YML

cat $DATABASE_YML

echo "You are ready to run the integration test suite..."
