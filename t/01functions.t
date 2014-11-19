#!/usr/bin/env perl

use Test::More;
use Test::Mojo;
use Mailnesia;
use Mailnesia::SQL;
use Mailnesia::Config;

use FindBin;
require "$FindBin::Bin/../script/website.pl";
use strict;
use warnings;


my $mailnesia = Mailnesia->new();
my $config    = Mailnesia::Config->new();




ok( $mailnesia->get_project_directory(), "get_project_directory" );



# test check_mailbox_characters
ok ( $mailnesia->check_mailbox_characters("acuahf_asfasf+fasf-asfavbg4g.3"), "check_mailbox_characters: valid");

is ( $mailnesia->check_mailbox_characters("fjsa;#aewfo#*"), "fjsa", "check_mailbox_characters: invalid");

ok ( ! $mailnesia->check_mailbox_characters("fjsa;#aewfo#*", 1), "check_mailbox_characters: invalid, strict");

ok ( $mailnesia->check_mailbox_characters( $mailnesia->random_name_for_testing() ), "check_mailbox_characters: random_name_for_testing");

ok ( $mailnesia->check_mailbox_characters( $mailnesia->random_name() ), "check_mailbox_characters: random_name");

ok ( my $random_name = $mailnesia->random_name(), "random_name" );

ok ( my $random_name_for_testing = $mailnesia->random_name_for_testing(), "random_name_for_testing" );
is ( length $random_name_for_testing, 30, "random_name_for_testing is 30 characters long" );
ok ( my $random_url_encoded_name = $mailnesia->get_url_encoded_mailbox($random_name_for_testing), "get_url_encoded_mailbox");
unlike ( $random_url_encoded_name, qr/\+/, "random_url_encoded_name does not contain +" );


ok ( $config->ban_mailbox($random_name_for_testing), "ban mailbox $random_name_for_testing");
ok ( $config->get_banned_mailbox(), "get_banned_mailbox" );
ok ( $config->is_mailbox_banned($random_name_for_testing), "$random_name_for_testing is banned");
ok ( $config->unban_mailbox($random_name_for_testing), "unban mailbox $random_name_for_testing");
ok ( ! $config->is_mailbox_banned($random_name_for_testing), "$random_name_for_testing is not banned");

my $ip = "192.168.10.166";

ok ( $config->ban_ip($ip), "ban ip $ip");
ok ( $config->is_ip_banned($ip), "$ip is banned");
ok ( $config->unban_ip($ip), "unban ip $ip");
ok ( ! $config->is_ip_banned($ip), "$ip is not banned");


# clicker is enabled by default
ok ( $config->is_clicker_enabled($random_name), "clicker enabled by default for $random_name" );
ok ( $config->is_clicker_enabled($random_name_for_testing), "clicker enabled by default for $random_name_for_testing" );

ok ( $config->disable_clicker($random_name_for_testing), "disable clicker for $random_name_for_testing" );
ok ( ! $config->is_clicker_enabled($random_name_for_testing), "clicker disabled for $random_name_for_testing" );
ok ( $config->enable_clicker($random_name_for_testing), "enable clicker for $random_name_for_testing" );
ok ( $config->is_clicker_enabled($random_name_for_testing), "clicker enabled for $random_name_for_testing" );


# $random_name_for_testing has 0 emails
is ( $mailnesia->emailcount($random_name_for_testing), 0, "$random_name_for_testing mailbox has 0 emails (with emailcount())" );
is ( $mailnesia->hasemail ( $random_name_for_testing), 0, "$random_name_for_testing mailbox has 0 emails (with hasemail())" );


# alias tests

is ( scalar @ { $mailnesia->get_alias_list($random_name_for_testing) }, 0, "get_alias_list returns 0 aliases for $random_name_for_testing" );

my $alias;
ok ( $alias = lc $mailnesia->random_name_for_testing(), "get a random lowercase name for testing" );


ok ( my $check = $mailnesia->setAlias_check($random_name_for_testing,$alias), "setAlias_check: mailbox, alias1" );


is ( $check->[0], 200, "alias can be set for mailbox, result code is 200");
is ( $check->[1], $mailnesia->message('alias_assign_success',$random_name_for_testing,$alias),
        "alias can be set for mailbox, result text OK"
    );

ok ( $check = $mailnesia->setAlias_check($alias,$alias), "setAlias_check: mailbox=alias");


is ( $check->[0], 409, "alias cannot be the same as mailbox, result code if 409" );
is ( $check->[1], $mailnesia->message('mailbox_eq_alias',$random_name_for_testing,$alias),
        "alias cannot be the same as mailbox, result text OK"
    );


ok ( $mailnesia->setAlias($random_name_for_testing,$alias), "setAlias: mailbox, alias1");

is_deeply ( $mailnesia->get_alias_list($random_name_for_testing), [$alias], "get_alias_list returns alias1" );


ok ( $check = $mailnesia->setAlias_check($alias,$mailnesia->random_name()), "alias cannot be set if the specified mailbox is an alias: setAlias_check");
is ( $check->[0], 409, "alias cannot be set if the specified mailbox is an alias: status=409");
is ( $check->[1], $mailnesia->message('alias_assign_error'), "alias cannot be set if the specified mailbox is an alias: text OK");

ok ( my $mailbox2 = lc $mailnesia->random_name_for_testing(), "mailbox2 = random lowercase name" );
ok ( my $alias2   = lc $mailnesia->random_name_for_testing(), "alias2 = random lowercase name" );

ok ( $mailnesia->setAlias($mailbox2,$alias2), "setAlias: mailbox2, alias2");


is_deeply (
        $mailnesia->get_alias_list($mailbox2),
        [$alias2],
        "get_alias_list returns alias2 for mailbox2"
    );

ok ( $check = $mailnesia->setAlias_check($mailnesia->random_name(),$mailbox2), "alias cannot be set if the specified alias is a mailbox (where an alias is set): setAlias_check" );
is ( $check->[0], 409, "alias cannot be set if the specified alias is a mailbox (where an alias is set): status == 409" );
is ( $check->[1], $mailnesia->message('alias_assign_error'), "alias cannot be set if the specified alias is a mailbox (where an alias is set): text OK" );

ok ( $mailnesia->removeAlias($mailbox2,$alias2), "removeAlias: mailbox2, alias2");


ok ( scalar @ { $mailnesia->get_alias_list($mailbox2) } == 0, "get_alias_list returns 0 aliases for mailbox2" );


ok ( $mailnesia->setAlias($random_name_for_testing,$alias2), "setAlias: mailbox, alias2");

is_deeply (
        $mailnesia->get_alias_list($random_name_for_testing),
        [$alias,$alias2],
        "get_alias_list returns alias1 and alias2 for mailbox"
    );



my $number_of_aliases = 100;

my @alias_list = ( $alias, $alias2 );

for (0..$number_of_aliases - 1 + scalar @alias_list)
{

    ok ( my $alias   = lc $mailnesia->random_name_for_testing(), "alias = lowercase random name");

    ok ( $mailnesia->setAlias($random_name_for_testing,$alias), "$_ : setAlias: $random_name_for_testing -> $alias");

    #save the current alias
    push @alias_list, $alias;


    is_deeply (
            $mailnesia->get_alias_list($random_name_for_testing),
            \@alias_list,
            "get_alias_list returns all aliases in \@alias_list for mailbox"
        );


}


#remove all aliases


for (0 .. scalar (@alias_list) - 1)
{

    my $alias   = shift @alias_list;

    ok ( $mailnesia->removeAlias($random_name_for_testing,$alias), "$_ : removeAlias: $random_name_for_testing -> $alias");


    is_deeply (
            $mailnesia->get_alias_list($random_name_for_testing),
            \@alias_list,
            "get_alias_list returns all aliases in \@alias_list for mailbox"
        );


}




ok ( scalar @ { $mailnesia->get_alias_list($random_name_for_testing) } == 0, "get_alias_list returns 0 aliases for mailbox" );


done_testing();


=head2 arrays_equal

return true if the two arrays contain the same elements, disregarding the order

=cut

sub arrays_equal {
        my $n = 0;
        my @a = sort @ { +shift };
        my @b = sort @ { +shift };

        for my $element (@a)
        {
            return unless $element eq $b[$n++]
        }
}
