FROM common.mailnesia.com:1.0.4

# Hostname where Postgres is listening. Example: postgres. Default port is appended. If empty, connection will be made to localhost.
ENV postgres_host="127.0.0.1"

# Hostname where Redis is listening. Example: redis. Default port is appended. If empty, do not connect to Redis.
ENV redis_host="127.0.0.1"

# Hostname where the ZeroMQ host is listening, normally the clicker app. Example: clicker. Default port is appended. If empty,
# do not connect to it.
ENV zeromq_host=""

# Enable logging into files under /var/log. If disabled (the default), all logs are printed to standard output.
ENV logging_enabled=""

EXPOSE 25

COPY . .

CMD [ "perl", "script/AnyEvent-SMTP-Server.pl" ]
