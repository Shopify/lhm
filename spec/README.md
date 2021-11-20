# Running master slave integration tests

## Setup

To setup local docker containers for mysql and proxysql used in integration tests via docker-compose run

    docker-compose up -d
    ./scripts/helpers/wait-for-dbs.sh # wait for mysql and proxysql instances to be ready

Setup the dependency gems

    export BUNDLE_GEMFILE=gemfiles/ar-5.0_mysql2.gemfile
    bundle install

## Run specs

To run the specs in master mode

    bundle exec rake integration

To run specs in slave mode, set the MASTER_SLAVE=1 when running tests:

    MASTER_SLAVE=1 bundle exec rake integration

# Connecting

you can connect by running (with the respective ports):

    mysql --protocol=tcp -uroot -ppassword -P 33007

