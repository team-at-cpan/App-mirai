package App::mirai;
# ABSTRACT: Monitor and debug Future objects
use strict;
use warnings;

our $VERSION = '0.001';

=encoding UTF-8

=head1 NAME

App::mirai -

=head1 SYNOPSIS

 # start an IO::Async::Listener on the given port/socket file. Means the event loop needs to
 # be running, but should be able to hook into an existing application without too much trouble.
 # Some complications around Future nesting (Futures are created by the debugger itself) but
 # that's easy enough to work around
 perl -d:Mirai=localhost:1234 script.pl
 perl -d:Mirai=/tmp/mirai.sock script.pl
 
 # Run Tickit interface directly, presuming that the code itself is silent - everything is
 # in-process, so no need for debugging to go via pipes
 perl -Mirai script.pl
 
 # Run the Tickit interface, and have it load the script as a separate process, directing
 # STDOUT/STDERR to windows in the UI and communicating via pipepair
 mirai script.pl

=head1 DESCRIPTION

Provides a basic debugging interface for tracing and interacting with L<Future>s. This should
allow you to see the L<Future> instances currently in use in a piece of code, and what their
current status is.

The UI is currently L<Tickit>-based, there's a web interface in the works as well.

Why the name? Mirai (未来) roughly translates to C< Future >, at least according to my limited
Japanese vocabulary.

=cut

use App::mirai::Tickit;

=head1 METHODS

=cut

sub new_from_argv {
	my ($class, @args) = @_;
	bless {}, $class
}

sub run {
	my $self = shift;
	App::mirai::Tickit->new->run;
}

1;

__END__

=head1 SEE ALSO

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2014. Licensed under the same terms as Perl itself.

