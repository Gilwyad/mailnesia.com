#!/usr/bin/env perl

use Test::More;
use Test::Mojo;
use Mailnesia;

use FindBin;
require "$FindBin::Bin/../script/api.pl";

my $mailnesia = Mailnesia->new();
my $t = Test::Mojo->new;
my $random_name = $mailnesia->random_name_for_testing();
my $random_url_encoded_name = $mailnesia->get_url_encoded_mailbox($random_name);


$t->get_ok("/api/mailbox/$random_url_encoded_name", "GET /api/mailbox/$random_url_encoded_name")
  ->status_is(200, "status is 200")
  ->content_is("[]", "page is []");

$t->get_ok("/api/", "GET /api/")
  ->status_is(404, "status is 404");

$t->get_ok("/api/mailbox/", "GET /api/mailbox/")
  ->status_is(404, "status is 404");

$t->get_ok("/api/mailbox/.a", "GET /api/mailbox/.a")
  ->status_is(200, "status is 200")
  ->content_is("[]", "page is []");

done_testing();
