# Zabbix plugin v2
# The previous version didn't work with newer Zabbix versions
#
# Copyright (C) 2013-2019 Rustam Tsurik

package zabbix2;

use strict;

use JSON;
use Switch;

use JSON::RPC::Legacy::Client;
use Time::Seconds;

my $_module_name = 'zabbix2';
my $_module_version = '1.0.0';

# do_rpc_call() puts error messages into these vars,
# this needs to be rewritten.
my $rpc_error = 0;
my $rpc_error_msg = "";

# zabbix::do_rpc_call
sub do_rpc_call {
    my (
        $uri, $req, 
        $ssl_verification
    ) = @_;

    my $client = new JSON::RPC::Legacy::Client;

    # Disable SSL verification if requested.
    if ($ssl_verification eq "false") {
        $client->ua->ssl_opts(
            verify_hostname => 0,
            SSL_verify_mode => 0x00
        );
    }

    # Run the API call.
    my $res = $client->call($uri, $req);

    # Check if we got an error and put it in the global vars.
    if ($res) { 
        if ($res->is_error) { 
            $rpc_error = 1; 
            $rpc_error_msg = $res->content->{'error'}->{'data'};
        }
    } else { 
        # We didn't even get an error code.
        $rpc_error = 1; $rpc_error_msg = "Unknown error";
    }

    # If we have any content returned by API call, return it.
    if (defined $res->content) {
        return $res->content->{'result'};
    } else { return () }
}

# zabbix::rpc_auth
# Authenticate on Zabbix server
sub zabbix_user_login {
    my ($module_config, $session_token) = @_;

    my $req = {
        method  => 'user.login',
        id => 0,
        jsonrpc => "2.0",
        params  => {
            user => $module_config->{'api_user'},
            password => $module_config->{'api_pass'}
        },
    };

    my $new_session_token = do_rpc_call(
        $module_config->{'api_uri'}, $req, $module_config->{'verify_ssl'}
    );
    return $new_session_token;
}

sub zabbix_user_logout {
    my ($module_config, $session_token) = @_;

    # We don't have a session token, exit  
    if ($session_token eq "") {
        return;
    }
 
    # https://www.zabbix.com/documentation/4.2/manual/api/reference/user/logout
    my $req = {
        jsonrpc => "2.0",
        method => 'user.logout',
        auth => $session_token,
        params => [],
        id => 8,
    };

    my $response = do_rpc_call(
        $module_config->{"api_uri"}, $req, $module_config->{'verify_ssl'}
    );

    if ($response == JSON::true ) {
        return 1;
    }
}

# zabbix::get_data
# Return triggers with error.
sub zabbix_get_data {
    my ($module_config, $session_token) = @_;

    my $new_session_token;    

    # Check if we already have a saved auth key.

    if ($session_token ne "") {
        $new_session_token = $session_token; 
    } else {
        $rpc_error = 0;

        $new_session_token = zabbix_user_login( 
            $module_config, $session_token
        ); 

        if ($rpc_error == 1) {
            # Authentication error
            my $json_text = JSON->new()->allow_nonref(1)->encode(
                { 
                    "status" => "error",
                    "errormsg" => "AUTH ERROR: $rpc_error_msg",
                    "session" => "",
                    "data" => ""
                }
            );
            return $json_text;
        }
    }

    # Request to get triggers.
    my $req = {
        'method'  => 'trigger.get',
        'auth' => $new_session_token,
        'id' => '3',
        'jsonrpc' => '2.0',
        'params'  => {
            'output' => 'extend',
            'select_hosts' => 'extend',
            'sortfield' => 'lastchange',
            'sortorder' => 'ASC',
            'expandExpression' => '0',
            'expandDescription' => '1',
            'selectHosts' => ['hostid', 'name'], 
            'active' => '1',
            'filter' => {
              'value' => '1',
            }
        }
    };

    # Attempt to retrieve triggers.
    $rpc_error = 0;
    my $triggers_data = do_rpc_call(
        $module_config->{'api_uri'}, $req, 
        $module_config->{'verify_ssl'}
    );

  if ( ($rpc_error == 1) && ($rpc_error_msg eq 'Not authorized') ) {
      # Not authorized, try to re-auth.
      $new_session_token = zabbix_user_login( $module_config, $session_token); 
      $req->{'auth'} = $new_session_token;

      # And then run the trigger.get call once again
      $rpc_error = 0;
      $triggers_data = do_rpc_call( 
          $module_config->{'api_uri'}, $req, 
          $module_config->{'verify_ssl'} 
      );
  }

  # Re-auth didn't help, or initially got some other error.
  if ($rpc_error == 1) {
    return JSON->new()->encode(
        { 
            'status' => 'error', 
            'errormsg' => "ERROR: $rpc_error_msg", 
            'session' => '', 
            'data' => '' 
        }
    );
  }

  my @data = ();

  foreach my $trigger (@{$triggers_data}) {

    # This call may select multiple hosts, 
    # use only the first one.
    my $hostname = $trigger->{'hosts'}->[0]->{'name'};

    my $description = $trigger->{'description'};
    my $age_in_seconds = (time - $trigger->{'lastchange'});

    # Just in case we got a negative age, but this shouldn't happen
    if ($age_in_seconds < 0) { $age_in_seconds = 0 };


    # Zabbix has five levels of priority, we convert them down to three;
    # 5 - disaster; 4 - high; 3 - average; 2 - warning; 1 - info
    my $priority = 'low';
    switch ( $trigger->{'priority'} ) {
        case ($_ < 3) { $priority = 'low' }
        case ($_ == 3) { $priority = 'medium' }
        case ($_ > 3) { $priority = 'high'}
    }

    # Push the parsed data into the array
    push (
      @data, 
      { 
        "hostname" => $hostname, 
        "data" => $description,
        "priority" => $priority,
        "age" => $age_in_seconds
      }
    );
  }

  return JSON->new()->allow_nonref(1)->encode(
    { 
        "status" => "ok",
        "session" => $new_session_token,
        "data" => \@data 
    }
  );

}

## Accepts the following params:
## callback name -> get/login/logout
sub _module_callback {
    my ( $call_name, $module_config, $session_token ) = @_;

    switch ($call_name) {
        case 'login'  { 
            return zabbix_user_login( $module_config, $session_token );
        }
        case 'logout' {
            return zabbix_user_logout( $module_config, $session_token ); 
        }
        case 'get'    { 
            return zabbix_get_data( $module_config, $session_token );
        }
    }
}

# Insert this plugin into the callbacks array in the main module
$main::modules_callbacks{ $_module_name } = \&_module_callback;

1;
