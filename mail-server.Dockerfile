FROM common.mailnesia.com:1.0.2

# Hostname where Postgres is listening. Example: postgres. Default port is appended. If empty, connection will be made to localhost.
ENV postgres_host="127.0.0.1"

# Hostname where Redis is listening. Example: redis. Default port is appended. If empty, do not connect to Redis.
ENV redis_host="127.0.0.1"

EXPOSE 25

COPY . .

CMD [ "perl", "script/AnyEvent-SMTP-Server.pl" ]
