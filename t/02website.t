#!/usr/bin/env perl

use Test::More;
use Test::Mojo;
use Mailnesia;

use FindBin;
require "$FindBin::Bin/../script/website.pl";

my $mailnesia = Mailnesia->new();
my $t = Test::Mojo->new;
my $random_name = $mailnesia->random_name_for_testing();
my $random_url_encoded_name = $mailnesia->get_url_encoded_mailbox($random_name);
my $random_name_lc = lc $random_name;


#\Q quote (disable) pattern metacharacters till \E

my $clicker_on_html = $mailnesia->message("clicker_on_html");


$t->get_ok("/settings/$random_url_encoded_name", "GET /settings/$random_url_encoded_name")
->status_is(200, "status is 200")
->content_like(qr/\Q$random_name_lc\E/, "page contains $random_name_lc")
->content_like(qr/\Q$clicker_on_html\E/, "page contains clicker status: ON")
->element_exists('div#clicker-status', "page contains clicker status")
->text_like('div#clicker-status span' => qr"ON", "page contains clicker status with text ON");

$t->get_ok("/mailbox/", "GET /mailbox/")
  ->status_is(200, "status is 200")
  ->text_like('html head title', qr'default @', 'title contains default');

done_testing();
