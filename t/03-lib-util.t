use v6;
use Test;

plan 5;

use-ok 'NativeLibs';
ok (my \Util = ::('NativeLibs::Searcher')) !~~ Failure,	'Class Searcher exists';
my $sub = Util.at-runtime('mysqlclient', 'mysql_init', 16..20);
does-ok $sub, Callable;
my $lib;
is $lib = $sub.(), "libmysqlclient.so.18",		"Indeed $lib";
ok $lib = Util.search('pq', 'PQstatus', 5),		"Postgres is $lib";

