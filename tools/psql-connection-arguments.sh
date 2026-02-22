#!/bin/bash

# This script can be sourced to get the connection arguments for psql in the variable `psqlArgs`.
# If a password has to be provided, it should be set in the environment variable
# `PGPASSWORD` before running this script.  The same applies to the username,
# host and database name, which can be set in `postgres_user`, `postgres_host`
# and `postgres_db` respectively.  If these variables are not set, the script
# will use the default values of "mailnesia" for the username and database,
# and "localhost" for the host.

username="${postgres_user:-mailnesia}"
database="${postgres_db:-mailnesia}"
#arguments to psql
psqlArgs="--tuples-only --no-psqlrc --username=$username --quiet --dbname=$database";
if [[ -n "$postgres_host" ]]; then
  psqlArgs="$psqlArgs --host=$postgres_host --port=5432";
fi
