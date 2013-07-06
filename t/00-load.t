#!perl
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Object::DI::Spring' ) || print "Bail out!\n";
}

diag( "Testing Object::DI::Spring $Object::DI::Spring::VERSION, Perl $], $^X" );
