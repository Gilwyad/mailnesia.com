#!/usr/bin/perl -w

use strict;
use Mojolicious::Lite;
use Mojo::Util qw(b64_encode url_escape);
use FindBin;
use lib "$FindBin::Bin/../lib/";
use Mailnesia;
use Mailnesia::Email;
use Mailnesia::Config;
use EV;
use AnyEvent;
use Carp qw/cluck/;

=head1 api.pl

HTTP API for email access

=cut


my $mailnesia = Mailnesia->new({decode_on_open=>":encoding(UTF-8)"});
my $config    = Mailnesia::Config->new;
my $sitename  = $config->{sitename};
my $siteurl   = $config->{siteurl};

app->mode  ( $mailnesia->{devel} ? "development" : "production");
app->config(hypnotoad => {
    listen    => ['http://127.0.0.1:8082'],
    pid_file  => '/tmp/mailnesia-api.pid',
    workers   => 2,
    accepts   => 0
});

app->log->info("HTTP API started, mode: ". app->mode);



group {
    under '/api';

=head2 GET /api

bad request

=cut

    get '/' => sub {
        return shift->render(
            text => '',
            status=>400
        );
    };

    get '/#anything' => sub {
        return shift->render(
            text => '',
            status=>400
        );
    };

=head2 GET /api/mailbox

bad request

=cut

    get '/mailbox' => sub {
        return shift->render(
            text => '',
            status=>400
        );
    };

=head2 GET /api/mailbox/#mailboxname

list emails in a mailbox in JSON format as:

[
    {
        id:1,
        date: 'timestamp',
        from: 'sender',
        to: 'recipient',
        subject: 'subject'
    },
    {
        id:2,
        date: 'timestamp2',
        from: 'sender2',
        to: 'recipient2',
        subject: 'subject2'
    }
]

Returns empty JSON list [] if there are no emails.

=cut


    get '/mailbox/#mailbox' => sub {
        my $self = shift;

        # parameters:
        my $original_url_decoded_mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );

        my $mailbox = $mailnesia->check_mailbox_characters( $original_url_decoded_mailbox );

        # bad request if wrong characters were used
        if ($mailbox ne $original_url_decoded_mailbox) {
            return $self->render(text => '', status => 400);
        }

        # Forbidden if mailbox banned
        if ($config->is_mailbox_banned( $mailbox )) {
            return $self->render(text => '', status => 403);
        }

        # forbidden if alias
        if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias}) {
            return $self->render(text => '', status => 403);
        }

        my $emaillist_page = $self->param('p') =~ m/(\d+)/ ? $1 : 0;

        # this is for polling for new mail
        my $newerthan = $1 if $self->param('newerthan') =~ m/(\d+)/;

        my $url_encoded_mailbox = $mailnesia->get_url_encoded_mailbox ($mailbox);

        my $email = Mailnesia::Email->new({dbh => $mailnesia->{dbh}});
        my $emaillist;

        if ($newerthan) {       # FIXME: needed?
            $emaillist = $email->get_emaillist_newerthan(
                $config->{date_format},
                $mailbox,
                $newerthan
            );
        } else {
            $emaillist = $email->get_emaillist(
                $config->{date_format},
                $mailbox,
                $config->{mail_per_page}, # FIXME: needed?
                $emaillist_page,
                1
            );
        }

        if (not defined $emaillist) {
            # error
            return $self->render(text=> 'Internal Server Error', status => 500, format => 'txt' );
        } else {
            return $self->render(json => [values %$emaillist]);
        }

    };




=head2 GET /api/mailbox/#mailboxname/#id

return an email in a mailbox suitable for displaying in JSON format,
or 404 error if not found.

=cut


    get '/mailbox/#mailbox/#id' => sub {
        my $self = shift;
        my $original_url_decoded_mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );
        my $mailbox = $mailnesia->check_mailbox_characters( $original_url_decoded_mailbox );
        my $id = $1 if $self->param('id') =~ m/(\d+)/;

        # bad request if wrong characters were used
        if ($mailbox ne $original_url_decoded_mailbox) {
            return $self->render(text => '', status => 400);
        }

        # Forbidden if mailbox banned
        if ($config->is_mailbox_banned( $mailbox )) {
            return $self->render(text => '', status => 403);
        }

        # forbidden if alias
        if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias}) {
            return $self->render(text => '',status => 403);
        }

        my $email = Mailnesia::Email->new(
            {
                dbh => $mailnesia->{dbh},
                to => [ $mailbox ],
                id => $id
            }
        );

        my $email_body = $email->body($id) ;
        if ( $email_body ) {
            # base64?
            # my %email_b64;
            # for my $tab (keys %$email_body) {
            #     $email_b64{$tab} = b64_encode $email_body->{$tab}
            # }
            return $self->render(
                json => $email_body
            );
        } else {
            return $self->render(text => '', status => 404);
        }
    };


=head2 GET /api/mailbox/#mailboxname/#id/raw

return an email in a mailbox in raw format, as received from a mail server

=cut


    get '/mailbox/#mailbox/#id/raw' => sub {
        my $self = shift;
        my $original_url_decoded_mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );
        my $mailbox = $mailnesia->check_mailbox_characters( $original_url_decoded_mailbox );
        my $id = $1 if $self->param('id') =~ m/(\d+)/;

        # bad request if wrong characters were used
        if ($mailbox ne $original_url_decoded_mailbox) {
            return $self->render(text => '', status => 400);
        }

        # Forbidden if mailbox banned
        if ($config->is_mailbox_banned( $mailbox )) {
            return $self->render(text => '', status => 403);
        }

        # forbidden if alias
        if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias}) {
            return $self->render(text => '',status => 403);
        }

        # status 404 if no email
        my $m = Mailnesia::Email->new({dbh => $mailnesia->{dbh}});
        my $email = $m->get_email($mailbox, $id);
        if ($email) {
            return $self->render (
                text   => $email,
                format => 'txt'
            );
        } else {
            return $self->render(text => '', status => 404);
        }
    };

};

app->secrets([$mailnesia->random_name_for_testing()]);
app->start;
