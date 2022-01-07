# mailnesia.com - Anonymous Email in Seconds

[Mailnesia](http://mailnesia.com) is a fully featured disposable email provider.  Just like a
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

See the common Docker file.

## Setting up Redis

Nothing to configure, by default TCP connections are accepted on the Redis default port.

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
#### emails

    CREATE TABLE emails (
        id SERIAL       PRIMARY KEY,
        arrival_date timestamp without time zone NOT NULL default CURRENT_TIMESTAMP,
        email_date varchar(31) default NULL,
        email_from varchar(100) default NULL,
        email_to varchar(100) default NULL,
        email_subject varchar(200)  default NULL,
        mailbox varchar(30) NOT NULL,
        email bytea
    );

Partitioning is used, the key being the id because that's the only
value that needs to be unique in the whole table across the partitions.
This is the "master" table from which all of the partitions inherit.
This contains no data so no indexes are required.  The creation of
partitions and modification of the insert trigger is handled by the
utility `psql-partition-update.sh`.

The insert trigger that calls the trigger function defined in
psql-partition-update.sh to redirect all writes to the latest partition:

    CREATE TRIGGER insert_emails_trigger
    BEFORE INSERT ON emails
    FOR EACH ROW EXECUTE PROCEDURE emails_insert_trigger();

The purpose of partitioning is to make it easy to discard old data.
Instead of `DELETE FROM emails WHERE ( EXTRACT(EPOCH FROM
current_timestamp - arrival_date) / 3600)::INT > ?;`, it's as simple
as `DROP TABLE emails_5;`.  The latter causes almost no disk activity
compared to the former, which can run for minutes, and cause
performance issues.

#### mailbox_alias

This table holds the alias names for mailboxes.

    CREATE TABLE mailbox_alias (
        mailbox varchar(30) NOT NULL,
        alias varchar(30) NOT NULL UNIQUE
    );

    ALTER TABLE mailbox_alias ADD CONSTRAINT lowercase_only CHECK (LOWER(alias) = alias);

#### emailperday

This table is for statistics only, contains the number of emails
received each day and the combined size of them.

    CREATE TABLE emailperday (
        day date default current_date UNIQUE,
        email integer DEFAULT 0,
        bandwidth integer DEFAULT 0
    );

## Translation

The script tools/translation.py is used to download the Google spreadsheet containing the translations.

## How to contribute to a project without knowing a damn bit about it

<http://domm.plix.at/perl/2013_09_open_source_plus_plus_contribute_without_knowing.html>

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

## Executing using Docker

Use `tools/increment-version.sh` to
 - increment and set the version (tag) on the HEAD in the git repo,
 - build the Docker images of the apps,
 - push the Docker images to the Dockerhub registry.

The app can be specified with option -a with the following values:
 - common: the base image all apps depend on
 - mail-server
 - website (contains all website pages where database access is required, like /mailbox/, /settings/)
 - website-pages (contains all website pages where database access is not required)
 - rss
 - clicker (script to "click" links in emails)
 - api (HTTP API used by the Angular website)
 - angular-website (modern mobile friendly alternative website)

To increment and set new version based on autotag, which can be major|minor|patch:

    tools/increment-version.sh -a api -i major

To build the a Docker image:

    tools/increment-version.sh -a common -b

To push the latest version of an image to the registry:

    tools/increment-version.sh -a rss -p

Options can be combined.  To execute:

    docker run --interactive --tty --env postgres_password="some-password" mail-server.mailnesia.com:1.0.0
    docker run --interactive --tty clicker.mailnesia.com:1.0.0
    docker run --interactive --tty --env postgres_password="some-password" website.mailnesia.com:1.0.0
    docker run --interactive --tty website-pages.mailnesia.com:1.0.0
    docker run --interactive --tty --env postgres_password="some-password" api.mailnesia.com:1.0.0
    docker run --interactive --tty --env postgres_password="some-password" rss.mailnesia.com:1.0.0

Note that the Dockerfiles contain additional information about the execution, for example environment variables.

Command to stop the container:

    docker stop mail-server.mailnesia.com:1.0.0

Command to remove the stopped container:

    docker rm mail-server.mailnesia.com:1.0.0

Enter the container and start a shell:

    docker exec --interactive --tty mail-server.mailnesia.com:1.0.0 bash

## Executing for development
    # PERL5LIB has to be set to the lib directory, example:
    export PERL5LIB=/home/peter/projects/mailnesia.com/lib

    # enable development mode:
    export mailnesia_devel=true

    # set the host where postgres is running
    export postgres_host=localhost

    # set the host where redis is running
    export redis_host=localhost

    # save postgres credentials in ~/.pgpass as hostname:port:database:username:password

    # email link clicker
    perl script/clicker.pl

    # Email server
    perl script/AnyEvent-SMTP-Server.pl

    # website pages (TODO: js&css)
    morbo --listen http://*:3000 ./script/website-pages.pl

    # website (TODO: js&css)
    morbo --listen http://*:3001 ./script/website.pl

    # email api
    morbo --listen http://*:3002 ./script/api.pl

    # RSS
    morbo --listen http://*:3003 ./script/rss.pl
