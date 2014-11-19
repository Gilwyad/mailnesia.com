# this file contains the module dependencies

requires 'AnyEvent::DNS'            , '>= 7.01';
requires 'AnyEvent::FCGI'           , '>= 0.04';
requires 'AnyEvent::HTTP'           , '>= 2.15';
requires 'AnyEvent::SMTP::Server'   , '>= 0.10';
requires 'CGI::Fast'                , '>= 1.09';
requires 'CGI::RSS'                 , '>= 0.9655';
requires 'Compress::Snappy'         , '>= 0.22';
requires 'DBD::Pg'                  , '>= 2.19.2';
requires 'DBI'                      , '>= 1.622';
requires 'Encode::CN'               , '>= 2.03';
requires 'Encode::Detect::Detector' , '>= 1.01';
requires 'Encode::EBCDIC'           , '>= 2.02';
requires 'Encode::HanExtra'         , '>= 0.23';
requires 'Encode::JP'               , '>= 2.04';
requires 'Encode::KR'               , '>= 2.03';
requires 'Encode::TW'               , '>= 2.03';
requires 'HTML::Entities'           , '>= 3.69';
requires 'MIME::Base64'             , '>= 3.14';
requires 'Mojolicious'              , '>= 4.63';
requires 'Privileges::Drop'         , '>= 1.03';
requires 'Redis'                    , '>= 1.967';



on 'test' => sub {
    requires 'Test::More'           , '>= 0.98';
    requires 'Test::WWW::Mechanize' , '>= 1.42';
    requires 'XML::LibXML'          , '>= 2.0107';
    requires 'HTML::Lint'           , '>= 2.20';
    requires 'WWW::Mechanize'       , '>= 1.71';
};
