#!/usr/bin/perl

use strict;
use Test::More ;
use Test::WWW::Mechanize;
use Sys::Hostname;
use HTML::Lint;
use DBI;
use XML::LibXML;
use Redis;

use FindBin;
use lib "$FindBin::Bin/../lib/";

use Mailnesia;
use Mailnesia::SQL;
use Mailnesia::Config;
use utf8;

########## redefine ##########################

{
  package HTML::Lint::Parser;

  *HTML::Lint::Parser::_text = sub  {
    my ($self,$text) = @_;

    while ( $text =~ /&(?![#0-9a-z])/ig ) {
      $self->gripe( 'text-use-entity', char => '&', entity => '&amp;' );
    }

    # while ( $text =~ /([^\x09\x0A\x0D -~])/g ) {
    #   my $bad = $1;
    #   $self->gripe(
    #                'text-use-entity',
    #                char => sprintf( '\x%02lX', ord($bad) ),
    #                entity => $char2entity{ $bad },
    #               );
    # }

    if ( not $self->{_unclosed_entities_regex} ) {
      # Get Gisle's list
      my @entities = sort keys %HTML::Entities::entity2char;

      # Strip his semicolons
      s/;$// for @entities;

      # Build a regex
      my $entities = join( '|', @entities );
      $self->{_unclosed_entities_regex} = qr/&($entities)(?!;)/;

      $self->{_entity_lookup} = { map { ($_,1) } @entities };
    }

    while ( $text =~ m/$self->{_unclosed_entities_regex}/g ) {
      my $ent = $1;
      $self->gripe( 'text-unclosed-entity', entity => "&$ent;" );
    }

    while ( $text =~ m/&([^;]+);/g ) {
      my $ent = $1;

      # Numeric entities are fine, if they're not too large.
      if ( $ent =~ /^#(\d+)$/ ) {
        if ( $1 > 65536 ) {
          $self->gripe( 'text-invalid-entity', entity => "&$ent;" );
        }
        next;
      }

      # Hex entities are fine, if they're not too large.
      if ( $ent =~ /^#x([\dA-F]+)$/i ) {
        if ( length($1) > 4 ) {
          $self->gripe( 'text-invalid-entity', entity => "&$ent;" );
        }
        next;
      }

      # If it's not a numeric entity, then check the lookup table.
      if ( !exists $self->{_entity_lookup}{$ent} ) {
        $self->gripe( 'text-unknown-entity', entity => "&$ent;" );
      }
    }

    return;
  }

}

########## /redefine ##########################

my $number_of_aliases = 50;      # test this number of aliases
my @aliases;
my @alias_restoration;
my $config = Mailnesia::Config->new;
my $mailnesia = Mailnesia->new();
my $global_mailbox = $mailnesia->random_name_for_testing();
my $sender_domain = q{gmail.com};
my $project_directory = $mailnesia->get_project_directory();
my $baseurl = $mailnesia->{devel} ? "http://" . $config->{siteurl_devel} : "http://" . $config->{siteurl};
my @languages = qw!/hu /it /lv /fi /pt /de /ru /pl /!;
my $mech = Test::WWW::Mechanize->new(
                                     autolint => HTML::Lint->new( only_types => HTML::Lint::Error::STRUCTURE ), # FIXME: reports unknown element <time>
                                     cookie_jar => undef
                                    );

my ($url,$category);


my $parser = XML::LibXML->new();

my $redis = Redis->new(
      encoding => undef,
      sock     => '/var/run/redis/redis.sock'
    );


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

      my $banned_mailbox = $config->get_banned_mailbox();
      ok( $banned_mailbox,
          "Banned mailbox defined:          $banned_mailbox");

      ( my $piddir = $config->{pidfile} ) =~ s!/[^/]+$!!;
      ok( -d $piddir, "piddir exists: {$piddir}" );

      return 10;
}

sub webpage_tests {
      $category = "webpage tests";
      print_test_category_header($category);

      for (@languages)
      {
        $url = $baseurl.$_;

        print_testcase_header($category . " " . $_);
        $mech->get_ok( $url, "GET $url" );
        $mech->content_lacks( 'service down' );
        $mech->text_contains( 'mailnesia' );
        $mech->content_lacks ('<div class="alert-message', 'no alert message on page');
        $mech->text_unlike ( qr/(\bnil\b)|�/, "Text does not contain 'nil' as separate word or an invalid utf8 character" );

        $mech->stuff_inputs;    # this is not counted as a test

        $mech->lacks_uncapped_inputs('forms have maxlength');

      }
      return scalar @languages * 6;

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

      $url = $baseurl . "/mailbox/,a";

      if ( $mech->get_ok( $url, "test invalid mailbox: $url" ) )
      {
          $mech->title_like( qr{^@ mailnesia}i, "title does not contain the invalid mailbox");
          $mech->content_unlike( qr{,a}, "page does not contain the invalid mailbox");
          $tests+=2;
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
  print "Checking RSS for $mailbox\n";
  my $tests = 0;
  my $url = $baseurl . "/rss/" . $mailnesia->get_url_encoded_mailbox ( $mailbox );

  if ( $mech->follow_link_ok( {url_abs => $url}, "follow RSS link on current page" ) )
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
      $mech->content_contains ('</link><title>' . lc $mailbox, "RSS title contains " . lc $mailbox);
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

=head1 check if mailbox is empty

=cut

sub check_empty_mailbox {
      print_test_category_header( );
      my $url = shift;
      $mech->get_ok( $url, "GET $url" );
      $mech->text_contains( 'No e-mail message for' ) or warn $mech->content(format=>'text');
      return 2;

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

sub email_sending_and_deleting {
  print_test_category_header( );

  #starting smtp server
  if (my $pid = fork())
    {
      #parent, sending email
      print "waiting for SMTP server to start...\n";
      sleep 2;
      my $tests;

      while (my $alias = shift @aliases)
      {
          $tests += send_mail_test($alias,$global_mailbox,$mailnesia->random_name_for_testing())
      };



      # test disabled, feature not enabled
      #      invalid_sender_test() +

      $tests += invalid_recipient_test() +
      banned_sender_test() +
      banned_recipient_test() +
      send_complete_email_test() ;

      # wipe $global_mailbox
      $tests += wipe_mailbox_test($global_mailbox) ;

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
  my $tests;

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

      $tests = rss_forbidden_tests($banned_mailbox);
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
  return 5;

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

      if ( ok ( my $first_email = $mech->find_link ( url_regex => $mail_link_regex ),
                'find first email' ) )
      {
          if ( $mech->get_ok ( $first_email, "open first email: " . $first_email->url() ) )
          {
              $tests += check_email_header();
              $mech->back;
          }

          $tests++;
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

            $tests += rss_tests($send_to);

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

                # turn validation back on
                $mech->autolint($old_status);

                #test original email view (raw)
                if ( $mech->follow_link_ok( {text_regex => qr/view original/i }, "open 'view original' link on current page" ) )
                {
                    is ( $mech->content_type(), 'text/plain', 'view original link returns text/plain content');
                    $tests++;
                    $mech->back();
                }

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
            }

            $tests += 7;

        }

        return $tests;

    }

=head1 send_mail

$send_to: recipient's email address
$from: sender's email address.  swaks default if not provided.
$data: filename of a complete email message to send

=cut

sub send_mail {
      my ($send_to, $from, $data) = @_;
      my @from = ( "--from", $from ) if $from;
      my @data = ( "--data", $data ) if $data;

      system ('swaks', '--suppress-data', '--server', 'localhost:2525', '--to', qq{$send_to} . '@a', @from, @data );
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

        return $tests;

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


=head1 done_testing

execute tests

=cut

done_testing(
        check_config() +

        mailbox_tests() +
        alias_positive_tests() +
        alias_negative_tests() +
        email_sending_and_deleting() +
        random_mailbox() +
        webpage_tests() +
        negative_delete_test() +

        restoration()
    );
