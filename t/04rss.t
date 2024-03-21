#!/usr/bin/env perl

use Test::More;
use Test::Mojo;
use Mailnesia;

use FindBin;
require "$FindBin::Bin/../script/rss.pl";

my $mailnesia = Mailnesia->new();
my $t = Test::Mojo->new;
my $random_name = $mailnesia->random_name_for_testing();
my $random_url_encoded_name = $mailnesia->get_url_encoded_mailbox($random_name);
my $random_name_lc = lc $random_name;


$t->get_ok("/rss/$random_url_encoded_name", "GET /rss/$random_url_encoded_name")
  ->status_is(200, "status is 200")
  ->content_like(qr/\Q$random_name_lc\E/, "page contains $random_name_lc");

$t->get_ok("/rss/", "GET /rss/")
  ->status_is(404, "status is 404");

$t->get_ok("/rss/.a", "GET /rss/.a")
  ->status_is(200, "status is 200")
  ->content_like(qr!<title>.a @ Mailnesia</title>!, "page contains .a in title");

done_testing();
