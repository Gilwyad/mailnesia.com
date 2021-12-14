FROM common.mailnesia.com:1.0.0

# Hostname where Postgres is listening. Example: postgres. Default port is appended. If empty, connection will be made to localhost.
ENV postgres_host="127.0.0.1"

EXPOSE 25

CMD [ "perl", "script/AnyEvent-SMTP-Server.pl" ]

# #2525