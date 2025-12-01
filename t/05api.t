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

my $mailbox2 = $mailnesia->get_url_encoded_mailbox(
    $mailnesia->random_name_for_testing()
);
my $alias1 = $mailnesia->get_url_encoded_mailbox(
    $mailnesia->random_name_for_testing()
);
my $alias2 = $mailnesia->get_url_encoded_mailbox(
    $mailnesia->random_name_for_testing()
);
my $alias3 = $mailnesia->get_url_encoded_mailbox(
    $mailnesia->random_name_for_testing()
);

# test that the same alias cannot be set for multiple mailboxes
$t->post_ok("/api/alias/$random_url_encoded_name/$alias1")
    ->status_is(201, "status is 201");

$t->post_ok("/api/alias/$mailbox2/$alias1")
    ->status_is(500, "status is 500");

# test that an alias cannot be set for an alias
$t->post_ok("/api/alias/$alias1/$alias2")
    ->status_is(409, "status is 409");

# test that the alias cannot be the same as the mailbox
$t->post_ok("/api/alias/$alias3/$alias3")
    ->status_is(409, "status is 409");

done_testing();
