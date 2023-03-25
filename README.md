# mailnesia.com - Anonymous Email in Seconds

[Mailnesia](https://mailnesia.com) is a fully featured disposable email provider.  Just like a
real email service but without any password or the ability to send
mail.  Features at a glance:

 - Automatically visits registration/activation links in
   emails, completing any registration process instantly
 - Alternate mailbox names (aliases) for extra anonymity, use any name you want
 - Alternative domain names (all mail is accepted regardless of domain name)
 - Displaying HTML emails correctly including attached images, files
 - Multiple encodings supported: Chinese, Japanese, Korean, Russian etc
 - RSS feed for every mailbox
 - New emails appear as they arrive, without needing to refresh the page
 - Fast, easy to use interface
 - Translated to 10+ languages

This repository contains the source code of Mailnesia.  What it includes:

 - The website including everything: images, CSS, JavaScript etc
 - The email receiving server
 - Additional utilities for maintenance, testing etc
 - How to set up the SQL tables

What is not included:

 - Configuration for web server, database server or any other external utility
 - Scripts to start and monitor the website/RSS/email server processes

## Architecture overview

Mailnesia is made with the perl programming language.  It runs on
Debian GNU/Linux.  Nginx is used as web server, PostgreSQL as database
server.  Redis in-memory key storage server is used to store banned
email addresses and IP's and other settings.

 - Custom SMTP server implemented in perl using AnyEvent::SMTP.  Event
   based, using only one thread.
 - Website implemented using Mojolicious, powered
   by Nginx web server.
 - Emails are stored in a PostgreSQL database
 - Hosted on a virtual private server with SSD storage

The email server sends all received emails to several URL clicker
processes using ZeroMQ to offload the email body processing which is
somewhat CPU intensive.

## Requirements and installation

Required Perl modules with versions are listed in the file 'cpanfile'.

## Installation

Some modules might require compilation of C source code; these
packages will take care of that on Debian 9 (Stretch):

    apt-get install autotools-dev g++ gcc dpkg-dev cpp fakeroot gdbserver libalgorithm-merge-perl libalgorithm-diff-xs-perl libalgorithm-diff-perl libdpkg-perl libltdl-dev libltdl7 libpython2.6 python2.6 libreadline6 libsqlite3-0 m4 make manpages-dev patch python2.6-minimal g++-4.4 libstdc++6-4.4-dev gcc-4.4 binutils cpp-4.4 libc6-dev libc-dev-bin libmpfr4 libgmp3c2 libgomp1 linux-libc-dev

On Debian 11 (Bullseye):

    apt-get update && apt-get install libzmq5 openssl libssl-dev zlib1g-dev autotools-dev g++ gcc dpkg-dev libdpkg-perl libltdl-dev libltdl7 libsqlite3-0 m4 make patch gcc-10 binutils cpp-10 libc6-dev libc-dev-bin libgomp1 linux-libc-dev libreadline8 cpanminus libpq-dev

The required Perl modules can be installed with the `cpanm` script. Install all requirements into a directory, for example ~/perl5:

    cpanm --installdeps /directory/where/you/cloned/mailnesia.com/ --local-lib-contained ~/perl5/ --skip-satisfied

The path `lib/perl5` under this chosen directory must be exported and used by each application, so they load their dependencies from it:

    export PERL5LIB=~/perl5/lib/perl5

## Setting up Redis

In /etc/redis/redis.conf:

    Port 0
    unixsocket /var/run/redis/redis.sock
    unixsocketperm 777


## Setting up PostgreSQL

### Using password-less "trust" authentication for mailnesia PSQL user
This applies only if clients connect locally on UNIX sockets.
In pg_hba.conf, after "Put your actual configuration here" but before
the local and host configurations:

    # TYPE  DATABASE    USER        CIDR-ADDRESS          METHOD
    local   mailnesia   mailnesia                         trust

### Create mailnesia user / database
  1. as root:

    su postgres
    cd
    createuser --superuser mailnesia
  2. createdb mailnesia
  3. as any user:

    psql -U mailnesia

### Create tables
Execute `tools/psql-create-tables.sh` to create all necessary tables and relations.
The script also contains some documentation.

## Translation

The script tools/translation.py is used to download the Google spreadsheet containing the translations.

## How to contribute to a project without knowing a damn bit about it

<https://domm.plix.at/perl/2013_09_open_source_plus_plus_contribute_without_knowing.html>

## Compressing CSS and JavaScript

Minifying is done with yui-compressor.  This code snippet will
automatically compress .js and .css files in the project directory
upon save in Emacs.

    (add-hook
     'after-save-hook
     (lambda ()
       (dolist (element '(
                          "/directory/containing/project/mailnesia.com/website/js/javascript.js"
                          "/directory/containing/project/mailnesia.com/website/css/style.css"
                          ))
         (when
             (string= buffer-file-name element)
           (save-window-excursion
             (shell-command (concat "yui-compressor -o " (replace-regexp-in-string "\\.\\([a-z]\\{2,3\\}\\)$" "-min.\\1" element ) " " element " &>/dev/null &"))
             )
           )
         )
       )
     )

## Testing

Test running website and mail server by sending test emails:
    tools/test-mailnesia.pl

Execute function tests under t/ (these don't require the website to be up):
    prove
