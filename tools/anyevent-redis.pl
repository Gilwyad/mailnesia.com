#!/usr/bin/perl -w

use strict;
use AnyEvent::Redis;

=head1 NAME

anyevent-redis - test AnyEvent::Redis

=head1 SYNOPSIS

add data to redis set or check existence

=head1 DESCRIPTION

parameters: [sadd|ismember] [database name]

Adds data to redis set (sadd) or checks existence (ismember).  Data to
be added/checked comes from STDIN.

=cut

# my $exit_timer = AnyEvent->timer
#   (
#    after    => 1,
#    cb	    => sub { exit() }
#   );

die "command? database?\n" unless $ARGV[0] and $ARGV[1];

my $redis     = AnyEvent::Redis->new(
  host        => '127.0.0.1',
  port        => 6379,
  encoding    => undef,
  on_error    => sub { warn @_ },
  on_cleanup  => sub { warn "Connection closed: @_" },
);

if ($ARGV[0] eq 'sadd')
  {
    while (<STDIN>)
      {
        chomp;
        my $data = $_;
        $redis->sadd( $ARGV[1], $data, sub
                        {
                          my $msg = shift;
                          unless ($msg)
                            {
                              print "error adding $data!\n";
                            }
                        }
                      );
      }
  }
elsif ($ARGV[0] eq 'sismember')
  {
    while (<STDIN>)
      {
        chomp;
        my $check = $_;
        $redis->sismember( $ARGV[1], $check, sub
                             {
                               my $msg = shift;
                               unless ($msg)
                                 {
                                   print "$check does not exist!\n";
                                 }
                             }
                           );
      }
  }
else
  {
    die "only command sadd and sismember is supported\n"
  }




AnyEvent->loop;
