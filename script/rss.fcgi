#!/usr/bin/perl

use strict;
use AnyEvent::FCGI;
use AnyEvent::DNS;
use DBI;
use CGI::RSS;
use Compress::Snappy;
use Carp qw/cluck/;

use Mailnesia;
use Mailnesia::SQL;
use Mailnesia::Email;
use Mailnesia::Config;
use Encode qw(encode);

use utf8;                       # getting back data decoded, then concatenate with utf8 char (at rss title)! Finally has to be encoded before print.


# only root can write to /var/run, this is run as www-data so /tmp has to be used
my $socket = '/tmp/mailnesia-rss.sock';
my $pidfile = '/tmp/mailnesia-rss.pid';

open FILE, ">", $pidfile or die "cannot open pidfile: $pidfile, $!\n";
print FILE $$;
close FILE;


{
    package CGI::RSS;

    *CGI::RSS::date = sub {

            my $valid_rfc8222_date = qr!^
                                        (?:
                                            (?:
                                                Mon | Tue | Wed |
                                                Thu | Fri | Sat |
                                                Sun
                                            )                    # day
                                            ,\s\s?               # comma, space or two
                                        )?                       # (these were optional)
                                        \d\d?\s                  # day with 1 or 2 digit, space
                                        (?:
                                            Jan | Feb | Mar |
                                            Apr | May | Jun |
                                            Jul | Aug | Sep |
                                            Oct | Nov | Dec
                                        )                        # month
                                        \s\d{4}\s                # space, 4 digit year, space
                                        \d\d:\d\d:\d\d\s         # hr:min:sec, space
                                        (?:
                                            [\+\-]\d\d\d\d  |    # time zone with digits, or
                                            UT  | GMT | EST |
                                            EDT | CST | CDT |
                                            MST | MDT | PST |
                                            PDT | Z   | A   |
                                            M   | N   | Y        # time zone with characters
                                        )$
                                       !ix;

            my $this = shift;

            return $this->pubDate($_[-1]) if $_[-1] =~ $valid_rfc8222_date ;

            if ( my $pd = ParseDate($_[-1]) )
            {
                my $date = UnixDate($pd, '%a, %d %b %Y %H:%M:%S %z');
                return $this->pubDate($date);
            }

            $this->pubDate(@_);
        }
}


my $dbh = Mailnesia::SQL->connect() ;
my $addr;
my %dns;

my $mailnesia = Mailnesia->new;
my $config    = Mailnesia::Config->new;
my $baseurl   = $mailnesia->{devel} ? "http://" . $config->{siteurl_devel} : "http://" . $config->{siteurl};

my $sigint  = AnyEvent->signal (signal => "INT",  cb => sub {
                                        terminate();
                                    });

my $sigkill = AnyEvent->signal (signal => "KILL", cb => sub {
                                        terminate();
                                    });



my $fcgi = new AnyEvent::FCGI
(
    socket => $socket,
    on_request => sub {
            my $request = shift;

            my $mailbox = lc $mailnesia->check_mailbox_characters( $mailnesia->get_url_decoded_mailbox ( $request->param('REQUEST_URI') =~ m,rss/([a-z0-9_\.\-\+\%]+),i ), 1);
            my $url_encoded_mailbox = $mailnesia->get_url_encoded_mailbox ( $mailbox );


            my $addr = $request->param('REMOTE_ADDR');
            my $mailcount = $request->param('QUERY_STRING') =~ m/mailcount=(\d+)/i ? $1 : 10;
            my $format = lc $1 if $request->param('QUERY_STRING') =~ m/format=(plain|html)/i;

            my @header;
            my ( $stdout, $stderr ) = ();

            if ( ! $mailbox )
            {
                @header = ( 'Status' => "400 Bad Request" );
            }
            elsif ( $config->is_ip_banned($addr) )
            {
                $stderr .= "REJECTED: request from banned ip $addr: " . $request->param('REQUEST_URI');

                @header = ( 'Status' => "403 Forbidden" );
            }
            elsif ( $config->is_mailbox_banned($mailbox) )
            {
                $stderr .= "REJECTED: requested banned mailbox $mailbox!";

                @header = ( 'Status' => "403 Forbidden" );
            }
            elsif (! ref $dbh)
            {
                @header = ( 'Status' => "503 Service Temporarily Unavailable" );
                $dbh = Mailnesia::SQL->connect() ;
            }
            elsif ( $mailnesia->check_mailbox_alias($mailbox)->{is_alias} )
            {
                @header = ( 'Status' => "403 Forbidden" );
            }
            else
            {
                if ( my $count = $config->mailboxes_per_IP($addr,$mailbox,$config->{daily_mailbox_limit}) )
                {

                    if (defined $dns{$addr} )
                    {
                        # dns already queried
                        # TODO: since google rss reader is discontinued, this section should be modified somehow ...
                        if ( my @match = grep m/google\.com$/i, @{ $dns{$addr} } )
                        {
                            $stderr .= "rDNS points to google, OK ($addr -> @match). ";
                        }
                        else
                        {
                            $stderr .= "REJECTED: too many RSS opened: $addr, $mailbox, $count, rDNS: " . @{ $dns{$addr} };
                            @header = ( Status  => "429 Too Many Requests" );
                            return;
                        }
                    }
                    else
                    {
                        AnyEvent::DNS::reverse_lookup $addr, sub {
                                $dns{$addr} = \@_;
                            };
                    }

                }

                my $cgirss = new CGI::RSS;

                $stdout .= '<?xml version="1.0" encoding="UTF-8"?>' .
                $cgirss->begin_rss(
                        title => "$mailbox @ " . $config->{sitename},
                        link  => $baseurl,
                        desc  => 'Anonymous Email in Seconds'
                    );

                my $query = $dbh->prepare ("SELECT * from emails WHERE mailbox=? ORDER BY arrival_date DESC LIMIT ?");

                unless ( $query->execute($mailbox,$mailcount) )
                {
                    # at SQL error, try to reconnect and complete
                    # the request with 503 Service Temporarily Unavailable
                    $dbh = Mailnesia::SQL->connect($dbh);
                    $request->print_stderr("SQL connection error at prepare, trying to reconnect!");
                    $request->respond("", 'Status' => "503 Service Temporarily Unavailable");
                    return;
                }

                while ( my $h = $query->fetchrow_hashref )
                {

                    $stdout .= $cgirss->item
                    (
                        $cgirss->title        ( encode ("UTF-8", "<![CDATA[".
                                                $h->{email_subject} . " – ". $h->{email_from} .
                                                "]]>" ) ),
                        $cgirss->link         ( "$baseurl/mailbox/$url_encoded_mailbox/".$h->{id}),
                        $cgirss->guid         ( "$baseurl/mailbox/$url_encoded_mailbox/".$h->{id}),
                        $cgirss->description  ( "<![CDATA[".
                                                substr
                                                (
                                                    Mailnesia::Email->new
                                                      (
                                                          {
                                                              raw_email => decompress $h->{email}
                                                          }
                                                      )->body_rss($format),
                                                    0,
                                                    $config->{max_rss_size}
                                                )
                                                ."]]>"),
                        $cgirss->date         ( $h->{email_date} || $h->{arrival_date} )
                    );
                }
                $stdout .= $cgirss->finish_rss;
                @header = ( "Content-Type" => "application/xml" );
            }

            $request->print_stderr($stderr) if $stderr;
            $request->respond ($stdout, @header);

        }
);


sub terminate {

        undef $sigint;
        undef $sigkill;
        undef $fcgi;

        unlink $pidfile;

        exit;
    }



AnyEvent->condvar->recv;
