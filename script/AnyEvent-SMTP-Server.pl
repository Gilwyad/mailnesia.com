#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib/";

use Mailnesia;
use Mailnesia::SQL;
use Mailnesia::Email;
use Mailnesia::Config;
use Privileges::Drop;
use AnyEvent::SMTP::Server;
use AnyEvent::SMTP::Client 'sendmail';
use Carp qw(cluck);
#use Mail::SPF;
use ZMQ::FFI qw(ZMQ_PUSH);
use POSIX qw(strftime);

{
    package AnyEvent::SMTP::Server;

    sub accept_connection {
        my ($self,$fh,$host,$port) = @_;
        warn "Client connected $host:$port \n" if $self->{debug};
        my $con = AnyEvent::SMTP::Conn->new(
            fh => $fh,
            host => $host,
            port => $port,
            debug => $self->{debug},
            timeout => 5
        );
        $self->{c}{int $con} = $con;
        $con->reg_cb(
            disconnect => sub {
                delete $self->{c}{int $_[0]};
                $self->event( disconnect => $_[0], $_[1] );
            },
            command => sub {
                $self->event( command => @_ )
            },
        );
        $self->eventif( client => $con );
        $con->reply("220 $self->{hostname} AnyEvent::SMTP Ready.");
        $con->want_command;
    }
}


# just for logging:
use open ':encoding(utf8)';
binmode(STDOUT, ":utf8");

my $tryAtMost = 1;
my $startingPort = 5000;
my @endpoints = map { "tcp://127.0.0.1:$_" } ($startingPort..$startingPort+$tryAtMost);
my $next = 0;

my $ctx  = ZMQ::FFI->new();
my @push = ($ctx->socket(ZMQ_PUSH)) x $tryAtMost;

for (my $i = 0; $i < $tryAtMost; $i++) {
    $push[$i]->connect($endpoints[$i]);
}

# return the next connection to use, from 0 to $tryAtMost-1
sub nextOne {
    if ($next < $tryAtMost - 1) {
        return ++$next;
    } else {
        return $next = 0;
    }
}

my $email_count=0;
my $email_bandwidth=0;

my $config = Mailnesia::Config->new;
my $mailnesia = Mailnesia->new;

#maximum size the clicker will download
my $url_clicker_page_size_limit = $config->{url_clicker_page_size_limit};

#maximum email size
my $max_email_size = $config->{max_email_size};

#not accepting mail from these domains
my $banned_sender_domain = $config->{banned_sender_domain};

#pid file:
my $pidfile = $config->{pidfile};
my $debugging_mode;

# do not save email / click logs
my $logging_disabled = 1;

my $sigint  = AnyEvent->signal (signal => "INT",  cb => sub {
                                        &terminate();
                                    });
my $sigkill = AnyEvent->signal (signal => "KILL", cb => sub {
                                        &terminate();
                                    });
my $sigusr  = AnyEvent->signal (signal => "USR1", cb => sub {
                                        &terminate();
                                    });

my $sighup  = AnyEvent->signal (signal => "HUP", cb => sub {
                                        &open_log();
                                    });

my $exit_timer;

# %cookie_jar will contain the cookies to use after redirects.  Once the request is done, cookies are discarded.
my %cookie_jar ;


if ($ARGV[0])
{
    $debugging_mode = ($ARGV[0] eq '-d' or $ARGV[0] eq '--debug') ? 1 : 0;
}
else
{
    $debugging_mode = 0;
}

my $server_port = $debugging_mode || $mailnesia->{devel} ? $config->{smtp_port_devel} : $config->{smtp_port};
my $server_ip   = $debugging_mode || $mailnesia->{devel} ? $config->{smtp_host_devel} : $config->{smtp_host};
my $dbh = $mailnesia->{dbh};
#my $spf_server = Mail::SPF::Server->new();

my $daily_mailcount_saver = AnyEvent->timer
(
    after     => 100,
    interval  => 300,
    cb        => sub { daily_mailcount_saver(20) }
);

my $daily_bandwidth_saver = AnyEvent->timer
(
    interval  => 300,
    cb        => sub { daily_bandwidth_saver(5) }
);

unless ($debugging_mode) {

        if (-e $pidfile)
        {
            open PID, "<", $pidfile;
            my $pid = <PID>;
            kill 0, $pid and die "SMTP server already running, pid: $pid !\n";
        }

        {
            (my $piddir = $pidfile)  =~ s,[^/]+$,,;
            mkdir $piddir unless -d $piddir;
        }

        open FILE, ">", $pidfile or die "unable to open pidfile! $pidfile, $!\n";
        print FILE $$;
        close FILE;

    }

sub open_log {
        if ($debugging_mode || $logging_disabled)
        {
            *LOG          = *STDOUT;
            *PROC_LOG     = *STDOUT;
            *CLICK_LOG    = *STDOUT;
            #    *NOCLICK_LOG  = *STDOUT;
        }
        else
        {

            close STDERR;close LOG;close PROC_LOG;close CLICK_LOG;
            open STDERR, ">", "/tmp/smtp-server-error.log";

            open LOG,         ">>", "/var/log/mailnesia-smtp_server.log"      or warn "error opening LOG file: $!\n";
            open PROC_LOG,    ">>", "/var/log/mailnesia-email_processing.log" or warn "error opening PROC_LOG file: $!\n";
            open CLICK_LOG,   ">>", "/var/log/mailnesia-click.log"            or warn "error opening CLICK_LOG file: $!\n";
            # open NOCLICK_LOG, ">>", "/var/log/mailnesia-noclick.log"          or warn "error opening NOCLICK_LOG file: $!\n";

            *STDERR = *LOG;
        }
    }
;

sub display_time {
        my ($sec,$min,$hour,$mday,$mon,$year,undef,undef,undef) = localtime(time);
        $year += 1900;
        $mon += 1;
        return "$year/".sprintf("%02d/%02d %02d:%02d:%02d",$mon,$mday,$hour,$min,$sec);
    }

{
    #cache lookups:
    package Net::DNS::Resolver;

    my %cache;

    sub send {
            my ($self, @args) = @_;

            # my @keys = keys %cache;
            # warn "keys: @keys";

            # if ($cache{"@args"})
            #   {
            #     warn "@args exists"
            #   }
            # else
            #   {
            #     warn "@args does not exist!"
            #   }

            return $cache{"@args"} ||= $self->SUPER::send(@args);
        }
}


my $server = AnyEvent::SMTP::Server->new(
        hostname => $config->{siteurl},
        host => $server_ip,
        port => $server_port,
        mail_validate => sub {
                my ($m,$addr) = @_;
                if ($addr =~ $banned_sender_domain)
                {
                    warn "bad sender: $addr\n";
                    return 0, 553, 'Bad sender.';
                }
                else
                {
                    # # check if domain name exists
                    # ( my $domain = $addr ) =~ s/.*@//;

                    # if ( $config->domain_exists($domain) )
                    #   {
                    #     #SPF record check. FIXME: too slow!

                    #     if ($m->{host})
                    #       {

                    #         my $request     = Mail::SPF::Request->new(
                    #           versions        => [1, 2], # optional
                    #           scope           => 'mfrom', # or 'helo', 'pra'
                    #           identity        => $addr,
                    #           ip_address      => $m->{host},
                    #           helo_identity   => $m->{helo},
                    #         );

                    #         my $result      = $spf_server->process($request);
                    #         if ( ref $result and $result->is_code('fail') )
                    #           {
                    #             my $errormessage = $result->received_spf_header . " " .
                    #             $result->authority_explanation;
                    #             warn "REJECTED: $errormessage\n";

                    #             return 0,
                    #             553,
                    #             $errormessage;
                    #           }
                    #         else
                    #           {
                    #             return 1;
                    #           }
                    #       }
                    #     else
                    #       {
                    #         #TODO: IP missing!!!???? Can't check SPF
                    #         return 1;
                    #       }

                    #   }

                    # else
                    #   {
                    #     warn "REJECTED: nonexistent domain name, mail from $addr\n";
                    #     return 0, 553, "REJECTED: nonexistent domain name";
                    #   }

                    return 1;

                }
            },
        rcpt_validate => sub {
                my ($m,$addr) = @_;
                my $mailbox;
                unless ( $mailbox = $mailnesia->check_mailbox_characters($addr, 1))
                {
                    warn "Tried to send to address with invalid characters: $addr\n";
                    return 0, 553, 'ERROR: invalid characters in email address!  Valid characters are described at https://mailnesia.com/features.html .';
                }

                if ( $config->is_mailbox_banned($mailbox) )
                {
                    warn "REJECTED: mail for banned mailbox: $addr\n";
                    return 0, 553, 'REJECTED: This mailbox has been banned due to violation of our terms and conditions of service (https://mailnesia.com/terms-of-service.html) .';
                }
                else
                {
                    return 1;
                }
            },
        data_validate => sub {
                my ($m,$data) = @_;
                my $size = length $data;
                if ($size > $max_email_size)
                {
                    warn "email too big: $size, from: $m->{from}, to: @{$m->{to}}, host: $m->{host}\n";
                    &process_email({
                            from => 'Mailnesia webmaster',
                            to   => $m->{to},
                            data => "Subject: Email rejected from $m->{from}
From: Mailnesia webmaster

Dear Mailnesia user,

we are sorry to inform you that an email message from $m->{from} was rejected by our mail server, because it's size ($size bytes) exceeded the limitations described at https://mailnesia.com/features.html .

Mailnesia webmaster
"
                        });

                    return 0, 552, 'REJECTED: message size limit exceeded - refer to the limitations at https://mailnesia.com/features.html';
                }
                else
                {
                    return 1;
                }
            }
    );

sub add_received_header {
    my $mail = $_[0];
    my $date = strftime("%a, %d %b %Y %H:%M:%S %z", localtime(time()));
    my $received_header = "Received: FROM $mail->{helo} [ $mail->{host} ] BY mailnesia.com ; $date\n";
    $mail->{data} = $received_header . $mail->{data};
}

$server->reg_cb(
        client => sub {
                my ($s,$con) = @_;
                if ($config->is_ip_banned($con->{host}))
                {
                    warn "Banned client from $con->{host}:$con->{port} connected\n";
                    $con->close;
                }
                # print &display_time()." Client from $con->{host}:$con->{port} connected\n" unless $con->{host} =~ m'127.0.0.1';
            },
        # disconnect => sub {
        #   my ($s,$con) = @_;
        #   print &display_time()." Client from $con->{host}:$con->{port} gone\n" unless $con->{host} =~ m'127.0.0.1';
        # },
        mail => sub {
                my $self = shift;
                my $email_obj = shift;
                add_received_header($email_obj);
                foreach my $recipient_address ( @ {$email_obj->{to} } )
                {
                    my $mailbox = $1 if $recipient_address =~ m/([a-z0-9\-\+_\.]+)@/i;

                    if (my $forwardTo = $config->{email_forwarding}->{$mailbox})
                    {
                        warn "forwarding for $mailbox -> $forwardTo";

                        #forward
                        sendmail
                        host    => '127.0.0.1',
                        port    => $mailnesia->{devel} ? 25 : 26,
                        from    => $email_obj->{from},
                        to      => $forwardTo,
                        data    => $email_obj->{data},
                        cb      => sub {
                                if (my $ok = shift)
                                {
                                    warn "Successfully forwarded email for $mailbox";
                                }

                                if (my $err = shift)
                                {
                                    warn "Failed to forward email for $mailbox: $err";
                                }
                            };
                    }
                }

                unless ( process_email($email_obj) )
                {
                    $self->{event_failed} = 1
                }
            }
    );

$server->start;
drop_privileges('nobody');

print &display_time()." $0 started on port $server_port\n";
open_log();

AnyEvent->condvar->recv;

sub terminate {
        undef $sigint;
        undef $sigkill;
        undef $sigusr;
        undef $daily_mailcount_saver;
        undef $daily_bandwidth_saver;

        print LOG "SMTP server stopped!\n";
        $server->stop;

        daily_mailcount_saver();
        daily_bandwidth_saver();

        $exit_timer = AnyEvent->timer
        (
            after    => 2,
            cb      => sub { exit }
        );

    }

sub process_email (\%) {
        my $mail = shift;
        # $mail = {
        #     from => ...,
        #     to   => [ ... ],
        #     data => '...',
        #     host => 'remote addr',
        #     port => 'remote port',
        #     helo => 'HELO/EHLO string',
        # };

        # open my $spamtest, "|/usr/bin/qsf -t";
        # print $spamtest $mail->{data};
        # my $is_spam = not close $spamtest;
        # warn "IS SPAM!!!!\n" if $is_spam;

        my $reconnect_counter = 0;

        until ($dbh and $dbh->ping)
        {
            if ( $reconnect_counter > 1 )
            {
                #try to connect two times, then give up and return 500 internal server error to the client
                return;
            }

            $dbh = Mailnesia::SQL->connect($dbh);
            sleep 1;
            $reconnect_counter++;
        }

        $SIG{__DIE__} = sub {
                cluck "Fatal exception: $_[0], saving email\n";
                my $to;
                $to = join('_', @ { $mail->{to} });
                my $tmp_dir = '/tmp/mailnesia';
                mkdir $tmp_dir unless -e $tmp_dir;

                my $rnd;
                ( $rnd .= random_number() ) for 1..4 ;
                open my $errorlog, ">", "$tmp_dir/$to-" . scalar time() ."_". $rnd;
                print $errorlog $mail->{data};
                close $errorlog;

                return;
            };

        my @to;
        foreach ( @{ $mail->{to} } )
        {
            if (m/[<>\'\" ]*([a-z0-9\.\-\+_]+)(\@[a-z0-9\.\-]+)?/i)
            {
                push @to, lc $1; # psql is case sensitive! have to insert lowercase since we search in lowercase!
            }
        }

        my $email = Mailnesia::Email->new({
                raw_email => $mail->{data},
                dbh       => $dbh,
                to        => \@to
            }) or die "unable to process email";

        my $subject = $email->subject;
        #warn $email->body;#not good here!

        $email->store() or die "unable to store email";        #$is_spam);

        # if at least one recipient has the clicker enabled, click
      TO: foreach (@to)
        {
            if ($config->is_clicker_enabled($_))
            {
                # select the next clicker for use
                my $next = nextOne();
                # send the email body to the chosen clicker
                $push[$next]->send($mail->{data});

                last TO;
            }
        }



        #calculate incoming email size (bandwidth used):
        $email_count++;
        $email_bandwidth += length $mail->{data};


        print PROC_LOG &display_time()." from: $mail->{from}, subject: $subject, to: @to, host: $mail->{host}, HELO: $mail->{helo}\n";

        return 1;

    }


# update the emailperday table with incoming mail count
# save only if count > $limit
sub daily_mailcount_saver {
        my $limit = shift || 0;

        if ($email_count > $limit)
        {
            if ( $dbh
                 ->prepare('UPDATE emailperday SET email = email + ? WHERE DAY=NOW()::DATE')
                 ->execute($email_count)
                 == 1)
            {
                # success
                $email_count = 0
            }
            else
            {
                # if affected rows != 1
                if ( $dbh
                     ->prepare('INSERT INTO emailperday VALUES ( DEFAULT, ?)')
                     ->execute($email_count)
                     == 1)
                {
                    # success
                    $email_count=0
                }
                else
                {
                    warn "updating emailperday with email_count failed"
                }
            }
        }
    }

# update the emailperday table with incoming mail bandwidth in megabytes
# save only if bandwidth > $limit
sub daily_bandwidth_saver {
        my $limit = shift || 0;

        my $email_bandwidth_mb = int ( $email_bandwidth / 1048576 );

        if (not defined $daily_bandwidth_saver and $email_bandwidth > 0)
        {
            # shutting down...
            $email_bandwidth_mb++;
        }

        if ($email_bandwidth_mb > $limit)
        {
            if ( $dbh
                 ->prepare('UPDATE emailperday SET bandwidth = bandwidth + ? WHERE DAY=NOW()::DATE')
                 ->execute($email_bandwidth_mb)
                 == 1)
            {
                # success
                $email_bandwidth = $email_bandwidth % 1048576
            }
            else
            {
                # if affected rows != 1
                if ( $dbh
                     ->prepare('INSERT INTO emailperday VALUES ( DEFAULT, DEFAULT, ?)')
                     ->execute($email_bandwidth_mb)
                     == 1)
                {
                    # success
                    $email_bandwidth = $email_bandwidth % 1048576
                }
                else
                {
                    warn "updating emailperday with email_bandwidth failed"
                }
            }
        }
    }


sub random_number
{
    return int ( rand(5) )
}
