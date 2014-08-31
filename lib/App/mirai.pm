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

use constant FORMAT => $ENV{MIRAI_FORMAT} || 'JSON'; # Sereal

use Socket qw(AF_UNIX SOCK_STREAM PF_UNSPEC);
use IO::Handle;

use if FORMAT eq 'Sereal', 'Sereal';
use if FORMAT eq 'JSON', 'JSON::MaybeXS';

sub run_test {
	package App::mirai::MonitoredCode; # Some::Code;
	my $f = Future->new->set_label('tester');
	my @pending = map Future->new->set_label("task_$_"), qw(1 2 3);
	my $compound = Future->needs_all(@pending)->set_label('needs_all');
	$pending[0]->done;
	$pending[1]->fail('error');
	$f->done('marked');
}

my ($child_pid);
my ($child_read, $parent_write);
my ($child_write, $parent_read);

BEGIN {
	# see perlipc
	socketpair $child_read, $parent_write, AF_UNIX, SOCK_STREAM, PF_UNSPEC or die $!;
	socketpair $child_write, $parent_read, AF_UNIX, SOCK_STREAM, PF_UNSPEC or die $!;
	$child_write->autoflush(1);
	$parent_write->autoflush(1);
	unless($child_pid = fork // die) {
		require App::mirai::Subprocess;

		# Wait for permission to start
		my $line = <$child_read>;
		$child_read->close or die $!;
warn "child active\n";
		my $encoder = FORMAT eq 'JSON' ? JSON::MaybeXS->new(utf8 => 1) : Sereal::Encoder->new;
		App::mirai::Subprocess->setup(sub {
			warn "Sending $_[0] message for " . $_[1]->{id} . "\n";
			eval {
				$child_write->print(pack 'N/a*', $encoder->encode(\@_));
			} or warn $@;
			warn "Sent\n";
		});
		run_test();
		$child_write->close or die $!;
		exit 0;
	}
}

use Future::Utils qw(fmap_void repeat);

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
		my $cs = IO::Async::Stream->new(
			read_handle => $parent_read,
			on_read => sub {
				my ($stream, $buff, $eof) = @_;
				warn "EOF" if $eof;
				if(length $$buff >= 4) {
					my $size = unpack 'N', substr $$buff, 0, 4, '';
					warn "Should read $size bytes\n";
					die "size is fucked" unless $size < 10485760;
					return sub {
						my ($stream, $buff, $eof) = @_;
						warn "EOF in data read";
						warn "Have " . length($$buff) . " out of $size\n";
						return 0 unless length($$buff) >= $size;
						warn "All data available, do the frame\n";
						$self->incoming_frame(substr $$buff, 0, $size, '');
						warn "REturning\n";
						undef
					}
				}
				0
			}
		)
	);
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
	$tickit->prepare;
	$tickit->watcher_future->on_done(sub {
		$ps->write("ok go\n");
		$ps->close or die $!;
	});
	$tickit->run;
}

sub decoder { shift->{decoder} ||= FORMAT eq 'JSON' ? JSON::MaybeXS->new(utf8 => 1) : Sereal::Decoder->new; }

sub incoming_frame {
	my ($self, $frame) = @_;
	# Always load this for display anyway
	require JSON::MaybeXS;
	JSON::MaybeXS->import;

	my $data = $self->decoder->decode($frame);
	my ($cmd, $args) = @$data;
	warn "Had $cmd => $args\n";
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
#	$child->close or die $!;
#	waitpid $child_pid, 0;
}

sub bus { shift->{bus} ||= Mixin::Event::Dispatch::Bus->new }

1;

__END__

=head1 SEE ALSO

=over 4

=item * L<Future>

=back

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2014. Licensed under the same terms as Perl itself.

