package cMonkUI;

use Curses;
use Switch;
use Time::Seconds;

=head1 NAME

cMonkUI - Curses UI module for cmonk

=head1 SYNOPSIS

    use cMonkUI;
    my $cui = cMonkUI->new();

    # Color scheme initialization. Draw the borders, etc.
    $cui->prepare(
        version => $VERSION,
        sort_order => $sort_order,
        display_columns => @display_columns,
    );

    # In a loop:
    # Clear the window, draw borders, etc.
    $cui->start_cycle(
        sort_order => $sort_order,
    );

    # For each monitoring plugin:
    $cui->print_header($running_threads{$thread_name}->{'name'});
    $cui->print_entry($host->{'hostname'}, $host->{'prio'}, $host->{'age'}, $host->{'data'});

    $cui->print_message($error_message);

    # Refresh screen
    $cui->finalize_cycle();

    # Detect screen resize, draw progress meter
    my $window_resized = $cui->pulse();

    # On exit
    $cui->cleanup();



=head1 DESCRIPTION

This module is supposed to be used as a part of cmonk software.

=head2 Methods

=cut

=item C<cMonkUI::prepare()>

Color scheme initialization. Draw the borders, etc.
This method is called only once during the program initialization.

=cut

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
        $self->{'y-max'} - 1, 1,
        "v" . $self->{'version'} . " | " . $args{'sort_order'} . " "
    );

    $win->refresh();
}

# -- cMonkUI::cleanup()
sub cleanup(){
    my ($self, %args) = @_;
    curs_set(1);
    endwin();
}

=item C<cMonkUI::start_cycle($self, %args)>

Prepare for screen redraw.

=cut

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
        $self->{'y-max'} - 1, 1,
        "v" . $self->{'version'} . " | " . $args{'sort_order'} . " "
    );
}

=item C<cMonkUI::finalize_cycle()>

Redraw the screen.

=cut

sub finalize_cycle {
    my ($self, %args) = @_;

    $self->{'window'}->refresh();
}

=item C<cMonkUI::pulse()>

Detect screen resize / draw a progress meter.

=cut

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
    if ($self->{'pulse'} == 2 ) { $puchr = '-'; }
    if ($self->{'pulse'} == 3 ) { $puchr = "\\"; $self->{'pulse'} = 0; }
    $self->{'pulse'} += 1;

    $self->{'window'}->addstr(1, $xmax - 3, $puchr);
    $self->{'window'}->refresh();

    return $resize;
}

=item C<color_ctl($self, $priority, $operation)>

Set text color accorging to the priority

=cut

sub color_ctl {
    my ($self, $priority, $operation) = @_;

    my %color_table = (
        "low"    => 3,  # white
        "high"   => 2,  # red
        "medium" => 4,  # yellow
    );

    my $color_pair = $color_table{$prio};

    switch ($operation) {
        case ('on') { $self->{'window'}->attron(COLOR_PAIR($color_pair)) }
        case ('off') { $self->{'window'}->attroff(COLOR_PAIR($color_pair)) }
    }
}

=item C<cMonkUI::print_header($self, $text)>

Output a header for a monitoring plugin.

=cut

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
        
        $self->color_ctl($prio, "on");
        $self->{'window'}->addstr($self->{'y-pos'}, 1, substr($text, 0, $self->{'x-max'} - 2));
        $self->color_ctl($prio, "off");

        $self->{'y-pos'} += 1;
    }
}

=item C<cMonkUI::print_entry($self, $text)>

Output a text message.

=cut

sub print_message {
    my ($self, $text) = @_;

    $self->color_ctl("low", "on");
    $self->{'window'}->addstr($self->{'y-pos'}, 1, substr($text, 0, $self->{'x-max'} - 2));
    $self->color_ctl("low", "off");

    $self->{'y-pos'} += 1;
}


=item C<cMonkUI::new()>

The class constructor.

=cut

sub new {
    my ($class, %args) = @_;
    bless \%args, $class;
    return $class;
}

1;

__END__

=head1 AUTHOR

Rustam Tsurik E<lt>rustam.tsurik@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013-2019 by Rustam Tsurik

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.

=cut