# cMonk UI module v2
# Copyright (C) 2013 Rustam Tsurik

package cMonkUI;
use Curses;
use Time::Seconds;

# -- cMonkUI::prepare()
sub prepare {
	my ($self, %args) = @_;

	initscr();
	curs_set(0);
	$win = Curses->new();
	$self->{'window'} = $win;

	$self->{'window'}->getmaxyx($ymax, $xmax);

	$self->{'x-max'} = $xmax;
	$self->{'y-max'} = $ymax;

	$self->{'pulse'} = 1;

	start_color();
	init_pair(1, COLOR_GREEN, COLOR_BLACK);
	init_pair(2, COLOR_RED, COLOR_BLACK);
	init_pair(3, COLOR_WHITE, COLOR_BLACK);
	init_pair(4, COLOR_YELLOW, COLOR_BLACK);
	init_pair(5, COLOR_MAGENTA, COLOR_BLACK);

	$win->attron(COLOR_PAIR(3));
	$win->box(0,0); $win->attroff(COLOR_PAIR(3));

	$win->attron(COLOR_PAIR(1)); 
	$win->addstr(1, 1, "Preparing data...");
	$win->attroff(COLOR_PAIR(1));


	$self->{'display_columns'} = $args{'display_columns'};

	$self->{'version'} = $args{'version'};
	$self->{'window'}->addstr(
		$self->{'y-max'} - 1, 
		1,
		"v" . $self->{'version'} . " Sorted by " . $args{'sort_order'} . " "
		);

	$win->refresh();
}

# -- cMonkUI::cleanup()
sub cleanup(){
	my ($self, %args) = @_;
	curs_set(1);
	endwin();
}

# -- cMonkUI::start_cycle()
# -- Prepare for screen redraw.
sub start_cycle {
	my ($self, %args) = @_;

	my $xmax; my $ymax;
	$self->{'window'}->getmaxyx($ymax, $xmax);

	$self->{'x-max'} = $xmax;
	$self->{'y-max'} = $ymax;
	$self->{'y-pos'} = 1; 

	$win->clear();

	$win->attron(COLOR_PAIR(3));
	$win->box(0,0);
	$win->attroff(COLOR_PAIR(3));

	$self->{'window'}->addstr(
		$self->{'y-max'} - 1, 
		1,
		"v" . $self->{'version'} . " Sorted by " . $args{'sort_order'} . " "
		);
}

# -- cMonkUI::finalize_cycle()
# -- Redraw screen.
sub finalize_cycle {
	my ($self, %args) = @_;

	$self->{'window'}->refresh();
}

# -- cMonkUI::pulse()
# -- Detect screen resize / draw a progress meter.
sub pulse {
	my ($self, %args) = @_;
	my $resize = 0;

	my $xmax; my $ymax;
	$self->{'window'}->getmaxyx($ymax, $xmax);
	if (($self->{'x-max'} != $xmax) | ($self->{'y-max'} != $ymax)) {
		$self->{'x-max'} = $xmax;
		$self->{'y-max'} = $ymax;
		$resize = 1;
	}

	my $puchr = '/';
	if ($self->{'pulse'} == 2 ) { $puchr = '—'; }
	if ($self->{'pulse'} == 3 ) { $puchr = "\\"; $self->{'pulse'} = 0; }
	$self->{'pulse'} += 1;

	$self->{'window'}->addstr(1, $xmax - 3, $puchr);
	$self->{'window'}->refresh();

	return $resize;
}

sub color_ctl {
	my $cpair = 3;  # normal, white
	my ($self, $prio, $op) = @_;
	my %c_t = (
		"low" => 3,     # white
		"high" => 2,    # red
		"medium" => 4,  # yellow
	);

	$cpair = $c_t{$prio};

	if ($op eq "on") {
		$self->{'window'}->attron(COLOR_PAIR($cpair));
	} else {
		$self->{'window'}->attroff(COLOR_PAIR($cpair));
	}
}

# -- cMonkUI::print_header
# -- Output a header for a monitoring plugin.
sub print_header {
my ($self, $text) = @_;

# Add some space.
$self->{'y-pos'} += 1;

$win->attron(COLOR_PAIR(1));
$self->{'window'}->addstr($self->{'y-pos'}, 1, substr($text, 0, $self->{'x-max'} - 2));
$win->attroff(COLOR_PAIR(1));

$self->{'y-pos'} += 1;
}

# -- cMonkUI::print_entry
# -- Output data for a host/trigger.
sub print_entry {
	my ($self, $host, $prio, $age, $data) = @_;

	if ($host ne 'na') {

		# convert age to pretty format
		my $age_ts=Time::Seconds->new($age);
		my $ap = $age_ts->pretty;
		$ap =~ tr/,//d;
		$ap =~ s/ seconds/sec/;
		$ap =~ s/ minutes/min/;
		$ap =~ s/ hours/hr/;
		$ap =~ s/ days/d/;

		my $text = "";
		
		my $col_counter = 1;
		my $col_max = scalar @{$self->{'display_columns'}};
		
		# output the data
		foreach $col (@{$self->{'display_columns'}}) {
			if ($col eq 'hostname') {
				#my $text = "$host - ($ap) - $data";
				$text .= $host;
			}
			if ($col eq 'age') {
				$text .= $ap;
			}
			if ($col eq 'data') {
				$text .= $data;
			}

			# delimiter			
			if ($col_counter++ < $col_max){
				$text .= " | ";	
			}

			
		}
		
#		$text = "$host - ($ap) - $data";

		$self->color_ctl($prio, "on");
		$self->{'window'}->addstr($self->{'y-pos'}, 1, substr($text, 0, $self->{'x-max'} - 2));
		$self->color_ctl($prio, "off");

		$self->{'y-pos'} += 1;
	}
}

# -- cMonkUI::print_entry
# -- Output a text message.
sub print_message {
	my ($self, $text) = @_;

	$self->color_ctl("low", "on");
	$self->{'window'}->addstr($self->{'y-pos'}, 1, substr($text, 0, $self->{'x-max'} - 2));
	$self->color_ctl("low", "off");

	$self->{'y-pos'} += 1;
}


# -- cMonkUI::new()
sub new {
	my ($class, %args) = @_;
	bless \%args, $class;
	return $class;
}
1;
