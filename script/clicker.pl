#!/usr/bin/perl

# ZeroMQ version used is 4.2.1

use ZMQ::FFI qw(ZMQ_PUSH ZMQ_PULL);
use AnyEvent;
use EV;
use AnyEvent::HTTP;
use strict;
use Mailnesia::Email;
use Mailnesia::Config;

my $config = Mailnesia::Config->new;

my $tryAtMost = 4;
my $startingPort = 5000;
my $endpoint;

my $ctx  = ZMQ::FFI->new();
my $pull = $ctx->socket(ZMQ_PULL);
my $success;

for my $i (0..$tryAtMost-1) {
    my $port = $startingPort + $i;

    eval {
        $endpoint = "tcp://127.0.0.1:$port";
        print "Trying to bind to $endpoint\n";
        $pull->bind($endpoint);
        1;
    } and do {
        $success = print "Success!\n";
        last;
    }
}

die "Unable to use any ports!\n" unless $success;

my $fd = $pull->get_fd();

my $w = AE::io $fd, 0, sub {
    while ( $pull->has_pollin ) {
        my $email = Mailnesia::Email->new({
            raw_email => $pull->recv()
        });

        my ($click_links,$noclick_links) = $email->links;

        if ( @$click_links )
        {
            url_clicker(@$click_links);
        }
    }
};


sub url_clicker {
    my $size;

    foreach my $url ( @_ ) {
        my $cookie_jar = {};

        http_request GET => $url,
        headers =>
        {
            "user-agent"       => "Mozilla/5.0 (Windows NT 6.0; rv:6.0.2) Gecko/20100101 Firefox/6.0.2",
            "accept"           => 'text/html, application/xml;q=0.9, application/xhtml+xml, image/png, image/webp, image/jpeg, image/gif, image/x-xbitmap, */*;q=0.1',
            "accept-language"  => 'en',
            "accept-encoding"  => 'gzip, deflate',
            "referer"          => 'http://mailnesia.com'
        },
        timeout        => 120,
        handle_params  => { max_read_size => 4096 },
        cookie_jar     => $cookie_jar,
        # TODO: error: Day too big - 26296 > 24853
        #Cannot handle date (51, 25, 15, 30, 11, 2041) at /usr/local/share/perl/5.10.1/AnyEvent/HTTP.pm line 1333
        # need to save cookies for redirects

        persistent  => 0,
        on_header   => sub { $_[0]{"content-type"} =~ /^text\/html\s*(?:;|$)/ },
        on_body     => sub
        {
            my $part = shift;
            $size +=  length $part;
            if ($size > $config->{url_clicker_page_size_limit})
            {
                warn "limit reached: $size for url $url\n";
                $size = 0;
                return 0;
            }
            else
            {
                return 1;
            }
        },

        sub
        {
            print $url;
            if ( $_[1]->{Status} =~ /^2/ )
            {
                print "\n";
            }
            else
            {
                print " failed: " . $_[1]->{Reason} . qq{ header: $_[1]->{Status}, $_[1]->{"content-type"}\n};
            }
        }
    }
}

EV::run();
