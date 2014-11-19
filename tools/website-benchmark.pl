#!/usr/bin/perl

use strict;
use DBI;
use Time::HiRes qw( gettimeofday tv_interval);

use Mailnesia;
use Mailnesia::SQL;
use Mailnesia::Config;
use WWW::Mechanize;

#use Data::Dumper;

my ($options, $count, $test);

if (scalar @ARGV == 3)
  {
    ($options, $count, $test) = @ARGV
  }
elsif (scalar @ARGV == 2)
  {
    ($count, $test) = @ARGV
  }

die "[--nodelay|-n] count? [emaillist|emailbody|rss]\n" unless $count =~ m/\d+/ ;




$SIG{INT} = \&stat;
my $table = 'emails';
my $dbh   = Mailnesia::SQL->connect() or die "connection error\n";
my $config = Mailnesia::Config->new;
my $baseurl = $Mailnesia::devel ? "http://" . $config->{siteurl_devel} : "http://" . $config->{siteurl};
my ( @slow_query_time, @fast_query_time );
my $t0;
my ($n, $slow_query, $fast_query);
my $delay = $options =~ m/--nodelay|-n/i ? 0 : 1;
my $mech = WWW::Mechanize->new(
  cookie_jar => undef
);

if ($test eq 'emailbody')
  {
    emailbody_test();
  }
elsif ($test eq 'emaillist')
  {
    emaillist_test();
  }
elsif ($test eq 'rss')
  {
    rss_test();
  }
else
  {
    die "no such test/table\n";
  }

&stat;


sub stat(){
      print "\n";

      my $length = scalar @slow_query_time;
      if ($length)
        {
          my $sum = 0;
          $sum += $_ for @slow_query_time;
          printf "slow query average: %0.3f sec\n", $sum / $length;
          printf "slow queries: %0.2f %%\n", 100 * $slow_query / $n;
        }
      else
        {
          warn "no slow queries!\n"
        }

      print "\n";

      $length = scalar @fast_query_time;
      if ($length)
        {
          my $sum = 0;
          $sum += $_ for @fast_query_time;
          printf "fast query average: %0.3f sec\n", $sum / $length;
          printf "fast queries: %0.2f %%\n", 100 * $fast_query / $n;
        }
      else
        {
          warn "no fast queries!\n"
        }
      exit;
    }

sub emailbody_test {


      my $min_id = 0;
      my $sql = "select id from $table order by id asc limit 1";
      my $query = $dbh->prepare ($sql);
      $query->execute or die "error $!\n";
      $query->bind_columns(\$min_id);
      $query->fetch;


      my $max_id = 0;
      $sql = "select id from $table order by id desc limit 1";
      $query = $dbh->prepare ($sql);
      $query->execute;
      $query->bind_columns(\$max_id);
      $query->fetch;

      print "min id: $min_id, max id: $max_id\n\n";

      my $url = "$baseurl/mailbox";

      while (1)
        {

          last if $count == $n;

          my $id = $min_id + int( rand($max_id - $min_id) ); # min < id < max
          $t0 = [gettimeofday];

          $mech->get("$url/$id");

          my $time = tv_interval ($t0);
          $n++;
          if ($time > 0.02)
            {
              $slow_query++;
              push @slow_query_time, $time;
              printf "SLOW: %5d / %5d = %6.2f %% - id: %15d, %0.3f sec\n", $slow_query, $n, 100*$slow_query/$n, $id, $time;
            }
          else
            {
              $fast_query++;
              push @fast_query_time, $time;
              printf "FAST: %5d / %5d = %6.2f %% - id: %15d, %0.3f sec\n", $fast_query, $n, 100*$fast_query/$n, $id, $time if $delay;
            }
          sleep $delay;

        }
    }


sub emaillist_test {
      my @mailboxes;
      my $sql = "select distinct mailbox from $table";
      my $query = $dbh->prepare ($sql);
      $query->execute or die "error $!\n";
      my $tbl_ary_ref = $query->fetchall_arrayref();
      my $size = scalar ( @$tbl_ary_ref );

      while (1)
        {

          $n++;
          my $mailbox =  $tbl_ary_ref->[ rand($size) ]->[0];

          $t0 = [gettimeofday];

          $mech->get("$baseurl/mailbox/$mailbox");

          my $time = tv_interval ($t0);
          if ($time > 0.02)
            {
              $slow_query++;
              push @slow_query_time, $time;
              printf "SLOW: %5d / %5d = %6.2f %% - mailbox: %30s, %0.3f sec\n", $slow_query, $n, 100*$slow_query/$n, $mailbox, $time;
            }
          else
            {
              $fast_query++;
              push @fast_query_time, $time;
              printf "FAST: %5d / %5d = %6.2f %% - mailbox: %30s, %0.3f sec\n", $fast_query, $n, 100*$fast_query/$n, $mailbox, $time if $delay;
            }
          last if $count == $n;
          sleep $delay;
        }


}


sub rss_test {
      my @mailboxes;
      my $sql = "select distinct mailbox from $table";
      my $query = $dbh->prepare ($sql);
      $query->execute or die "error $!\n";
      my $tbl_ary_ref = $query->fetchall_arrayref();
      my $size = scalar ( @$tbl_ary_ref );

      while (1)
        {

          $n++;
          my $mailbox =  $tbl_ary_ref->[ rand($size) ]->[0];

          $t0 = [gettimeofday];

          $mech->get("$baseurl/rss/$mailbox");

          my $time = tv_interval ($t0);
          if ($time > 0.02)
            {
              $slow_query++;
              push @slow_query_time, $time;
              printf "SLOW: %5d / %5d = %6.2f %% - mailbox: %30s, %0.3f sec\n", $slow_query, $n, 100*$slow_query/$n, $mailbox, $time;
            }
          else
            {
              $fast_query++;
              push @fast_query_time, $time;
              printf "FAST: %5d / %5d = %6.2f %% - mailbox: %30s, %0.3f sec\n", $fast_query, $n, 100*$fast_query/$n, $mailbox, $time if $delay;
            }
          last if $count == $n;
          sleep $delay;
        }


}
