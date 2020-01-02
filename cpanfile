# this file contains the module dependencies

requires 'AnyEvent'                 , '== 7.14';
requires 'AnyEvent::DNS'            , '== 7.14';
requires 'AnyEvent::FCGI'           , '== 0.04';
requires 'AnyEvent::HTTP'           , '== 2.24';
requires 'AnyEvent::SMTP'           , '== 0.10';
requires 'AnyEvent::SMTP::Client'   , '== 0.10';
requires 'AnyEvent::SMTP::Server'   , '== 0.10';
requires 'CGI::RSS'                 , '== 0.9660';
requires 'Captcha::reCAPTCHA'       , '== 0.98';
requires 'Carp'                     , '== 1.50';
requires 'Compress::Snappy'         , '== 0.24';
requires 'DBD::Pg'                  , '== 3.7.4';
requires 'DBI'                      , '== 1.642';
requires 'EV'                       , '== 4.25';
requires 'Email::MIME'              , '== 1.946';
requires 'Encode::Alias'            , '== 2.24';
requires 'Encode::CN'               , '== 2.03';
requires 'Encode::Detect::Detector' , '== 1.01';
requires 'Encode::EBCDIC'           , '== 2.02';
requires 'Encode::HanExtra'         , '== 0.23';
requires 'Encode::JP'               , '== 2.04';
requires 'Encode::KR'               , '== 2.03';
requires 'Encode::TW'               , '== 2.03';
requires 'FindBin'                  , '== 1.51';
requires 'HTML::Entities'           , '== 3.69';
requires 'HTML::Scrubber'           , '== 0.17';
requires 'HTML::Template'           , '== 2.97';
requires 'MIME::Base64'             , '== 3.15';
requires 'Mojolicious'              , '== 8.12';
requires 'Privileges::Drop'         , '== 1.03';
requires 'Redis'                    , '== 1.991';
requires 'Sys::Hostname'            , '== 1.22';
requires 'Text::MultiMarkdown'      , '== 1.000035';
requires 'ZMQ::FFI'                 , '== 1.11';

on 'test' => sub {
    requires 'HTML::Lint'           , '== 2.20';
    requires 'HTML::Lint::Pluggable', '== 0.08';
    requires 'Test::More'           , '== 1.302133';
    requires 'Test::WWW::Mechanize' , '== 1.52';
    requires 'WWW::Mechanize'       , '== 1.91';
    requires 'XML::LibXML'          , '== 2.0134';
};

on 'develop' => sub {
    requires 'AnyEvent::Redis'            , '== 0.23';
    requires 'Text::Greeking'             , '== 0.12';
    requires 'Time::HiRes'                , '== 1.9759';
}
