package Mailnesia;

use Sys::Hostname;
use Text::MultiMarkdown;
use Encode qw 'decode';
use Mailnesia::SQL;

=head1 Mailnesia

# usable options:
# 1). no "use utf8"; no <:encoding(UTF-8) on open; no encode("UTF8") on print; strings are bytes not characters
# 2). use utf8 (or manually decode); <:encoding(UTF-8) on open; encode("UTF8") on print; strings are characters not bytes

The proper way is to use 2) but CGI::Fast (index.fcgi) works only with 1), Mojolicious (website.pl) works with 2).

=cut


=head2 new

options:
{
decode_on_open => ":encoding(UTF-8)" # use this encoding for decoding on open, defaults to ""
skip_sql_connect => true # whether to skip connecting to SQL
}

returns:
{
weighted           : letters for random name generation,
project_directory  : project directory
text               : text used on website,
devel              : false on live server (based on hostname),
dbh                : the SQL connection handle
}

=cut

sub new {
        my $package = shift;
        my $options = shift;

        my $self = bless {
                weighted => generate(),
                devel    => sub {
                        # if not running on "production" machine, use devel mode

                        if ( ( my $hostname = hostname() ) ne 'azaleas' )
                        {
                            return $hostname;
                        }

                        #execute this anonymous sub:
                    }->(),
                dbh => $options->{skip_sql_connect} ? undef : Mailnesia::SQL->connect()
            },$package;

        $self->{text} = $self->initialize_text($options->{decode_on_open});

        return $self;
    }

=head2 connect_sql

(re)connect to SQL

=cut

sub connect_sql
{
    my $self = shift;
    $self->{dbh} = Mailnesia::SQL->connect( $self->{dbh} );
}

=head1 check_mailbox_characters

check characters in email address, can only contain [-.+_a-z0-9], 1-30
long. Must be used on url decoded string (no %2B).

Parameters:

1) email address
2) strict mode, boolean, default: false.
  True:  return false if one or more characters are invalid.
  False: return the valid part.

=cut

sub check_mailbox_characters {
        my $self = shift;
        my $name = shift;

        if ($name =~ m/^([\-\.\+_a-z0-9]{1,30})([^@]*)/i)
        {
            my $strict_mode = shift;

            if ($2)
            {
                # got invalid chars
                if ($strict_mode)
                {
                    return
                }
                else
                {
                    return $1
                }
            }
            else
            {
                return $1;
            }
        }
        else
        {
            return;
        }
    }



=head1 get_url_encoded_mailbox

mailbox => url_encoded_mailbox

=cut

sub get_url_encoded_mailbox
{
    my $self = shift;
    my $url_encoded_mailbox = shift;
    $url_encoded_mailbox =~ s/\+/%2B/g;
    return $url_encoded_mailbox;
}

=head1 get_url_decoded_mailbox

url_encoded_mailbox => mailbox

=cut

sub get_url_decoded_mailbox
{
    my $self = shift;
    my $url_decoded_mailbox = shift;
    $url_decoded_mailbox =~ s/%2B/\+/g;
    return $url_decoded_mailbox;
}

sub random_name {
        my $self=shift;
        my $lang = shift;
        $lang = 'en' unless exists $self->{'weighted'}->{$lang};

        my ($random,@consonant_or_vowel);

        for (0..int(rand(8))+2)
        {
            $consonant_or_vowel[$_] = int(rand(2))
            while
            $consonant_or_vowel[$_] == $consonant_or_vowel[$_-1] and
            $consonant_or_vowel[$_] == $consonant_or_vowel[$_-2];

            $random .= $self->{'weighted'}->{$lang}[$consonant_or_vowel[$_]]->[int(rand(scalar(@{$self->{'weighted'}->{$lang}[$consonant_or_vowel[$_]]})))];
        }

        return $random;
    }


=head2 random_name_for_testing

generate a 30 character random name for testing purposes

=cut

sub random_name_for_testing {
        my @characters = qw /a b c d e f g h i j k l m n o p q r s t u v w x y z + - . _ A B C D E F G H I J K L M N O P Q R S T U V W X Y Z . - + _/;
        my ($name,$char) ;

        1 while (( $char = $characters[ int(rand( scalar @characters )) ] ) =~ m/^[\-\+]$/ );
        # do not use a - or + as first character
        $name = $char;

        for (2..30)
        {
            $name .= $characters[ int(rand( scalar @characters )) ];
        }

        return $name;
    }



sub generate {
        my $vowel = 'aieou';
        my $consonant = 'bcdfghjklmnpqrstvwxyz';
        my %weighted;

        my %hash = (

                en =>{
                        a => 8.167,
                        b => 1.492,
                        c => 2.782,
                        d => 4.253,
                        e => 12.702,
                        f => 2.228,
                        g => 2.015,
                        h => 6.094,
                        i => 6.966,
                        j => 0.153,
                        k => 0.772,
                        l => 4.025,
                        m => 2.406,
                        n => 6.749,
                        o => 7.507,
                        p => 1.929,
                        q => 0.095,
                        r => 5.987,
                        s => 6.327,
                        t => 9.056,
                        u => 2.758,
                        v => 0.978,
                        w => 2.360,
                        x => 0.150,
                        y => 1.974,
                        z => 0.074,
                    },

                fr =>{
                        a => 7.636,
                        b => 0.901,
                        c => 3.260,
                        d => 3.669,
                        e => 14.715,
                        f => 1.066,
                        g => 0.866,
                        h => 0.737,
                        i => 7.529,
                        j => 0.545,
                        k => 0.049,
                        l => 5.456,
                        m => 2.968,
                        n => 7.095,
                        o => 5.378,
                        p => 3.021,
                        q => 1.362,
                        r => 6.553,
                        s => 7.948,
                        t => 7.244,
                        u => 6.311,
                        v => 1.628,
                        w => 0.114,
                        x => 0.387,
                        y => 0.308,
                        z => 0.136
                    },

                de =>{
                        a => 6.51,
                        b => 1.89,
                        c => 3.06,
                        d => 5.08,
                        e => 17.40,
                        f => 1.66,
                        g => 3.01,
                        h => 4.76,
                        i => 7.55,
                        j => 0.27,
                        k => 1.21,
                        l => 3.44,
                        m => 2.53,
                        n => 9.78,
                        o => 2.51,
                        p => 0.79,
                        q => 0.02,
                        r => 7.00,
                        s => 7.27,
                        t => 6.15,
                        u => 4.35,
                        v => 0.67,
                        w => 1.89,
                        x => 0.03,
                        y => 0.04,
                        z => 1.13,
                    },

                es =>{
                        a => 12.53,
                        b => 1.42,
                        c => 4.68,
                        d => 5.86,
                        e => 13.68,
                        f => 0.69,
                        g => 1.01,
                        h => 0.70,
                        i => 6.25,
                        j => 0.44,
                        k => 0.01,
                        l => 4.97,
                        m => 3.15,
                        n => 6.71,
                        o => 8.68,
                        p => 2.51,
                        q => 0.88,
                        r => 6.87,
                        s => 7.98,
                        t => 4.63,
                        u => 3.93,
                        v => 0.90,
                        w => 0.02,
                        x => 0.22,
                        y => 0.90,
                        z => 0.52,
                    },

                pt =>{
                        a => 14.63,
                        b => 1.04,
                        c => 3.88,
                        d => 4.99,
                        e => 12.57,
                        f => 1.02,
                        g => 1.30,
                        h => 1.28,
                        i => 6.18,
                        j => 0.40,
                        k => 0.02,
                        l => 2.78,
                        m => 4.74,
                        n => 5.05,
                        o => 10.73,
                        p => 2.52,
                        q => 1.20,
                        r => 6.53,
                        s => 7.81,
                        t => 4.74,
                        u => 4.63,
                        v => 1.67,
                        w => 0.01,
                        x => 0.21,
                        y => 0.01,
                        z => 0.47,
                    },

                eo =>{
                        a => 12.12,
                        b => 0.98,
                        c => 0.78,
                        d => 3.04,
                        e => 8.99,
                        f => 1.03,
                        g => 1.17,
                        h => 0.38,
                        i => 10.01,
                        j => 3.50,
                        k => 4.16,
                        l => 6.14,
                        m => 2.99,
                        n => 7.96,
                        o => 8.78,
                        p => 2.74,
                        q => 0.00,
                        r => 5.91,
                        s => 6.09,
                        t => 5.27,
                        u => 3.18,
                        v => 1.90,
                        w => 0.00,
                        x => 0.00,
                        y => 0.00,
                        z => 0.50,
                    },

                it =>{
                        a => 11.74,
                        b => 0.92,
                        c => 4.5,
                        d => 3.73,
                        e => 11.79,
                        f => 0.95,
                        g => 1.64,
                        h => 1.54,
                        i => 11.28,
                        j => 0.00,
                        k => 0.00,
                        l => 6.51,
                        m => 2.51,
                        n => 6.88,
                        o => 9.83,
                        p => 3.05,
                        q => 0.51,
                        r => 6.37,
                        s => 4.98,
                        t => 5.62,
                        u => 3.01,
                        v => 2.10,
                        w => 0.00,
                        x => 0.00,
                        y => 0.00,
                        z => 0.49,
                    },

                tr =>{
                        a => 11.68,
                        b => 2.95,
                        c => 0.97,
                        d => 4.87,
                        e => 9.01,
                        f => 0.44,
                        g => 1.34,
                        h => 1.14,
                        i => 8.27,
                        j => 0.01,
                        k => 4.71,
                        l => 5.75,
                        m => 3.74,
                        n => 7.23,
                        o => 2.45,
                        p => 0.79,
                        q => 0,
                        r => 6.95,
                        s => 2.95,
                        t => 3.09,
                        u => 3.43,
                        v => 0.98,
                        w => 0,
                        x => 0,
                        y => 3.37,
                        z => 1.50,
                    },

                sv =>{
                        a => 9.3,
                        b => 1.3,
                        c => 1.3,
                        d => 4.5,
                        e => 9.9,
                        f => 2.0,
                        g => 3.3,
                        h => 2.1,
                        i => 5.1,
                        j => 0.7,
                        k => 3.2,
                        l => 5.2,
                        m => 3.5,
                        n => 8.8,
                        o => 4.1,
                        p => 1.7,
                        q => 0.007,
                        r => 8.3,
                        s => 6.3,
                        t => 8.7,
                        u => 1.8,
                        v => 2.4,
                        w => 0.03,
                        x => 0.1,
                        y => 0.6,
                        z => 0.02,
                    },

                pl =>{
                        a => 8.0,
                        b => 1.3,
                        c => 3.8,
                        d => 3.0,
                        e => 6.9,
                        f => 0.1,
                        g => 1.0,
                        h => 1.0,
                        i => 7.0,
                        j => 1.9,
                        k => 2.7,
                        l => 3.1,
                        m => 2.4,
                        n => 4.7,
                        o => 7.1,
                        p => 2.4,
                        q => 0,
                        r => 3.5,
                        s => 3.8,
                        t => 2.4,
                        u => 1.8,
                        v => 0,
                        w => 3.6,
                        x => 0,
                        y => 3.2,
                        z => 5.1,
                    },

                nl =>{
                        a => 7.49,
                        b => 1.58,
                        c => 1.24,
                        d => 5.93,
                        e => 18.91,
                        f => 0.81,
                        g => 3.40,
                        h => 2.38,
                        i => 6.50,
                        j => 1.46,
                        k => 2.25,
                        l => 3.57,
                        m => 2.21,
                        n => 10.03,
                        o => 6.06,
                        p => 1.57,
                        q => 0.009,
                        r => 6.41,
                        s => 3.73,
                        t => 6.79,
                        u => 1.99,
                        v => 2.85,
                        w => 1.52,
                        x => 0.04,
                        y => 0.035,
                        z => 1.39,
                    }
            );

        # find the least probable, but greater than 0
        my %min;

        while ( my ($lang, $value) = each(%hash))
        {
            while (my ($letter, $p) = each %$value)
            {
                unless (defined ($min{$lang}))
                {
                    $min{$lang} = 100;
                }

                if ($p < $min{$lang} and $p > 0)
                {
                    $min{$lang} = $p;
                }
            }
        }

        while ( my ($lang, $value) = each(%hash))
        {
            while (my ($letter, $p) = each %$value)
            {
                push @{$weighted{$lang}->[is_vowel($letter)]}, $letter for 1..($p / $min{$lang});
            }
        }

        return \%weighted;
    }

sub is_vowel {
        return 1 if (index ("euioa",+shift) > -1);
    }


=head1 check_mailbox_alias

return as hash reference:
{
        mailbox       => $mailbox,        # mailbox
        alias         => $alias,          # alias
        is_alias      => $is_alias,       # is this an alias?
        defined_alias => $defined_alias   # is there an alias defined for this mailbox?
}

=cut

sub check_mailbox_alias {
        my $self = shift;
        my $question = shift;

        return {is_alias => 1} unless ref $self->{dbh};
        my ($mailbox,$alias);
        my $query = $self->{dbh}->prepare ("SELECT mailbox,alias FROM mailbox_alias WHERE alias = ? OR mailbox = ?") or return {is_alias => 1};

        $query->execute($question,$question);
        $query->bind_columns(\$mailbox,\$alias);
        $query->fetch;

        my $is_alias = 1 if $question eq $alias;
        my $defined_alias = $alias if $question eq $mailbox;
        #  warn "is_alias: $is_alias, defined_alias: $defined_alias\n";
        return {
                mailbox       => $mailbox,
                alias         => $alias,
                is_alias      => $is_alias,
                defined_alias => $defined_alias
            };
    }


=head1 get_project_directory

find the project root directory in @INC, based on lib/Mailnesia.pm

=cut

sub get_project_directory
{

    # $INC[0] will contain the first include directory which is the mailnesia project directory if started with perl -I..., or PERL5LIB is set

    my $self = shift;
    return $self->{project_directory} ||= do {

            my $project_directory;

          CHECK: foreach (@INC)
            {
                if (-e "$_/Mailnesia.pm" )
                {
                    ($project_directory = $_) =~ s#/lib/?$##;        # remove /lib subdirectory

                    last CHECK;
                }
            }

            die "Cannot find project directory in \@INC! Try setting \$PERL5LIB or start with perl -I/project_directory!\n" unless $project_directory;

            $project_directory;
        }
}

=head1 initialize_text

load all text from translation files, load all pages from markdown files and convert to html

=cut

sub initialize_text {
        my $self = shift;
        my $decode_on_open = shift;

        my $markdown = Text::MultiMarkdown->new;

        my %message = (nonexistent=>"nil");
        my @lang_array;         # language number to text: 0 -> en
        my %lang_hash;          # to check if a translation exists
        my %pages;


        # @lang_array is used globally so all 3 tsv files should contain the same languages in the same order
        my $string_separator; # used in translation_table
        if ($decode_on_open)
        {
            my $separator = decode("UTF-8",  "§");
            $string_separator = qr/ *$separator */;
        }
        else
        {
            $string_separator = qr/ *§ */;
        }



        my $project_directory = $self->get_project_directory();

        open my $language_file, "<$decode_on_open", "$project_directory/translation/mailnesia_translation - mailnesia_translation.tsv"
        or die "unable to open $project_directory/translation/mailnesia_translation - mailnesia_translation.tsv: $!";

        while (<$language_file>)
        {
            chomp;

            my @row = split /\t/ or next; # skip empty lines (those without tab)

            my $key = shift @row;
            my $category = shift @row or next;

            if (! @lang_array)
            {
                @lang_array = @row; # [en hu it lv fi pt de]
                %lang_hash = map { $_ => 0 } @lang_array;
            }
            else
            {
                for my $language_number (0..scalar @lang_array -1)
                {

                    my $string = $row[$language_number] || $row[0];
                    my $lang = $lang_array[$language_number];

                    if ($category == 1)
                    {

                        if ( $key eq 'mail_for_emailaddress' )
                        {
                            $string =~ s!_x!<a href="mailto:_x\@mailnesia.com">_x</a>!;
                        }
                        elsif ( $key ne 'page' )
                        {
                            # can't use <i> at page because it doesn't work in <a title
                            $string =~ s!_x!<i>_x</i>!;
                        }

                        $message{$key}{$lang} = $string;

                    }
                    elsif ($category == 2)
                    {

                        my @string = split ($string_separator,$string);

                        $message{$key}{$lang} = {
                                text       => $string[0],
                                text_plain => $string[1],
                                text_html  => $string[2]
                            }

                    }
                    elsif ($category == 3)
                    {

                        $message{$key}{$lang} = qq{<p><a href="/features.html#alias">$string</a></p>};

                    }
                    elsif ($category == 4)
                    {

                        my @string = split ($string_separator,$string);
                        $message{$key}{$lang} = qq{<p><strong>$string[0]</strong> <a href="/features.html">$string[1]</a></p>};

                    }
                    elsif ($category == 5)
                    {

                        my @string = split ($string_separator,$string);
                        $message{$key}{$lang} = qq{<p><strong>$string[0]</strong> $string[1] <a href="/features.html">$string[2]</a></p>};

                    }
                    elsif ($category == 6)
                    {

                        my @string = split ($string_separator,$string);
                        $message{$key}{$lang} = qq{<strong>$string[0]</strong> $string[1]};

                    }
                }
            }
        }


        $message{clicker_on_html}{en}        = decode ( "UTF8", qq{<span class="label success">ON ✓</span>});
        $message{clicker_off_html}{en}       = decode ( "UTF8", qq{<span class="label important">OFF ✗</span>});
        $message{internal_server_error}{en}  = qq{500 Internal Server Error};
        $message{bad_request}{en}            = qq{400 Bad Request};





        # loading features page from mailnesia_translation - features page.tsv


        my %features_page;
        my $level = 0;

        open my $features_page_file, "<$decode_on_open", "$project_directory/translation/mailnesia_translation - features page.tsv"
        or die             "unable to open $project_directory/translation/mailnesia_translation - features page.tsv: $!\n";
        while (<$features_page_file>)
        {
            chomp;
            my @row = split /\t/ or next; # skip empty lines (those without tab)
            my $key = shift @row;
            my $category = shift @row;

            next unless ( $category and $category =~ m/\d+/ ); # skip empty and non-number lines


            for my $language_number (0..scalar @lang_array -1)
            {
                my $lang = $lang_array[$language_number];
                my $string = $row[$language_number] || $row[0];

                if ($category == 1)
                {
                    $pages{features}{$lang}{description} = $string
                }
                elsif ($category > 1 and $category < 8)
                {
                    # <h1..6>
                    $features_page{$lang}{body} .= qq{<h$category id="};
                    $features_page{$lang}{body} .= $key || "sec$level";
                    $features_page{$lang}{body} .= qq{">$string</h$category>\n\n};
                }
                elsif ($category == 8)
                {
                    # paragraph
                    $features_page{$lang}{body} .= qq{$string\n\n}
                }
            }

            $level++ if ( $category > 1 and $category < 8 );

        }

        # todo: menu on each page
        for (@lang_array)
        {
            $pages{features}{$_}{body} = qq{<div id="main"><h1>} .
            $message{features}{$_} . qq{</h1>} .
            toc (  $features_page{$_}{body} ) .
            $markdown->markdown ( $features_page{$_}{body} ) .
            qq{</div>} ;
        }





        # loading main page from mailnesia_translation - main page.tsv

        my $main_html_template = q{<div id="main"><div id="content">

<h2><!-- TMPL_VAR NAME=MOTTO --></h2>

<table class="muse-table" border="0">
<tbody>

<!-- TMPL_LOOP NAME=FEATURE_LIST -->
<tr>
<td>
<span class="mail-image mail<!-- TMPL_VAR NAME=FEATURE_COUNT -->"></span>
</td>
<td>
<a href="features.html#<!-- TMPL_VAR NAME=FEATURE_SECTION -->">
<!-- TMPL_VAR NAME=FEATURE_TEXT -->
</a>
</td>
</tr>
<!-- /TMPL_LOOP -->

</tbody>
</table>

<!-- TMPL_VAR NAME=BODY_TEXT -->

</div>

<div id="menu">

<ul>
<li><a href="<!-- TMPL_IF NAME="LANGUAGE_CODE" -->/<!-- TMPL_VAR NAME="LANGUAGE_CODE" --><!-- /TMPL_IF -->/features.html"><!-- TMPL_VAR NAME=FEATURES --></a></li>
<li><a href="https://blog.mailnesia.com"><!-- TMPL_VAR NAME=BLOG --></a></li>
<li><a href="/translation.html"><!-- TMPL_VAR NAME=TRANSLATION --></a></li>
<li><a href="/thanksto.html"><!-- TMPL_VAR NAME=THANKSTO --></a></li>
<li><a href="/contact.html"><!-- TMPL_VAR NAME=CONTACT --></a></li>
<li><a href="/FAQ.html"><!-- TMPL_VAR NAME=FAQ --></a></li>
</ul>

</div>
</div>
};

        # compact html:
        $main_html_template =~ s/>\s+</></g;


        {
            my %param;
            my %main_body;
            my $count = 0;      # span class="mail-image mail#"

            open my $main_page_file, "<$decode_on_open", "$project_directory/translation/mailnesia_translation - main page.tsv"
            or die         "unable to open $project_directory/translation/mailnesia_translation - main page.tsv: $!\n";
            while (<$main_page_file>)
            {
                chomp;
                my @row = split /\t/ or next; # skip empty lines (those without tab)
                my $key      = shift @row;
                my $category = shift @row;
                next unless ( $category and $category =~ m/\d+/ ); # skip empty and non-number lines
                $count++ if ($category == 3);

                for my $language_number (0..scalar @lang_array -1)
                {
                    my $lang = $lang_array[$language_number];
                    my $string = $row[$language_number] || $row[0];

                    if ($category == 1)
                    {
                        #description
                        $pages{main}{$lang}{$key} = $string;
                    }
                    elsif ($category == 2)
                    {
                        # menu
                        $param{$lang}{$key} = $string;
                    }
                    elsif ($category == 3)
                    {
                        # feature list
                        push @ { $param{$lang}{"FEATURE_LIST"} }, {
                                FEATURE_COUNT   => $count,
                                FEATURE_SECTION => $key,
                                FEATURE_TEXT    => $string
                            };
                    }
                    elsif ($category == 4)
                    {
                        # body text
                        $main_body{ $lang } .= "$string\n\n";

                        if ($row[$language_number])
                        {
                            # language complete
                            $lang_hash{ $lang } = 1
                        }
                    }
                }
            }


            # featured
            $main_body{en} .= q{<span class="featured">Featured on: <img src="/lifehacker.png" alt="Lifehacker" height="35" width="128"><img src="/makeuseof.png" alt="MakeUseOf" height="35" width="129"></span>};

            for (@lang_array)
            {
                # saving features text for the features page:
                $message{features}{$_} = $param{$_}{features};

                $param{$_}{"BODY_TEXT"} = $markdown->markdown( $main_body{ $_ } ) ;
                $param{$_}{"LANGUAGE_CODE"} = $_ unless $_ eq 'en';
                $param{$_}{"MOTTO"} = $message{'motto'}{$_};

                $pages{main}{$_}{param} = $param{$_};
            }
        }








        # load markdown pages

        foreach my $filename (glob($project_directory ."/markdown-pages/*.markdown"))
        {
            my $page = $1 if $filename =~ m,/markdown-pages/([a-z0-9-]+).markdown$,i;

            my $language = 'en';

            open my $fh, "<$decode_on_open", $filename or die "cannot open $filename: $!";
            my $content;

            while (<$fh>)
            {

                if (m/^#([a-z]+) (.*)$/)
                {
                    # headers, title, description etc
                    $pages{$page}{$language}{$1} = $2
                }
                else
                {
                    $content .= $_
                }

                #change every utf character to html entity
                #encode_entities(decode('UTF-8',$value,Encode::FB_HTMLCREF), '^\n\x20-\x25\x27-\x7e');
            }

            #generating table of contents
            my $content_html = $markdown->markdown($content) ;
            $content_html =~ s/<contents>/toc($content_html)/e;

            $pages{$page}{$language}{body} = '<div id="main"><h1>' .
            $pages{$page}{$language}{title} .
            '</h1>' .
            $content_html .
            '</div>';

        }

        # 'test' page
        $pages{test}->{en}->{body} = 'test successful';

        return {
                project_directory => $project_directory,
                message => \%message,
                pages => \%pages,
                lang_hash => \%lang_hash,
                lang_array => \@lang_array
            }

    }



=head1 toc

generate table of contents from html, based on <h2> sections

=cut

sub toc {
        my $content = shift;
        my $toc = '<ul>';

        if ( my @matches = $content =~ m{<h2 id="(.+?)">(.+?)</h2>}g )
        {
            while (my $id = shift @matches)
            {
                my $title = shift @matches;
                $toc .= qq{<li><a href="#$id">$title</a></li>};
            }
        }

        $toc .= '</ul>';
        return $toc;

    }


=head1 message

function to get the text to be printed

=cut


sub message {
        ##### the logic is:
        # perl -e '$a=q{asd _x qwe _y poi}; $b=sub{$a =~ s/_x/$_[0]/; $a =~ s/_y/$_[1]/;return $a}; print $b->("HH","JJ")."\n";'
        #####
        my $self = shift;

        my ($message_key,@inner_variable) = @_;

        my $message_language = $self->{text}->{message}{$message_key}{ $self->{language} } ? $self->{language} : "en";

        # if the message is not string, return as is:
        return $self->{text}->{message}{$message_key}{$message_language} if
        ref    $self->{text}->{message}{$message_key}{$message_language} ;

        if ($self->{text}->{message}{$message_key}{$message_language})
        {
            if (@inner_variable)
            {
                # replace _x and _y in %message if called with 2 parameters
                my $string = $self->{text}->{message}{$message_key}{$message_language};

                $string =~ s!_x!$inner_variable[0]!g ;

                if ($inner_variable[1])
                {
                    $string =~ s!_y!<i>$inner_variable[1]</i>!;
                }

                return  $string;

            }
            else
            {
                return $self->{text}->{message}{$message_key}{$message_language} ;
            }
        }
        else
        {
            return $self->{text}->{message}{"nonexistent"};
        }
    }


=head2 generate_language_selection_links

return the language selection html part in the footer

=cut

sub generate_language_selection_links {
        my $self = shift;
        return $self->{language_selection_links} ||= do {

                my $separator = shift;
                my $html;

                my $n = scalar @ { $self->{text}->{lang_array} };

                for (0 .. $n-2) # last element is "your language here", should be ignored
                {
                    my $lang = $self->{text}->{lang_array}[$_];

                    $html .= qq%<a href="/% ;
                    my $translation_complete = $self->{text}->{lang_hash}{$lang};

                    if ($lang ne 'en' and $translation_complete)
                    {
                        # link to / if en or language incomplete
                        $html .= qq%$lang/% ;
                    }

                    $html .= qq%" class="$lang" title="% .
                    $self->{text}->{message}->{language_selection}->{$lang} .
                    qq%" onClick="return setLanguage('$lang',$translation_complete);">% .
                    $self->{text}->{message}->{language_selection}->{$lang} .
                    qq%</a>%;
                    $html .= $separator if $_ < $n-2; # dont insert separator after last flag
                }

                $html;
            }
    }



=head2 generate_footer

print footer html

=cut

sub generate_footer {
        my $self = shift;
        return $self->{footer} ||= do {

                my $separator = ' &middot; ';
                my $footer = qq%<div id="footer"><div class="left">% .
                $self->generate_language_selection_links($separator) .
                qq%</div><div class="right">Built with the <a href="https://perl.org">Perl Programming Language</a>%.
                qq%$separator%.
                qq%<a href="/terms-of-service.html">Terms and conditions of service</a>%.
                qq%$separator%.
                qq%<a href="/privacy-policy.html">Privacy policy</a></div></div>%.
                qq%<script src="//ajax.googleapis.com/ajax/libs/jquery/1.7.1/jquery.min.js" type="text/javascript"></script>%.
                qq%<script src="//cdnjs.cloudflare.com/ajax/libs/moment.js/2.9.0/moment-with-locales.min.js" type="text/javascript"></script>%.
                qq%<script src="/js/javascript-min.js" type="text/javascript"></script>%;

                $footer .= "</body></html>";

                $footer;

            }
    }


=head2 get_alias_list

return arrayref of aliases set for mailbox

=cut

sub get_alias_list
{
    my $self = shift;
    my $mailbox = shift;

    my $query = $self->{dbh}->prepare ("SELECT alias FROM mailbox_alias WHERE mailbox=?") or return;
    $query->execute($mailbox) or return;
#    return $query->fetchall_arrayref();
    my @alias_list;

    while (my $row = $query->fetchrow_arrayref)
    {
        push @alias_list, $row->[0]
    }

    return \@alias_list;
}


=head2 setAlias_check

check mailbox and alias whether the alias can be set.  parameters:
mailbox, alias. returns array: HTTP code, text to send to the client,
for example:

[200, "success"]

=cut

sub setAlias_check {
        my $self = shift;
        my $mailbox = shift;
        my $alias = shift;

        # mailbox cannot be same as alias
        if ($mailbox eq $alias)
        {
            return [ 409, $self->message('mailbox_eq_alias') ];
        }

        # is alias an empty mailbox?
        if ($self->emailcount($alias))
        {
            return [ 409, $self->message('alias_not_empty_for_alias_assignment') ];
        }

        # do nothing if the mailbox is an alias (try to set an alias to an alias), or if the specified alias is a mailbox which already has an alias
        my $query = $self->{dbh}->prepare ("SELECT 1 FROM mailbox_alias WHERE alias = ? OR mailbox = ? LIMIT 1");
        $query->execute($mailbox,$alias)

        or return [ 500, $self->message('internal_server_error') ];

        # $query->bind_columns(\$count);
        # $query->fetch or return;

        # return if alias OR mailbox already set
        if ( $query->fetchrow_array )
        {
            return [ 409, $self->message('alias_assign_error') ];
        }


        return [ 200, $self->message('alias_assign_success',$mailbox,$alias) ];
    }


=head2 setAlias

assign new alias to mailbox

=cut

sub setAlias {
        my $self = shift;
        my $mailbox = shift;
        my $alias = shift;

        return unless ($mailbox and $alias);

        my $query = $self->{dbh}->prepare ( "INSERT INTO mailbox_alias VALUES (?,?)" );
        return $query->execute($mailbox,$alias);
}


=head2 modifyAlias

assign new alias to mailbox

=cut

sub modifyAlias {
        my $self = shift;
        my $mailbox = shift;
        my $remove_alias = shift;
        my $new_alias = shift;

        return unless ($mailbox and $new_alias and $remove_alias);

        my $query = $self->{dbh}->prepare ( "UPDATE mailbox_alias SET alias=? WHERE mailbox=? AND alias=?");
        # return true only if number of affected rows == 1
        $query->execute($new_alias,$mailbox,$remove_alias) == 1;
}


=head2 removeAlias

delete alias from mailbox

=cut

sub removeAlias {
        my $self = shift;
        my $mailbox = shift;
        my $remove_alias = shift;

        return unless ($mailbox and $remove_alias);

        my $query = $self->{dbh}->prepare ( "DELETE FROM mailbox_alias WHERE mailbox=? AND alias=?");
        # return true only if number of affected rows == 1
        $query->execute($mailbox,$remove_alias) == 1;
}

=head2 emailcount

return number of emails a mailbox has or undef on error

=cut

sub emailcount {
        my $self = shift;

        my $count;
        my $mailbox = shift;
        my $query = $self->{dbh}->prepare ("SELECT count(*) FROM emails WHERE mailbox = ?") or return;

        $query->execute($mailbox);
        $query->bind_columns(\$count);
        $query->fetch or return;
        return $count;
    }



=head2 hasemail

return 1 if mailbox has email, 0 if not, undef on error

=cut

sub hasemail {
        my $self = shift;
        my $result = undef;
        my $mailbox = shift;
        my $query = $self->{dbh}->prepare ("SELECT 1 FROM emails WHERE mailbox = ? LIMIT 1") or return;

        $query->execute($mailbox) or return;

        $query->bind_columns(\$result);
        $query->fetch or return 0;
        return $result;

    }




=head2 delete_mail

delete email based on mailbox and id.  Parameters:

mailbox
id

returns true on success.

=cut

sub delete_mail
{
    my $self = shift;
    my $mailbox = shift;
    my $id = shift;

    return unless $mailbox and $id;

    my $query = $self->{dbh}->prepare("DELETE FROM emails WHERE mailbox = ? AND id = ? ")
    or return;

    $query->execute($mailbox,$id) or return;

    if ( ( my $num_rows = $query->rows ) == 1 )
    {
        return 1
    }
    else
    {
        return
    }
}


=head2 delete_mailbox

delete all emails in a mailbox. Parameters:

mailbox

returns true on success.

=cut

sub delete_mailbox
{
    my $self = shift;
    my $mailbox = shift;

    return unless $mailbox ;

    my $query = $self->{dbh}->prepare("DELETE FROM emails WHERE mailbox = ?")
    or return;

    $query->execute($mailbox) or return;

    if ( ( my $num_rows = $query->rows ) > 0 )
    {
        return 1
    }
    else
    {
        return
    }
}

=head2 has_email_or_alias

return 1 if the mailbox given as parameter has any emails or alias(es) set, 0 otherwise. Values above 1000 represent SQL errors.

=cut


sub has_email_or_alias {
        my $self = shift;
        return 1000 unless ref $self->{dbh};
        my $question = shift;
        my $result = 0;

        my $query = $self->{dbh}->prepare
        ("SELECT 1 FROM emails WHERE mailbox=? UNION SELECT 1 FROM mailbox_alias WHERE mailbox=? OR alias=? LIMIT 1")
        or return 1001;

        $query->execute($question,$question,$question) or return 1002;
        $query->bind_columns(\$result);
        $query->fetch ;
        return $result;
    }


1;
