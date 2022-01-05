FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y apt-utils locales && rm -rf /var/lib/apt/lists/* \
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

ENV LANG=en_US.utf8

# Hostname where Redis is listening. Example: redis. Default port is appended. If empty, do not connect to Redis.
ENV redis_host=""

# Hostname where Postgres is listening. Example: postgres. Default port is appended. If empty, do not connect to Postgres.
ENV postgres_host=""
# Postgres database name
ENV postgres_database="mailnesia"
# Postgres username to use
ENV postgres_user="mailnesia-user"
# Postgres password to use
ENV postgres_password=""

# Hostname where the ZeroMQ host is listening, normally the clicker app. Example: clicker. Default port is appended. If empty,
# do not connect to it.
ENV zeromq_host=""

# ReCaptcha private key
ENV recaptcha_private_key=""

# Some modules might require compilation of C source code; these packages will take care of that:
RUN apt-get update && apt-get install -y libzmq5 openssl libssl-dev zlib1g-dev autotools-dev g++ gcc dpkg-dev libdpkg-perl libltdl-dev libltdl7 libsqlite3-0 m4 make patch g++-8 gcc-10 binutils cpp-10 libc6-dev libc-dev-bin libgomp1 linux-libc-dev libreadline8 cpanminus libpq-dev
#libstdc++-8-dev ?

# Install some Perl package requirements
RUN apt-get install -y libcommon-sense-perl libcgi-fast-perl libcgi-pm-perl libemail-mime-perl libio-aio-perl libdbi-perl libdbd-pg-perl libhtml-scrubber-perl libredis-perl libcaptcha-recaptcha-perl libtext-multimarkdown-perl libfilesys-diskspace-perl libhtml-template-perl liblib-abs-perl libprivileges-drop-perl libanyevent-http-perl libev-perl libzmq-ffi-perl libwww-mechanize-perl libtest-www-mechanize-perl

WORKDIR /usr/src/mailnesia.com

COPY cpanfile .

ENV PERL5LIB=/usr/src/mailnesia.com/lib

# CMD bash

# install dependencies, which were not satisfied by apt-get install:
RUN [ "cpanm", "--skip-satisfied", "--installdeps", "." ]

COPY . .
