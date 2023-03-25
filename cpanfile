# this file contains the module dependencies

requires 'AnyEvent::HTTP'           , '>= 2.15, < 3.0';
requires 'AnyEvent::SMTP'           , '>= 0.10, < 1.0';
requires 'AnyEvent::SMTP::Client'   , '>= 0.08, < 1.0';
requires 'AnyEvent::SMTP::Server'   , '>= 0.08, < 1.0';
requires 'Captcha::reCAPTCHA'       , '>= 0.93, < 1.0';
requires 'Carp'                     , '>= 1.20, < 2.0';
requires 'Compress::Snappy'         , '>= 0.22, < 1.0';
requires 'DBD::Pg'                  , '>= 3.0, < 4.0';
requires 'DBI'                      , '>= 1.622, < 2.0';
requires 'EV'                       , '>= 4.11, < 5.0';
requires 'Email::MIME'              , '>= 1.910, < 2.0';
requires 'Encode::Alias'            , '>= 2.00, < 3.0';
requires 'Encode::CN'               , '>= 2.03, < 3.0';
requires 'Encode::Detect::Detector' , '>= 1.01, < 2.0';
requires 'Encode::EBCDIC'           , '>= 2.02, < 3.0';
requires 'Encode::HanExtra'         , '>= 0.23, < 1.0';
requires 'Encode::JP'               , '>= 2.04, < 3.0';
requires 'Encode::KR'               , '>= 2.03, < 3.0';
requires 'Encode::TW'               , '>= 2.03, < 3.0';
requires 'FindBin'                  , '>= 1.50, < 2.0';
requires 'HTML::Entities'           , '>= 3.69, < 4.0';
requires 'HTML::Scrubber'           , '>= 0.09, < 1.0';
requires 'HTML::Template'           , '>= 2.91, < 3.0';
requires 'MIME::Base64'             , '>= 3.14, < 4.0';
requires 'Mojolicious'              , '>= 4.63, < 5.0';
requires 'Privileges::Drop'         , '>= 1.03, < 2.0';
requires 'Redis'                    , '>= 1.967, < 2.0';
requires 'Sys::Hostname'            , '>= 1.00, < 2.0';
requires 'Text::MultiMarkdown'      , '>= 1.000034, < 2.0';
requires 'ZMQ::FFI'                 , '>= 1.11, < 2.0';

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
