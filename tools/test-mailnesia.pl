#!/usr/bin/perl

use strict;
use Test::More ;
use Test::WWW::Mechanize;
use HTML::Lint;
use HTML::Lint::Pluggable;
use DBI;
use XML::LibXML;
use Redis;
use IO::Socket qw(AF_INET);

use FindBin;
use lib "$FindBin::Bin/../lib/";

use Mailnesia;
use Mailnesia::SQL;
use Mailnesia::Config;
use utf8;

my $number_of_aliases = 10;      # test this number of aliases
my @aliases;
my @alias_restoration;
my $config = Mailnesia::Config->new;
my $mailnesia = Mailnesia->new();
my $global_mailbox = $mailnesia->random_name_for_testing();
my $mailbox_for_api_test = $mailnesia->random_name_for_testing();
my $email_id;
my $sender_domain = q{gmail.com};
my $project_directory = $mailnesia->get_project_directory();
my $baseurl = $mailnesia->{devel} ? "http://" . $config->{siteurl_devel} : "http://" . $config->{siteurl};

# language pages to test:
my @languages = qw!/ /hu /it /lv /fi /pt /de /ru /pl /zh /fr /es /cs /es-ar /ms /id /pt-br!;
my $lint = HTML::Lint::Pluggable->new();       # plugin system for HTML::Lint
$lint -> load_plugin("HTML5");                 # loads HTML::Lint::Pluggable::HTML5
$lint -> load_plugin("TinyEntitesEscapeRule"); # loads HTML::Lint::Pluggable::TinyEntitesEscapeRule

my $mech = Test::WWW::Mechanize->new(
                                     autolint => $lint,
                                     cookie_jar => undef
                                    );

my ($url,$category);


my $parser = XML::LibXML->new();

my $redis = Redis->new(
      encoding => undef,
      sock     => '/var/run/redis/redis.sock'
    );

my $mailbox_to_ban = 'ban-this-mailbox-as-a-test';

# tests:

=head1 webpage tests

=cut

sub check_config {
    print_test_category_header( );

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

    ok( $config->ban_mailbox($mailbox_to_ban), "mailbox $mailbox_to_ban banned" );

    my $banned_mailbox = $config->get_banned_mailbox();
    ok( $banned_mailbox,
        "Banned mailbox defined:          $banned_mailbox");
    ok( $banned_mailbox eq $mailbox_to_ban,
        "Banned mailbox ($banned_mailbox) is the same as the one we wanted: $mailbox_to_ban"
    );


    ( my $piddir = $config->{pidfile} ) =~ s!/[^/]+$!!;
    ok( -d $piddir, "piddir exists: {$piddir}" );

    return 12;
}

sub webpage_tests {
    $category = "webpage tests";
    print_test_category_header($category);
    my $numof_tests;

    for (@languages)
    {
        $url = $baseurl.$_;

        print_testcase_header($category . " " . $_);
        $numof_tests = webpage_tests_internal($url);

        $url = $baseurl.$_."/features.html";
        $numof_tests += webpage_tests_internal($url);
    }
    return scalar @languages * $numof_tests;

}

sub webpage_tests_internal {
    my $url = shift;

    $mech->get_ok( $url, "GET $url" );
    $mech->text_lacks( 'service down' );
    $mech->text_contains( 'mailnesia' );
    $mech->content_lacks ('<div class="alert-message', 'no alert message on page');
    $mech->text_unlike ( qr"\bnil\b", "Text does not contain 'nil' as separate word" );
    $mech->text_lacks ( "�", "Text does not contain a common invalid utf8 character");
    $mech->text_lacks ( "*", "Text does not contain an asterisk" );

    $mech->stuff_inputs;        # this is not counted as a test

    $mech->lacks_uncapped_inputs('forms have maxlength');
    return 8;

}

=head2 mailbox_settings_page_tests

open the settings page of a random mailbox via url

=cut

sub mailbox_settings_page_tests {
    print_test_category_header( $category = "mailbox settings page tests" );
    my $mailbox = $mailnesia->random_name_for_testing();
    my $mailbox_lowercase = lc $mailbox;
    my $mailbox_url_encoded = $mailnesia->get_url_encoded_mailbox ( $mailbox );
    my $tests = 0;

    $url = $baseurl. "/settings/$mailbox_url_encoded";

    if ( $mech->get_ok( $url, "GET $url" ) ) {
        $mech->text_contains( qq{Welcome to the preferences page of mailbox $mailbox_lowercase!}, "page contains the mailbox name");
        $tests++;
    }
    $tests++;

    if ( $mech->follow_link_ok( {text_regex => qr/Access here/i }, "open 'Recent visitors of this mailbox' link on current page" ) )
    {
        $tests += check_visitors_header();
        $mech->back();
    }
    $tests++;

    return $tests;
}

=head2 mailbox_tests

open a random mailbox via url and form, case checking: must convert everything to lowercase

=cut

sub mailbox_tests {

      print_test_category_header( $category = "mailbox tests" );
      my $mailbox = $mailnesia->random_name_for_testing();
      my $mailbox_url_encoded = $mailnesia->get_url_encoded_mailbox ( $mailbox );
      my $tests = 0;

      $url = $baseurl. "/mailbox/$mailbox_url_encoded";

      $mech->get_ok( $url, "GET $url" );
      $tests += 1 + check_mailbox_header();

      $mech->submit_form_ok(
              {
                  fields  => {
                          mailbox => $mailbox
                      },
                  form_number => 1
              },
              'getting mailbox with form button'
          );
      $tests += 1 + check_mailbox_header();
      my $valid_part = "wfef8yudl8sylisgyhsldigalf8e";
      my $invalid_part = ",1";
      $url = $baseurl . "/mailbox/" . $valid_part . $invalid_part;

      if ( $mech->get_ok( $url, "test invalid mailbox: $url" ) )
      {
          $mech->title_like( qr{^$valid_part @ mailnesia}i, "title contains the valid part");
          $mech->text_contains( qq{Invalid characters entered! (valid: $valid_part)}, "page contains the valid part and error message");
          $mech->text_lacks( qq{$valid_part . $invalid_part}, "page does not contain the invalid mailbox");
          $tests+=3;
      }
      $tests++;

      return $tests;
}

=head2 alias_negative_tests

test that alias setting: modification is not possible if the mailbox itself is an alias, or the alias to be used already has an alias set (is a mailbox)

=cut

sub alias_negative_tests {

        print_test_category_header( );
        my $tests = 0 ;
        my $alias_fail;

        foreach (@aliases)
        {

            $alias_fail = $mailnesia->random_name_for_testing();

            # try to set an alias for an alias
            $mech->post("$baseurl/settings/$_/alias/set",
                        {
                            alias=>$alias_fail
                        }
                    );

            is ( $mech->status(),
                 403,
                 "try to set random alias for an alias: $_ => $alias_fail, status 403" );


            $mech->text_lacks ("Alias ". lc $alias_fail . " assigned to mailbox ". lc $_ . "!", "lacks successful response" );
            $mech->text_contains ( "", "empty response" );






            #try to set an alias that is already set
            $mech->post("$baseurl/settings/$alias_fail/alias/set",
                        {
                            alias=>$_
                        }
                    );

            is ( $mech->status(),
                 500,
                 "try to set an alias that is already set: $alias_fail => $_, status 500" );


            $mech->text_lacks ("Alias ". lc $alias_fail . " assigned to mailbox ". lc $_ . "!", "lacks successful response" );
            $mech->text_contains ("Internal Server Error" );


            $tests += 6;

        }


        if (@aliases)
        {
            #try to set an alias that is a mailbox (has alias)
            $mech->post("$baseurl/settings/$alias_fail/alias/set",
                        {
                            alias=>$global_mailbox
                        }
                    );

            is ( $mech->status(),
                 409,
                 "try to set an alias that is a mailbox (has alias): $alias_fail => $global_mailbox, status 409" );


            $mech->text_lacks ("Alias ". lc $alias_fail . " assigned to mailbox ". lc $_ . "!", "lacks successful response" );
            $mech->text_contains ("Alias assignment error! This name is already taken" );

            $tests += 3;
        }

        return $tests;
    }

=head2 alias_positive_tests

set some aliases, verify

=cut


sub alias_positive_tests {

        print_test_category_header( );

        my $tests = 2;          # number of tests in this sub

        my $mailbox_url_encoded = $mailnesia->get_url_encoded_mailbox ( lc $global_mailbox );
        my $alias_url_encoded;

        $url = "$baseurl/mailbox/$mailbox_url_encoded" ;
        $mech->get_ok( $url, "GET $url" );
        $url = "$baseurl/settings/$mailbox_url_encoded";

        if ($mech->follow_link_ok( { url => "/settings/$mailbox_url_encoded" }, "follow settings link" ))
        {

            # check default clicker mode: ON
            $mech->text_contains("ON ✓", "page contains: ON ✓");

            $mech->content_contains( '<div class="alias_form"', "alias form present" );
            $tests+=2;


            # ignore missing body|head|html|title tags
            my $old_status = $mech->autolint (
                $lint->load_plugins(
                    WhiteList => +{
                        rule => +{
                            'doc-tag-required' => sub {
                                my $param = shift;
                                return $param->{tag} =~ /body|head|html|title/;
                            },
                        }
                    }
                )
            );

            # assign aliases
            for ( my $n = 0; $n <= $number_of_aliases; $n++ )
            {
                my $alias = $mailnesia->random_name_for_testing();

                if ( $mech->post_ok("$baseurl/settings/$mailbox_url_encoded/alias/set",
                                    {
                                        alias=>$alias
                                    },
                                    "$n: set alias with POST request: $mailbox_url_encoded => $alias"
                                )
                 )
                {
                    push @aliases, $alias;
                    $mech->text_contains ("Alias ". lc $alias . " assigned to mailbox ". lc $global_mailbox . "!", "successful response" );
                    $tests++;
                }
                $tests++;
            }


            # turn validation back on
            $mech->autolint($old_status);

            $mech->get_ok( $url, "GET $url" );
            $tests++;
            $mech->content_contains( '<div class="alias_form"', "alias form still present" );
            $tests++;

            #aliases present
            for (@aliases)
            {
                my $alias = lc;

                $mech->content_like(qr{<input type="text"[^>]+value="\Q$alias\E">}, "form input contains alias $alias");
                $mech->content_like(qr{<input type="hidden" name="remove_alias" value="\Q$alias\E">}, "form hidden field contains alias $alias");
                $tests+= 2;
            }


        }


        if ( @aliases )
        {
            #test the first alias
            $alias_url_encoded = $mailnesia->get_url_encoded_mailbox ( $aliases[0] );

            $url = $baseurl. "/mailbox/$alias_url_encoded" ;
            $mech->get_ok( $url, "open alias $aliases[0] at $url" );

            $mech->content_lacks( '<div class="alias_form"', "no form to set alias" );
            $mech->content_lacks( '<h1 class="emails">Mail for', "no 'mail for' text" );
            $mech->content_contains( q{<div class="alert-message warning"><p><a href="/features.html#alias">}, "warning present: 'this is an alias...'" );

            $tests += 4 + rss_forbidden_tests ($alias_url_encoded);

        }
        return $tests;
  }

sub random_mailbox {
      print_test_category_header( );

      $url = $baseurl. "/random/";
      return check_empty_mailbox($url);
}

=head1 validate rss

check content-type and xml validation

parameters: mailbox name

=cut

sub rss_tests {

  my $mailbox = lc shift;
  my $tests = 0;
  my $url = $baseurl . "/rss/" . $mailnesia->get_url_encoded_mailbox ( $mailbox );

  if ( $mech->follow_link_ok( {url_abs => $url}, "follow RSS link on current page: $url" ) )
  {

      my $content_type = $mech->response()->header( 'Content-Type' );
      is ( $content_type, 'application/xml', "Content-Type is application/xml");

      eval {
              my $parser = XML::LibXML->load_xml
              (
                  string => $mech->content
              );
          };

      ok (! $@, "RSS valid") ;
      my $url_encoded_mailbox = $mailnesia->get_url_encoded_mailbox($mailbox);
      $mech->content_contains ('<title>' . lc $mailbox, "RSS title contains " . lc $mailbox);
      $mech->content_contains ("<link>$baseurl/mailbox/" . $url_encoded_mailbox, "RSS link contains " . $url_encoded_mailbox);

      $mech->back(); # going back to page so next test can operate on current page
      $tests = 4;

  }

  return $tests + 1;

}

=head1 check if rss request is forbidden

parameters: mailbox name

=cut

sub rss_forbidden_tests {
  my $mailbox = shift;
  print "Checking forbidden RSS for $mailbox\n";
  my $url = $baseurl . "/rss/" . $mailnesia->get_url_encoded_mailbox ( $mailbox );

  ok ( $mech->get( $url ), "GET $url" );
  is ( $mech->status(), 403, "Status is 403 Forbidden");
  unless ( ok ( ! $mech->content, "got empty response"))
    {
      warn "#   got unexpected output: " . $mech->content;
    }

  return 3;
}

=head1 check if API request for mailbox is forbidden

parameters: mailbox name

=cut

sub api_forbidden_tests {
    my $mailbox = shift;
    print "Checking forbidden API request for $mailbox\n";
    my $url = $baseurl . "/api/mailbox/" . $mailnesia->get_url_encoded_mailbox ( $mailbox );

    ok ( $mech->get( $url ), "GET $url" );
    is ( $mech->status(), 403, "Status is 403 Forbidden");
    unless ( ok ( ! $mech->content, "got empty response")) {
        warn "#   got unexpected output: " . $mech->content;
    }

    $mech->back();

    return 3;
}

=head1 check if mailbox is empty

=cut

sub check_empty_mailbox {
      print_test_category_header( );
      my $url = shift;
      $mech->get_ok( $url, "GET $url" );
      $mech->text_contains( 'No e-mail message for' ) or warn $mech->content(format=>'text');
      return 2;

}

=head1 check if mailbox is empty using the API

Parameter: full URL. Should return empty array in JSON.

=cut

sub api_check_empty_mailbox {
    print_test_category_header( );
    my $url = shift;
    $mech->get_ok( $url, "GET $url" );
    is ( $mech->status(), 200, "Status is 200");
    $mech->content_is( "[]", "Content is an empty array!" ) or warn $mech->content(format=>'text');
    $mech->back();
    return 3;
}

=head1 check if mailbox is not empty using the API

Parameter: full URL. Should return JSON array.

=cut

sub api_check_mailbox {
    print_test_category_header( );
    my $url = shift;
    $mech->get_ok( $url, "GET $url" );
    is ( $mech->status(), 200, "Status is 200");
    ok ( $mech->content() ne "", "Content is not empty!" ) or warn $mech->content(format=>'text');
    $mech->back();
    return 3;
}

=head1 check empty response using the API

Parameter: full URL. Should return empty page with 204 status.

=cut

sub api_check_mailbox_204 {
    print_test_category_header( );
    my $url = shift;
    $mech->get_ok( $url, "GET $url" );
    is ( $mech->status(), 204, "Status is 204");
    ok ( $mech->content() eq "", "Content is empty" ) or warn $mech->content(format=>'text');
    $mech->back();
    return 3;
}

=head1 check email using the API

Parameter: full URL. Should return email.

=cut

sub api_check_email {
    print_test_category_header( );
    my $url = shift;
    $mech->get_ok( $url, "GET $url" );
    is ( $mech->status(), 200, "Status is 200");
    ok ( $mech->content() ne "", "Content is not empty!" ) or warn $mech->content(format=>'text');
    $mech->back();
    return 3;
}

=head1 check if API returns error 400 bad request

Parameter: full URL. Should return empty response and HTTP error 400.

=cut

sub api_check_bad_request {
    print_test_category_header( );
    my $url = shift;
    ok ( $mech->get( $url ), "GET $url" );
    is ( $mech->status(), 400, "Status is 400");
    $mech->content_is( "", "Content is empty!" ) or warn $mech->content(format=>'text');
    $mech->back();
    return 3;
}

=head1 check if API returns error 403 forbidden

Parameter: full URL. Should return empty response and HTTP error 403.

=cut

sub api_check_forbidden {
    print_test_category_header( );
    my $url = shift;
    ok ( $mech->get( $url ), "GET $url" );
    is ( $mech->status(), 403, "Status is 403");
    $mech->content_is( "", "Content is empty!" ) or warn $mech->content(format=>'text');
    $mech->back();
    return 3;
}

sub negative_delete_test {
      print_test_category_header( );
      my $mailbox = $mailnesia->random_name_for_testing();
      my $id = int(rand(1_000_000));
      my $url = "$baseurl/mailbox/" . lc $mailbox . "/$id";

      $mech->post( $url, {delete => 1} );

      is ($mech->status(), 500, "POST to delete nonexistent email returned status 500, $url");

      $mech->text_contains( "Deleting message $id failed" );
      $mech->content_lacks( '<div class="alias_form"' );
      $mech->content_lacks( '<h1 class="emails">Mail for' );
      return 4;

}

sub visitor_test {
    print_test_category_header();
    my $mailbox = lc $mailnesia->random_name_for_testing();
    my $visitor_list = $config->get_formatted_visitor_list($mailbox);
    is(scalar @$visitor_list, 0, 'visitor list should be empty');

    my $url = "$baseurl/mailbox/" . $mailbox;
    $mech->get($url);
    $visitor_list = $config->get_formatted_visitor_list($mailbox);
    is(scalar @$visitor_list, 1, 'visitor list should contain 1 item');

    # one visitor is only logged once in each hour
    $mech->get($url);
    $visitor_list = $config->get_formatted_visitor_list($mailbox);
    is(scalar @$visitor_list, 1, 'visitor list should contain 1 items');

    return 3;
}

sub email_sending_and_deleting {
  print_test_category_header( );

  #starting smtp server
  if (my $pid = fork())
    {
      #parent, sending email
      print "waiting for SMTP server to start...\n";
      sleep 2;
      my $tests;
      my $wipeTest = scalar @aliases;

      while (my $alias = shift @aliases)
      {
          $tests += send_mail_test($alias,$global_mailbox,$mailnesia->random_name_for_testing())
      };

      $tests += send_mail_test($mailbox_for_api_test, $mailbox_for_api_test);
      $tests += send_mail_test($mailbox_for_api_test, $mailbox_for_api_test);

      # test disabled, feature not enabled
      #      invalid_sender_test() +

      $tests += invalid_recipient_test() +
      banned_sender_test() +
      banned_recipient_test() +
      send_complete_email_test() +
      test_url_clicker();

      # wipe $global_mailbox if there were alias tests
      if ($wipeTest) {
        $tests += wipe_mailbox_test($global_mailbox) ;
      }

      $tests += check_empty_mailbox("$baseurl/mailbox/$global_mailbox");

      kill 15, $pid ;
      waitpid ( $pid, 0 );

      return $tests;
    }
  elsif ($pid == 0)
    {
      #child, start smtp szerver
      my $server = "$project_directory/script/AnyEvent-SMTP-Server.pl";

      exec ('/usr/bin/perl', $server, '-d');
    }
  else
    {
      die "error forking\n";
    }
}

=head1 banned recipient tests

=cut

sub banned_recipient_test {
  print_test_category_header( );
  my $iterations = 2;
  my $tests = 0;

  for (1..$iterations)
    {
      # send_mail to banned mailbox
      my $banned_mailbox = $config->get_banned_mailbox();
      ok( send_mail ( $banned_mailbox, $mailnesia->random_name_for_testing() ."@". $sender_domain ) != 0, "sending email to banned mailbox $banned_mailbox fails" );

      $url = $baseurl. "/mailbox/" . $mailnesia->get_url_encoded_mailbox ( $banned_mailbox );
      $mech->get( $url );
      is ($mech->status, 403, "open a banned mailbox: GET $url" );
      $mech->text_lacks( qq{Mail for } . $banned_mailbox );
      $mech->content_contains ('<div class="alert-message error">This mailbox has been banned',
                               "page contains the banned mailbox warning" );

      $tests = rss_forbidden_tests($banned_mailbox)
        + api_forbidden_tests($banned_mailbox);
    }
  return (4 + $tests) * $iterations;

}


=head1 invalid recipient tests (containing invalid characters)

=cut

sub invalid_recipient_test {
  print_test_category_header( );
  my $invalid_mailbox = "asd^qwe|5-g";

  ok( send_mail ( $invalid_mailbox, $mailnesia->random_name_for_testing() ."@". $sender_domain ) != 0, "sending email to invalid mailbox $invalid_mailbox fails" );

  $url = $baseurl. "/mailbox/" . $mailnesia->get_url_encoded_mailbox ( $invalid_mailbox );
  $mech->get_ok( $url, "open an invalid mailbox (will show warning only): GET $url" );
  $mech->text_contains( q{Invalid characters entered! (valid: asd)} );
  $mech->text_unlike ( qr/\bnil\b/, "Text does not contain 'nil' as separate word" );
  $mech->text_unlike ( qr/�/, "Text does not contain an invalid utf8 character" );
  my $api_tests = api_check_bad_request($baseurl. "/api/mailbox/" . $mailnesia->get_url_encoded_mailbox ( $invalid_mailbox ));
  return 5 + $api_tests;
}



=head1 invalid sender tests: nonexistent domain name, SPF fails

=cut

sub invalid_sender_test {
  print_test_category_header( );

  for (qw { example.com nonexistent-domain-name.com })
    {
      my $mailbox = $mailnesia->random_name_for_testing();

      ok( send_mail ( $mailbox , $mailnesia->random_name_for_testing() ."@". $_ ) != 0, "sending email from invalid domain $_ fails" );

      $url = $baseurl. "/mailbox/" . $mailnesia->get_url_encoded_mailbox ( $mailbox );
      $mech->get_ok( $url, "open mailbox (should be empty): GET $url" );
      $mech->text_contains( qq{Mail for } . lc $mailbox );
      $mech->text_contains( qq{No e-mail message for } . lc $mailbox );
    }

  return 4*2;

}


=head1 banned_sender_test

check if senders in $config->{banned_sender_domain} are banned

=cut

sub banned_sender_test {
      print_test_category_header( );
      my $tests = 0;

      foreach (qw(proton.xen.prgmr.com mailnesia.com))
      {
        my $recipient = $mailnesia->random_name_for_testing() . '@1';
        my $sender    = $mailnesia->random_name_for_testing() . '@' . $_;

        ok( send_mail ( $recipient, $sender ) != 0, "sending email from $sender fails" );

        (my $recipient_url_encoded = $mailnesia->get_url_encoded_mailbox ($recipient)) =~ s/@.*//; # do not use @ in URL

        $url = $baseurl. "/mailbox/$recipient_url_encoded";
        $mech->get_ok( $url, "GET $url" );

        $mech->text_contains( 'No e-mail message for' );
        $mech->text_lacks( "Mail for ". lc $recipient );

        $tests += 4;
      }

      return $tests;
}


=head1 send_mail_test

$send_to: recipient's email address
$check_here: the mailbox name where the email should be delivered
$from: sender's email address.  swaks default if not provided.

=cut

sub send_mail_test {
      print_test_category_header( );
      my ($send_to, $check_here, $from) = @_;

      my $tests = 2;

      ok ( send_mail($send_to,$from . "@" . $sender_domain ) == 0, "email sending to $send_to" );

      my $check_here_url_encoded = $mailnesia->get_url_encoded_mailbox ($check_here);

      $url = $baseurl. "/mailbox/$check_here_url_encoded";
      $mech->get_ok( $url, "GET $url" );
      $tests += check_mailbox_header( $check_here );

      $mech->text_lacks( 'No e-mail message for' );
      my $lc_check_here_url_encoded = $mailnesia->get_url_encoded_mailbox (lc $check_here);
      my $mail_link_regex = qr{/mailbox/$lc_check_here_url_encoded/\d+};
      $mech->content_like ($mail_link_regex, "mailbox view contains a link to open email");
      # also get mailbox using API
      $tests += api_check_mailbox($baseurl. "/api/mailbox/$check_here_url_encoded");
      if ( ok ( my $first_email = $mech->find_link ( url_regex => $mail_link_regex ),
                'find first email' ) )
      {
          if ( $mech->get_ok ( $first_email, "open first email: " . $first_email->url() ) )
          {
              $tests += check_email_header();
              $mech->back;
          }

          $tests++;
          # also get email using API
          $email_id = $1 if $first_email->url() =~ m^/(\d+)$^;
          ok ($email_id, "Found ID of first email on page");
          $tests += 1 + api_check_email($baseurl. "/api/mailbox/$check_here_url_encoded/$email_id");

          $tests += api_check_mailbox($baseurl. "/api/mailbox/$check_here_url_encoded?newerthan=1");
          $tests += api_check_mailbox_204($baseurl. "/api/mailbox/$check_here_url_encoded?newerthan=9999999");
          $tests += api_check_mailbox($baseurl. "/api/mailbox/$check_here_url_encoded?page=5");
      }

      $tests += 3 + rss_tests($check_here);

      my $alias_fail = $mailnesia->random_name_for_testing();

      $mech->post("$baseurl/settings/$alias_fail/alias/set",
                          {
                              alias=>$check_here
                          }
                      );

      is ( $mech->status(),
           409,
           "try to set random alias in not empty mailbox: $check_here => $alias_fail, status 409" );


      $mech->text_lacks ("Alias ". lc $alias_fail . " assigned to mailbox ". lc $check_here . "!", "lacks successful response" );
      $mech->text_contains ("Alias assignment error! Can only use empty mailbox for an alias name!" );
      $mech->back();            # go back from error page so next test can operate on page

      return 3+$tests;

}


=head1 test_url_clicker

Send a mail with a URL that triggers the clicker, check that it is "clicked" by listening on
port 5555 on localhost and checking a connection.

=cut

sub test_url_clicker {
    print_test_category_header( );
    my $send_to = $mailnesia->random_name_for_testing();
    my $check_here_url_encoded = $mailnesia->get_url_encoded_mailbox ($send_to);
    my $hostname = '127.0.0.1';
    my $port = 5555;
    my $body = "This is a test mailing with a URL: http://$hostname:$port/test-activation";

    #wait for the URL clicker to connect
    ok(my $sock = IO::Socket->new(
        Domain => AF_INET,
        Blocking => 1,
        Listen => 1,
        Timeout => 3,
        Proto => 'tcp',
        LocalHost => $hostname,
        LocalPort => $port,
    ), "Opening port for listening") || return 1;

    ok(send_mail($send_to, "test\@$sender_domain", undef, $body) == 0, "sending test mail with URL to $send_to" );
    ok($sock->accept(), 'URL clicker connected');

    return 3;
}


=head1 send_complete_email_test

send complete emails in project directory/test-email/*

=cut

sub send_complete_email_test {
        print_test_category_header( );
        my $send_to = $mailnesia->random_name_for_testing();
        my $tests = 0;
        my $check_here_url_encoded = $mailnesia->get_url_encoded_mailbox ($send_to);

        for (glob $project_directory . "/test-email/*")
        {
            ok ( send_mail($send_to,"test\@$sender_domain", $_) == 0, "sending $_ to $send_to" );

            $url = $baseurl. "/mailbox/$check_here_url_encoded";

            # disable HTML validation, since the page contains the email which can be invalid
            my $old_status = $mech->autolint (0);
            $mech->get_ok( $url, "GET $url" );

            $mech->text_lacks( 'No e-mail message for' );
            $mech->content_lacks( '<div class="alias_form"' );
            $mech->text_contains( "Mail for ". lc $send_to );
            # TODO: also get mailbox using API
            $tests += rss_tests($send_to);
            $tests += api_check_email($baseurl. "/api/mailbox/$check_here_url_encoded");


            my $lc_check_here_url_encoded = $mailnesia->get_url_encoded_mailbox ( lc $send_to );
            my $mail_link_regex = qr{/mailbox/$lc_check_here_url_encoded/\d+};
            $mech->content_like ($mail_link_regex, "mailbox view contains a link to open email");

            if ( ok ( my $first_email = $mech->find_link ( url_regex => $mail_link_regex ),
                      'find first email' ) )
            {
                $mech->get_ok ( $first_email, "open first email: " . $first_email->url() );

                # FIXME: test somehow that an email is displayed on the page
                $mech->text_lacks( 'No e-mail message for' );
                $mech->content_lacks( '<div class="alias_form"' );
                $tests += 2;

                # turn validation back on (this only works if the whitelist is set up in alias_positive_tests)
                $mech->autolint($old_status);
                # also get email using API
                my $email_id = $1 if $first_email->url() =~ m^/(\d+)$^;
                ok ($email_id, "Found ID of first email on page");
                $tests += 1 + api_check_email($baseurl. "/api/mailbox/$lc_check_here_url_encoded/$email_id");


                #test original email view (raw)
                if ( $mech->follow_link_ok( {text_regex => qr/view original/i }, "open 'view original' link on current page" ) )
                {
                    is ( $mech->content_type(), 'text/plain', 'view original link returns text/plain content');
                    $tests++;
                    # verify Received: header
                    $mech->content_like(qr/Received: FROM example.com \[ [\d:\.]+ \] BY mailnesia.com ; [a-zA-Z]{3}, \d\d [a-zA-Z]{3} \d{4} \d\d:\d\d:\d\d \+\d{4}/);
                    $tests++;
                    $mech->back();
                }

                # also get raw email using API
                $tests += api_check_email($baseurl. "/api/mailbox/$lc_check_here_url_encoded/$email_id/raw");

                #test URL clicker button
                if ( $mech->follow_link_ok( {text_regex => qr/test URL clicker/i }, "open 'test URL clicker' link on current page" ) )
                {
                    $mech->content_like( qr'^<div class="alert-message block-message info"><h2>Clicked links:</h2><ul>', "'test URL clicker' link returns 'clicked links'");
                    $tests++;
                    $mech->back();
                }

                # delete the sent email
                if ($mech->post_ok(
                        $mech->uri(), {
                                delete => 1
                            },
                        "try to delete current email"
                    )
                )
                {
                    $mech->text_like   ( qr"Deleted message \d+" );
                    $mech->text_unlike ( qr"Deleting message \d+ failed" );
                    $tests+=2;
                }

                $tests += 4;

                $tests += api_check_empty_mailbox($baseurl. "/api/mailbox/$lc_check_here_url_encoded");
            }

            $tests += 7;

        }

        return $tests;

    }

=head1 send_mail

$send_to: recipient's email address
$from: sender's email address.  swaks default if not provided.
$data: filename of a complete email message to send
$body: string to to use as email body

=cut

sub send_mail {
    my ($send_to, $from, $data, $body) = @_;
    my @from = ( "--from", $from ) if $from;
    my @data = ( "--data", "@" . $data ) if $data;
    my @body = ( "--body", $body ) if $body;

    system (
        'swaks',
        '--suppress-data',
        '--server', 'localhost:2525',
        '--ehlo', 'example.com',
        '--to', qq{$send_to} . '@a',
        @from,
        @data,
        @body,
    );
}

sub delete_mail_test {
      print_test_category_header( );
      my $mailbox = shift;
      my $lower_mailbox = $mailnesia->get_url_encoded_mailbox ( lc $mailbox );
      my $email_link_regex = qr{$baseurl/mailbox/$lower_mailbox/(\d+)};

      if ($mech->follow_link_ok( {url_regex => $email_link_regex }, "open an email to delete" ))
      {
        if ( ok ( $mech->uri() =~ $email_link_regex, "Find email ID in current URL" ) )
        {

          my $id = $1;

          $mech->post_ok(
                $mech->uri(), {
                      delete  => 1
                     },
                "try to delete current email"
               );

          $mech->text_contains ( "Deleted message $id" );
          $mech->text_lacks    ( "Deleting message $id failed" );

          return 5;
        }
      }
      else
      {
        return 1;
      }
    }



sub wipe_mailbox_test {
      print_test_category_header( );
      my $mailbox = shift;
      my $lower_mailbox = lc $mailbox ;
      my $lower_esc_mailbox = $mailnesia->get_url_encoded_mailbox ( $lower_mailbox );

      $mech->post_ok(
            $baseurl . qq{/mailbox/$lower_esc_mailbox}, {
                  delete  => 1
                 },
            "try to wipe mailbox $mailbox"
           );

      $mech->text_contains ( "Deleted all emails in $lower_mailbox" );
      $mech->text_lacks    ( "Deleting all emails in $lower_mailbox failed" );

      return 3;
    }



sub restoration {
        my $tests = 0;

        print_test_category_header( );
        my $mailbox_url_encoded = $mailnesia->get_url_encoded_mailbox ( lc $global_mailbox );
        my $url = "$baseurl/settings/$global_mailbox";

        if (@aliases)
        {

            while ( my $alias = shift @aliases )
            {
                if ( $mech->post_ok("$baseurl/settings/$mailbox_url_encoded/alias/remove",
                                    {
                                        remove_alias=>$alias
                                    },
                                    "remove alias with POST request, $global_mailbox => $alias"
                                )
                 )
                {
                    $mech->text_contains ("Alias ". lc $alias . " removed from mailbox ". lc $global_mailbox . "!", "successful response" );
                    $tests++;
                }
                $tests++;
            }

            $mech->get_ok($url);

            $mech->content_contains( '<div class="alias_form"', "alias form still present" );

            #no aliases set
            $mech->content_unlike(qr{name="remove_alias" value="(.{1,30})"},"page contains no alias");
            $tests+=3;


        }

        ok( $config->unban_mailbox($mailbox_to_ban), "mailbox $mailbox_to_ban unbanned" );
        $tests++;

        return $tests;

    }

sub arrayref_to_json {
    my $array = shift;
    my $json = join '","', @$array;

    return qq{["$json"]};
}

=head1 alias tests via the api

set some aliases on a random mailbox, modify and delete them

=cut

sub api_alias_tests {
    print_test_category_header( );
    my $mailbox = $mailnesia->random_name_for_testing();
    my $alias1 = $mailnesia->random_name_for_testing();
    my $alias2 = $mailnesia->random_name_for_testing();
    my $tests = 0;
    $tests += test_empty_alias_list($mailbox);
    $tests += add_alias_to_mailbox($mailbox, $alias1);
    $tests += test_alias_list($mailbox, [$alias1]);
    $tests += add_alias_to_mailbox($mailbox, $alias2);
    $tests += test_alias_list($mailbox, [$alias1, $alias2]);

    my $alias3 = $mailnesia->random_name_for_testing();
    $tests += modify_alias($mailbox, $alias2, $alias3);
    $tests += test_alias_list($mailbox, [$alias1, $alias3]);

    $tests += delete_alias($mailbox, $alias3);
    $tests += test_alias_list($mailbox, [$alias1]);

    $tests += delete_alias($mailbox, $alias1);
    $tests += test_empty_alias_list($mailbox);

    return $tests;
}

sub test_empty_alias_list {
    my $mailbox = shift;
    my $url = $baseurl . "/api/alias/$mailbox";
    $mech->get_ok( $url, "GET $url" );
    $mech->header_is('Content-Type', 'application/json');
    $mech->content_is( '[]' ) or warn $mech->content();
    return 3;
}

sub add_alias_to_mailbox {
    my $mailbox = shift;
    my $alias = shift;
    my $url = $baseurl . "/api/alias/$mailbox/$alias";
    $mech->post_ok( $url, "POST $url" );
    $mech->header_is('Content-Type', 'application/json');
    $mech->content_is( lc "\"$alias\"" ) or warn $mech->content();
    return 3;
}

sub test_alias_list {
    my $mailbox = shift;
    my $alias_list = shift;
    my $url = $baseurl . "/api/alias/$mailbox";
    $mech->get_ok( $url, "GET $url" );
    $mech->header_is('Content-Type', 'application/json');
    $mech->content_is( lc arrayref_to_json($alias_list) ) or warn $mech->content();
    return 3;
}

sub modify_alias {
    my $mailbox = shift;
    my $alias = shift;
    my $new_alias = shift;
    my $url = $baseurl . "/api/alias/$mailbox/$alias/$new_alias";
    $mech->put_ok( $url, "PUT $url" );
    $mech->header_is('Content-Type', 'application/json');
    my $result = $mech->content;
    my $expected = lc "\"$new_alias\"";
    is_deeply(sort $expected, sort $result, 'check alias list') or warn $mech->content();
    return 3;
}

sub delete_alias {
    my $mailbox = shift;
    my $alias = shift;
    my $url = $baseurl . "/api/alias/$mailbox/$alias";
    $mech->delete_ok( $url, "DELETE $url" );
    $mech->header_is('Content-Type', 'text/plain;charset=UTF-8');
    $mech->content_is( "" ) or warn $mech->content();
    return 3;
}

=head1 mailbox delete tests via api
Delete all mail that was sent to $mailbox_for_api_test
=cut

sub mailbox_delete_tests_via_api {
    my $tests = 0;
    $tests += delete_mail($mailbox_for_api_test, $email_id);
    $tests += delete_mailbox($mailbox_for_api_test);
    return $tests;
}

sub delete_mail {
    my $mailbox = shift;
    my $id = shift;
    my $url = $baseurl . "/api/mailbox/$mailbox/$id";
    $mech->delete_ok( $url, "DELETE $url" );
    $mech->header_is('Content-Type', 'text/plain;charset=UTF-8');
    $mech->content_is( "" ) or warn $mech->content();
    return 3;
}

sub delete_mailbox {
    my $mailbox = shift;
    my $url = $baseurl . "/api/mailbox/$mailbox";
    $mech->delete_ok( $url, "DELETE $url" );
    $mech->header_is('Content-Type', 'text/plain;charset=UTF-8');
    $mech->content_is( "" ) or warn $mech->content();
    return 3;
}

####### end tests ########


sub print_test_category_header {
      print "\n",
      "=" x 40,
      "\n",
      (caller(1))[3],
      "\n",
      "=" x 40,
      "\n";
}



sub print_testcase_header {
      print "\n",
      "=" x 20,
      $_[0],
      "=" x 20,
      "\n";
}




=head1 url_encoded_mailbox => mailbox

=cut

sub get_mailbox
{
  my $mailbox = shift;
  $mailbox =~ s/%2B/\+/g;
  return $mailbox;
}




=head1 check_email_header

check presence of email header in email page: Date From To Subject

=cut

sub check_email_header
{
    $mech->content_contains ( qq!<div id="delete_email">!, "page contains 3 buttons" );
    $mech->content_like     ( qr!<table .*class="header"!, "page contains email table");
    $mech->text_like        ( qr{Date *From *To *Subject}, "page contains email table header: Date From To Subject" );
    $mech->content_contains ( qq!<div class="emails">!, "page contains top email container div" );

    return 4;
}


=head1 check_mailbox_header

check presence of email header in mailbox page: Date From To Subject

=cut

sub check_mailbox_header
{
    my $mailbox = shift;

    $mech->text_contains( qq{Mail for } . lc $mailbox );
    $mech->content_like ( qr!<table .*class="email"!, "page contains email table");
    $mech->text_like    ( qr{Date *From *To *Subject}, "page contains email table header: Date From To Subject" );

    return 3;
}

=head1 check_visitors_header

check presence of visitors header in visitors page: Date, IP, User Agent

=cut

sub check_visitors_header
{
    my $mailbox = shift;

    $mech->content_like ( qr!<table .*class="email"!, "page contains visitors table");
    $mech->text_like    ( qr{Date *IP *User Agent}, "page contains visitors table header: Date, IP, User Agent" );

    return 2;
}

=head1 done_testing

execute tests

=cut

done_testing(
        check_config() +
        visitor_test() +
        mailbox_tests() +
        alias_positive_tests() +
        alias_negative_tests() +
        email_sending_and_deleting() +
        random_mailbox() +
        webpage_tests() +
        negative_delete_test() +
        api_alias_tests() +
        mailbox_delete_tests_via_api() +
        mailbox_settings_page_tests() +
        restoration()
    );
