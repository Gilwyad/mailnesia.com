FROM debian:buster-slim
#FROM perl:5-buster

RUN apt-get update && apt-get install -y apt-utils locales && rm -rf /var/lib/apt/lists/* \
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf8

RUN apt-get update && apt-get install -y libzmq5 openssl libssl-dev zlib1g-dev autotools-dev g++ gcc dpkg-dev libdpkg-perl libltdl-dev libltdl7 libsqlite3-0 m4 make patch g++-8 libstdc++-8-dev gcc-8 binutils cpp-8 libc6-dev libc-dev-bin libgomp1 linux-libc-dev libreadline7 cpanminus libpq-dev

COPY . /usr/src/mailnesia.com
WORKDIR /usr/src/mailnesia.com

# CMD bash

# install dependencies
RUN [ "cpanm", "--installdeps", "." ]

EXPOSE 25

CMD [ "perl", "script/AnyEvent-SMTP-Server.pl" ]

# #2525