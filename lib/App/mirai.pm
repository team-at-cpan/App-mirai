package App::mirai;
# ABSTRACT: 
use strict;
use warnings;

our $VERSION = '0.001';

=encoding UTF-8

=head1 NAME

App::mirai -

=head1 SYNOPSIS

=head1 DESCRIPTION

未来

=cut

use App::mirai::Tickit;

=head1 METHODS

=cut

sub new_from_argv {
	my ($class, @args) = @_;
	bless {}, $class
}

sub run { }

1;

__END__

=head1 SEE ALSO

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2014. Licensed under the same terms as Perl itself.

