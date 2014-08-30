package App::mirai::Tickit;

use strict;
use warnings;
use utf8;

use Tickit::DSL qw(:async);
use App::mirai::Tickit::TabRibbon;
use App::mirai::Tickit::Widget::Logo;

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
MenuBar { bg: 'blue'; fg: 'hi-yellow'; rv: 0; }
Menu { bg: '232'; fg: 'white'; rv: 0; }
EOF

sub new { bless {}, shift }

sub app_about {
	float {
		my $f = shift;
		frame {
			vbox {
				customwidget {
					App::mirai::Tickit::Widget::Logo->new
				};
				static 'A tool for debugging Futures', 'parent:expand' => 1;
				button {
					$f->remove;
				} 'OK';
			}
		} title => '未来',
		  style => {
			linetype => 'single'
		}
	} top => 2,
	  left => 2,
	  right => -2,
	  bottom => -2;
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
						static 'tab 1', 'parent:label' => 'Pending (1)';
						static 'tab 2', 'parent:label' => 'Done (23)';
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

