package App::mirai::Watcher;

use strict;
use warnings;

use parent qw(Mixin::Event::Dispatch);

use Variable::Disposition;

sub new { my $class = shift; bless { @_ }, $class }

sub discard {
	App::mirai::Future->delete_watcher($_[0]);
	dispose $_[0];
}

1;

