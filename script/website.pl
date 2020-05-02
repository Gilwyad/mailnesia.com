#!/usr/bin/perl -w

use strict;
use Mojolicious::Lite;

use FindBin;
use lib "$FindBin::Bin/../lib/";

use Mailnesia;
use Mailnesia::Email;
use Mailnesia::Config;
use EV;
use AnyEvent;
use Carp qw/cluck/;

=head1 website.pl

script contains all website pages where SQL access is required, including /mailbox/, /settings/.

=cut

my $mailnesia = Mailnesia->new({decode_on_open=>":encoding(UTF-8)"});
my $config    = Mailnesia::Config->new;
my $sitename  = $config->{sitename};
my $siteurl   = $config->{siteurl};

app->mode  ( $mailnesia->{devel} ? "development" : "production");
app->config(hypnotoad => {
        listen    => ['http://127.0.0.1:8080'],
        pid_file  => '/tmp/mailnesia-website.pid',
        workers   => 2,
        accepts   => 0
    });

app->log->info("started, mode: ". app->mode);

# cookies expire after this amount of seconds
my $cookie_expiration = \$config->{cookie_expiration};

# Global logic shared by all routes
under sub {
        my $self = shift;

        # mailbox derived from the requested URL, ends with / or @

        my $mailbox = $mailnesia->check_mailbox_characters(
                lc $mailnesia->get_url_decoded_mailbox ( $1 )
            )
        if $self->req->url->path =~ m!/(?:settings|mailbox)/([^/@]+)! ;


        # check SQL connection on each pageload, try to reconnect if fails
        $mailnesia->connect_sql();

        my $ip = $self->req->headers->header('X-Forwarded-For');

        if ($ip) {
            # redirect to captcha if too many mailbox requests
            if (  my $excess = $config->mailboxes_per_IP($ip,$mailbox,$config->{daily_mailbox_limit}) )
            {
                app->log->info("too many mailbox opened: $ip, $mailbox, $excess");
                if ($self->req->method eq 'GET')
                {
                    # save the mailbox in cookie so a redirect can be made after successful captcha verification
                    $self->cookie( mailbox => $mailbox, {path => '/', expires => time + $$cookie_expiration} ) if $mailbox;
                    $self->redirect_to(Mojo::URL->new->path('/captcha.html'));
                    return;
                }
                else
                {
                    $self->render(text => '', status => 403);
                    return;
                }
            }
            $config->log_ip($ip, $mailbox, $self->req->headers->user_agent);
        }

        my $language = lc $1 if
                (
                    $self->cookie('language') ||
                    $self->req->headers->header('accept-language') ||
                    "en"
                ) =~ m/^([a-z-]{2,5})/i;


        #language check:
        if ( not exists($mailnesia->{text}->{lang_hash}{$language}) )
        {
            # if we don't have this language
            if ( length $language > 2 )
            {
                # check if this is a language variant such as en-US
                my $two_letter_language_code = substr $language, 0, 2 ;
                if ( exists($mailnesia->{text}->{lang_hash}{$two_letter_language_code}) )
                {
                    # use the two letter code instead, for ex: en-US => en
                    $language = $two_letter_language_code;
                }
                else
                {
                    # default language
                    $language = 'en';
                }
            }
            else
            {
                # default language
                $language = 'en';
            }
        }

        #save language for each pageload
        $mailnesia->{language} = $language;

        # and in cookie
        $self->cookie( language => $language, {path => '/', expires => time + $$cookie_expiration} );

        $self->cookie( mailbox => $mailbox, {path => '/', expires => time + $$cookie_expiration} ) if $mailbox;


        # 403 Forbidden if mailbox banned
        if ($config->is_mailbox_banned( $mailbox ))
        {
            if ($self->req->method eq 'GET')
            {
                $self->stash(
                        mailbox   => $mailbox,
                        mailnesia => $mailnesia,
                        index_url => $mailnesia->{language} eq "en" ?
                        "/" :
                        "/".$mailnesia->{language}."/"
                    );

                $self->content(content => qq{<div class="alert-message error">This mailbox has been banned due to violation of our terms and conditions of service.</div>});
                $self->render(
                        template => $self->param('noheadernofooter') ? "" : "pages",
                        status => 403
                    );
                return;
            }
            else
            {
                $self->render(text => '', status => 403);
                return;
            }
        }

        # 403 Forbidden if IP banned
        if ($config->is_ip_banned( $ip ))
        {
            $self->stash(
                    mailbox   => $mailbox,
                    mailnesia => $mailnesia,
                    index_url => $mailnesia->{language} eq "en" ?
                    "/" :
                    "/".$mailnesia->{language}."/"
                );

            $self->content(content => qq{<div class="alert-message error">Your IP address has been banned from visiting this website, because it was listed on <a href="http://stopforumspam.com/">stopforumspam.com</a> for spamming activities.</div>});

            $self->render(
                    template => $self->param('noheadernofooter') ? "" : "pages",
                    status => 403
                );
            return;
        }

        # continue with request
        return 1;
    };



group {

        under '/mailbox';



=head2 GET /mailbox/mailboxname

list emails in a mailbox. If param noheadernofooter is used, omit any headers, footers, only print main content.

=cut

        get '/#mailbox' => {mailbox => 'default'} => sub {
                my $self = shift;

                # parameters:
                my $original_url_decoded_mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );

                my $mailbox = $mailnesia->check_mailbox_characters( $original_url_decoded_mailbox );

                my $emaillist_page = $self->param('p') =~ m/(\d+)/ ? $1 : 0;

                # this is used for ajax queries: when scrolling down the mailbox view, to automatically load the next page, and to check for new mail
                my $noheadernofooter = $self->param("noheadernofooter");

                # this is for polling for new mail
                my $newerthan = $1 if $self->param('newerthan') =~ m/(\d+)/;


                # forbidden if alias

                if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias})
                {

                    $self->stash(
                            mailbox => $mailbox,
                            mailnesia => $mailnesia,
                            index_url => $mailnesia->{language} eq "en" ?
                            "/" :
                            "/".$mailnesia->{language}."/"
                        );

                    $self->content(content => qq{<div class="alert-message warning">} .
                        $mailnesia->message('mailbox_is_an_alias',$mailbox) .
                        qq{</div>});

                    return $self->render
                    (
                        template => $noheadernofooter ? '' : 'pages'
                    );

                }

                if ($mailbox ne $original_url_decoded_mailbox)
                {
                    if ($noheadernofooter)
                    {
                        return $self->render(text => '', status => 400);
                    }
                    else
                    {
                        $self->stash(
                                mailbox   => $mailbox,
                                mailnesia => $mailnesia,
                                index_url => $mailnesia->{language} eq "en" ?
                                "/" :
                                "/".$mailnesia->{language}."/"
                            );

                        $self->content(content => qq{<div class="alert-message warning">} .
                            $mailnesia->message('invalid_characters',$mailbox) .
                            qq{</div>});

                        return $self->render
                        (
                            template => 'pages'
                        );
                    }
                }

                my $url_encoded_mailbox = $mailnesia->get_url_encoded_mailbox ($mailbox);

                my $email = Mailnesia::Email->new({dbh => $mailnesia->{dbh}});
                my $emaillist;

                if ($newerthan)
                {
                    $emaillist = $email->get_emaillist_newerthan(
                            $config->{date_format},
                            $mailbox,
                            $newerthan
                        );
                }
                else
                {
                    $emaillist = $email->get_emaillist(
                            $config->{date_format},
                            $mailbox,
                            $config->{mail_per_page},
                            $emaillist_page
                        );
                }

                if (not ref $emaillist)
                {
                    # error
                    if ($noheadernofooter)
                    {
                        return $self->render(text=> 'Internal Server Error', status => 500, format => 'txt' );
                    }
                    else
                    {
                        $self->content(content => 'Internal Server Error');
                        return $self->render(
                                status => 500,
                                template => 'pages'
                            );
                    }
                }

                elsif ((my $number_of_emails = scalar @{ $emaillist } ) == 0)
                {
                    # no emails

                    # return empty page if there is no new mail
                    return $self->render(text=> '', status => 204 ) if $newerthan;

                    $self->stash(
                            mailnesia            => $mailnesia,
                            mailbox              => $mailbox,
                            url_encoded_mailbox  => $url_encoded_mailbox,
                            index_url            => $mailnesia->{language} eq "en" ?
                            "/" :
                            "/".$mailnesia->{language}."/"
                        );

                    if ($noheadernofooter) # FIXME: is this used?
                    {
                        $self->render
                        (
                            text  => ''
                        );
                    }
                    else
                    {
                        $self->render
                        (
                            template  => 'emaillist_nomail',
                            format    => 'html',
                            handler   => 'ep',
                            layout    => 'mailbox_nomail'
                        );
                    }


                }
                else
                {

                    my $last_page = 0;

                    # if ( $number_of_emails == 1 and not $emaillist_page )
                    # {
                    #     # we got 1 email, displaying


                    #     $self->stash(
                    #             mailnesia            => $mailnesia,
                    #             mailbox              => $mailbox,
                    #             url_encoded_mailbox  => $url_encoded_mailbox
                    #         );

                    #     $self->render(
                    #             template  => 'emaillist',
                    #             format    => 'html',
                    #             handler   => 'ep',
                    #             layout    => 'mailbox_1_mail'
                    #         );

                    # }
                    # elsif ( $number_of_emails == $config->{mail_per_page} )
                    # {
                    #     # we got 1 page worth of emails, pagination needed, calculate last page
                    #     {
                    #         use integer;
                    #         $last_page = ($mailnesia->emailcount($mailbox) - 1) / $config->{mail_per_page};
                    #         # wont display next page link at 10 messages because of the -1
                    #     }

                    #     my $pagination_html =  emaillist_pagination($url_encoded_mailbox,$emaillist_page,$last_page);


                    #     $self->stash(
                    #             mailnesia            => $mailnesia,
                    #             mailbox              => $mailbox,
                    #             url_encoded_mailbox  => $url_encoded_mailbox,
                    #             emaillist            => $emaillist,
                    #             pagination           => $pagination_html
                    #         );


                    #     return $noheadernofooter ?
                    #     $self->render(
                    #             template  => 'emaillist_1page_mail',
                    #             format    => 'html',
                    #             handler   => 'ep'
                    #         )
                    #     :
                    #     $self->render(
                    #             template  => 'emaillist_1page_mail',
                    #             format    => 'html',
                    #             handler   => 'ep',
                    #             layout    => 'mailbox_1page_mail'
                    #         );

                    # }
                    # else
                    {
                        # more than 1 email but less than 1 page worth of emails
                        # if page was given, still need to calculate last page, pagination

                        my $pagination_html = "";

                        if ( not $newerthan and ( $emaillist_page or $number_of_emails == $config->{mail_per_page} ) )
                        {
                            # calculate pagination if we got 1 page worth of emails and not when polling for new mail
                            use integer;
                            $last_page = ($mailnesia->emailcount($mailbox) - 1) / $config->{mail_per_page};
                            $pagination_html = emaillist_pagination($url_encoded_mailbox,$emaillist_page,$last_page);
                        }


                        $self->stash(
                                mailnesia            => $mailnesia,
                                mailbox              => $mailbox,
                                url_encoded_mailbox  => $url_encoded_mailbox,
                                index_url            => $mailnesia->{language} eq "en" ?
                                "/" :
                                "/".$mailnesia->{language}."/",
                                emaillist            => $emaillist,
                                pagination           => $pagination_html
                            );


                        my $layout = "mailbox";
                        if ( $noheadernofooter or $newerthan )
                        {
                            $layout = ''
                        }

                        return $self->render(
                                template  => 'emaillist',
                                format    => 'html',
                                handler   => 'ep',
                                layout    => $layout
                            );

                    }

                }

            };









=head2 GET /mailbox/mailboxname/id

open an email

=cut

        get '/#mailbox/#id' => {mailbox => 'default'} => sub {
                my $self = shift;

                my $original_url_decoded_mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );

                my $mailbox = $mailnesia->check_mailbox_characters( $original_url_decoded_mailbox );

                my $id = $1 if $self->param('id') =~ m/(\d+)/;

                # this is used for ajax queries: when opening an email in the mailbox view (not on a new page with the arrow)
                my $noheadernofooter = $self->param("noheadernofooter");


                # forbidden if alias
                if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias})
                {

                    $self->stash(
                            mailbox   => $mailbox,
                            mailnesia => $mailnesia,
                            index_url => $mailnesia->{language} eq "en" ?
                            "/" :
                            "/".$mailnesia->{language}."/"
                        );

                    $self->content(content => qq{<div class="alert-message warning">} .
                        $mailnesia->message('invalid_characters',$mailbox) .
                        qq{</div>});

                    return $self->render
                    (
                        template => 'pages'
                    );

                }

                if ($mailbox ne $original_url_decoded_mailbox)
                {
                    if ($noheadernofooter)
                    {
                        return $self->render(text => '', status => 400);
                    }
                    else
                    {
                        $self->stash(
                            mailbox   => $mailbox,
                            mailnesia => $mailnesia,
                            index_url => $mailnesia->{language} eq "en" ?
                            "/" :
                            "/".$mailnesia->{language}."/"
                        );

                        $self->content(content => qq{<div class="alert-message warning">} .
                            $mailnesia->message('invalid_characters',$mailbox) .
                            qq{</div>});

                        return $self->render
                        (
                            template => 'pages'
                        );
                    }
                }


                my $email = Mailnesia::Email->new(
                        {
                            dbh => $mailnesia->{dbh},
                            to => [ $mailbox ],
                            id => $id
                        }
                    );

                my $email_body = $email->body($id) ;
                if ( $email_body )
                {

                    my @tabs = keys %$email_body;
                    my $tabs = '';
                    my $active_tab = $tabs[0]; # show first part or HTML part by default

                    # if the email has more than one parts display selector tabs
                    if (scalar @tabs > 1)
                    {
                        $tabs = '<ul class="tabs" data-tabs="tabs">';

                        foreach ( @tabs )
                        {
                            my $tab_name = $_;
                            $active_tab = $tab_name if m/text_html/i; # save HTML part as active

                            $tabs .= '<li';
                            $tabs .= ' class="active"' if m'text_html';
                            $tabs .= qq{><a href="#${tab_name}_${id}" title="} .
                            $mailnesia->message('prefer_html')->{'text'} .
                            $mailnesia->message('prefer_html')->{$tab_name} .
                            qq{">$tab_name</a></li>};
                        }

                        $tabs .= q{</ul>};
                    }



                    $self->stash(
                            mailnesia => $mailnesia,
                            tabs      => $tabs,
                            id        => $id,
                            active_tab=> $active_tab,
                            email     => $email_body,
                            date      => $email->date(),
                            from      => $email->from(),
                            to        => $email->to(),
                            subject   => $email->subject(),
                            mailbox   => $mailbox,
                            index_url => $mailnesia->{language} eq "en" ?
                            "/" :
                            "/".$mailnesia->{language}."/"
                        );

                    $self->render(
                            template  => 'email',
                            format    => 'html',
                            handler   => 'ep',
                            layout    => $noheadernofooter ? '' : 'mailbox_email'
                        );
                }
                else
                {
                    #no such mail
                    (my $url_encoded_mailbox = $mailbox) =~ s/\+/%2B/g;


                    $self->stash(
                            mailnesia           => $mailnesia,
                            mailbox             => $mailbox,
                            index_url           => $mailnesia->{language} eq "en" ?
                            "/" :
                            "/".$mailnesia->{language}."/",
                            url_encoded_mailbox => $url_encoded_mailbox
                        );

                    $self->render
                    (
                        template             => 'emaillist_nomail',
                        format               => 'html',
                        handler              => 'ep',
                        layout               => $noheadernofooter ? '' : 'mailbox_nomail'
                    );
                }

            };



=head2 POST /mailbox/mailboxname/id

delete email based on mailbox and id.  URL parameters:

mailbox  => name of mailbox
id       => id of mail

POST parameters:

delete   => 1

=cut

        post '/#mailbox/#id' => sub {
                my $self = shift;

                my $mailbox = $mailnesia->check_mailbox_characters( lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') ), 1 );
                my $id = $1 if $self->param('id') =~ m/(\d+)/;
                my $delete = $self->param('delete');


                # 400 bad request if missing parameters
                unless ( $mailbox and $id and $delete )
                {
                    return $self->render(
                            text   => 'Bad Request',
                            status => 400,
                            format => 'txt'
                        );
                }


                # forbidden if alias
                if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias})
                {
                    return $self->render(text   => '', status => 403);
                }


                if ($mailnesia->delete_mail($mailbox,$id))
                {
                    return $self->render
                    (
                        text => qq{<div class="alert-message success">Deleted message $id</div>}
                    );
                }
                else
                {
                    return $self->render
                    (
                        text => qq{<div class="alert-message error">Deleting message $id failed</div>},
                        status => 500
                    );
                }

            };




=head2 POST /mailbox/mailboxname

delete all emails in a mailbox. Parameters:

mailbox

mailbox  => name of mailbox
delete   => 1

=cut

        post '/#mailbox' => sub {
                my $self = shift;

                my $mailbox = $mailnesia->check_mailbox_characters( lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') ), 1 );
                my $delete = $self->param('delete');


                # 400 bad request if missing parameters
                unless ( $mailbox and $delete )
                {
                    return $self->render(
                            text => 'Bad Request',
                            status => 400,
                            format => 'txt'
                        );
                }


                # forbidden if alias
                if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias})
                {
                    return $self->render(text   => '', status => 403);
                }



                if ($mailnesia->delete_mailbox($mailbox))
                {
                    return $self->render
                    (
                        text => qq{<div class="alert-message success">Deleted all emails in $mailbox</div>}
                    );
                }
                else
                {
                    return $self->render
                    (
                        text => qq{<div class="alert-message error">Deleting all emails in $mailbox failed</div>},
                        status => 500
                    );
                }

            };






=head2 GET /mailbox/mailboxname/id/test_url_clicker

test URL clicker, show clicked and not clicked links

=cut

        get '/#mailbox/#id/test_url_clicker' => sub {
                my $self = shift;
                my $mailbox = $mailnesia->check_mailbox_characters( lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') ), 1 );
                my $id = $1 if $self->param('id') =~ m/(\d+)/;

                # 400 bad request if missing parameters
                unless ( $mailbox and $id )
                {
                    return $self->render(
                            text => 'Bad Request',
                            status => 400,
                            format => 'txt'
                        );
                }

                my $email = Mailnesia::Email->new (
                        {
                            dbh => $mailnesia->{dbh},
                            to  => [ $mailbox ],
                            id  => $id
                        }
                    );

                return $self->render (
                        text   => "INTERNAL SERVER ERROR",
                        status => 500,
                        format => 'txt'
                    )
                unless ref $email->{email};

                my ($clicked,$not_clicked) = $email->links(1);

                my $html =  q{<div class="alert-message block-message info"><h2>Clicked links:</h2><ul>};
                if (@$clicked)
                {
                    for (@$clicked)
                    {
                        $html .= qq{<li><a href="$_">$_</a></li>};
                    }
                }
                else
                {
                    $html .= q{<span class="label important">None</span>};
                }


                $html .= "</ul><h2>Not clicked links:</h2><ul>";
                if (@$not_clicked)
                {
                    for (@$not_clicked)
                    {
                        $html .= qq{<li><a href="$_">$_</a></li>};
                    }
                }
                else
                {
                    $html .= q{<span class="label important">None</span>};
                }
                $html .= q{</ul><p>Please <a href="/contact.html">get in touch</a> if you believe a link was not clicked, or one was clicked mistakenly. Thanks!</p></div>};

                return $self->render
                (
                    text => $html
                );

            };








=head2 GET /mailbox/mailboxname/id/raw

show original (raw) view of email in plain text

=cut

        get '/#mailbox/#id/raw' => sub {
                my $self = shift;
                my $mailbox = $mailnesia->check_mailbox_characters( lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') ), 1 );
                my $id = $1 if $self->param('id') =~ m/(\d+)/;

                # 400 bad request if missing parameters
                unless ( $mailbox and $id )
                {
                    return $self->render(
                            text   => 'Bad Request',
                            status => 400,
                            format => 'txt'
                        );
                }

                my $email = Mailnesia::Email->new({dbh=>$mailnesia->{dbh}});

                return $self->render (
                        text   => $email->get_email (
                                $mailbox,
                                $id
                            ),
                        format => 'txt'
                    );

            };





    };



#  script is called under /settings, all routes are valid under /settings
group
{

    under '/settings';


=head2 POST /settings/mailbox/alias/set

Set alias.  POST values:

alias    => the new alias to set

=cut

    post '/#mailbox/alias/set' => sub {

            my $self    = shift;
            my $mailbox = $mailnesia->check_mailbox_characters( lc $self->param('mailbox'),   1);
            my $alias   = $mailnesia->check_mailbox_characters( lc $self->param('alias'), 1);

            # 400 bad request if no mailbox or alias was given
            unless ( $mailbox and $alias )
            {
                $self->render(text => 'Bad Request', status => 400);
                return ;
            }


            # forbidden if alias
            if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias})
            {
                return $self->render
                (
                    text   => '',
                    status => 403
                );
            }

            # check if the alias can be set
            my $status = $mailnesia->setAlias_check($mailbox, $alias);

            if ($status->[0] == 200)
            {
                if ($mailnesia->setAlias($mailbox,$alias))
                {
                    $self->render(text => $status->[1] );
                    return 1;
                }
                else
                {
                    return $self->render(text => 'Internal Server Error', status => 500);
                }
            }
            else
            {
                $self->render(text => $status->[1], status => $status->[0]);
                return;
            }


        };


=head2 POST /settings/mailbox/alias/modify

Modify alias.  POST values:

remove_alias => the current alias to modify
alias    => the new alias to set

=cut

    post '/#mailbox/alias/modify' => sub {

            my $self             = shift;
            my $mailbox          = $mailnesia->check_mailbox_characters( lc $self->param('mailbox'),      1);
            my $alias            = $mailnesia->check_mailbox_characters( lc $self->param('alias'),        1);
            my $remove_alias     = $mailnesia->check_mailbox_characters( lc $self->param('remove_alias'), 1);

            unless ($mailbox and $alias and $remove_alias)
            {
                #ERROR
                $self->render(text => 'Bad Request', status => 400);
                return ;
            };


            # forbidden if alias
            if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias})
            {
                return $self->render
                (
                    text   => '',
                    status => 403
                );
            }


            # check if the alias can be set
            my $status = $mailnesia->setAlias_check($mailbox, $alias);

            if ($status->[0] == 200)
            {
                if ($mailnesia->modifyAlias($mailbox,$remove_alias,$alias))
                {
                    $self->render(text => $status->[1] );
                    return 1;
                }
                else
                {
                    return $self->render(text => 'Internal Server Error', status => 500);
                }
            }
            else
            {
                $self->render(text => $status->[1], status => $status->[0]);
                return;
            }

        };

=head2 POST /settings/mailbox/alias/remove

Remove alias.  POST values:

remove_alias => the current alias to remove

=cut

    post '/#mailbox/alias/remove' => sub {

            my $self            = shift;
            my $mailbox         = $mailnesia->check_mailbox_characters( lc $self->param('mailbox'),      1);
            my $remove_alias    = $mailnesia->check_mailbox_characters( lc $self->param('remove_alias'), 1);


            unless ($mailbox and $remove_alias)
            {
                #ERROR
                $self->render(text => 'Bad Request', status => 400);
                return ;
            }


            # forbidden if alias
            if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias})
            {
                return $self->render
                (
                    text   => '',
                    status => 403
                );
            }



            if ($mailnesia->removeAlias($mailbox,$remove_alias))
            {
                $self->render(text => $mailnesia->message('alias_delete_success',$mailbox,$remove_alias) );
                return 1;
            }
            else
            {
                return $self->render(text => 'Internal Server Error', status => 500);
            }

        };



=head2 POST /settings/mailbox/clicker

turn URL clicker on/off.  POST values:

clicker=true perl value => ON
clicker=0               => OFF

=cut

    post '/#mailbox/clicker' => sub {

            my $self = shift;
            my $mailbox        = $mailnesia->check_mailbox_characters( lc $self->param('mailbox'), 1 );
            my $clicker        = $self->param('set_clicker');

            # 400 bad request if no mailbox was given
            unless ( $mailbox )
            {
                $self->render(text => 'Bad Request', status => 400);
                return ;
            }


            # forbidden if alias
            if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias})
            {
                return $self->render
                (
                    text   => '',
                    status => 403
                );
            }

            if ($clicker)
            {
                if ( $config->enable_clicker( $mailbox ) )
                {
                    $self->render(text => $mailnesia->message('clicker_on_html'))
                }
                else
                {
                    return $self->render(text => 'Internal Server Error', status => 500);
                }
            }

            else

            {
                if ( $config->disable_clicker( $mailbox ) )
                {
                    $self->render(text =>  $mailnesia->message('clicker_off_html'))
                }
                else
                {
                    return $self->render(text => 'Internal Server Error', status => 500);
                }

            }
        };





=head2 GET /settings/mailboxname

show the preferences for the requested mailbox

=cut

    get '/#mailbox' => {mailbox => 'default'} => sub {
            my $self = shift;

            my $original_url_decoded_mailbox = lc $mailnesia->get_url_decoded_mailbox ( $self->param('mailbox') );

            my $mailbox = $mailnesia->check_mailbox_characters( $original_url_decoded_mailbox );



            # forbidden if alias
            if ($mailnesia->check_mailbox_alias($mailbox)->{is_alias})
            {
                return $self->render
                (
                    text   => '',
                    status => 403
                );
            }

            if ($mailbox ne $original_url_decoded_mailbox)
            {
                $self->stash(
                        mailbox   => $mailbox,
                        mailnesia => $mailnesia,
                        index_url => $mailnesia->{language} eq "en" ?
                        "/" :
                        "/".$mailnesia->{language}."/"
                    );

                $self->content(content => qq{<div class="alert-message warning">} .
                    $mailnesia->message('invalid_characters',$mailbox) .
                    qq{</div>});

                return $self->render
                (
                    template => 'pages'
                );
            }


            # clicker status
            my $clicker_enabled = $config->is_clicker_enabled($mailbox) ? 1 : 0;
            my $clicker_html = qq{<div id="clicker-status">};
            $clicker_html .= $clicker_enabled ?
            $mailnesia->message('clicker_on_html') :
            $mailnesia->message('clicker_off_html') ;

            $clicker_html .= qq{</div><input type="checkbox" name="checkbox" value="value" id="clicker_checkbox"} ;
            $clicker_html .= "checked" if $clicker_enabled ;
            $clicker_html .= qq{ onClick='return toggleClicker()'>} ;



            my $alias_list = $mailnesia->get_alias_list($mailbox);

            # The "stash" in Mojolicious::Controller is used to pass data to templates
            $self->stash(
                    mailnesia           => $mailnesia,
                    mailbox             => $mailbox,
                    alias_list          => $alias_list,
                    index_url           => $mailnesia->{language} eq "en" ?
                    "/" :
                    "/".$mailnesia->{language}."/",
                    clicker_html        => $clicker_html,
                );

            $self->render(
                    template  => 'settings',
                    format    => 'html',
                    handler   => 'ep'
                );


        } => 'settings';

};



=head2 POST /random/

redirect to a random empty mailbox

=cut

get '/random/' => sub {
        my $self = shift;

        my $safety_counter = 0;
        my $randomname;

      RANDOM: while ( $mailnesia->has_email_or_alias( $randomname = $mailnesia->random_name($mailnesia->{language}) ) )
        {
            $safety_counter++;
            if ($safety_counter > 10)
            {
                # if cannot get an unused mailbox in 10 tries, render error page
                $self->stash(
                        mailnesia => $mailnesia,
                        index_url => $mailnesia->{language} eq "en" ?
                        "/" :
                        "/".$mailnesia->{language}."/",
                        mailbox   => ''
                    );

                $self->content(content => 'Internal Server Error');
                return $self->render(
                        status => 500,
                        template => 'page'
                    );
            }

        }
        $self->redirect_to(Mojo::URL->new->path("/mailbox/$randomname"));

    };





=head2 POST /redirect/

redirect to /mailbox/mailbox_name. Parameters:

mailbox => the mailbox to redirect to

=cut

post '/redirect/' => sub {
        my $self = shift;

        my $mailbox = $mailnesia->check_mailbox_characters( $self->param('mailbox'), 1 ) ;
        my $url;

        if ($mailbox)
        {
            # if valid mailbox
            $url = "/mailbox/$mailbox" ;          # FIXME: encode url? a+b vs a%2Bb ?
        }
        else
        {
            # otherwise redirect to main page with selected language
            $url = $mailnesia->{language} eq 'en' ?
            "/" :
            "/" . $mailnesia->{language} . "/"
        }

        $self->res->code(303);
        return $self->redirect_to ( Mojo::URL->new->path( $url ) );

    };



=head2 GET /stats.html

the statistics page

=cut

get '/stats.html' => sub{
        my $self = shift;

        my $sql = qq{SELECT to_char ( CURRENT_TIMESTAMP - arrival_date, 'DD" days "HH24" hours."') FROM emails  ORDER BY id ASC LIMIT 1;};

        $self->stash(
                mailnesia => $mailnesia,
                index_url => $mailnesia->{language} eq "en" ?
                "/" :
                "/".$mailnesia->{language}."/",
                mailbox   => $mailnesia->check_mailbox_characters( $self->cookie('mailbox') )
            );

        my $query = $mailnesia->{dbh}->prepare ($sql) or
        return internal_server_error();

        $query->execute;
        my $time;
        $query->bind_columns(\$time) ;
        $query->fetch;

        return internal_server_error() unless $time;


        my $page = q{<h2>Statistics</h2>} .
        q{<h3>E-mails</h3>} .
        qq{<p>Currently emails are deleted within $time</p>} .
        q{<h3>E-mails received and incoming bandwidth / day</h3>} .
        q{<div id="dygraph" style="width:800px; height:400px;"></div>} .
        q{<script type="text/javascript" src="/js/dygraph-combined.js"></script><script type="text/javascript">
g = new Dygraph(
    document.getElementById("dygraph"),
    "Date,Email,Bandwidth\n"};

        $sql = 'SELECT * FROM (SELECT * FROM emailperday ORDER BY day DESC LIMIT 180) AS t ORDER BY t.day';
        $query = $mailnesia->{dbh}->prepare ($sql) or internal_server_error();
        $query->execute or internal_server_error();


        while ( my @h = $query->fetchrow_array )
        {
            $page .= ' + "' . $h[0] . "," . $h[1] . "," . ( $h[2] * 1048576 ) . '\n"';
        }

        $page .= ", {
series:
{
    Bandwidth : { axis : 'y2' }
},
digitsAfterDecimal: 0,
labelsKMG2: true,
ylabel: 'number of emails',
y2label: 'bandwidth (bytes)'
});</script>";

        $self->content(content => $page);
        $self->render
        (
            template => 'pages'
        );


    };


app->secrets([$mailnesia->random_name_for_testing()]);
app->start;


=head2 emaillist_pagination

construct emaillist pagination html. Parameters:
 - mailbox name, URL encoded
 - page number we're currently on
 - last page number

=cut

sub emaillist_pagination
{
    my $url_encoded_mailbox = shift;
    my $emaillist_page = shift;
    my $last_page = shift;

    my $number_of_page_links_to_display_next_to_the_current_in_both_sides = 8;
    my $innerPages ;
    my $separator = " · ";

    #previous page:
    if ($emaillist_page > 0)
    {
        $innerPages .= qq{<li><a href="/mailbox/$url_encoded_mailbox?p=}.
        ($emaillist_page-1).qq{">&larr; }.
        $mailnesia->message('previous').
        qq{</a></li>};
    }
    else
    {
        # first page
        $innerPages .=  qq{<li class="prev disabled"><a href="#">&larr; }.
        $mailnesia->message('previous').
        qq{</a></li>};
    }

    for ($emaillist_page - $number_of_page_links_to_display_next_to_the_current_in_both_sides .. $emaillist_page + $number_of_page_links_to_display_next_to_the_current_in_both_sides)
    {
        next if $_ < 0;
        last if $_ > $last_page;

        # selected page
        $innerPages .= qq{<li};
        $innerPages .= qq{ class="active"} if ($emaillist_page == $_);
        $innerPages .= qq{><a title="}.$mailnesia->message('page',$_+1).qq{" href="/mailbox/$url_encoded_mailbox?p=$_">}.($_+1).qq{</a></li>};
    }

    #next page:
    if ( $emaillist_page < $last_page )
    {
        $innerPages .= qq{<li><a id="next" title="}.$mailnesia->message('next').
        qq{" href="/mailbox/$url_encoded_mailbox?p=}.
        ($emaillist_page+1).qq{">}.
        $mailnesia->message('next').
        qq{ &rarr;</a></li>};
    }
    else
    {
        # on last page
        $innerPages .=  qq{<li class="next disabled"><a href="#">&rarr; }.
        $mailnesia->message('next').
        qq{</a></li>};
    }

    my $pagination = qq{<div class="pagination"><ul><li};
    $pagination .= qq{ class="disabled"} unless $emaillist_page;
    $pagination .= qq{><a title="}.$mailnesia->message('newest').
    qq{" href="/mailbox/$url_encoded_mailbox?p=0">&#x21e4;</a></li>};
    $pagination .= $innerPages;
    $pagination .= qq{<li};
    $pagination .= qq{ class="disabled"} if $emaillist_page >= $last_page;
    $pagination .= qq{><a title="}.$mailnesia->message('oldest').
    qq{" href="/mailbox/$url_encoded_mailbox?p=$last_page">&#x21e5;</a></li>};
    $pagination .= '</ul></div>';

    return $pagination ;


}


sub internal_server_error {
        my $self = shift;
        return $self->render(text => 'Internal Server Error', status => 500) ;
}
