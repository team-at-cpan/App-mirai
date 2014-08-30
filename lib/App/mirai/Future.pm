package App::mirai::Future;

use strict;
use warnings;

use Future;
use Time::HiRes ();
use Scalar::Util ();
use List::UtilsBy ();

use Carp qw(cluck);

use App::mirai::Watcher;

BEGIN { $Future::TIMES = 1 }

our %FUTURE_MAP;
our @WATCHERS;

=head1 create_watcher

Returns a new L<App::mirai::Watcher>.

=cut

sub create_watcher {
	my $class = shift;
	push @WATCHERS, my $w = App::mirai::Watcher->new;
	$w->subscribe_to_event(@_) if @_;
	# explicit discard
#	Scalar::Util::weaken $WATCHERS[-1];
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

=head1 futures

Returns all the Futures we know about.

=cut

sub futures {
	grep defined, map $_->{future}, sort values %FUTURE_MAP
}

=head1 MONKEY PATCHES

=cut

sub Future::DESTROY {
	my $f = shift;
	# my $f = $destructor->(@_);
	my $entry = delete $FUTURE_MAP{$f};
	$_->invoke_event(destroy => $f) for grep defined, @WATCHERS;
	$f
}

BEGIN {
	my $prep = sub {
		my $f = shift;
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
			nodes => [
			],
		};
		Scalar::Util::weaken($entry->{future});
		$FUTURE_MAP{$f} = $entry;
		$f->set_label('unknown');
		my $name = "$f";
		$f->on_ready(sub {
			my $f = shift;
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

Tom Molesworth <cpan@entitymodel.com>

=head1 LICENSE

Copyright Tom Molesworth 2014. Licensed under the same terms as Perl itself.

