# this file contains the module dependencies

requires 'AnyEvent'                 , '>= 7.01';
requires 'AnyEvent::DNS'            , '>= 7.01';
requires 'AnyEvent::FCGI'           , '>= 0.04';
requires 'AnyEvent::HTTP'           , '>= 2.15';
requires 'AnyEvent::SMTP'           , '>= 0.10';
requires 'AnyEvent::SMTP::Client'   , '>= 0.08';
requires 'AnyEvent::SMTP::Server'   , '>= 0.08';
requires 'CGI::Fast'                , '>= 1.09';
requires 'CGI::RSS'                 , '>= 0.9655';
requires 'Captcha::reCAPTCHA'       , '>= 0.93';
requires 'Carp'                     , '>= 1.20';
requires 'Compress::Snappy'         , '>= 0.22';
requires 'DBD::Pg'                  , '>= 2.19.2';
requires 'DBI'                      , '>= 1.622';
requires 'EV'                       , '>= 4.11';
requires 'Email::MIME'              , '>= 1.910';
requires 'Encode::Alias'            , '>= 1.00';
requires 'Encode::CN'               , '>= 2.03';
requires 'Encode::Detect::Detector' , '>= 1.01';
requires 'Encode::EBCDIC'           , '>= 2.02';
requires 'Encode::HanExtra'         , '>= 0.23';
requires 'Encode::JP'               , '>= 2.04';
requires 'Encode::KR'               , '>= 2.03';
requires 'Encode::TW'               , '>= 2.03';
requires 'FindBin'                  , '>= 1.50';
requires 'HTML::Entities'           , '>= 3.69';
requires 'HTML::Scrubber'           , '>= 0.09';
requires 'HTML::Template'           , '>= 2.91';
requires 'MIME::Base64'             , '>= 3.14';
requires 'Mojolicious'              , '>= 4.63';
requires 'Privileges::Drop'         , '>= 1.03';
requires 'Redis'                    , '>= 1.967';
requires 'Sys::Hostname'            , '>= 1.00';
requires 'Text::MultiMarkdown'      , '>= 1.000034';
requires 'ZMQ::FFI'                 , '>= 1.11';

on 'test' => sub {
    requires 'HTML::Lint'           , '== 2.26';
    requires 'HTML::Lint::Pluggable', '>= 0.03';
    requires 'Test::More'           , '>= 0.98';
    requires 'Test::WWW::Mechanize' , '>= 1.42';
    requires 'WWW::Mechanize'       , '>= 1.71';
    requires 'XML::LibXML'          , '>= 2.0107';
    requires 'Test::MockTime'       , '>= 0.17.1';
};

on 'develop' => sub {
    requires 'AnyEvent::Redis'            , '>= 0.23';
    requires 'Text::Greeking'             , '>= 0.12';
    requires 'Time::HiRes'                , '>= 1.972101';
}
