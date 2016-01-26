package App::mirai;
# ABSTRACT: Monitor and debug Future objects
use strict;
use warnings;

our $VERSION = '0.001';

=encoding UTF-8

=head1 NAME

App::mirai - debugging for L<Future>-based code

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

=head2 SERIALISATION

Defines the serialisation format to use. Prefers L<Sereal> if available, will fall back
to JSON via L<JSON::MaybeXS>. Set C< MIRAI_SERIALISATION > to override:

=over 4

=item * Sereal

=item * JSON

=back

=cut

use constant SERIALISATION => $ENV{MIRAI_SERIALISATION} || (eval { require Sereal } ? 'Sereal' : 'JSON');

use Socket qw(AF_UNIX SOCK_STREAM PF_UNSPEC);
use IO::Handle;

my ($child_pid);
my ($child_read, $parent_write);
my ($child_write, $parent_read);

BEGIN {
	# see perlipc
	socketpair $child_read, $parent_write, AF_UNIX, SOCK_STREAM, PF_UNSPEC or die $!;
	socketpair $child_write, $parent_read, AF_UNIX, SOCK_STREAM, PF_UNSPEC or die $!;
	$child_write->autoflush(1);
	$parent_write->autoflush(1);

	die "No script provided" unless defined(my $script = shift @ARGV);
	unless($child_pid = fork // die) {
		require App::mirai::Subprocess;

		# Wait for permission to start
		my $line = <$child_read>;
		# $child_read->close or die $!;

		my $encoder = SERIALISATION eq 'JSON' ? JSON::MaybeXS->new(utf8 => 1) : Sereal::Encoder->new;
		App::mirai::Subprocess->setup(sub {
			eval {
				$child_write->print(pack 'N/a*', $encoder->encode(\@_));
			} or warn $@;

			# Single-step mode... not very efficient at all.
			my $line = <$child_read>;
		});

		if(!defined(do $script) && $@) {
			$child_write->print(
				pack 'N/a*', $encoder->encode([
					error => {
						location => $script,
						exception => $@
					}
				])
			);
		}

		$child_write->close or die $!;
		exit 0;
	}
}

use Future::Utils qw(fmap_void repeat);

use File::HomeDir;
use File::ShareDir;

use Mixin::Event::Dispatch::Bus;
use App::mirai::FutureProxy;
use App::mirai::Tickit;

=head1 METHODS

=cut

sub new_from_argv {
	my ($class, @args) = @_;
	bless {}, $class
}

sub run {
	my $self = shift;
	my $tickit = App::mirai::Tickit->new(bus => $self->bus);
	my $loop = App::mirai::Tickit::loop();
	$loop->add(
		my $ps = IO::Async::Stream->new(
			write_handle => $parent_write,
			on_read => sub {
				my ($stream, $buff, $eof) = @_;
				warn "read from parent, that's backwards...";
				warn "eof on parent" if $eof;
				0
			}
		)
	);
	$loop->add(
		my $cs = IO::Async::Stream->new(
			read_handle => $parent_read,
			on_read => sub {
				my ($stream, $buff, $eof) = @_;
				if(length $$buff >= 4) {
					my $size = unpack 'N', substr $$buff, 0, 4, '';
					# just in case someone tries to use a single socketpair
					# for all communications and gets back our starter message
					# instead of the encoded data we were expecting >_>
					die "Unexpected size is fucked" unless $size < 10485760;

					return sub {
						my ($stream, $buff, $eof) = @_;
						return 0 unless length($$buff) >= $size;
						$self->incoming_frame(substr $$buff, 0, $size, '');
						$ps->write("ok\n");
						undef
					}
				}
				0
			}
		)
	);
	$tickit->prepare;
	$tickit->watcher_future->on_done(sub {
		$ps->write("go\n");
#		$ps->close or die $!;
	});
	$tickit->run;
	$child->close or die $!;
	waitpid $child_pid, 0;
}

sub decoder { shift->{decoder} ||= SERIALISATION eq 'JSON' ? JSON::MaybeXS->new(utf8 => 1) : Sereal::Decoder->new; }

sub incoming_frame {
	my ($self, $frame) = @_;
	# Always load this for display anyway
	require JSON::MaybeXS;
	JSON::MaybeXS->import;

	my $data = $self->decoder->decode($frame);
	my ($cmd, $args) = @$data;
#	warn "Had $cmd => $args\n";
	my $f;
	if($cmd eq 'create') {
		$f = App::mirai::FutureProxy->new(%$args);
		App::mirai::FutureProxy->_create($f);
	} elsif($cmd eq 'label') {
		$f = App::mirai::FutureProxy->_lookup($args->{id}) or die "we have no " . $args->{id};
		$f->{$_} = $args->{$_} for keys %$args;
	} elsif($cmd eq 'ready') {
		$f = App::mirai::FutureProxy->_lookup($args->{id});
		$f->{$_} = $args->{$_} for keys %$args;
	} elsif($cmd eq 'destroy') {
		$f = App::mirai::FutureProxy->_lookup($args->{id});
		require Time::HiRes;
		$f->{deleted} = Time::HiRes::time;
		App::mirai::FutureProxy->_delete($f);
	} else {
		warn "unknown: $cmd => $args\n"
	}
	$self->bus->invoke_event($cmd => $f);
}

sub bus { shift->{bus} ||= Mixin::Event::Dispatch::Bus->new }

sub user_path {
	shift->{user_path} //= File::HomeDir->my_dist_data(
		'App-mirai',
		{ create => 1 }
	);
}

sub share_path {
	shift->{user_path} //= File::ShareDir->my_dist_data(
		'App-mirai',
		{ create => 1 }
	);
}

1;

__END__

=head1 SEE ALSO

=over 4

=item * L<Future>

=back

=head1 AUTHOR

Tom Molesworth <TEAM@cpan.org>

=head1 LICENSE

Copyright Tom Molesworth 2014-2015. Licensed under the same terms as Perl itself.

