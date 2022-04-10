FROM common.mailnesia.com:1.0.4

# Hostname where Postgres is listening. Example: postgres. Default port is appended. If empty, do not connect to Postgres.
ENV postgres_host=""
# Postgres database name
ENV postgres_database="mailnesia"
# Postgres username to use
ENV postgres_user="mailnesia-user"
# Postgres password to use
ENV postgres_password=""

# Hostname where Redis is listening. Example: redis. Default port is appended. If empty, do not connect to Redis.
ENV redis_host=""

EXPOSE 4000

COPY . .

CMD [ "hypnotoad", "--foreground", "./script/api.pl" ]
