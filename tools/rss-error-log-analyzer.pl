#!/usr/bin/perl

use strict;

=head1 NAME

rss-error-log-analyzer - List rejected users due to too many rss opened.

=head1 DESCRIPTION

rss-error-log-analyzer.pl < mailnesia.error.log

=cut

my ( %cnt, %dns );
# cnt: rdns -> count
# dns: rdns -> ip

while (<>)
{
    my ($ip,$count,$rdns) = m/too many RSS opened: ((?:\d+\.\d+\.\d+\.\d+)|(?:[a-zA-Z0-9:]+)), [^ ]+, (\d+), rDNS: ([^ ]*)/;
    next unless $ip and $count;
    $cnt{$ip} = $count if $count > $cnt{$ip};
    $dns{$ip} = $rdns;
}


foreach my $key (sort {$cnt{$b} <=> $cnt{$a} }
                 keys %cnt)
{
    printf ("%5d %s %s\n", $cnt{$key}, $key, $dns{$key});
}
