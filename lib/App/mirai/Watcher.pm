package App::mirai::Watcher;

use strict;
use warnings;

use parent qw(Mixin::Event::Dispatch);

=head1 NAME

App::mirai::Watcher - event class for L<App::mirai::Future> notifications

=cut

use Variable::Disposition;

sub new { my $class = shift; bless { @_ }, $class }

=head2 discard

Disposes of this watcher. Will raise an exception if anything else is
holding on to it.

=cut

sub discard {
	App::mirai::Future->delete_watcher($_[0]);
	dispose $_[0];
}

1;

__END__

=head1 AUTHOR

Tom Molesworth <TEAM@cpan.org>

=head1 LICENSE

Copyright Tom Molesworth 2014-2015. Licensed under the same terms as Perl itself.


