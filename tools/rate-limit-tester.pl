#!/usr/bin/perl -w

use strict;
use WWW::Mechanize;
use AnyEvent;

=head1 NAME

rate-limit-tester - some kind of rate limit tester

=head1 SYNOPSIS

?

=head1 DESCRIPTION

?

=cut

my ($counter,$ok,$nok) = 0;

sub stats
{
    printf "%0.1f%% (%d/%d)\n", 100 * $ok / ($counter||1), $ok, $counter ;
}

my $sigint  = AnyEvent->signal (signal => "INT",  cb => sub
                                {
                                    stats();
                                    exit;
                                }
                            );


my $mech = WWW::Mechanize->new(
        autocheck => 0
    );

my $url = 'http://where/the/website/is/running/mailbox/ratelimit-test';


my $loop = AnyEvent->idle
(
    cb=>sub{
            $mech->get($url) ;
            if ($mech->success())
            {
                $ok++;
            }
            else
            {
                sleep 1;
                stats();
            }
            $counter++;

        }
);



# my $stat_timer = AnyEvent->timer
# (
#   after => 2,
#   interval => 1,
#   cb	 => stats()
#  );

AnyEvent->condvar->recv;


