=head1 NAME

Mailnesia::Email - displaying emails

=head1 SYNOPSIS

use Mailnesia::Email;

my $email = Mailnesia::Email->new({raw_email=>$raw_email});

my ($body,@tabs) = $email->body($_[1]);

my ($clicked,$not_clicked) = $email->links;

=head1 DESCRIPTION

main program to display emails

=cut

package Mailnesia::Email;

use Email::MIME;
use Encode qw(encode decode);
use Encode::HanExtra;
use Encode::Alias;
require Encode::Detect;
use Encode::Detect::Detector;
use HTML::Scrubber;
use Compress::Snappy;
use POSIX qw(strftime);
use DBD::Pg qw(:pg_types);

# email encoding aliases
define_alias(
        "CN-GB"           => "GB2312",
        #      "ANSI_X3.4-1968" => "US-ASCII", # my charset regexp does not accept a dot
        "ANSI_X3"         => "US-ASCII",
        "UT-8"            => "UTF-8",
        "win-1251"        => "windows-1251",
        "iso"             => "ISO-8859-1",
        qr/latin(\d+)/i     => '"ISO-8859-$1"',
        qr/iso-8559-(\d+)/i => '"ISO-8859-$1"',
        qr/utf\-?8/i        => '"UTF-8"',
        "utf"               => "UTF-8",
        "x-mac-cyrillic"    => "MacCyrillic",
        "windows-1252http-equivContent-Type" => "windows-1252"
    );

# regex for clicking links
my $click = qr"confirm|
               activat[ei]|
               register|
               regid[^a-z]|
               reg[^a-z]|
               \bvalidat[ei]|
               accept|
               aktival|
               regisztracio|
               verify|
               verification|
               invit[ae]|
               subscrib|
               signup|
               soundcloud.com/emails/|
               mail.google.com/mail/vf-|
               \bcheck\b|
               wqrw/podziekowania\?id=\d+&key=[a-z0-9]+|
               \bact\b|
               yify-torrents.com/[a-z0-9]+"ix;

# regex for not clicking links
my $noclick = qr"opt[^a-z]?out|
                 deactivat[ei]|
                 reject|
                 unsubscrib|
                 leiratk|
                 delete|
                 cancel|
                 block|
                 unsub[^a-z]|
                 [^a-z]spam[^a-z]|
                 [^a-z]report[^a-z]|
                 [^a-z]remove[^a-z]|
                 \btwitter\.com\b|
                 \bsammobile.com\b|
                 mail.google.com/mail/uf-|
                 reset"ix;

my %encodings;         # stores the Encode objects corresponding to an
                       # encoding, saving 22ms time by not calling
                       # find_encoding() each time!

### redefine to croak on fewer emails

{
    package Email::Simple::Header;
    my $valid_cte = qr/([78]bit)|(base64)|(quoted-printable)|(binary)/i ;

    *Email::Simple::Header::_header_to_list = sub {
            my ($self, $head, $mycrlf) = @_;

            my @headers;

            my $crlf = Email::Simple->__crlf_re;

            while ($$head =~ m/\G(.+?)$crlf/go)
            {
                local $_ = $1;
                if (s/^\s+// or not /^([^:]+):\s*(.*)/)
                {
                    # This is a continuation line. We fold it onto the end of
                    # the previous header.
                    next if !@headers; # Well, that sucks.  We're continuing nothing?

                    #              warn "-1: " . $headers[-1] . " -2: " . $headers[-2];

                    if (lc $headers[-2] eq 'content-transfer-encoding')
                    {
                        # if we are continuing a content-tranfer-encoding header
                        if ($headers[-1])
                        {
                            # and there is actually something to continue, validate cte
                            $headers[-1] = $self->_validate_cte ( $headers[-1] . " $_" )
                        }
                        else
                        {
                            # validate only the "continuing" part
                            $headers[-1] = $self->_validate_cte ( $_ )
                        }
                    }
                    else
                    {
                        # original code
                        $headers[-1] .= $headers[-1] ? " $_" : $_;
                    }

                }
                else
                {
                    if (lc $1 eq 'content-transfer-encoding')
                    {
                        # validate cte
                        push @headers, $1, $self->_validate_cte($2);
                    }
                    else
                    {
                        # original code
                        push @headers, $1, $2;
                    }
                }
            }

            return \@headers;
        };

    *Email::Simple::Header::_validate_cte = sub {
            my ($self,$cte) = @_;
            if ($cte =~ $valid_cte)
            {
                # return only a valid cte
                return $+;
            }
            else
            {
                # default transfer encoding
                return "7bit";
            }
        };
}


### saved static objects: ###

# to make links clickable at the text 2 html conversion
my $url_regex = qr{(https?://.+?)(&gt;|&lt;|&quot;|<|>|\t|\n|\'|\"|\s|$)};

# filter styles at html scrub conversion
my $style_filter = qr!^
                      (?:
                      [\-\,\.\'\"\:\/\;a-z0-9\%\s]+
                      | (?:rgb\([\d, ]+\))?
                      | (?:\#[0-9a-f]{3,6})?
                      )+
                      $!xi;

# html scrub object
my $scrubber = HTML::Scrubber->new
(
    allow => [ qw[a abbr acronym address area b big blockquote br button caption center cite code col colgroup dd del dfn dir div dl dt em fieldset font form h1 h2 h3 h4 h5 h6 hr i img input ins kbd label legend li map menu ol optgroup option p pre q s samp select small span strike strong sub sup table tbody td textarea tfoot th thead tr tt u ul var] ],
    rules => [
            a => {
                    href  => qr{^(?!(?:java)?script)}i,
                    style => $style_filter
                },
            img => {
                    src   => qr{^(?:https?://)|(?:cid)}i,
                    style => $style_filter,
                }
        ],

    default => [ undef,
                 {
                     align        => 1,
                     alt          => 1,
                     axis         => 1,
                     border       => 1,
                     cellpadding  => 1,
                     cellspacing  => 1,
                     class        => 1,
                     clear        => 1,
                     cols         => 1,
                     colspan      => 1,
                     color        => 1,
                     height       => 1,
                     hspace       => 1,
                     id           => 1,
                     label        => 1,
                     maxlength    => 1,
                     media        => 1,
                     name         => 1,
                     rel          => 1,
                     rev          => 1,
                     rows         => 1,
                     rowspan      => 1,
                     size         => 1,
                     span         => 1,
                     style        => $style_filter,
                     title        => 1,
                     type         => 1,
                     usemap       => 1,
                     valign       => 1,
                     value        => 1,
                     vspace       => 1,
                     width        => 1,
                     '*'          => 0,  # deny all other attributes
                 }]
);



=head2 new

my $email = Mailnesia::Email->new({
       raw_email => $data,
       dbh       => $dbh,
       to        => \@to,
       id        => $id
      });

raw_email: the email received in the SMTP transaction

dbh: SQL connection handle

to: array of mailboxes

id: id of email

If to and id is given, get the raw_email using get_email, else use the parameter raw_email.

=cut

sub new {
        my $package = shift;
        my $options = shift;

        my $self = bless {
                raw_email  => $options->{raw_email},
                dbh        => $options->{dbh},
                mailbox    => $options->{to}
            },$package;

        if ( $options->{to}->[0] and $options->{id} )
        {
            $self->{email} = Email::MIME->new(
                    $self->get_email(
                            $options->{to}->[0],
                            $options->{id}
                        )
                )
        }
        elsif ($options->{raw_email})
        {
            $self->{email} = Email::MIME->new($self->{raw_email})
        }

        return $self;
    }

=head2 get_emaillist

fetch emails for a given mailbox from SQL: execute SELECT query and return fetchall_arrayref. Parameters:

PSQL date format
mailbox
number of emails on one page
page number to get

=cut

sub get_emaillist
{
    my $self             = shift;
    my $date_format      = shift;
    my $mailbox          = shift;
    my $mail_per_page    = shift;
    my $page             = shift;

    my $query = $self->{dbh}->prepare (
                "SELECT
id,
to_char( arrival_date, ?),
email_from,
email_to,
email_subject
FROM emails
WHERE mailbox = ?
ORDER BY arrival_date DESC
LIMIT ? OFFSET ?")
    or return undef;

    $query->execute(
            $date_format,
            $mailbox,
            $mail_per_page,
            $mail_per_page * $page
        )
    or return undef;

    return $query->fetchall_arrayref()

}


=head2 get_emaillist_newerthan

fetch emails for a given mailbox from SQL which are newer than what is
displayed on page: execute SELECT query and return
fetchall_arrayref. Parameters:

PSQL date format
mailbox
id of newest email currently on page

=cut

sub get_emaillist_newerthan
{
    my $self             = shift;
    my $date_format      = shift;
    my $mailbox          = shift;
    my $newerthan        = shift;

    my $query = $self->{dbh}->prepare (
                "SELECT
id,
to_char( arrival_date, ?),
email_from,
email_to,
email_subject
FROM emails
WHERE mailbox = ?
AND id > ?
ORDER BY arrival_date DESC")
    or return undef;

    $query->execute(
            $date_format,
            $mailbox,
            $newerthan
        )
    or return undef;

    return $query->fetchall_arrayref()

}




=head2 get_email

fetch email based on mailbox and id from SQL: execute SELECT query and return fetchall_arrayref. Parameters:

mailbox
id

=cut

sub get_email
{
    my $self             = shift;
    my $mailbox          = shift;
    my $id               = shift;
    my $raw_email ;


    my $query = $self->{dbh}->prepare (
            q{SELECT email FROM emails WHERE mailbox=? AND id=? }
        ) or return undef;

    $query->execute($mailbox,$id) or return undef;
    $query->bind_columns(\$raw_email);
    $query->fetch;

    return decompress $raw_email;
}


=head2 body

Return email suitable for printing on webpage.  Parameters:

 - email ID
 - which part to return, "text_html" or "text_plain" etc, defaults to all

$body = $email->body(15351354,"text_html")
$body = $email->body

returns array of which the first element is the email in html, consecutive elements are the email MIME part names

=cut

sub body {
        my $self            = shift;
        my $id              = shift;
        my $selected_part   = shift ;
        my $active          = "text_plain";


        my %complete_decoded_body;
        my $complete_decoded_body = "";

        $self->{"email"}->walk_parts(
                sub {
                        my $part = shift;
                        my $content_type = $part->content_type || "";

                        return if ($content_type =~ m"^multipart/"i);

                        my $key = "text_plain";
                        my $filename = $part->filename;

                        if ($content_type)
                        {
                            $key = $content_type =~ m,^([a-z]+)/([a-z]+),i ?
                            "$1_$2" :
                            "other";
                        }


                        if ($content_type =~ m"^text/"i or
                            $content_type =~ m"^message/"i or
                            ! $content_type )
                        {
                            my $charset = $1 if
                            $content_type =~ m"charset\s*=\s*[\"\']?([a-z0-9_-]+)"i;

                            my $body = decode_charset ($part->body,$charset);

                            if ($content_type =~ m"^text/html"i)
                            {
                                $complete_decoded_body{"${key}_${id}"} .= $complete_decoded_body{"${key}_${id}"} ?
                                qq{<div class="alert-message info">$content_type</div>}.
                                $scrubber->scrub($body) :
                                $scrubber->scrub($body);
                                $active = "text_html";
                            }
                            else
                            {
                                $complete_decoded_body{"text_plain_$id"} .= $complete_decoded_body{"text_plain_$id"} ?
                                qq{<div class="alert-message info">$content_type</div>} .
                                &text2html($body) :
                                &text2html($body) ;
                            }
                        }
                        elsif ($content_type =~ m"^image/"i)
                        {
                            return if $part->header("Content-ID"); # this is an html embedded image, processed separately

                            my $type = $1 if $content_type =~ m!(\w+/\w+)!;

                            $complete_decoded_body{"$key\_$id"} .= qq{<div class="page-header"><h2>$filename<small>$type</small></h2></div>}.
                            qq{<img alt="$filename" src="data:$type;}.
                            $part->header("Content-Transfer-Encoding").
                            ",".
                            $part->body_raw. qq{">} ;
                        }
                        else
                        {       # any other attachment
                            my $type = $1 if $content_type =~ m!(\w+/\w+)!;

                            $complete_decoded_body{"$key\_$id"} .= qq{<div class="page-header"><h2>$filename<small>$type</small></h2></div>}.
                            qq{<a title="download $content_type" href="data:$type;}.
                            $part->header("Content-Transfer-Encoding").
                            ",".
                            $part->body_raw. qq{">Download $content_type</a>}
                        }
                    }
            );

        $complete_decoded_body{"text_html_$id"} =~ s/(?<=src=\")cid:(.*?)(?=\")/$self->cid2dataurl($1)/eig if
        $complete_decoded_body{"text_html_$id"};

        if ($selected_part)     # return selected part
        {
            return
                          qq{<div id="$selected_part" class="active">}.
                          $complete_decoded_body{"${selected_part}_${id}"}.
                          q{</div>}
                          ;
        }
        else                    # return each part concatenated
        {
            while (my ($key,$value) = each %complete_decoded_body)
            {
                next unless $value;

                $complete_decoded_body .= $complete_decoded_body{$key} = qq{<div id="$key"};
                $complete_decoded_body .= qq{ class="active"} if $key =~ $active;
                $complete_decoded_body .= ">" . $value . q{</div>};
            }
        }




        return ( $complete_decoded_body, keys %complete_decoded_body );

    }




=head2 body_rss

Return email suitable for RSS.  Parameters:

 - email ID
 - which part to return, "html" or "plain", defaults to the one that is greater (in bytes)

$body_rss = $email->body(15351354,"plain")

=cut

sub body_rss {
        my $self = shift;
        my $selected_part  = shift ;

        my %complete_decoded_body;
        my $complete_decoded_body;

        $self->{"email"}->walk_parts(
                sub {
                        my $part = shift;
                        my $content_type = $part->content_type || "";

                        if ($content_type =~ m"^text/"i or
                            $content_type =~ m"^message/"i or
                            ! $content_type )
                        {
                            my $charset = $1 if
                            $content_type =~ m"charset\s*=\s*[\"\']?([a-z0-9_-]+)"i;

                            my $body = decode_charset ($part->body,$charset);

                            if ($content_type =~ m"^text/html"i)
                            {
                                $complete_decoded_body{"html"} .= $scrubber->scrub($body) ;
                            }
                            else
                            {
                                $complete_decoded_body{"plain"} .= $body;
                            }
                        }
                    }
            );

        if ($selected_part && $complete_decoded_body{$selected_part}) # return only selected part, if exists
        {
            return encode("utf-8",
                          $complete_decoded_body{$selected_part}
                      );
        }
        else                    # return whichever part is bigger
        {
            return encode("utf-8",
                          (length $complete_decoded_body{"html"} > length $complete_decoded_body{"plain"}) ?
                          $complete_decoded_body{"html"} : $complete_decoded_body{"plain"}
                      );
        }

    }



=head2 body_text_nodecode

Return body text without any decoding or processing, for the links.

TODO: check if it works with unicode URL's, then check if it fails
because there's no decoding of text here.

$email->body_text_nodecode

=cut

sub body_text_nodecode {
        my $self = shift;
        return $self->{"body_text_nodecode"} ||= do {

                my $complete_body;

                $self->{"email"}->walk_parts(
                        sub {
                                my $part = shift;
                                my $content_type = $part->content_type || "";

                                if ($content_type =~ m"^text/"i or
                                    $content_type =~ m"^message/"i or
                                    ! $content_type )
                                {
                                    $complete_body .= $part->body;
                                }
                            }
                    );
                $complete_body;
            }
    }

=head2 cid2dataurl

Return the part identified by "content id", as data url. Used for images.

=cut

sub cid2dataurl {


        my $self = shift;
        my $cid  = shift;
        my $dataurl;

        $self->{email}->walk_parts(sub{
                                           my ($part) = @_;
                                           return unless $part->header("Content-ID") eq "<$cid>";

                                           my $type = $1 if $_->content_type =~ m!(\w+/\w+)!i;

                                           $dataurl = "data:$type;".
                                           $_->header("Content-Transfer-Encoding").
                                           ",".
                                           $_->body_raw ;
                                       });

        return $dataurl || "content not found";
    }


=head2 date

email date header in utf8

$email->date

=cut

sub date {
        my $self = shift;
        return $self->{"date"} ||=
        do  {
                my $date;
                if ($date = $self->{email}->header("Date"))
                {
                    $date =~ s/[^A-Za-z0-9:, \+\-]/ /g;
                    $date;
                }
                else
                {
                    $date = strftime "%a, %e %b %Y %H:%M:%S %z\n", localtime;
                }
            }
    }

=head2 subject

email subject header in utf8

$email->subject

=cut

sub subject {
        my $self = shift;
        $self->{"subject"} ||= escHTML( $self->{email}->header("Subject") );
    }

=head2 to

email to header in utf8

$email->to

=cut


sub to {
        my $self = shift;
        $self->{"to"} ||= escHTML ( $self->{email}->header("To") );
    }

=head2 from

email from header in utf8

$email->from

=cut

sub from {
        my $self = shift;
        $self->{"from"} ||= escHTML ( $self->{email}->header("From") );
    }

=head2 store

$email->store()

store $email in SQL

=cut

sub store {
        my $self = shift;
        my $is_spam = shift;    # TODO: unimplemented

        my $dbh = $self->{dbh};
        my $query = $dbh->prepare
        ("INSERT INTO emails (email_date, email_from, email_to, email_subject, mailbox, email)".
         " VALUES (?::varchar(31),?::varchar(100),?::varchar(100),?::varchar(200),?::varchar(30),?)")
        or die "prepare failed: $!\n";

        $query->bind_param(6, undef, { pg_type => DBD::Pg::PG_BYTEA });

        foreach my $mailbox ( @ {$self->{"mailbox"} } )
        {
            my $real_mailbox;
            my $alias_query = $dbh->prepare("SELECT mailbox FROM mailbox_alias WHERE alias=?");
            $alias_query->execute($mailbox);
            $alias_query->bind_columns(\$real_mailbox);
            $alias_query->fetch;
            unless ($query->execute
                    (
                        $self->date,
                        encode("UTF-8", $self->from),
                        encode("UTF-8", $self->to),
                        encode("UTF-8", $self->subject),
                        $real_mailbox || $mailbox,
                        compress ($self->{raw_email})
                    )
                )
            {
                # error storing email
                return undef;
            }
        }

        return 1;
    }


=head2 links

return array references of links to click and not click

=cut

sub links  {

        my $self=shift;
        #  my %urls;
        my $body = $self->body_text_nodecode;

        my (%clicked,%not_clicked);

        # this caused an endless loop on the server with perl 5.10.1: while ($self->body =~ ...
        while ($body =~ m!(https?://(?:www\.)?[^\s\"\'<>/]+?/[^\s\"\'<>]+)!gi)
        {
            ( my $url = $1 ) =~ s/&amp;/&/g;

            if ($url =~ $noclick)
            {
                ++$not_clicked{$url};
            }
            elsif ($url =~ $click)
            {
                ++$clicked{$url};
            }
            else
            {
                ++$not_clicked{$url};
            }
        }

        return [keys %clicked],[keys %not_clicked];

    }


### no more OOP methods, just plain subroutines

sub escHTML {
        my $text = shift;

        $text =~ s/&/&#x26;/g;
        $text =~ s/</&#x3c;/g;
        $text =~ s/>/&#x3e;/g;
        $text =~ s/"/&#x22;/g;
        $text =~ s/'/&#x27;/g;

        return $text;
    }


sub decode_charset {

        # not needed lol

        # return $_[0] if ( utf8::decode($_[0]) ||
        #          utf8::is_utf8($_[0]) );

        #   if ( utf8::decode($_[0])) {
        #     warn "utf8::decode ! \n";
        # #    warn "$_[0]\n";
        #     return $_[0];
        #   }

        #   if (utf8::is_utf8($_[0])) {
        #     warn "utf8::is_utf8 ! \n";
        # #    warn "$_[0]\n";
        #     return $_[0];
        #   }

        my $charset = $_[1];

        for ( $charset ||= detect($_[0]), detect($_[0]))
        {
            $_ ||= "ascii";     #default charset
            if (ref ( $encodings{$_} ||= Encode::find_encoding($_) ))
            {
                return $encodings{$_}->decode($_[0],Encode::FB_XMLCREF);
            }
            else
            {
                warn "decode() error: unsupported encoding: $_\n";
            }
        }
        return $_[0];
    }


sub text2html {
        return unless $_[0];

        my $html = escHTML($_[0]);
        $html =~ s{$url_regex}{<a href="$1">$1</a>$2}ig;
        return "<pre>$html</pre>";
    }


1;
