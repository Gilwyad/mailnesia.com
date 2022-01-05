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


$t->get_ok("/rss")->status_is(404, "status is 404");

$t->get_ok("/rss/$random_url_encoded_name")
  ->status_is(200, "status is 200")
  ->element_exists('rss channel link', "rss channel link exists")
  ->element_exists('rss channel title', "rss channel title exists")
  ->element_exists('rss channel description', "rss channel description exists");


done_testing();
