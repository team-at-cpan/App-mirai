package App::mirai::Watcher;

use strict;
use warnings;

use parent qw(Mixin::Event::Dispatch);

use Variable::Disposition;

sub new { my $class = shift; bless { @_ }, $class }

sub discard {
	my $self = shift;
	App::mirai::Future->delete_watcher($self);
	dispose $self;
}

1;

