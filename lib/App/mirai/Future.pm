package App::mirai::Future;

use strict;
use warnings;

=head1 NAME

App::mirai::Future - injects debugging code into L<Future>

=head1 DESCRIPTION

On load, this will monkey-patch L<Future> to provide various precarious
hooks for Future-related events.

=cut

use Future;
use Time::HiRes ();
use Scalar::Util ();
use List::UtilsBy ();

use Carp qw(cluck);

use App::mirai::Watcher;

# Elapsed time is important to us, even though we could leave this off and
# track it ourselves
BEGIN { $Future::TIMES = 1 }

our %FUTURE_MAP;
our @WATCHERS;

=head1 create_watcher

Returns a new L<App::mirai::Watcher>.

 my $watcher = App::mirai::Future->create_watcher;
 $watcher->subscribe_to_event(
  create => sub { my ($ev, $f) = @_; warn "Created new future: $f\n" },
 );

=cut

sub create_watcher {
	my $class = shift;
	push @WATCHERS, my $w = App::mirai::Watcher->new;
	$w->subscribe_to_event(@_) if @_;
	$w
}

=head1 delete_watcher

Deletes the given watcher.

=cut

sub delete_watcher {
	my ($class, $w) = @_;
	$w = Scalar::Util::refaddr $w;
	List::UtilsBy::extract_by { Scalar::Util::refaddr($_) eq $w } @WATCHERS;
	()
}

sub future { $FUTURE_MAP{$_[1]} }

=head1 futures

Returns all the Futures we know about.

=cut

sub futures {
	grep defined, map $_->{future}, sort values %FUTURE_MAP
}

=head1 MONKEY PATCHES

These reach deep into L<Future> and are likely to break any time a new version
is released.

=cut

{ no warnings 'redefine';
sub Future::DESTROY {
	my $f = shift;
	# my $f = $destructor->(@_);
	$_->invoke_event(destroy => $f) for grep defined, @WATCHERS;
	my $entry = delete $FUTURE_MAP{$f};
	$f
}

sub Future::set_label {
	my $f = shift;
	( $f->{label} ) = @_;
	$_->invoke_event(label => $f) for grep defined, @WATCHERS;
	return $f;
}
}

BEGIN {
	my $prep = sub {
		my $f = shift;

		# Grab the stacktrace first, so we know who started this
		my (undef, $file, $line) = caller(1);
		my $stack = do {
			my @stack;
			my $idx = 1;
			while(my @x = caller($idx++)) {
				unshift @stack, [ @x[0, 1, 2] ];
			}
			\@stack
		};
		if(exists $FUTURE_MAP{$f}) {
			$FUTURE_MAP{$f}{type} = (exists $f->{subs} ? 'dependent' : 'leaf');
			return $f;
		}
		$f->{constructed_at} = do {
			my $at = Carp::shortmess( "constructed" );
			chomp $at; $at =~ s/\.$//;
			$at
		};

		my $entry = {
			future => $f,
			dependents => [ ],
			type => (exists $f->{subs} ? 'dependent' : 'leaf'),
			created_at => "$file:$line",
			creator_stack => $stack,
			status => 'pending',
		};
		Scalar::Util::weaken($entry->{future});
		$FUTURE_MAP{$f} = $entry;
		my $name = "$f";
		$f->on_ready(sub {
			my $f = shift;
			my (undef, $file, $line) = caller(2);
			$FUTURE_MAP{$f}->{status} = 
				  $f->{failure}
				? "failed"
				: $f->{cancelled}
				? "cancelled"
				: "done";
			$FUTURE_MAP{$f}->{ready_at} = "$file:$line";
			$FUTURE_MAP{$f}->{ready_stack} = do {
				my @stack;
				my $idx = 1;
				while(my @x = caller($idx++)) {
					unshift @stack, [ @x[0,1,2] ];
				}
				\@stack
			};
			# cluck "here -> $f";
			$_->invoke_event(on_ready => $f) for grep defined, @WATCHERS;
		});
	};

	my %map = (
		new => sub {
			my $constructor = shift;
			sub {
				my $f = $constructor->(@_);
				$prep->($f);
				$_->invoke_event(create => $f) for grep defined, @WATCHERS;
				$f
			};
		},
		_new_dependent => sub {
			my $constructor = shift;
			sub {
				my @subs = @{$_[1]};
				my $f = $constructor->(@_);
				$prep->($f);
				my $entry = $FUTURE_MAP{$f};
				# Inform subs that they have a new parent
				for(@subs) {
					die "missing future map entry for $_?" unless exists $FUTURE_MAP{$_};
					push @{$FUTURE_MAP{$_}{dependents}}, $f;
					Scalar::Util::weaken($FUTURE_MAP{$_}{dependents}[-1]);
				}
				$_->invoke_event(dependent => $f) for grep defined, @WATCHERS;
				$f
			};
		},
	);

	for my $k (keys %map) {
		my $orig = Future->can($k);
		my $code = $map{$k}->($orig);
		{
			no strict 'refs';
			no warnings 'redefine';
			*{'Future::' . $k} = $code;
		}
	}
}

1;

__END__

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2014. Licensed under the same terms as Perl itself.

