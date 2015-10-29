# -- Zabbix cMonk plugin
# -- Copyright (C) 2013 Rustam Tsurik

{
  package zabbix;

  use JSON::RPC::Legacy::Client;
  use Time::Seconds;
  use JSON;

  use strict;

  my $rpc_error = 0;
  my $rpc_error_msg = "";
  

  # -- zabbix::do_rpc_call
  # -- ...
  sub do_rpc_call {
    my ($uri, $req, $sslver) = @_;

    my $client = new JSON::RPC::Legacy::Client;

    # -- Disable SSL verification.
    if ($sslver eq "off") {
      $client->ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0x00
      );
    }

    my $res = $client->call($uri, $req);

    if($res) { 
      if ($res->is_error) { 
        $rpc_error = 1; 
        $rpc_error_msg = $res->content->{error}->{data};
      }
    } else { # We didn't even get an error code.
      $rpc_error = 1;
      $rpc_error_msg = "Unknown error";
    }

    if (defined $res->content) {
      return $res->content->{'result'};
    } else {
      my $empty = ();
      return $empty;
    }
  }

  # -- zabbix::rpc_auth
  # -- Authenticate on Zabbix server.
  sub rpc_auth {
    my ($uri, $user, $pass, $ssl) = @_;

    my $req = {
      method  => 'user.authenticate',
      auth => "",
      id => 0,
      jsonrpc => "2.0",
      params  => {
        user => $user,
        password => $pass
      },
    };

    my $authkey = do_rpc_call($uri, $req, $ssl);
    return $authkey;
  }

  # -- zabbix::get_data
  # -- Return triggers with error.
  sub get_data {
    my ($conf, $session) = @_;
  
    my $uri = $conf->{"api_uri"};
    my $authhash;    

    # -- Check if we already have saved auth key.
    if ($session ne "") {
      $authhash = $session; 
    } else {
    # -- Authenticate, if we haven't yet.
      $rpc_error = 0;
      $authhash = rpc_auth($conf->{"api_uri"}, $conf->{'api_user'}, $conf->{'api_pass'}, $conf->{"verify_ssl"});

      if ($rpc_error == 1) {
         # Authentication error.
         my $json = JSON->new();
         my $json_text = $json->encode({ "status" => "error", "errormsg" => "AUTH ERROR: $rpc_error_msg", "session" => "", "data" => "" });
         return $json_text;
      }

    }

    # -- Get triggers.
    my $req = {
      method  => 'trigger.get',
      auth => $authhash,
      id => 3,
      jsonrpc => "2.0",
      params  => {
        output => "extend",
        select_hosts => "extend",
        sortfield => "lastchange",
        sortorder => "ASC",
        expandData => 1,
        active => 1,
        "filter" => {
          "value" => "1",
        },
      },
    };

    $rpc_error = 0;
    my $triggers_data = do_rpc_call($uri, $req, $conf->{"verify_ssl"});

    if ($rpc_error == 1) {
      if ($rpc_error_msg eq 'Not authorized') {
        # Not authorized. Try to re-auth.
        $authhash = rpc_auth($conf->{"api_uri"}, $conf->{'api_user'}, $conf->{'api_pass'}, $conf->{"verify_ssl"});
        $req->{'auth'} = $authhash;

        # And run RPC call once again.
        $rpc_error = 0;
        $triggers_data = do_rpc_call($uri, $req, $conf->{"verify_ssl"});

        if ($rpc_error == 1) {
          my $json = JSON->new();
          my $json_text = $json->encode({ "status" => "error", "errormsg" => "ERROR: $rpc_error_msg", "session" => "", "data" => "" });
          return $json_text;
        }
      } else {
        # Other error.
         my $json = JSON->new();
         my $json_text = $json->encode({ "status" => "error", "errormsg" => "ERROR: $rpc_error_msg", "session" => "", "data" => "" });
         return $json_text;
      }
    }

    my @data = ();
    my $c = 0;

    foreach my $trigger (@{$triggers_data}) {
      my $hostname = $trigger->{host};
      my $text_data = $trigger->{description};
  
      my $age_sec = (time - $trigger->{lastchange});
      if ($age_sec < 0) { $age_sec = 0 };

      my $tr_prio = $trigger->{priority}; # 5 - disaster, 4 - high, 3 - average, 2 - warning, 1 - info
      $text_data =~ s/\{HOSTNAME\}/$hostname/;

      my $prio = 'low';
      if ($tr_prio < 3) { $prio = "low"; }
      if ($tr_prio == 3) { $prio = "medium"; }
      if ($tr_prio > 3) { $prio = "high"; }

      # -- Push the parsed data into the array
      push (
        @data, 
        { 
          "hostname" => $hostname, 
          "data" => $text_data,
          "prio" => $prio,
          "age" => $age_sec
        }
      );

      $c++;
    }

    my $json = JSON->new();
    my $json_text = $json->encode({ "status" => "ok", "session" => $authhash, "data" => \@data });

    # -- Log out.
    $req = {
      jsonrpc => "2.0",
      method => 'user.logout',
      auth => $authhash,
      params => [],
      id => 8,
    };

    # Logging out doesn't work in Zabbix 1.8
    # see: https://support.zabbix.com/browse/ZBX-3907

    #my $logout_status = do_rpc_call($uri, $req, $conf->{"verify_ssl"});


    return $json_text;
  }

  # -- Register the plugin.
  # -- This is executed when module loads.
  $main::plugins_list{'zabbix'} = \&get_data;
}

1;
