#!/bin/bash

# Partitioning is done based on id (primary key). This script creates
# the current and next partition. It has to be run periodically,
# (e.g. every 20 minutes) before the id reaches $check_next2.

# | current partition | next partition | partition after next |
# | $current          | $next          | $next2               |
# ↑                   ↑                ↑
# $check_prev    $check_next      $check_next2

#create new partition after this many rows:
new_partition_rows=300000;

#arguments to psql
psqlArgs="--tuples-only --no-psqlrc --username=mailnesia --quiet";

#number of partitions to keep
partition_count=30

# function to create current partition
createCurrent()
{
echo create current $current
echo "
CREATE TABLE emails_$current ( CHECK ( id >= $check_prev and id < $check_next  ) ) INHERITS (emails) ;

CREATE INDEX emails_${current}_mailbox_idx on emails_$current(mailbox);
CREATE INDEX emails_${current}_id_idx ON emails_$current USING btree (id);
"|psql $psqlArgs
}

# function to create next partition
createNext()
{
echo create next $next
echo "
CREATE TABLE emails_$next    ( CHECK ( id >= $check_next and id < $check_next2 ) ) INHERITS (emails) ;

CREATE INDEX emails_${next}_mailbox_idx on emails_$next(mailbox);
CREATE INDEX emails_${next}_id_idx ON emails_$next USING btree (id);
"|psql $psqlArgs

}

# function to create or replace insert trigger PSQL function
createTrigger()
{
echo create trigger
echo "
CREATE OR REPLACE FUNCTION emails_insert_trigger()
RETURNS TRIGGER AS \$$
BEGIN

    IF ( NEW.id >= $check_prev AND
         NEW.id <  $check_next ) THEN
    INSERT INTO emails_$current VALUES (NEW.*);

    ELSIF ( NEW.id >= $check_next AND
            NEW.id <  $check_next2 ) THEN
    INSERT INTO emails_$next VALUES (NEW.*);

    ELSE
        RAISE EXCEPTION 'ID out of range.  Fix the emails_insert_trigger() function / psql-partition-update.sh!';
    END IF;

    RETURN NULL;
END;
\$$
LANGUAGE plpgsql;
" |psql $psqlArgs
}


# check if variable is set
checkVar()
{
    if [ -z "$1" -o ! -v "$1" ]
    then
        echo "ERROR: variable $1 is empty!" >&2
        exit 1;
    fi
}

#check mandatory parameters
checkVar new_partition_rows
checkVar partition_count


#get highest id
declare -i id;
id=$(echo "SELECT nextval('emails_id_seq');"  |psql $psqlArgs);

checkVar id

#the currently used partition:
# 0..$new_partition_rows => 1, $new_partition_rows..$new_partition_rows * 2 => 2 ...
let "current = $id / $new_partition_rows + 1";

#the previous partition
let "previous = $current - 1";

#the next partition
let "next = $current + 1";

#the partition after the next
let "next2 = $current + 2";

#the next id where we switch to the next partition
let "check_next = $new_partition_rows * $current";

#the id where we switch to the partition after the next partition
let "check_next2 = $new_partition_rows * $next";

#the previous id where we switched to the current partition
let "check_prev = $new_partition_rows * $previous";

# select oldest partition:
# SELECT
#   MIN ( trim(leading 'emails_' from child.relname)::int )        AS child_schema
# FROM pg_inherits
#         JOIN pg_class child         ON pg_inherits.inhrelid   = child.oid ;

# list all partitions, filter empty lines, remove " emails_", sort numerically:
partitionList=$(psql $psqlArgs -c 'SELECT
child.relname        AS child_schema
FROM pg_inherits
JOIN pg_class child         ON pg_inherits.inhrelid   = child.oid ;
' | grep -v '^$' | cut -b 9- | sort --numeric-sort);

checkVar partitionList

# create current and next and trigger if neither exist
if ! egrep -q "$current|$next" <<<"$partitionList"
then
    createCurrent;
    createNext;
    createTrigger;

# create current and trigger if does not exist
elif ! grep -q "$current" <<<"$partitionList"
then
    createCurrent;
    createTrigger;

# create next and trigger if does not exist
elif ! egrep -q "$next" <<<"$partitionList"
then
    createNext;
    createTrigger;

fi

# delete oldest partition if there are more than $partition_count partitions or the free space is less than 3 GB
if [ $(wc -l <<<"$partitionList") -gt $partition_count -o $(df / | tail -1 | awk '{print $4}') -lt 3000000 ]
then
    oldestPartition=$(head -n 1 <<<"$partitionList");
    checkVar oldestPartition
    echo delete partition $oldestPartition
    psql $psqlArgs -c "DROP TABLE emails_$oldestPartition;"
fi

