#!/usr/bin/perl

#
# cmonk - console monitoring kit 
# A simple ncurses-based frontend for Zabbix, Nagios, etc.
# Version 2.0.2, 2019-06-15
# Copyright (C) 2013-2019 Rustam Tsurik
# 

use strict;
use warnings;

use Term::ANSIColor qw(:constants);  # Do we use this module?
local $Term::ANSIColor::AUTORESET = 1;

use threads;
use threads::shared;
use Switch;
use JSON;
use Term::ReadKey;
use YAML::XS;
use Env qw(HOME);
use Time::HiRes qw(usleep nanosleep);
use File::Basename;

my $VERSION = '2.0.2';

my $TICK_PERIOD = 100000;        # 100'000us = 10 ticks per second
my $TICK_MAX = 10;                # Reset UI every 10 ticks

my $user_config;                # Loaded user config(.cmonk.yaml) as a Perl object

our %modules_callbacks = ();    # Shared with modules, contains the list of callbacks subs 
my %running_threads = ();        # The list of running threads, includes names and handles

my $do_ui_redraw :shared;        # Used to send the redraw signal from threads to the main process
my $do_shutdown :shared;        # Used to tell the threads to exit the loop
my %last_data :shared;            # Data received from the modules

my $sort_order = 'age';            # Issues sort order, e.g. age or hostname

## start_thread() - The thread subroutine
## arguments: TODO

sub start_thread {

    my ($thread_name, $module_config) = @_;

    # Setup a handler for shutting down this thread
    local $SIG{'KILL'} = sub {
        threads->exit(); 
    };
    
    # The default loop timeout is 60 seconds,
    # but if we have a user-defined one, use it instead
    my $loop_timeout = 60;
    if (defined $module_config->{'refresh'}) {
        $loop_timeout = $module_config->{'refresh'};
    }
    
    # The module type, e.g. zabbix, nagios
    my $module_type = $module_config->{'type'};

    # Enter the loop
    while ($do_shutdown == 0) {

        # Retrieve session data from the last data
        my $json = JSON->new(); $json->allow_nonref(1);
        my $thread_data = $json->decode($last_data{$thread_name});
        my $sess = $thread_data->{'session'};

        # Exec the callback function
        # Send the complete module config and session data
        my $plugin_json_output = $modules_callbacks{$module_type}->('get', $module_config, $sess);

        # Push new data for this thread into the shared variable.
        {
            lock(%last_data);
            $last_data{$thread_name} = $plugin_json_output;
        };

        # Got new data, force UI redraw
        {
            lock($do_ui_redraw);
            $do_ui_redraw = 1;
        };

        sleep($loop_timeout);
    }

}

## load_configs() - Loop through the list of dirs(.:$HOME:/etc), find and load the config
## arguments: NONE

sub load_configs {

    my @CONFIG_DIRS = ('.', $HOME, '/etc');
    my $user_config_path; 

    foreach my $dir (@CONFIG_DIRS) {
        $user_config_path = "$dir/.cmonk";
        (-e $user_config_path) && last;
    }

    die "Couldn't find the config file!" unless (-e $user_config_path);
    $user_config = YAML::XS::LoadFile( $user_config_path );

    (defined $user_config->{'modules'}) or die("Config file parse error: the modules section not found");

    # Default sort order is age, see at the top.
    if (defined $user_config->{'gui'}->{'sort_order'}){
        $sort_order = $user_config->{'gui'}->{'sort_order'};
    }    

}

## load_modules() - TODO
## arguments: NONE

sub load_modules {

    my $modules = $user_config->{'modules'};
    my %loaded_modules = ();

    my $thread_id = 0;

    foreach my $mod (@$modules) {
        # Is it already loaded?
        if (! defined $loaded_modules{$mod->{'type'}} ) {

            # Nope, build the path to this module and attempt to load. 
            my $new_module = "modules/" . $mod->{'type'} . ".pm";
            eval { 
                require $new_module; 
            };
        
            # Check if it was actually loaded and register as such.
            (defined $INC{$new_module}) or die("Unable to load the plugin for " . $mod->{'type'} ."\n");
            $loaded_modules{$mod->{'type'}} = 1;
        }

        # Check whether this module is disabled in the config
        my $mod_enabled = 1;
        if (defined $mod->{'enabled'}){
            if ($mod->{'enabled'} eq 'off') { $mod_enabled = 0; }
        }

        if ($mod_enabled){
            # Now spawn a thread for this module
            # Build a name for this thread, e.g. 10-zabbix-2        
            my $thread_name = $mod->{'position'} . '-' . $mod->{'type'} . "-". $thread_id;

            $running_threads{$thread_name} = {
                "name" => $mod->{'name'},
                "handle" => threads->create('start_thread', $thread_name, $mod),
                "mod" =>  $mod,
            };

            # Init JSON data for this thread
            #
            # data => monitoring data
            # session => auth/session data for this module
            # status => ok/error
            # errormsg => the message
            $last_data{$thread_name} = '{"data":null,"session":"","status":"error","errormsg":"Waiting for data..."}'; 
        }
    } 

}

sub cleanup_and_exit {
    my ($cui) = @_;

    $cui->cleanup();        # clean up UI

    ReadMode('normal');

    # It's likely that this var is already set to 1, but anyway.
    $do_shutdown = 1;

    # Now, shut down all threads by sending the KILL signal
    foreach my $thread_name (keys %running_threads) {
        $running_threads{$thread_name}->{'handle'}->kill('KILL')->detach();

        # The module type, e.g. zabbix or nagios, and session token
        my $module_type = $running_threads{$thread_name}->{'mod'}->{'type'};
        my $sess = JSON->new->allow_nonref->decode( $last_data{$thread_name} )->{'session'};

        # Exec the callback function
        # Send the complete module config and session data
        my $plugin_json_output = $modules_callbacks{$module_type}->(
            'logout', $running_threads{$thread_name}->{'mod'}, $sess
        );

    }

    exit(0);
}

sub setup_ui {

    my ($cui) = @_;

    my @display_columns = ['hostname', 'age', 'data'];
    if (defined $user_config->{'gui'}->{'display_columns'}){
        @display_columns = $user_config->{'gui'}->{'display_columns'};
    }

    ReadMode('cbreak');
    $cui->prepare(
        version => $VERSION,
        sort_order => $sort_order,
        display_columns => @display_columns,
    );
}

sub check_keypress {

    my $read_key = ReadKey(-1); # -1 == non-blocking read
    if (defined $read_key) {

        switch ($read_key) {
            case ["q", "Q"]    {
                # Shutdown the app
                $do_shutdown = 1;
            }
            case ["s", "S"]    {
                # Change the sort order
                if ($sort_order eq 'age'){
                    $sort_order = 'hostname';
                } else {
                    $sort_order = 'age';
                }

                # and force redraw
                {
                    lock $do_ui_redraw;
                    $do_ui_redraw = 1;
                }
            }
        }

    }
}

sub redraw_ui {
    
    my ($cui) = @_;

    # Clear the window, draw borders, etc
    $cui->start_cycle(
        sort_order => $sort_order,
        );

    foreach my $thread_name (sort keys %last_data) {
        # Print the thread name.
        $cui->print_header($running_threads{$thread_name}->{'name'});

        my $json = new JSON; $json->allow_nonref(1);
        my $thread_data = $json->decode($last_data{$thread_name});
        
        if ($thread_data->{'status'} eq 'ok'){
            my $count = 0;

            # Reorder data as per settings
            my @sorted_thread_data = ();

            # won't sort if empty
            if (scalar $thread_data->{'data'} > 0) {
                if ($sort_order eq 'age'){
                    @sorted_thread_data = sort {$b->{'age'} <=> $a->{'age'}} @{$thread_data->{'data'}}
                } else {
                    @sorted_thread_data = sort {$a->{'hostname'} cmp $b->{'hostname'}} @{$thread_data->{'data'}}
                }

                foreach my $host ( @sorted_thread_data ) {
                    # Print the host info.
                    $cui->print_entry($host->{'hostname'}, $host->{'priority'}, $host->{'age'}, $host->{'data'});
                    $count++;
                }
            }
            if ($count == 0) {
                $cui->print_message("No issues detected.");
            }
        } else {
            my $error_message = $thread_data->{'errormsg'};
            $cui->print_message($error_message);
        }

        # Done with GUI, check threads health and restart if needed.
        if (! $running_threads{$thread_name}->{'handle'}->is_running()) {
            $cui->print_message("Thread is NOT running, restart attempted.");

            my $mod = $running_threads{$thread_name}->{'mod'};
            $running_threads{$thread_name}->{'handle'} = threads->create('start_thread', $thread_name, $mod);
        }
    }

    # Refresh the window
    $cui->finalize_cycle();

    # Done with redrawing
    { 
        lock($do_ui_redraw); 
        $do_ui_redraw = 0; 
    }
}

## 
## Let's go! Start the main thread.
##

# Init the variables
$do_shutdown = 0;    # Global, shared var
$do_ui_redraw = 0;    # Global, shared var

# Load the configs and load the modules
load_configs();
load_modules();

# Create a new UI object and call the setup_ui function
my $cui = cMonkUI->new();
setup_ui($cui);

# Set up a handler for the INT signal/Ctrl-C
$SIG{'INT'} = sub { 
    cleanup_and_exit($cui);
};

# Main loop tick counter
my $tick = 1;

# Enter the main loop
while ($do_shutdown == 0) {

    # Check if any keys have been pressed
    check_keypress();

    # Redraw UI if we got new data or something
    if ($do_ui_redraw == 1) {
        redraw_ui($cui);
    }

    usleep($TICK_PERIOD);
    if ($tick == $TICK_MAX) {
        $tick = 1;

        # cMonkUI->pulse() updates the progress bar and detects window resize
        my $window_resized = $cui->pulse();
        if ( $window_resized == 1 ) {
            lock($do_ui_redraw); 
            $do_ui_redraw = 1; 
        }
    }
    $tick++;
}

# We are done, clean up and exit
cleanup_and_exit($cui);

# Load the UI module
BEGIN {
    my $dir = dirname(__FILE__);
    push @INC, $dir; 
    require cMonkUI;
}
