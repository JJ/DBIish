use v6;

unit module DBDish::Pg::Native;
use NativeLibs;
use NativeHelpers::Blob;

constant LIB = NativeLibs::Searcher.at-runtime('pq', 'PQstatus', 5);

#------------ My Visible Types

constant Oid = uint32;
constant OidArray is export = CArray[Oid];

sub PQlibVersion(-->uint32) is native(LIB) is export { * }
sub PQfreemem(Pointer) is native(LIB) { * }
sub PQunescapeBytea(str, size_t is rw --> Pointer) is native(LIB) { * }

class PGresult	is export is repr('CPointer') {
    method PQclear is native(LIB) { * }
    method PQcmdTuples(--> Str) is native(LIB) { * }
    method PQfname(int32 --> Str) is native(LIB) { * }
    method PQftype(int32 --> int32) is native(LIB) { * };
    method PQparamtype(int32 --> int32) is native(LIB) { * };
    method PQgetisnull(int32, int32 --> int32) is native(LIB) { * }
    method PQgetvalue(int32, int32 --> Str) is native(LIB) { * }
    method PQnfields(--> int32) is native(LIB) { * }
    method PQnparams(--> int32) is native(LIB) { * }
    method PQntuples(--> int32) is native(LIB) { * }
    method PQresultErrorMessage(--> str) is native(LIB) { * }
    method PQresultStatus(--> int32) is native(LIB) { * }

    method is-ok {
	self.PQresultStatus ~~ (0 .. 4);
    }
    method get-value(Int $row, Int $col, Mu $t) {
	sub PQgetvalue(PGresult, int32, int32 --> Pointer) is native(LIB) { * }
	sub PQgetlength(PGresult, int32, int32 --> int32) is native(LIB) { * }
	sub PQfformat(PGresult, int32 --> int32) is native(LIB) { * }

	my \ptr = PQgetvalue(self, $row, $col);
	given PQfformat(self, $col) {
	    when 0 { #Text
		my $str = nativecast(Str, ptr);
		given $t {
		    when Str { $str } # Done
		    when Date { Date.new($str) }
		    when DateTime { DateTime.new($str.split(' ').join('T')) }
		    when Array { $str } # External process
		    when Bool { $str eq 't' }
		    when Blob {
			my \ptr = PQunescapeBytea($str, my size_t $elems);
			LEAVE { PQfreemem(ptr) if ptr }
			with ptr {
			    blob-from-pointer(ptr, :$elems, :type($t))
			} else { die "Can't allocate memory!" };
		    }
		    default { $t($str) } # Cast
		}
	    }
	    when 1 { # Binary
		my $size = PQgetlength(self, $row, $col);
		# TODO This is certainly incomplete
		given $t {
		    when Str { nativecast(Str, ptr) }
		    when Blob {
			blob-from-pointer(ptr, :elems($size));
		    }
		}
	    }
	}
    }
}

class pg-notify is export {
    has Str   $.relname;
    has int32 $.be_pid;
    has Str   $.extra;
}

class PGconn is export is repr('CPointer') {
    method PQexec(str --> PGresult) is native(LIB) { * }
    method PQexecPrepared(
        str $statement_name,
        int32 $n_params,
        CArray[Str] $param_values,
        CArray[int32] $param_length,
        CArray[int32] $param_formats,
        int32 $resultFormat
    ) returns PGresult is native(LIB) { * }

    method PQerrorMessage(--> Str) is native(LIB) { * }
    method PQdescribePrepared(str --> PGresult) is native(LIB) { * }
    method PQstatus(--> int32) is native(LIB) { * }
    method PQprepare(str $sth_name, str $query, int32 $n_params, OidArray --> PGresult)
	is native(LIB) { * }
    method PQfinish is native(LIB) { * }

    method escapeBytea(Buf:D $buf) {
	sub PQescapeByteaConn(PGconn, Buf, size_t, size_t is rw --> Pointer)
	    is native(LIB) { * }
	my size_t $sz;
	my \ptr = PQescapeByteaConn(self, $buf, $buf.elems * nativesizeof($buf.of), $sz);
	LEAVE { PQfreemem(ptr) if ptr }
	with ptr {
	    nativecast(Str, $_);
	} else {
	    die "Can't allocate memory!"
	}
    }

    method pg-socket(--> int32) is symbol('PQsocket') is native(LIB) { * }

    method pg-notifies(--> pg-notify) {
        class PGnotify is repr('CStruct') {
            has Str                           $.relname; # char* relname
            has int32                         $.be_pid; # int be_pid
            has Str                           $.extra; # char* extra
        }
        sub PQnotifies(PGconn --> Pointer) is native(LIB) { * }

        my \ptr = PQnotifies(self);
        LEAVE { PQfreemem(ptr) if ptr }
        with ptr && nativecast(PGnotify, ptr) -> \self {
            pg-notify.new(:$.relname, :$.be_pid, :$.extra)
        } else { Nil }
    }

    method pg-parameter-status(Str --> Str) is symbol('PQparameterStatus')
	is native(LIB) { * }

    multi method new(Str $conninfo) { # Our legacy constructor
	sub PQconnectdb(str --> PGconn) is native(LIB) { * };
	PQconnectdb($conninfo);
    }

    multi method new(%connparms) { # Our named constructor
	sub PQconnectdbParams(CArray[Str], CArray[Str], int32 --> PGconn)
	    is native(LIB) { * };

	my $keys = CArray[Str].new; my $vals = CArray[Str].new;
	my int $i = 0;
	for %connparms.kv -> $k,$v {
	    next without $v;
	    $keys[$i] = $k.subst('-','_');
	    $vals[$i] = $v; $i++;
	}
	$keys[$i] = Str; $vals[$i] = Str;
	PQconnectdbParams($keys, $vals, 1);
    }
}

constant Null is export = Pointer;
constant ParamArray is export = CArray[Str];

# from pg_type.h
constant %oid-to-type is export = (
        16  => Bool,  # bool
        17  => Buf,   # bytea
        20  => Int,   # int8
        21  => Int,   # int2
        23  => Int,   # int4
        25  => Str,   # text
       114  => Str,   # json
       142  => Str,   # xml
       700  => Num,   # float4
       701  => Num,   # float8
       705  => Empty, # unknown
      1000  => Bool,  # _bool
      1001  => Buf,   # _bytea
      1005  => Array[Int],     # Array(int2)
      1007  => Array[Int],     # Array(int4)
      1009  => Array[Str],     # Array(text)
      1015  => Str,            # _varchar

      1021  => Array[Num],     # Array(float4)
      1022  => Array[Num],     # Array(float4)
      1028  => Array[Int],     # Array<oid>
      1043  => Str,            # varchar
      1082  => Date,           # date
      1083  => Str,            # time
      1114  => DateTime,       # Timestamp
      1184  => DateTime,       # Timestamp with time zone
      1186  => Duration,       # interval
      1263  => Array[Str],     # Array<varchar>
      1700  => Rat,   # numeric
      2950  => Str,   # uuid
      2951  => Str,   # _uuid
).hash;

constant CONNECTION_OK         is export = 0;
constant CONNECTION_BAD        is export = 1;

constant PGRES_EMPTY_QUERY     is export = 0;
constant PGRES_COMMAND_OK      is export = 1;
constant PGRES_TUPLES_OK       is export = 2;
constant PGRES_COPY_OUT        is export = 3;
constant PGRES_COPY_IN         is export = 4;
constant PGRES_BAD_RESPONSE    is export = 5;
constant PGRES_NON_FATAL_ERROR is export = 6;
constant PGRES_FATAL_ERROR     is export = 7;
constant PGRES_COPY_BOTH       is export = 8;
constant PGRES_SINGLE_TUPLE    is export = 9;
