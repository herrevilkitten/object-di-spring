package Object::DI::Spring;
use Modern::Perl;
use Moose;
use namespace::sweep;

use File::Spec;
use IO::File;
use XML::Simple;
use Scalar::Util;

use Object::DI::Spring::Bean;

has sources => is => 'ro', isa => 'ArrayRef', default => sub { [] };
has beans => is => 'ro', isa => 'HashRef', default => sub { {} };
has objects => is => 'ro', isa => 'HashRef', default => sub { {} };

=head1 NAME

Object::DI::Spring - Simple dependency injection container

=head1 VERSION

Version 1.00

=cut

our $VERSION = '1.00';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Object::DI::Spring;

    my $foo = Object::DI::Spring->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 BUILD

=cut

sub BUILD {
	my ($self, $args) = @_;
	if ( $args->{source} ) {
		if ( ref($args->{source}) eq 'ARRAY' ) {
			$self->load(@{ $args->{source} });
		} else {
			$self->load($args->{source});
		}

		if ( $args->{make_methods} ) {
			while ( my ($id, $entry) = each %{ $self->{objects} } ) {
				no strict 'refs';
				my $name = lc $id;
				$name =~ s/_+/_/go;
				$name =~ s/\s+//go;
				my $method = __PACKAGE__ . "::${name}";
				*{$method} = sub { $entry };
			}
		}

		while ( my ($id, $entry) = each %{ $self->{objects} } ) {
			if ( !$entry->lazy ) {
				$entry->instantiate;
			}
		}
	}
}

=head2 load

=cut

sub load {
	my ($self, @sources) = @_;
	
	foreach my $source ( @sources ) {
		next if !defined $source;
		my $ref = ref($source);
		my $xml;
		if ( !$ref ) {
			# Filename
			$source = $self->_load_file($source);
			$ref = ref($source);
		}

		my $input;
		if ( $ref eq 'GLOB' || $ref eq 'IO::File' ) {
			# Filehandle
			$input = join('', <$source>);
		} elsif ( $ref eq 'SCALAR' ) {
			# XML data input
			$input = $$source;
		} else {
			warn "$source is not a source of injectable components.";
			next;
		}

		if ( defined $input ) {
			$xml = XMLin($input, KeepRoot => 0, NSExpand => 1);
		}

		$self->load_beans($xml);
	}
}

sub load_beans {
	my ($self, $xml) = @_;
	
		use Data::Dumper;
		$Data::Dumper::Indent = 1;
	my $beans = $xml->{bean};
		say Dumper($xml);
	while ( my ($id, $def) = each %$beans ) {
		$def->{id} = $id;
		my $bean = Object::DI::Spring::Bean->new($def);
	}
}

sub load_source {
	my ($self, $source) = @_;
	
	foreach my $item ( @$source ) {
		if ( !ref($item) ) {
			$self->_load_file($item);
			next;			
		}
		if ( $item->{include} ) {
			$self->_load_file($item->{include});
			next;
		} elsif ( $item->{package} && $item->{package} eq '_constants' ) {
			while ( my ($key, $value) = each %{ $item->{data}} ) {
				my $id = $key;
				my $entry = Object::DI::Entry->new(
					id => $id,
				);
				$entry->{container} = $self;
				$entry->{scope} = 'singleton';
				$entry->{class} = 'VALUE';
				$entry->{source} = $source;
				$entry->{instance} = undef;
				$entry->{data} = $value;
				$entry->{lazy} = 0;

				if ( $self->{objects}->{$id} ) {
					warn "Overwriting existing $id";
				}
				$self->{objects}->{$id} = $entry;				
			}
		} else {
			my $id = $item->{id};
			my $entry = Object::DI::Entry->new(
				id => $id,
			);
			$entry->{container} = $self;
			$entry->{scope} = lc($item->{scope} // 'singleton');
			$entry->{class} = $item->{package} // 'VALUE';
			$entry->{source} = $source;
			$entry->{instance} = undef;
			$entry->{properties} = $item->{properties};
			$entry->{arguments} = $item->{arguments};
			$entry->{factory} = $item->{factory};
			$entry->{method} = $item->{method} // 'new';
			$entry->{data} = $item->{data};
			$entry->{lazy} = $item->{lazy} // 1;
			$entry->{dereference} = $item->{dereference} // 1;

			if ( $self->{objects}->{$id} ) {
				warn "Overwriting existing $id [" . $self->get($id) . "]";
			}
			$self->{objects}->{$id} = $entry;
		}
	}
}

sub _load_file {
	my ($self, $file) = @_;

	my @path = ( '', '.' );
	if ( $file =~ s/^inc:(.+)/$1/io ) {
		# Search @INC
		push @path, @INC;
	}

	foreach my $path ( @path ) {
		my $full_path = File::Spec->catfile($path, $file);
		next if !-r $full_path;
		return IO::File->new($full_path, 'r');
	}

	die "Unable to load $file\n";
}

=head2 get

=cut

sub get {
	my ($self, $id) = @_;

	$id = lc $id;
	my $object = $self->{objects}->{$id};
	if ( !defined $object ) {
		die "No object '$id' found in container.";
	}

	return $object->instantiate();
}

sub get_by_package {
	my ($self, $package) = @_;
	my @objects = ();
	if ( defined $package && $package ne '' ) {
		while ( my ($id, $object) = each %{ $self->{object} } ) {
			if ( $object->{class} ne $package ) {
				next;
			}
			push @objects, $object;
		}
	}

	return @objects;		
}

sub get_by_isa {
	my ($self, $package) = @_;
	my @objects = ();
	if ( defined $package && $package ne '' ) {
		while ( my ($id, $object) = each %{ $self->{object} } ) {
			my $class = $object->{class};
			if ( $class eq 'VALUE' || !$class->isa($package) ) {
				next;
			}
			push @objects, $object;
		}
	}

	return @objects;		
}

sub get_by_role {
	my ($self, $package) = @_;
	my @objects = ();
	if ( defined $package && $package ne '' ) {
		while ( my ($id, $object) = each %{ $self->{object} } ) {
			my $class = $object->{class};
			if ( $class eq 'VALUE' || !$class->can('does') || !$class->does($package) ) {
				next;
			}
			push @objects, $object;
		}
	}

	return @objects;		
}

=head1 AUTHOR

Eric Kidder, C<< <eric.kidder at sensus.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-Object-DI at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Object-DI>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Object::DI


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Object-DI>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Object-DI>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Object-DI>

=item * Search CPAN

L<http://search.cpan.org/dist/Object-DI/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Eric Kidder.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of Object::DI
