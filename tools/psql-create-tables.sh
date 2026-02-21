#!/bin/bash

# This script can be run initially to create all tables and necessary relations.

# Resolve the full path of the script
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

#arguments to psql
source $SCRIPT_DIR/psql-connection-arguments.sh

# Partitioning is used, the key being the id because that's the only
# value that needs to be unique in the whole table across the partitions.
# "emails" is the "master" table from which all of the partitions inherit.
# This contains no data so no indexes are required.  The creation of
# partitions and modification of the insert trigger is handled by the
# utility `psql-partition-update.sh`.

# The purpose of partitioning is to make it easy to discard old data.
# Instead of `DELETE FROM emails WHERE ( EXTRACT(EPOCH FROM
# current_timestamp - arrival_date) / 3600)::INT > ?;`, it's as simple
# as `DROP TABLE emails_5;`.  The latter causes almost no disk activity
# compared to the former, which can run for minutes, and cause
# performance issues.

# function to create the emails table
createEmailsTable()
{
  echo "create emails table"
  echo "
  CREATE TABLE IF NOT EXISTS emails (
    id SERIAL PRIMARY KEY,
    arrival_date timestamp without time zone NOT NULL default CURRENT_TIMESTAMP,
    email_date varchar(31) default NULL,
    email_from varchar(100) default NULL,
    email_to varchar(100) default NULL,
    email_subject varchar(200) default NULL,
    mailbox varchar(30) NOT NULL,
    email bytea
  );

  "|psql $psqlArgs
}

# function to create the mailbox alias table
# This table holds the alias names for mailboxes.
createMailboxAliasTable()
{
  echo "create mailbox alias table"
  echo "
  CREATE TABLE IF NOT EXISTS mailbox_alias (
    mailbox varchar(30) NOT NULL,
    alias varchar(30) NOT NULL UNIQUE
  );

  ALTER TABLE mailbox_alias ADD CONSTRAINT lowercase_only CHECK (LOWER(alias) = alias);

  "|psql $psqlArgs
}

# function to create the email per day statistics table
# This table is for statistics only, contains the number of emails
# received each day and the combined size of them.

createEmailPerDayTable()
{
  echo "create email per day statistics table"
  echo "
  CREATE TABLE IF NOT EXISTS emailperday (
    day date default current_date UNIQUE,
    email integer DEFAULT 0,
    bandwidth integer DEFAULT 0
  );

  "|psql $psqlArgs
}

# function to start partitioning the emails table
# insert_emails_trigger is the insert trigger that calls the trigger function defined in
# psql-partition-update.sh to redirect all writes to the latest partition.
startPartitioning()
{
  echo "running psql-partition-update.sh"
  /bin/bash $SCRIPT_DIR/psql-partition-update.sh

  echo "starting partitioning the emails table"
  echo "
  CREATE TRIGGER insert_emails_trigger
  BEFORE INSERT ON emails
  FOR EACH ROW EXECUTE PROCEDURE emails_insert_trigger();

  "|psql $psqlArgs
}


createEmailsTable
createMailboxAliasTable
createEmailPerDayTable
startPartitioning
