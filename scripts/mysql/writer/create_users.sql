# Creates replication user in Writer
CREATE USER IF NOT EXISTS 'writer'@'%' IDENTIFIED BY 'password';
CREATE USER IF NOT EXISTS 'reader'@'%' IDENTIFIED BY 'password';

CREATE USER IF NOT EXISTS 'replication'@'%' IDENTIFIED BY 'password';
GRANT REPLICATION SLAVE ON *.* TO' replication'@'%';
