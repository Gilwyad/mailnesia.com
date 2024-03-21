#!/usr/bin/env perl

use Test::More;
use Test::Mojo;
use Mailnesia;

use FindBin;
require "$FindBin::Bin/../script/website-pages.pl";

my $mailnesia = Mailnesia->new({
    skip_sql_connect => 1,
});
my $t = Test::Mojo->new;
my $random_name = $mailnesia->random_name_for_testing();
my $random_url_encoded_name = $mailnesia->get_url_encoded_mailbox($random_name);
my $random_name_lc = lc $random_name;

my $clicker_on_html = $mailnesia->message("clicker_on_html");


# $t->get_ok("/hu/", "GET /hu/")
#     ->status_is(200, "status is 200");

my @languages = keys %{$mailnesia->{text}->{lang_hash}};

for (@languages) {
    next if $_ eq 'en';
    $t->get_ok("/$_/", "GET /$_/")
        ->status_is(200, "status is 200 for /$_/");
}


done_testing();
