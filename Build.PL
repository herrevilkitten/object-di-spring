use 5.006;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Object::DI::Spring',
    license             => 'Artistic_2_0',
    dist_author         => q{Eric Kidder <kageneko@evilkitten.org>},
    dist_version_from   => 'lib/Object/DI/Spring.pm',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        #'ABC'              => 1.6,
        #'Foo::Bar::Module' => 5.0401,
    },
    add_to_cleanup     => [ 'Object-DI-Spring-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
