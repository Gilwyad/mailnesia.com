#!/usr/bin/env perl

use Test::More;
use Test::Mojo;
use Mailnesia::Config;

use FindBin;
require "$FindBin::Bin/../script/website.pl";

my $config    = Mailnesia::Config->new();


ok( $config->{sitename},
    "sitename set:                    {$config->{sitename}}");
ok( $config->{siteurl},
    "siteurl set:                     {$config->{siteurl}}");
ok( $config->{siteurl_devel},
    "siteurl_devel set:               {$config->{siteurl_devel}}");
ok( $config->{date_format},
    "date_format set:                 {$config->{date_format}}" );
ok( $config->{mail_per_page},
    "mail_per_page set:               {$config->{mail_per_page}}" );
ok( $config->{max_rss_size},
    "max_rss_size set:                {$config->{max_rss_size}}" );
ok( $config->{max_email_size},
    "max_email_size set:              {$config->{max_email_size}}" );
ok( $config->{daily_mailbox_limit},
    "daily_mailbox_limit set:         {$config->{daily_mailbox_limit}}" );
ok( $config->{url_clicker_page_size_limit},
    "url_clicker_page_size_limit set: {$config->{url_clicker_page_size_limit}}" );
ok( $config->{banned_sender_domain},
    "banned_sender_domain set:        {$config->{banned_sender_domain}}" );
ok( $config->{pidfile},
    "pidfile set:                     {$config->{pidfile}}");
ok( $config->{smtp_port},
    "smtp_port set:                   {$config->{smtp_port}}");
ok( $config->{smtp_port_devel},
    "smtp_port_devel set:             {$config->{smtp_port_devel}}");
ok( $config->{smtp_host},
    "smtp_host set:                   {$config->{smtp_host}}");
ok( $config->{smtp_host_devel},
    "smtp_host_devel set:             {$config->{smtp_host_devel}}");

( my $piddir = $config->{pidfile} ) =~ s!/[^/]+$!!;
ok( -d $piddir, "piddir exists: {$piddir}" );



done_testing();
