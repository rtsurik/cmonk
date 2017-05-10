# -- Nagios cMonk plugin
# -- Copyright (C) 2013 Rustam Tsurik

{
  package NagiosParse;
  use base "HTML::Parser";
  use URI::Escape;

  # -- Init vars.
  my $capture = 0;
  my $table_lock = 0;
  my $td_counter = 0;

  my $wrk_host = "na";
  my $wrk_serv = "na";
  my $wrk_age = 0;
  my $wrk_prio = "low";
  my $wrk_text = "No data";


  # -- NagiosParse::end()
  # -- This is not called directly, matches tags end
  sub end {
    my ($self, $tag, $origtext) = @_;

    if ($tag =~ 'table'){
      if ($table_lock > 0){ $table_lock-- }
    }
  }

  # -- NagiosParse::start()
  # -- This is not called directly, matches tags start
  sub start {
    my ($self, $tag, $attr, $attrseq, $origtext) = @_;

    if ($tag =~ 'table'){
        if (($origtext =~ "CLASS=\'status\'")|($origtext =~ "class=\'status\'")){
            $table_lock = 0;
        } else { $table_lock++ }
    }
    # ------ process TR tag
    if (($tag eq 'tr')&(!$table_lock)){
        $td_counter = 0;    # <td> counter = 0
    }
    if (($tag eq 'td')&(!$table_lock)){
        $td_counter++;
        $capture = 1;
    }
    if ($tag eq 'a'){
        if ($origtext =~ "extinfo\.cgi(.*)&host=(.*)&service=(.*)\'>"){
            $wrk_host = $2;
            $wrk_serv = uri_unescape($3);
            $wrk_serv =~ tr{\+}{\ }d;
            $wrk_prio = 'low';
        }
    }
  }

  # -- NagiosParse::text()
  # -- This is not called directly, matches tags contents
  sub text {
    my ($self, $text) = @_;

    if (($capture == 1)&($td_counter>0)&($td_counter<8)){
        $text =~ tr{\n\r}{}d;

        my %table_columns = (
        1 => sub {},
        2 => sub {},
        3 => sub { 
               if ($text =~ m/WARN/) { $wrk_prio = 'medium'};
               if ($text =~ m/CRITICAL/) { $wrk_prio = 'high'};
             },
        4 => sub {}, # here $text == last check, don't need this.
        5 => sub { 
               $text=~ s/^\s//; # <-- age, convert to seconds + adjust according to current time.
             },
        6 => sub {}, # here $text == attempt, don't need this.
        7 => sub { 
               $text =~ s/\&.([0-9]+)\;/pack('C',$1)/ge; 
               $text =~ s/&nbsp;/ /g;

               # push host data into array here
               # ...
               if (($wrk_prio eq 'high') | ($wrk_prio eq 'medium')) {
                 my $c = $self->{cnt};
                 push (
                   @{$self->{data}}, 
                   { 
                     "hostname" => $wrk_host, 
                     "data" => $wrk_serv . ' - ' . $text,
                     "prio" => $wrk_prio,
                     "age" => 0
                   }
                 );
                 $self->{cnt} = ($c + 1);
               }
             }
        );

        $table_columns{$td_counter}->();
        $capture = 0;
    }
  }

  # -- NagiosParse::reset_counter()
  # -- Init the class variables before use
  sub reset_counter {
    my ($self, $value) = @_;

    $self->{cnt} = 0;
    $self->{data} = ();
  }

  # -- NagiosParse::get_hosts()
  # -- Returns the collected data
  sub get_hosts {
    my ($self, %value) = @_;

    # -- return a reference to the data array
    my @ret_hosts = $self->{data};
    return \@ret_hosts; 
  } 
} 
# -- package NagiosParse ends here

{
  package nagios;
  use LWP::UserAgent;
  use JSON;
  use Encode;
  use Data::Dumper;

  # -- nagios::get_data()
  # -- Retrieve the web page, parse it and return json code. 
  sub get_data {
    my ($conf, $session) = @_;

    $nag_usr = $conf->{'api_user'};
    $nag_pwd = $conf->{'api_pass'};

    my $myuseragent = new LWP::UserAgent;
    $myuseragent->timeout(120);

    # -- Disable SSL verification.

    my $sslver = "on";
    if (defined $conf->{"verify_ssl"}) {
      $sslver = $conf->{"verify_ssl"};
    }

    if ($sslver eq "off") {
      $myuseragent->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0x00
      );
    }


    my($uri_scheme, $hostname, $uri_path) =
    $conf->{'api_uri'} =~ m|(https?://)([^/]*)(.*)|;

    my $url = $conf->{'api_uri'} . "/cgi-bin/status.cgi?host=all&limit=0";

    my $auth_realm = 'Nagios Access';
    if (defined $conf->{'api_realm'}){
      $auth_realm = $conf->{'api_realm'};
    }

    $myuseragent->credentials($hostname . ":80", 
      $auth_realm , $nag_usr => $nag_pwd);

    $myuseragent->credentials($hostname . ":443",
      $auth_realm , $nag_usr => $nag_pwd);


    my $request = new HTTP::Request('GET', $url);
    my $response = $myuseragent->request($request);
    
    my $json = new JSON; $json->allow_nonref(1);
    my $json_text; 

    if (!$response->is_success) {
      # -- Couldn't retrieve the web page.
      $json_text = $json->encode({ "status" => "error", "errormsg" => "Couldn't retrieve data." });

    } else {
      # -- Web page retrieved, parse it.
      my $content = decode_utf8 $response->content();

      my $dash_parser = NagiosParse->new();
      $dash_parser->reset_counter();
      $dash_parser->parse($content);
      my @ext_parsed = @{$dash_parser->get_hosts()};

      $json_text = $json->encode({ "status" => "ok", "session" => "", "data" => @ext_parsed });

      # -- clean up
      $dash_parser->reset_counter();
      @ext_parsed = ();
    }

    # -- return JSON code
    return $json_text;
  }

  # -- Register the plugin.
  # -- This is executed when module loads.
  $main::modules_callbacks{'nagios'} = \&get_data;
}

1;
