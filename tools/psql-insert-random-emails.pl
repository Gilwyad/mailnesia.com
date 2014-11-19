#!/usr/bin/perl -w

use common::sense;
use Text::Greeking;
use AnyEvent;
use DBI;
use Compress::Snappy;
use DBD::Pg qw(:pg_types);

$/ = "\r\n";                    # DOS encoded file

=head1 NAME

psql-insert-random-emails - fill the database with random data

=head1 DESCRIPTION

Insert random emails into the PostgreSQL table for testing purposes.
Requirement: debian package rig (random identity generator).

=cut



my $lastname_db = '/usr/share/rig/lnames.idx';
my $malename_db = '/usr/share/rig/mnames.idx';
my $femalename_db = '/usr/share/rig/fnames.idx';

my (@lastnames, @firstnames);

open LN, "<", $lastname_db;
open MN, "<", $malename_db;
open FN, "<", $femalename_db;


chomp (my @lastnames = <LN>);
my @firstnames = <FN> , <MN>;
chomp @firstnames;


my $lastname_count  = scalar @lastnames;
my $firstname_count = scalar @firstnames;

my $email_body = Text::Greeking->new;
$email_body->paragraphs(5,1000); # min/max paragraph
$email_body->sentences(3,8);     # min/max  sentences
$email_body->words(4,16);        # min max words

my $subject = Text::Greeking->new;
$subject->paragraphs(1,1);
$subject->sentences(1,2);
$subject->words(3,6);

my $email;
my $count=0;
my $seconds=0;
my $count_per_sec=0;
my $prev_count;

my $dbh;

my $sql = "INSERT INTO emails VALUES (default,default,default,?,?,?,?,?)";

#loop
#for (1..1)
my $w = AnyEvent->timer
(
    interval => 0.2,
    cb => sub {

            $count++;
            &connect_sql;

            my $random_name = &random_name;

            my $name       = "$random_name->{first} $random_name->{last}";
            my $from_email = "$random_name->{first}.$random_name->{last}\@example.com";
            my $to_email   = "$random_name->{first}.$random_name->{last}\@example.com";

            $email =
            "From: $name <$from_email>
To: $name <$from_email>
Subject: $subject" . $email_body->generate;

            #     print $email;

            ( my $mailbox = lc $to_email ) =~ s/@.*$//;


            my $query = $dbh->prepare($sql);
            $query->bind_param(5, undef, { pg_type => DBD::Pg::PG_BYTEA });
            $query->execute($name . " <" .$from_email."<",
                            $name . " <" .$to_email."<",
                            $subject->generate,
                            $mailbox,
                            compress ($email_body->generate)
                        );


        }
);

my $timer = AnyEvent->timer
(
    interval => 1,
    cb	 => sub {
            $count_per_sec = $count - $prev_count;
            $prev_count = $count;

            printf "%d / sec, %d %d sec\n", $count_per_sec, $count, ++$seconds;
        }
);



sub random_name ()
{
    return {
            first => $firstnames[int(rand($firstname_count))],
            last  =>  $lastnames[int(rand($lastname_count))]
        };
}

sub connect_sql (){
        until ($dbh and $dbh->ping)
        {
            sleep 1;
            $dbh = DBI->connect("dbi:Pg:dbname=mailnesia", "mailnesia", "");
        }
    }

AnyEvent->condvar->recv;
