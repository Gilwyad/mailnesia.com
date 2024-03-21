#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
use Mojolicious::Lite;
use Mojo::Util qw(b64_encode url_escape);
use FindBin;
use lib "$FindBin::Bin/../lib/";
use Mailnesia;
use Mailnesia::Email;
use Mailnesia::Config;
use EV;
use AnyEvent;
use Carp qw/confess/;

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

# executed at startup of the worker
Mojo::IOLoop->next_tick(sub {
    $mailnesia->{dbh} = $mailnesia->connect_sql();
});


# Global logic shared by all routes
under sub {
    my $self = shift;
    # parameters:
    if ($self->req->url->path =~ m!/mailbox/([^/]+)!) {

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
    under '/api';

    group {
        under '/mailbox';
        # Return all emails in a mailbox in JSON format as:

        # [
        #     {
        #         id:1,
        #         date: 'timestamp',
        #         from: 'sender',
        #         to: 'recipient',
        #         subject: 'subject'
        #     },
        #     {
        #         id:2,
        #         date: 'timestamp2',
        #         from: 'sender2',
        #         to: 'recipient2',
        #         subject: 'subject2'
        #     }
        # ]

        # Returns empty JSON list [] if there are no emails.

        # URL parameters:

        #  - newerthan
        #    only emails newer than the specified id are returned. Returns 204 no content if none found.
        #  - page
        #    Returns the specified page number only. One page equals 40 items, starting from 0.
        get '/#mailbox' => sub {
            my $self = shift;

            # parameters:
            my $mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );

            my $emaillist_page = 0;
            if (my $page = $self->param('page')) {
                $emaillist_page = $1 if $page =~ m/(\d+)/;
            }

            # this is for polling for new mail
            my $newerthan = 0;
            if (my $newerthan_param = $self->param('newerthan')) {
                $newerthan = $1 if $newerthan_param =~ m/(\d+)/;
            }

            my $url_encoded_mailbox = $mailnesia->get_url_encoded_mailbox ($mailbox);

            my $email = Mailnesia::Email->new({dbh => $mailnesia->{dbh}});
            my $emaillist;

            if ($newerthan) {
                $emaillist = $email->get_emaillist_newerthan(
                    $config->{date_format},
                    $mailbox,
                    $newerthan,
                    1
                );
            } else {
                my $mail_per_page = $config->{mail_per_page} if ($emaillist_page);

                $emaillist = $email->get_emaillist(
                    $config->{date_format},
                    $mailbox,
                    $mail_per_page,
                    $emaillist_page,
                    1
                );
            }

            if (ref $emaillist) {
                my @result = sort { $b->{id} <=> $a->{id} } values %$emaillist;
                if ($newerthan and not scalar @result) {
                    # return 204 if no email for newerthan requests
                    return $self->render(text => '', status => 204);
                } else {
                    return $self->render(json => \@result);
                }
            } else {
                # error
                return $self->render(text=> "Internal Server Error - $emaillist", status => 500, format => 'txt' );
            }

        };

        # delete all emails of a mailbox
        del '/#mailbox' => sub {
            my $self = shift;
            my $mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );
            my $status = $mailnesia->delete_mailbox($mailbox) ? 204 : 500;
            $self->res->headers->header('Content-Type' => 'text/plain;charset=UTF-8');
            return $self->render(status=>$status, data=>'');
        };

        # return an email in a mailbox suitable for displaying in JSON format,
        # or 404 error if not found.
        get '/#mailbox/#id' => sub {
            my $self = shift;
            my $mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );
            my $id = $1 if $self->param('id') =~ m/(\d+)/;

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

                # convert json fields to camel case (text_html => textHtml, text_plain => textPlain)
                my $text_html = delete $email_body->{'text_html'};
                $email_body->{'textHtml'} = $text_html if $text_html;
                my $text_plain = delete $email_body->{'text_plain'};
                $email_body->{'textPlain'} = $text_plain if $text_plain;

                return $self->render(
                    json => $email_body
                );
            } else {
                return $self->render(text => '', status => 404);
            }
        };

        # delete an email
        del '/#mailbox/#id' => sub {
            my $self = shift;
            my $mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );
            my $id = $1 if $self->param('id') =~ m/(\d+)/;
            $self->res->headers->header('Content-Type' => 'text/plain;charset=UTF-8');
            my $status = $mailnesia->delete_mail($mailbox, $id) ? 204 : 500;
            $self->res->headers->header('Content-Type' => 'text/plain;charset=UTF-8');
            return $self->render(status=>$status, data=>'');
        };

        # return an email in a mailbox in raw format, as received from a mail server
        get '/#mailbox/#id/raw' => sub {
            my $self = shift;
            my $mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );
            my $id = $1 if $self->param('id') =~ m/(\d+)/;

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

    # return the recent visitors of a mailbox
    get '/visitors/#mailbox' => sub {
        my $self = shift;
        my $mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );
        my $visitors = $config->get_formatted_visitor_list($mailbox);

        return $self->render (json => $visitors);
    };

    group {
        under '/alias';

        # get all aliases of a mailbox
        get '/#mailbox' => sub {
            my $self = shift;
            my $mailbox =  lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );
            my $alias_list = $mailnesia->get_alias_list($mailbox);
            return $self->render(json => $alias_list);
        };

        # add an alias to a mailbox
        post '/#mailbox/#alias' => sub {
            my $self = shift;
            my $mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );
            my $alias   = lc $mailnesia->get_url_decoded_mailbox ( $self->param( 'alias' ) );
            my $status = $mailnesia->setAlias($mailbox, $alias) ? 201 : 500;
            return $self->render(status=>$status, json=>$alias);
        };

        # modify an alias of a mailbox from alias to new_alias
        put '/#mailbox/#alias/#new_alias' => sub {
            my $self = shift;
            my $mailbox   = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox'   ) );
            my $alias     = lc $mailnesia->get_url_decoded_mailbox ( $self->param('alias'     ) );
            my $new_alias = lc $mailnesia->get_url_decoded_mailbox ( $self->param('new_alias' ) );
            my $status = $mailnesia->modifyAlias($mailbox, $alias, $new_alias) ? 200 : 500;
            return $self->render(status=>$status, json=>$new_alias);
        };

        # remove an alias from a mailbox
        del '/#mailbox/#alias' => sub {
            my $self = shift;
            my $mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );
            my $alias   = lc $mailnesia->get_url_decoded_mailbox ( $self->param( 'alias' ) );
            my $status = $mailnesia->removeAlias($mailbox, $alias) ? 204 : 500;
            $self->res->headers->header('Content-Type' => 'text/plain;charset=UTF-8');
            return $self->render(status=>$status, data => '');
        };

    };
};

app->secrets([$mailnesia->random_name_for_testing()]);
app->start;
