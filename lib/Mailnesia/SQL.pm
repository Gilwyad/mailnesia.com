package Mailnesia::SQL;

use DBI;

=head1 NAME

connect - connect to SQL

=head1 SYNOPSIS

#open new connection:

my $dbh = Mailnesia::SQL->connect();

#verify connection:

$dbh = Mailnesia::SQL->connect($dbh);

#call a function in case error: (the first parameter will be the SQL error)

$dbh = Mailnesia::SQL->connect($dbh,
                               sub
                               {
                                   warn "sql connect error! $_[0]";
                               }
                           );


#call a function with parameters in case error: (the first parameter will be the SQL error)

$dbh = Mailnesia::SQL->connect(
        $dbh,
        sub
        {
            my ($sqlerr,$noreconnect,$warn) = @_;
            warn "sql error: $sqlerr\n";
            unless ($warn) {
                    print h1({-class=>"error"},"SERVICE DOWN -- please try again later. ");
                }
            $dbh = Mailnesia::SQL->connect($dbh) unless $noreconnect;
        },
        "don't connect to sql!!!!",
        "warn me pls");

=head1 DESCRIPTION

?

=cut

sub connect ($;\$$&) {

        my $class = shift;
        my $dbh = shift;
        my $error_handling_die_function = shift;
        my @error_params = @_;

        if ($dbh and $dbh->ping)
        {
            #    warn "SQL connection alive\n";
            return $dbh;
        }
        else
        {
            #    warn "connecting to SQL, warn: $warn\n";
            my $db = "Pg";
            my $db_database = $ENV{postgres_database} || "mailnesia";
            my $db_table = "emails";
            my $user = $ENV{postgres_user} || "mailnesia";
            my $password = $ENV{postgres_password} || "";
            my $host = $ENV{postgres_host} || "localhost";
            my $connection_string = "dbi:$db:database=$db_database;"; # connect on socket

            if ($password) {
                # connect on TCP
                $connection_string += "host=$host;port=5432";
            }

            $dbh = DBI->connect_cached(
                $connection_string,
                $user,
                $password,
                {
                    RaiseError => 0,
                    AutoCommit => 1,
                    PrintWarn=>1,
                    pg_enable_utf8 => 1 # to get the data already decoded
                }
            );

            if (ref $dbh)
            {
                return $dbh;
            }
            else
            {
                $error_handling_die_function->($DBI::errstr,@error_params) if $error_handling_die_function;
                return;
            }
        }
    }

1;
