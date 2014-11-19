#!/usr/bin/perl -w

use FindBin;
use lib "$FindBin::Bin/../lib/";

use strict;
use Mailnesia::Config;

=head1 NAME

redis - add/remove data to redis or check existence

=head1 SYNOPSIS

Example usage:

comm -23 banned_IPs.txt tor_IPs.txt | fgrep -v 162.250.144.109 | /home/peter/projects/mailnesia.com/tools/redis.pl ban_ip

curl --silent --limit-rate 50k 'http://www.stopforumspam.com/downloads/listed_email_1.zip' | funzip | perl -ne 'print "$1\n" if m/^([^\@]+)\@mailnesia\.com$/i' | /home/peter/projects/mailnesia.com/tools/redis.pl ban_mailbox

=head1 DESCRIPTION

parameters: [ban_mailbox|unban_mailbox|is_mailbox_banned|ban_ip|unban_ip|is_ip_banned]

Data to be added/checked comes from STDIN.

=cut



my $config = Mailnesia::Config->new();


if ($ARGV[0] eq 'ban_mailbox')
{
    while (<STDIN>)
    {
        chomp;
        $config->ban_mailbox($_) or warn "failed to ban mailbox $_\n";
    }
}

elsif ($ARGV[0] eq 'unban_mailbox')
{
    while (<STDIN>)
    {
        chomp;
        $config->unban_mailbox($_) or warn "failed to unban mailbox $_\n";
    }
}

elsif ($ARGV[0] eq 'is_mailbox_banned')
{
    while (<STDIN>)
    {
        chomp;
        if ( $config->is_mailbox_banned($_) )
        {
            print "banned\n"
        }
        else
        {
            print "not banned\n"
        }
    }
}

elsif ($ARGV[0] eq 'ban_ip')
{
    while (<STDIN>)
    {
        chomp;
        $config->ban_ip($_) or warn "failed to ban ip $_\n";
    }
}

elsif ($ARGV[0] eq 'unban_ip')
{
    while (<STDIN>)
    {
        chomp;
        $config->unban_ip($_) or warn "failed to unban ip $_\n";
    }
}

elsif ($ARGV[0] eq 'is_ip_banned')
{
    while (<STDIN>)
    {
        chomp;
        if ( $config->is_ip_banned($_) )
        {
            print "banned\n"
        }
        else
        {
            print "not banned\n"
        }
    }
}

else
{
    die "supported commands: ban_mailbox, unban_mailbox, is_mailbox_banned, ban_ip, unban_ip, is_ip_banned\n"
}
