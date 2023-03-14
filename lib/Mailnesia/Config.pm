=head1 NAME

Mailnesia::Config - configuration options

=head1 SYNOPSIS

use Mailnesia::Config;

my $config       = Mailnesia::Config->new;

my $sitename     = $config->{sitename};
my $siteurl      = $config->{siteurl};
my $date_format  = $config->{date_format};

$config->wipe_mailbox_per_IP_list($addr);

if (my $excess = $config->mailboxes_per_IP($addr,$mailbox,$config->{daily_mailbox_limit}))
{
  ...
}

if ($mailbox and $config->is_mailbox_banned($mailbox))
{
  ...
}

=head1 DESCRIPTION

settings and common functions

=cut

package Mailnesia::Config;
use Redis;
use Mailnesia;
#use Net::DNS::Resolver;
use POSIX qw(strftime);

=head2 new

my $config = Mailnesia::Config->new;

Parameters:

 - if true, indicates development (testing) version; does not save ad code 'ad_top'

=cut

sub new {
        my $package = shift;
        my $devel = shift;

        # loading private configuration items
        # ex: recaptcha private key - without the correct key every captcha solution will be invalid
        my %mailnesia_private;

        {
            my $conf = Mailnesia->get_project_directory() . "/lib/Mailnesia/mailnesia-private.conf";
            if ( open my $f, "<", $conf )
            {
                while (<$f>)
                {
                    chomp;
                    next unless m/^([a-z_]+)\s*=\s*(.*)$/;
                    my ($key, $value) = ($1, $2);
                    $mailnesia_private{$key} = ($key eq 'ad_top' and $devel) ? '' : $value;
                }
                close $f;
            }
            else
            {
                if ( open my $f, ">", $conf )
                {
                    print $f "recaptcha_private_key = XXXXXXXXXXXXXXXXXXXXXXX\n";
                    warn "The file lib/Mailnesia/mailnesia-private.conf has to be set up in the project directory containing the ReCaptcha private key!\n";
                    close $f;
                }
                else
                {
                    warn "The file lib/Mailnesia/mailnesia-private.conf has to be set up in the project directory containing the ReCaptcha private key but creation of the file failed: $conf - $!\n"
                }
            }
        }




        my $self = bless {

                sitename       => "MailNesia",
                siteurl        => "mailnesia.com",   # URL in production
                siteurl_devel  => "mailnesia.test", # URL in development

                # email date format on website, postgresql setting
                date_format         => 'YYYY-MM-DD HH24:MI:SS+00:00',

                # cookie expiration in seconds
                cookie_expiration   => 60 * 60 * 24 * 30,

                # IPs will be banned for this duration in seconds
                ip_ban_expiration   => 60 * 60 * 24 * 30,

                # number of emails on one page
                mail_per_page       => 40,

                # maximum size of an RSS feed in bytes that would be displayed, excess part is truncated
                max_rss_size        => 10_000,

                # maximum size of an email in bytes, bigger emails are rejected
                max_email_size      => 500_000,

                # maximum number of mailboxes that can be opened in a 24 hour period
                daily_mailbox_limit => 25, # per IP

                # items from the private conf file
                private_config => \%mailnesia_private,

                # after this amount a captcha is displayed
                recaptcha_private_key => $mailnesia_private{recaptcha_private_key},
                recaptcha_public_key  => "6LcRvY0UAAAAAH5W4VrIOyWqk_yLoxW7ss22C2r5",

                # download limit for the url clicker in bytes
                url_clicker_page_size_limit => 100_000,

                # not receiving emails from these domains
                banned_sender_domain        => qr'@proton.xen.prgmr.com|@mailnesia.com|@mnet.com|mnetmaster@cjmnetmedia.com|root@jcubei.com',

                #SMTP server pid file:
                pidfile                     => "/tmp/mailnesia-smtp-server.pid",

                # limited from addresses:
                sender_log => {'confirm.*@facebook' => undef},

                # email forwarding, mailbox => email
                email_forwarding  => {
                        abuse     => 'peter@localhost'
                    },

                redis      => Redis->new(
                        encoding => undef,
                        sock     => '/var/run/redis/redis.sock'
                    ),

                # name of used redis databases
                redis_databases => {
                        banned_mailboxes  => "banned_mailboxes",
                        banned_ips        => sub { "banned_IPs:" . +shift },
                        clicker_disabled  => "clicker_disabled",
                        mbox_per_ip       => sub { "mbox_per_IP:" . +shift },
                        domain_exists     => sub { "domain_exists:" . +shift },
                        mailbox_visitors  => sub { "visitors:" . +shift }
                    },

                # keep the visitor ips for this time period expressed in seconds
                redis_mailbox_visitors_retention_period => 180 * 24 * 60 * 60,
                redis_mailbox_visitors_field_separator => "\0",

                smtp_port        => 25,                # mail server port in production
                smtp_port_devel  => 2525,              # mail server port in development
                smtp_host        => "172.106.75.153",  # mail server IP in production
                smtp_host_devel  => "::"               # listen on all addresses in development

            },$package;

        return $self;
    }

=head2 is_mailbox_banned

Check if mailbox is banned.  Banned mailbox names are stored in a
Redis set named banned_mailboxes.

=cut

sub is_mailbox_banned {
        my ($self, $mailbox) = @_;
        return unless $mailbox;

        $self->{redis}->sismember(
                $self->{redis_databases}->{banned_mailboxes},
                $mailbox
            );
    }


=head2 is_ip_banned

Check if ip is banned.  Banned IPs are stored in Redis as keys and
values where the key contain the IPs prefixed with "banned_IPs:" and
the value is 1.

=cut

sub is_ip_banned {
        my ($self, $ip) = @_;
        return unless $ip;

        $self->{redis}->get(
                $self->{redis_databases}->{banned_ips}->($ip)
            );
    }


=head2 is_clicker_enabled

Check if URL clicker is enabled for a mailbox. A Redis set named
clicker_disabled contains all mailboxes where it is disabled.
Otherwise it is enabled.

=cut

sub is_clicker_enabled {
        my ($self, $mailbox) = @_;
        ! $self->{redis}->sismember(
                $self->{redis_databases}->{clicker_disabled},
                $mailbox
            );
    }

=head2 enable_clicker

Enable URL clicker for a mailbox.

=cut

sub enable_clicker {
        my ($self, $mailbox) = @_;
        $self->{redis}->srem(
                $self->{redis_databases}->{clicker_disabled},
                $mailbox
            );
    }


=head2 disable_clicker

Disable URL clicker for a mailbox.

=cut

sub disable_clicker {
        my ($self, $mailbox) = @_;
        $self->{redis}->sadd(
                $self->{redis_databases}->{clicker_disabled},
                $mailbox
            );
    }

=head2 mailboxes_per_IP

Number of mailboxes opened by an IP.  Returns the number if it's
higher than the limit ($Mailnesia::Config::daily_mailbox_limit), 0 if
lower.

=cut

sub mailboxes_per_IP {

        my $self    = shift;
        my $addr    = shift;
        my $mailbox = shift;
        my $limit   = shift; #$Mailnesia::Config::daily_mailbox_limit;

        my $database = $self->{redis_databases}->{mbox_per_ip}->($addr);

        return 0 if ! $addr || $addr eq '127.0.0.1' || ! $mailbox;

        # add the mailbox to the list of the IP
        $self->{redis}->sadd($database, $mailbox);
        # set expiration on IP
        $self->{redis}->expire($database, 86400);

        # check the number of mailboxes opened so far
        my $count = $self->{redis}->scard($database);

        if ( $count > $limit )
        {
            return $count;
        }
        else
        {
            return 0;
        }
    }

=head2 wipe_mailbox_per_IP_list

Remove the mailbox list associated with IP from redis.  Used after
successful captcha verification.

=cut

sub wipe_mailbox_per_IP_list {
        my $self = shift;
        my $addr = shift;

        $self->{redis}->del($self->{redis_databases}->{mbox_per_ip}->($addr));
    }

=head2 domain_exists

Check if domain MX record exists, store results in redis database.
Not used because

 - even with caching there would be far too many DNS requests
 - don't know how to use in a non-blocking way
 - don't know how many legitimate mail would be rejected

=cut

sub domain_exists {

        warn "UNIMPLEMENTED FUNCTION: domain_exists";

        return 1;

        # my $self      = shift;
        # my $domain    = shift;

        # return 0 unless $domain;

        # my $database  = $self->{redis_databases}->{domain_exists}->($domain);

        # #check redis
        # my $result = $self->{redis}->get($database);

        # if ( defined $result )
        #   {
        #     # result should be 1 (exists) or 0 (does not exist)
        #     return $result
        #   }
        # else
        #   {
        #     # not set, need to check dns
        #     my $resolver = Net::DNS::Resolver->new->send($domain, "MX");
        #     my $exists = ( ref $resolver and $resolver->answer ) ? 1 : 0;

        #     $self->{redis}->set($database, $exists);
        #     return $exists;
        #   }
    }



=head1 select a random banned mailbox

=cut

sub get_banned_mailbox
{
    my $self=shift;
    return $self->{redis}->srandmember( $self->{redis_databases}->{banned_mailboxes} ) # first element of array(ref)
}


=head1 ban_mailbox

ban the mailbox specified in parameter

=cut

sub ban_mailbox
{
    my $self = shift;
    my $mailbox = shift;

    return $self->{redis}->sadd(
            $self->{redis_databases}->{banned_mailboxes},
            $mailbox
        )
}


=head1 unban_mailbox

unban the mailbox specified in parameter

=cut

sub unban_mailbox
{
    my $self = shift;
    my $mailbox = shift;

    return $self->{redis}->srem(
            $self->{redis_databases}->{banned_mailboxes},
            $mailbox
        )
}


=head1 ban_ip

ban the ip specified in parameter

=cut

sub ban_ip
{
    my $self = shift;
    my $ip = shift;

    # SETEX key seconds value

    return  $self->{redis}->setex(
            $self->{redis_databases}->{banned_ips}->($ip),
            $self->{ip_ban_expiration},
            1
        )
}


=head1 unban_ip

unban the ip specified in parameter

=cut

sub unban_ip
{
    my $self = shift;
    my $ip = shift;

    return  $self->{redis}->del(
            $self->{redis_databases}->{banned_ips}->($ip)
        )
}

=head1 log_ip

Log unixtime, the ip, the mailbox & user agent specified in parameters.
When getting a mailbox, add the unix timestamp, the visitor ip and
useragent to its sorted set, e.g.:

    zadd visitors:${mailbox} ${unixtime} "${unixtime}\0${ip}\0${useragent}"

Then expire the sorted set after RETENTION_PERIOD:

    expire visitors:${mailbox} ${RETENTION_PERIOD}

=cut

sub log_ip {
    my $self = shift;
    my $ip = shift;
    my $mailbox = shift;
    my $user_agent = shift;

    my $current_timestamp = time(); # e.g. 1637446547
    # only save visit once every hour: subtract seconds and minutes
    my ($min, $sec) = (0, 0);
    ($min, $sec) = ($1, $2) if (strftime "%M:%S", gmtime($current_timestamp)) =~ m/(\d+):(\d+)/;
    $current_timestamp -= ($sec + $min * 60);

    my $key = $self->{redis_databases}->{mailbox_visitors}->($mailbox); # e.g. visitors:peter

    $self->{redis}->zadd(
        $key,
        $current_timestamp,
        join($self->{redis_mailbox_visitors_field_separator}, $current_timestamp, $ip, $user_agent)
    );

    return $self->{redis}->expire(
        $key,
        $self->{redis_mailbox_visitors_retention_period}
    );
}

=head1 get_visitor_list

Return the unixtime, the ip & user agent logged for the specified mailbox.
It is the list produced by:

    zrange visitors:${mailbox} 0 -1

=cut

sub get_visitor_list {
    my $self = shift;
    my $mailbox = shift;

    my $key = $self->{redis_databases}->{mailbox_visitors}->($mailbox); # e.g. visitors:peter

    return $self->{redis}->zrange($key, 0, -1);
}

sub transform_visitor {
    my $self = shift;
    my $visitor = shift;

    my ($ts, $ip, $ua) = split /$self->{redis_mailbox_visitors_field_separator}/, $visitor;
    return {
        timeStamp => strftime("%Y-%m-%d %H:%M:%S+00:00", gmtime($ts)),
        ip => $ip,
        userAgent => $ua
    };
}

=head1 get_formatted_visitor_list

Return the unixtime, the ip & user agent logged for the specified mailbox.
It is the list produced by:

    zrange visitors:${mailbox} 0 -1

=cut

sub get_formatted_visitor_list {
    my $self = shift;
    my $mailbox = shift;

    my @list = $self->get_visitor_list($mailbox);
    my @formatted_list = map { $self->transform_visitor($_) } reverse @list;

    return \@formatted_list;
}

1;
