#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
use Mojolicious::Lite;
use FindBin;
use lib "$FindBin::Bin/../lib/";
use Mailnesia;
use Mailnesia::Email;
use Mailnesia::Config;
use Compress::Snappy;

=head1 rss.pl

RSS email access

=cut


my $mailnesia = Mailnesia->new({decode_on_open=>":encoding(UTF-8)"});
my $config    = Mailnesia::Config->new;
my $sitename  = $config->{sitename};
my $baseurl   = $ENV{baseurl} ? "http://" . $ENV{baseurl} :
    $mailnesia->{devel} ?
        "http://" . $config->{siteurl_devel} :
        "https://" . $config->{siteurl};

app->mode  ( $mailnesia->{devel} ? "development" : "production");
app->config(hypnotoad => {
    listen    => ['http://*:4000'],
    pid_file  => '/tmp/mailnesia-rss.pid',
    workers   => 2,
    accepts   => 0
});

app->log->info("RSS started, mode: ". app->mode);

# executed at startup of the worker
Mojo::IOLoop->next_tick(sub {
    $mailnesia->{dbh} = $mailnesia->connect_sql();
});


# Global logic shared by all routes
under sub {
    my $self = shift;
    # parameters:
    if ($self->req->url->path =~ m!/rss/([^/]+)!) {

        my $original_url_decoded_mailbox = lc $mailnesia->get_url_decoded_mailbox ( $1 );
        if (not $original_url_decoded_mailbox) {
            $self->render(text => '', status => 400);
            return;
        }

        my $mailbox = $mailnesia->check_mailbox_characters( $original_url_decoded_mailbox );
        # bad request if wrong characters were used
        if (!$mailbox || $mailbox ne $original_url_decoded_mailbox) {
            $self->render(text => '', status => 400);
            return;
        }

        # Forbidden if mailbox banned
        if ($config->is_mailbox_banned( $mailbox )) {
            $self->render(text => '', status => 403);
            return;
        }

        # forbidden if alias
        if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias}) {
            $self->render(text => '', status => 403);
            return;
        }

        if (my $ip = $self->req->headers->header('X-Forwarded-For')) {
            # redirect to captcha if too many mailbox requests
            if ( my $excess = $config->mailboxes_per_IP($ip, $mailbox, $config->{daily_mailbox_limit}) ) {
                # save the mailbox in cookie so a redirect can be made after successful captcha verification
                $self->cookie( mailbox => $mailbox, {path => '/', expires => time + $config->{cookie_expiration}} ) if $mailbox;
                $self->redirect_to(Mojo::URL->new->path('/captcha.html'));
                return;
            }
            $config->log_ip($ip, $mailbox, $self->req->headers->user_agent);
        }
    }

    # continue with request
    return 1;
};

group {
    under '/rss';

    get '/' => sub {
        return shift->render(
            text => '',
            status=>404
        );
    };

    get '/#rss' => sub {

        my $self = shift;
        my $mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('rss') );

        my $mailcount = 0;
        if (my $mailcount_param = $self->param('mailcount')) {
            $mailcount = $1 if $mailcount_param =~ m/(\d+)/;
        }

        # this is for polling for new mail
        my $format;
        if (my $format_param = $self->param('format')) {
            $format = $1 if $format_param =~ m/(\d+)/;
        }

        my $url_encoded_mailbox = $mailnesia->get_url_encoded_mailbox ($mailbox);

        my $email = Mailnesia::Email->new({dbh => $mailnesia->{dbh}});
        my $emaillist;

        $emaillist = $email->get_full_emaillist(
            $mailbox,
            $config->{mail_per_page},
        );

        if (ref $emaillist) {
            my @result = map {
                $_->{email} = substr(
                    Mailnesia::Email->new(
                        {
                            raw_email => decompress $_->{email}
                        }
                    )->body_rss($format),
                    0,
                    $config->{max_rss_size}
                );
                $_;
            } values %$emaillist;

            $self->stash(
                mailbox             => $mailbox,
                url_encoded_mailbox => $url_encoded_mailbox,
                emaillist           => \@result,
                baseurl             => $baseurl,
            );
            return $self->render(
                template => 'rss',
                format   => 'xml',
                handler  => 'ep',
            );
        } else {
            # error
            return $self->render(text=> "Internal Server Error - $emaillist", status => 500, format => 'txt' );
        }

    };

};

app->secrets([$mailnesia->random_name_for_testing()]);
app->start;
