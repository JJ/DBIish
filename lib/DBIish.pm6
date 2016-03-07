use v6;
# DBIish.pm6

unit class DBIish:auth<mberends>:ver<0.1.4>;
    use DBDish;

    package GLOBAL::X::DBIish {
	our class DriverNotFound is Exception {
	    has $.bogus;
	    method message { "DBIish: No DBDish driver found: $.bogus" };
	}
	our class LibraryMissing is Exception {
	    has $.driver;
	    has $.library;
	    method message { "DBIish: DBDish::$.driver needs $.library, not found" }
	}
	our class NotADBIishDriver is Exception {
	    has $.who;
	    method message { "$.who is not a DBDish::Driver" };
	}
    }

    my %installed;

    my $err-handler = DBDish::ErrorHandling.new(:parent(Nil));
    method err { $err-handler.err };
    method errstr { $err-handler.errstr };

    method connect($driver,
	:$RaiseError = True,
	:$PrintError = False,
	:$AutoCommit = True,
	*%opts
    ) {
	# The first native call done by the driver can trigger an X::AdHoc
	# to report missing libraries.
	# I catch here to avoid the drivers the need of this logic.
	CATCH {
	    when $_.message ~~ m/
		^ "Cannot locate native library "
		( "'" <-[ ' ]> * "'" ) 
	    / {
		X::DBIish::LibraryMissing.new(:library($/[0]), :$driver).fail;
	    }
	    default {
		.throw;
	    };
	}
	my $d = self.install-driver( $driver );
        my $connection = $d.connect(:$RaiseError, :$PrintError, :$AutoCommit, |%opts );
        $connection;
    }
    method install-driver( $drivername ) {
	my $d = %installed{$drivername} //= do {
	    CATCH {
		when X::CompUnit::UnsatisfiedDependency {
		    X::DBIish::DriverNotFound.new(:bogus($drivername)).fail;
		}
		default {
		    .throw;
		}
	    }
	    my $module = "DBDish::$drivername";
	    my \M = (require ::($module));
	    # The DBDish namespace isn't formally reserved for DBDish's drivers,
	    # and is a good place for related common code.
	    # An assurance at driver load time is in place,
	    unless M ~~ DBDish::Driver {
		# This warn will be converted in a die after the Role is settled,
		# it's an advice for authors for externally developed drivers
		warn "$module dosn't DBDish::Driver role!";
	    }
	    M.new(:parent($err-handler), :RaiseError);
	}
	without $d { .throw; };
	$d;
    }
    method install_driver($drivername) is hidden-from-backtrace {
	warn "DBIish::install_driver is DEPRECATED, please use install-driver";
	self.install-driver($drivername)
    }
    method installed-drivers {
	%installed.pairs.cache;
    }


# The following list of SQL constants was produced by the following
# adaptation of the EXPORT_TAGS suggestion in 'perldoc DBI':
#    perl -MDBI -e'for (@{ $DBI::EXPORT_TAGS{sql_types} })
#        { printf "our sub %s { %d }\n", $_, &{"DBI::$_"}; }'
our sub SQL_GUID { -11 }
our sub SQL_WLONGVARCHAR { -10 }
our sub SQL_WVARCHAR { -9 }
our sub SQL_WCHAR { -8 }
our sub SQL_BIGINT { -5 }
our sub SQL_BIT { -7 }
our sub SQL_TINYINT { -6 }
our sub SQL_LONGVARBINARY { -4 }
our sub SQL_VARBINARY { -3 }
our sub SQL_BINARY { -2 }
our sub SQL_LONGVARCHAR { -1 }
our sub SQL_UNKNOWN_TYPE { 0 }
our sub SQL_ALL_TYPES { 0 }
our sub SQL_CHAR { 1 }
our sub SQL_NUMERIC { 2 }
our sub SQL_DECIMAL { 3 }
our sub SQL_INTEGER { 4 }
our sub SQL_SMALLINT { 5 }
our sub SQL_FLOAT { 6 }
our sub SQL_REAL { 7 }
our sub SQL_DOUBLE { 8 }
our sub SQL_DATETIME { 9 }
our sub SQL_DATE { 9 }
our sub SQL_INTERVAL { 10 }
our sub SQL_TIME { 10 }
our sub SQL_TIMESTAMP { 11 }
our sub SQL_VARCHAR { 12 }
our sub SQL_BOOLEAN { 16 }
our sub SQL_UDT { 17 }
our sub SQL_UDT_LOCATOR { 18 }
our sub SQL_ROW { 19 }
our sub SQL_REF { 20 }
our sub SQL_BLOB { 30 }
our sub SQL_BLOB_LOCATOR { 31 }
our sub SQL_CLOB { 40 }
our sub SQL_CLOB_LOCATOR { 41 }
our sub SQL_ARRAY { 50 }
our sub SQL_ARRAY_LOCATOR { 51 }
our sub SQL_MULTISET { 55 }
our sub SQL_MULTISET_LOCATOR { 56 }
our sub SQL_TYPE_DATE { 91 }
our sub SQL_TYPE_TIME { 92 }
our sub SQL_TYPE_TIMESTAMP { 93 }
our sub SQL_TYPE_TIME_WITH_TIMEZONE { 94 }
our sub SQL_TYPE_TIMESTAMP_WITH_TIMEZONE { 95 }
our sub SQL_INTERVAL_YEAR { 101 }
our sub SQL_INTERVAL_MONTH { 102 }
our sub SQL_INTERVAL_DAY { 103 }
our sub SQL_INTERVAL_HOUR { 104 }
our sub SQL_INTERVAL_MINUTE { 105 }
our sub SQL_INTERVAL_SECOND { 106 }
our sub SQL_INTERVAL_YEAR_TO_MONTH { 107 }
our sub SQL_INTERVAL_DAY_TO_HOUR { 108 }
our sub SQL_INTERVAL_DAY_TO_MINUTE { 109 }
our sub SQL_INTERVAL_DAY_TO_SECOND { 110 }
our sub SQL_INTERVAL_HOUR_TO_MINUTE { 111 }
our sub SQL_INTERVAL_HOUR_TO_SECOND { 112 }
our sub SQL_INTERVAL_MINUTE_TO_SECOND { 113 }

=begin pod
=head1 SYNOPSIS

    use v6;
    use DBIish;

    my $dbh = DBIish.connect("SQLite", :database<example-db.sqlite3>, :RaiseError);

    my $sth = $dbh.do(q:to/STATEMENT/);
        DROP TABLE nom
        STATEMENT

    $sth = $dbh.do(q:to/STATEMENT/);
        CREATE TABLE nom (
            name        varchar(4),
            description varchar(30),
            quantity    int,
            price       numeric(5,2)
        )
        STATEMENT

    $sth = $dbh.do(q:to/STATEMENT/);
        INSERT INTO nom (name, description, quantity, price)
        VALUES ( 'BUBH', 'Hot beef burrito', 1, 4.95 )
        STATEMENT

    $sth = $dbh.prepare(q:to/STATEMENT/);
        INSERT INTO nom (name, description, quantity, price)
        VALUES ( ?, ?, ?, ? )
        STATEMENT

    $sth.execute('TAFM', 'Mild fish taco', 1, 4.85);
    $sth.execute('BEOM', 'Medium size orange juice', 2, 1.20);

    $sth = $dbh.prepare(q:to/STATEMENT/);
        SELECT name, description, quantity, price, quantity*price AS amount
        FROM nom
        STATEMENT

    $sth.execute();

    my $arrayref = $sth.fetchall_arrayref();
    say $arrayref.elems; # 3

    $sth.finish;

    $dbh.disconnect;

See also F<README.pod> for more documentation.

=head1 DESCRIPTION
The name C<DBIish> has two meanings.  In lowercase it indicates the
github project being used for development.  In mixed case it is the
module name and class name that database client applications should use.

=head1 DBIish CLASSES and ROLES

=head2 DBIish
The C<DBIish> class exists mainly to provide the F<connect> method,
which acts as a constructor for database connections.

=head2 DBDish
The C<DBDish> role should only be used with 'does' to provide standard
members for DBDish classes.

=head1 SEE ALSO
L<http://dbi.perl.org>
=end pod
