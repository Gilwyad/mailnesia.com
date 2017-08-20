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
 - Website implemented using AnyEvent::FCGI and Mojolicious, powered
   by Nginx web server.
 - Emails are stored in a PostgreSQL database
 - Hosted on a virtual private server with SSD storage

## Requirements

Required Perl modules with versions are listed in the file 'cpanfile'.

## Installation

The required Perl modules can be installed with the `cpan` script: 

    cpan Privileges::Drop AnyEvent::SMTP::Server AnyEvent::DNS AnyEvent::HTTP Encode::Detect::Detector HTML::Entities Compress::Snappy Encode::CN Encode::EBCDIC Encode::JP Encode::KR Encode::TW Encode::HanExtra CGI::RSS MIME::Base64 AnyEvent::FCGI Mojolicious
    
Or using the Debian package management for those that are available:

    apt-get install libcommon-sense-perl libcgi-fast-perl libcgi-pm-perl libemail-mime-perl libio-aio-perl libdbi-perl libdbd-pg-perl libhtml-scrubber-perl libredis-perl libcaptcha-recaptcha-perl libtext-multimarkdown-perl libfilesys-diskspace-perl libhtml-template-perl liblib-abs-perl libprivileges-drop-perl libanyevent-http-perl libev-perl

Or using cpanm:

    cpanm --installdeps /directory/where/you/cloned/mailnesia.com/

Some modules might require compilation of C source code; these
packages will take care of that:

    apt-get install autotools-dev g++ gcc dpkg-dev cpp fakeroot gdbserver libalgorithm-merge-perl libalgorithm-diff-xs-perl libalgorithm-diff-perl libdpkg-perl libltdl-dev libltdl7 libpython2.6 python2.6 libreadline6 libsqlite3-0 m4 make manpages-dev patch python2.6-minimal g++-4.4 libstdc++6-4.4-dev gcc-4.4 binutils cpp-4.4 libc6-dev libc-dev-bin libmpfr4 libgmp3c2 libgomp1 linux-libc-dev

## Setting up Redis

In /etc/redis/redis.conf:

    Port 0
    unixsocket /var/run/redis/redis.sock
    unixsocketperm 777


## Setting up PostgreSQL

### Using password-less "trust" authentication for mailnesia PSQL user
In pg_hba.conf:

    # TYPE  DATABASE    USER        CIDR-ADDRESS          METHOD
    local   mailnesia   mailnesia                         trust

### Create mailnesia user / database
  1. as root: su postgres
     createuser mailnesia
     (superuser: Y)
  2. createdb mailnesia
  3. as any user: psql -U mailnesia

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


How to contribute to a project without knowing a damn bit about it
----------

<http://domm.plix.at/perl/2013_09_open_source_plus_plus_contribute_without_knowing.html>

Compressing CSS and JavaScript
------------------------------

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


