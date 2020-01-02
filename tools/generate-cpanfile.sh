#!/bin/bash

list=(
    AnyEvent
    AnyEvent::DNS
    AnyEvent::FCGI
    AnyEvent::HTTP
    AnyEvent::SMTP
    AnyEvent::SMTP::Client
    AnyEvent::SMTP::Server
    CGI::Fast
    CGI::RSS
    Captcha::reCAPTCHA
    Carp
    Compress::Snappy
    DBD::Pg
    DBI
    EV
    Email::MIME
    Encode::Alias
    Encode::CN
    Encode::Detect::Detector
    Encode::EBCDIC
    Encode::HanExtra
    Encode::JP
    Encode::KR
    Encode::TW
    FindBin
    HTML::Entities
    HTML::Scrubber
    HTML::Template
    MIME::Base64
    Mojolicious
    Privileges::Drop
    Redis
    Sys::Hostname
    Text::MultiMarkdown
    ZMQ::FFI
    HTML::Lint
    HTML::Lint::Pluggable
    Test::More
    Test::WWW::Mechanize
    WWW::Mechanize
    XML::LibXML
    AnyEvent::Redis
    Text::Greeking
    Time::HiRes
)

for module in "${list[@]}"
do
    echo -n "${module} - "
    perl -M${module} -e 'print $'${module}'::VERSION ."\n";'
done
