package App::mirai::Tickit;

use strict;
use warnings;
use utf8;

use Tickit::DSL qw(:async);
use Tickit::Utils qw(substrwidth textwidth);
use App::mirai::Tickit::TabRibbon;
use App::mirai::Tickit::Widget::Logo;
use Future;
use POSIX qw(strftime);

use File::HomeDir;
use JSON::MaybeXS;

my %widget;
my $path = File::HomeDir->my_dist_data(
	'App-mirai',
	{ create => 1 }
);

Tickit::Style->load_style(<<'EOF');
Breadcrumb {
 powerline: 1;
 highlight-bg: 238;
}
MenuBar { bg: 'blue'; fg: 'hi-yellow'; rv: 0; highlight-fg: 'black'; }
Menu { bg: '232'; fg: 'white'; rv: 0; }
Table { highlight-bg: '238'; highlight-fg: 'hi-yellow'; highlight-b: 0; }
FileViewer { highlight-b: 0; }
EOF

sub new { bless {}, shift }

sub app_about {
	my $vbox = shift;
	my ($tw, $th) = map $vbox->window->$_, qw(cols lines);
	my ($w, $h) = (34, 18);
	float {
		my $f = shift;
		frame {
			vbox {
				customwidget {
					App::mirai::Tickit::Widget::Logo->new
				};
				static 'A tool for debugging Futures', align => 0.5, 'parent:expand' => 1;
				hbox {
					static ' ', 'parent:expand' => 1;
					button {
						$f->remove;
					} 'OK';
					static ' ', 'parent:expand' => 1;
				};
			} style => { spacing => 1 };
		} title => '未来',
		  style => {
			linetype => 'single'
		}
	} top => int(($th-$h)/2),
	  left => int(($tw-$w)/2),
	  right => int($tw - ($tw-$w)/2),
	  bottom => int($th - ($th-$h)/2);
}

sub app_menu {
	menubar {
		submenu File => sub {
			menuitem 'Open session' => sub { warn 'open' };
			menuitem 'Save session' => sub {
				my $sp = "$path/last_session";
				unlink $sp if -l $sp;
				my $session = { };
				my @win = @{$widget{desktop}->{widgets}};
				for my $widget (@win) {
					my $label = $widget->label;
					$session->{$label} = {
						geometry => [
							map {;
								$widget->window->rect->$_
							} qw(top left lines cols)
						]
					};
				}
				open my $fh, '>', $sp or die $!;
				$fh->print(encode_json($session));
			};
			menuitem 'Save session as...' => sub { warn 'save as' };
			menuspacer;
			menuitem Exit  => sub { tickit->stop };
		};
		submenu Debug => sub {
			menuitem Copy => sub { warn 'copy' };
			menuitem Cut => sub { warn 'cut' };
			menuitem Paste => sub { warn 'paste' };
		};
		menuspacer;
		submenu Help => sub {
			menuitem About => sub {
				app_about();
			};
		};
	};
}

sub apply_layout {
	vbox {
		floatbox {
			vbox {
				app_menu();
				$widget{desktop} = desktop {
					vbox {
						my $bc = breadcrumb {
						} item_transformations => sub {
							my ($item) = @_;
							return '' if $item->name eq 'Root';
							$item->name
						};
						my $tree = tree {
						} data => [
							Pending => [
								qw(label2 label3 label4)
							],
							Done => [
								qw(label5)
							],
							Failed => [
								qw(label6)
							],
							Cancelled => [
								qw(label7)
							],
							Dependents => [
								needs_all => [
									qw(label2 label4)
								]
							],
						];
						$bc->adapter($tree->position_adapter);
					} 'parent:top' => 3,
					  'parent:left' => 3,
					  'parent:lines' => 5,
					  'parent:label' => 'Futures';
					tabbed {
						table {
						} columns => [
							{ label => 'Created' },
							{ label => 'Type' },
							{ label => 'Elapsed' },
						], 'parent:label' => 'Pending (1)';
						{ # Cancelled
							my $tbl;
							my $truncate = sub {
								my ($row, $col, $item) = @_;
								my $def = $tbl->{columns}[$col];
								return Future->wrap($item) unless textwidth($item) > $def->{value};
								Future->wrap(substrwidth $item, textwidth($item) - $def->{value});
							};
							$tbl = table {
								my ($row, $future) = @_;
							} item_transformations => [sub {
								my ($row, $f) = @_;
								my $info = App::mirai::Future->future($f);
								my $elapsed = $f->elapsed;
								my $ms = sprintf '.%03d', int(1000 * ($elapsed - int($f->elapsed)));
								Future->wrap([
									$f->label,
									$info->{created_at} // '?',
									$info->{ready_at} // '?',
									($info->{type} eq 'dependent' ? 'dep' : $info->{type}),
									strftime('%H:%M:%S', gmtime int $elapsed) . $ms
								]);
							}], columns => [
								{ label => 'Label' },
								{ label => 'Created', transform => [$truncate] },
								{ label => 'Cancelled', transform => [$truncate] },
								{ label => 'Type', width => 5 },
								{ label => 'Elapsed', align => 'right', width => 12},
							], 'parent:label' => 'Pending (1)';
							$tbl->adapter->push([ my $f = Future->new->set_label('test') ]);
							tickit->later($f->curry::done);
						}
						static 'tab 2', 'parent:label' => 'Failed (42)';
						static 'tab 2', 'parent:label' => 'Cancelled (123)';
					} ribbon_class => 'App::mirai::Tickit::TabRibbon',
					  tab_position => 'top',
					  'parent:label' => 'By state';
					fileviewer {
					} 'example.pl',
					  'tabsize' => 4,
					  'parent:label' => 'example.pl';
				} 'parent:expand' => 1;
			}
		} 'parent:expand' => 1;
		$widget{statusbar} = statusbar { };
	};
	$widget{statusbar}->update_status('OK');
}

sub run {
	my ($self) = @_;
	apply_layout();
	if(-r "$path/last_session") {
		open my $fh, '<', "$path/last_session" or die $!;
		my $session = decode_json(do { local $/; <$fh> });
		tickit->later(sub {
			my @win = @{$widget{desktop}->{widgets}};
			for my $widget (@win) {
				my $label = $widget->label;
				warn "have widget with label $label";
				if(exists $session->{$label}) {
					warn "Set geometry: ", join(',', @{$session->{$label}->{geometry}});
					$widget->window->change_geometry(
						@{$session->{$label}->{geometry}}
					)
				}
			}
			$win[0]->{linked_widgets}{right} = [
				left => $win[1]
			];
			$win[0]->{linked_widgets}{top} = [
				top => $win[1]
			];
		});
	}
	tickit->run;
}

1;

