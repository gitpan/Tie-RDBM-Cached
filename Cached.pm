package Tie::RDBM::Cached;
use strict;
use warnings;
use vars qw($VERSION @ISA);
use Tie::RDBM;
use Carp;
$VERSION = '0.01';
@ISA = qw(Tie::RDBM);

sub TIEHASH {
    my $type = shift;
    my $class = ref($type) || $type;
    my ($dsn,$opt) = ref($_[0]) ? (undef,$_[0]) : @_;
    my $self  = $class->SUPER::TIEHASH($dsn,$opt);

    $self->{cache_size} = $opt->{cache_size};
    $self->{cache} = _create_cache($opt->{cache_type});
        
    bless ($self, $class);
    return $self;

}

sub FETCH {
    my($self,$key) = @_;
    if($self->{'cache_size'} > 0) {
        if($self->{'cache'}->{$key}) {
            return $self->{'cache'}->{$key};
        }
    }  
    return $self->SUPER::FETCH($key);
}

sub STORE {
    my($self,$key,$value) = @_;
    if($self->{'cache_size'} > 0) {
        $self->{'cache'}->{$key} = $value; 
        
        if( keys %{ $self->{'cache'} } <= $self->{'cache_size'} ) {
            return;
        }else {
            $self->_flush_cache();
            return;
        }
    }
    return $self->SUPER::STORE($key,$value);
}

sub EXISTS {
    my($self,$key) = @_;
    #if( $self->{'cache_size'} > 0) {
        if($self->{'cache'}->{$key}) {
            return;
        } 
    #}
    return $self->SUPER::EXISTS($key);
}

sub commit {
    my $self = shift;
    $self->_flush_cache();
}  

sub _flush_cache {
    my $self = shift;
    my ($key,$value);
    while ( ($key, $value) = each %{ $self->{'cache'} } ) {
        my $frozen = 0;
        if (ref($value) && $self->{'canfreeze'}) {
            $frozen++;
            $value = $self->SUPER::nfreeze($value);
        }

        if ($self->{'brokenselect'}) {
           $self->EXISTS($key) ? $self->SUPER::_update($key,$value,$frozen)
                                       : $self->SUPER::_insert($key,$value,$frozen);
        }else {
           $self->SUPER::_update($key,$value,$frozen) || $self->SUPER::_insert($key,$value,$frozen);
        }
    }
    if($self->{'insert'}) { $self->{'insert'}->finish; }
    if($self->{'update'}) { $self->{'update'}->finish; }

    $self->SUPER::commit();
    
    %{ $self->{'cache'}} = ();
    return;
}

sub DELETE {
    my($self,$key) = @_;
    if( $self->{'cache'}->{$key} ) {
        delete($self->{'cache'}->{$key} );
    }    
    $self->SUPER::DELETE($key);
}

sub CLEAR {
    my $self = shift;
    $self->{'cache'} = ();
    $self->SUPER::CLEAR();
}

sub FIRSTKEY {
    my $self = shift;
    if( keys %{ $self->{'cache'} } > 0) {
        $self->_flush_cache();
    }
    $self->SUPER::FIRSTKEY();
}

sub NEXTKEY {
    my $self = shift;
    if( keys %{ $self->{'cache'} } > 0) {
        $self->_flush_cache();
    }
    $self->SUPER::NEXTKEY();
}

sub DESTROY {
    my $self = shift;
    $self->{'cache'} = ();
    $self->SUPER::DESTROY();
}

sub _create_cache {

    my ($type) = @_;

    if ($type eq 'HASH') {
        return {};
    }
        return {};
}

sub _berkeley_closure {

    my $self = shift;
    return sub {
                 my $key = shift;
                 if (@_) { $self->{$key} = shift }
                 return    $self->{$key};
               };
}


1;
__END__

=head1 NAME

Tie::RDBM::Cached - Tie hashes to relational databases.

=head1 SYNOPSIS

=head1 DESCRIPTION

In addition to Tie::RDBM this module provides a caching method for 
fast access and retrieval of data. This can be easily achieved by the user
without resorting to this module. I wrote the module because I like 
the interface to the hash and once done forever usefull.

For more information please see the Documentation for Tie::RDBM. I will 
document where this module adds functionality to the base class or deviates 
from base class usage. 

Please note that where you see "Tie::RDBM::Cached" in the documentation that 
the functionality or action may be inherited from Tie::RDBM.

=head1 TIEING A DATABASE

   tie %VARIABLE,Tie::RDBM::Cached,DSN [,\%OPTIONS]

You tie a variable to a database by providing the variable name, the
tie interface (always "Tie::RDBM::Cached"), the data source name, and an
optional hash reference containing various options to be passed to the
module and the underlying database driver.

The data source may be a valid DBI-style data source string of the
form "dbi:driver:database_name[:other information]", or a
previously-opened database handle.  See the documentation for DBI and
your DBD driver for details.  Because the initial "dbi" is always
present in the data source, Tie::RDBM::Cached will automatically add it 
for you.

The options array contains a set of option/value pairs.  If not
provided, defaults are assumed.  The options with defaults are:

=over 4

=item user ['']

Account name to use for database authentication, if necessary.
Default is an empty string (no authentication necessary).

=item password ['']

Password to use for database authentication, if necessary.  Default is
an empty string (no authentication necessary).

=item db ['']

The data source, if not provided in the argument.  This allows an
alternative calling style:

   tie(%h,Tie::RDBM::Cached,{db=>'dbi:mysql:test',create=>1};

=item table ['pdata']

The name of the table in which the hash key/value pairs will be
stored.

=item key ['pkey']

The name of the column in which the hash key will be found.  If not
provided, defaults to "pkey".

=item value ['pvalue']

The name of the column in which the hash value will be found.  If not
provided, defaults to "pvalue".

=item frozen ['pfrozen']

The name of the column that stores the boolean information indicating
that a complex data structure has been "frozen" using Storable's
freeze() function.  If not provided, defaults to "pfrozen".  

NOTE: if this field is not present in the database table, or if the
database is incapable of storing binary structures, Storable features
will be disabled.

=item create [0]

If set to a true value, allows the module to create the database table
if it does not already exist.  The module emits a CREATE TABLE command
and gives the key, value and frozen fields the data types most
appropriate for the database driver (from a lookup table maintained in
a package global, see DATATYPES below).

The success of table creation depends on whether you have table create
access for the database.

The default is not to create a table.  tie() will fail with a fatal
error.

=item drop [0]

If the indicated database table exists, but does not have the required
key and value fields, Tie::RDBM::Cached can try to add the required fields to
the table.  Currently it does this by the drastic expedient of
DROPPING the table entirely and creating a new empty one.  If the drop
option is set to true, Tie::RDBM::Cached will perform this radical
restructuring.  Otherwise tie() will fail with a fatal error.  "drop"
implies "create".  This option defaults to false.

=item autocommit [1]

If set to a true value, the "autocommit" option causes the database
driver to commit after every SQL statement.  If set to a false
value, this option will not commit to the database until you
explicitly call the Tie::RDBM::Cached commit() method. Due to the way the 
cache works this option does not imply that every time you add a value
to the Tied hash that it gets inserted. 

The autocommit option defaults to true.

=item DEBUG [0]

When the "DEBUG" option is set to a true value the module will echo
the contents of SQL statements and other debugging information to
standard error.


=item cache_type ['HASH']

You will eventually have a choice between using a HASH or a BerkeleyDB
file as the cache.


=item cache_size [0]

This optio allows you to specify the size the cache will be allowed 
to grow to before it is committed to the database. 


=back

=head1 USING THE TIED ARRAY

The standard fetch, store, keys(), values() and each() functions will
work as expected on the tied array.  In addition, the following
methods are available on the underlying object, which you can obtain
with the standard tie() operator:

=over 4

=item commit()

   (tied %h)->commit();

This function has been overridden. It will flush the cache then commit to 
the database, otherwise it performs the same function as the base class.
When using a database with the autocommit option turned off, values
that are stored into the hash will not become permanent until commit()
is called.  Otherwise they are lost when the application terminates or
the hash is untied.

Some SQL databases don't support transactions, in which case you will
see a warning message if you attempt to use this function.

=item rollback()

   (tied %h)->rollback();

When using a database with the autocommit option turned off, this
function will roll back changes to the database to the state they were
in at the last commit().  This function has no effect on database that
don't support transactions.

=back

=head1 PERFORMANCE

What is the performance hit when you use this module?  This is very 
dependant on how you are using the data. If you are doing raw inserts 
of large amounts of data then I do not recommend using this module because 
the performance is very slow. If however you are doing a large amount of 
updates on the data and most of the updates will fall inside the cache 
then this module can increase the performance of these operations considerably. 

Unfortunately deletes do not offer any gain in performance when using 
this module. The reason for the performance drop on certain types of operation 
is because when using a hash tied to a database we need to check for 
existance before we can carry out an insert or update. This adds an extra 
SQL statement to the operation.

The following code will show you roughly how I tested the performance. It is
not a definitive guide and you should carry out your own tests.

 my $update_counter = 20000;
 my $rand_counter = 5000;
 my $counter;

 srand(100000);
 my $random;
 my $start_time = new Benchmark;
 while($counter < $update_counter) {
     $random = int(rand($rand_counter));
     $RDBM{$random}++;
     $counter++;
 }
 tied(%RDBM)->commit;
 my $end_time = new Benchmark;
 my $difference = timediff($end_time, $start_time);
 print "\nIt took Tie::RDBM ", timestr($difference), "\n\n";

The "%RDBM" hash in the code is the tied hash. For the DBI test I used the 
following piece of code.


 my $sql = qq{ update robot_state set value_state = ? where key_ip_address = ? };
 my $sth = $dbh->prepare( $sql );
 my $sql2 = qq{ insert into robot_state( key_ip_address , value_state ) values( ? ,? )};
 my $sth2 = $dbh->prepare( $sql2 );

 $counter = 0;
 $start_time = new Benchmark;
 while($counter < $update_counter) {
     $random = int(rand($rand_counter));
     eval {
         $sth->execute($random,$counter);
     };
     if ($@) { 
         eval {
             $sth2->execute($random, $counter);
         };
         if($@) { print "Error\n $@"; exit 1; };
    }
    $counter++;
 }
 $dbh->commit();
 $end_time = new Benchmark;
 $difference = timediff($end_time, $start_time);
 print "\nIt took Raw DBI ", timestr($difference), "\n\n";

You will notice above that the DBI may need to carry out more than one statement.
I have made the first statement an update rather than an insert because the 
majority of operations will be updates rather than inserts.

Between each test the table was "truncated" and "vacuum analysed". This was to 
ensure that the order of the tests would have no bearing on the results. 

Test where carried out on using Postgres 7.3 with $dbi->{AutoCommit} = 0" during 
the tests.

I carried out each set of tests 3 times so that a system average can be 
guaged. 


Cache size = 0
It took Tie::RDBM         300 wallclock secs (33.13 usr +  2.01 sys = 35.14 CPU)
It took Tie::RDBM::Cached 345 wallclock secs (38.28 usr +  2.11 sys = 40.39 CPU)
It took Raw DBI           51  wallclock secs ( 6.33 usr +  0.64 sys =  6.97 CPU)

It took Tie::RDBM         315 wallclock secs (33.69 usr +  1.78 sys = 35.47 CPU)
It took Tie::RDBM::Cached 349 wallclock secs (37.89 usr +  2.10 sys = 39.99 CPU)
It took Raw DBI           50  wallclock secs ( 6.66 usr +  0.56 sys =  7.22 CPU)

It took Tie::RDBM         314 wallclock secs (33.06 usr +  1.66 sys = 34.72 CPU)
It took Tie::RDBM::Cached 352 wallclock secs (38.56 usr +  1.74 sys = 40.30 CPU)
It took Raw DBI           53  wallclock secs ( 6.80 usr +  0.72 sys =  7.52 CPU)

We can see straight away that if you are not using the cache that the extra abstraction
in the Tie::RDBM::Cached code causes a performance hit. The raw DBI goes like lightning 
compared to the two tied modules and this is why I advocate using it unless you need
to do something very specific and the DBI does not cover it.

Cache size = 50



Cache size = 100



Cache size = 500 





Cache size = 1000





Cache size = 2000





Cache size = 5000



=head1 TO DO LIST

    - Add the BerkelyDB as a caching method.
    - Produce some performance metrics. 
    - Write tests for release.

=head1 BUGS

Of that I am sure.

=head1 AUTHOR

Harry Jackson, harry@hjackson.org

=head1 COPYRIGHT

  Copyright (c) 2003, Harry Jackson

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 AVAILABILITY

The latest version can be obtained from:
   

=head1 SEE ALSO

perl(1), Tie::RDBM, DBI(3), Storable(3)

=cut
