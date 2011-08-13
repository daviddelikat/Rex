#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=3 sw=3 tw=0:
# vim: set expandtab:
   
package Rex::Cloud::Jiffybox;
   
use strict;
use warnings;

use Rex::Logger;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON::XS;
use Data::Dumper;

use Rex::Cloud::Base;

use base qw(Rex::Cloud::Base);
   
sub new {
   my $that = shift;
   my $proto = ref($that) || $that;
   my $self = { @_ };

   bless($self, $proto);

   $self->{"__endpoint"} = "https://api.jiffybox.de/%s/v1.0/%s";

   return $self;
}

sub _auth_key {
   my ($self) = @_;
   return $self->{"__auth_key"};
}

sub _do_request {
   my ($self, $type, $action, @params) = @_;

   my $url = sprintf($self->{"__endpoint"}, $self->_auth_key, $action);
   my $ua  = LWP::UserAgent->new;
   my ($res);

   if($type eq "GET") {
      $res = $ua->request(GET $url);
   }
   elsif($type eq "POST") {
      $res = $ua->request(POST $url, \@params);
   }
   elsif($type eq "PUT") {
      my $req = POST $url, \@params;
      $req->method("PUT");
      $res = $ua->request($req);
   }
   elsif($type eq "DELETE") {
      my $req = GET $url;
      $req->method("DELETE");
      $res = $ua->request($req);
   }

   if($res->code >= 500) {
      print $res->content;
      die("Error on request.");
   }

   my $json = JSON::XS->new;
   my $data = $json->decode($res->decoded_content);
   
   return $data;
}

sub _result_to_array {
   my ($self, $data, $with_key) = @_;

   my @ret = ();

   for my $key (keys %{$data->{"result"}}) {
      if($with_key) {
         $data->{"result"}->{$key}->{$with_key} = $key;
      }
      push(@ret, $data->{"result"}->{$key});
   }

   return @ret;
}

sub set_auth {
   my ($self, $key) = @_;
   $self->{"__auth_key"} = $key;
}

sub list_plans {
   my ($self) = @_;
   my $data = $self->_do_request("GET", "plans");

   return $self->_result_to_array($data);
}

sub list_operating_systems {
   my ($self) = @_;
   my $data = $self->_do_request("GET", "distributions");

   return $self->_result_to_array($data, "os_id");
}

=item run_instance(%data)

 $o->run_instance(
   name         => "Name01",
   plan_id      => 10,
   image_id     => "ubuntu_8_4_lts_64bit",
   password     => "...", # optional
   key          => 1, # optional
   metadata     => "{json...}" # optional
 );

=cut
sub run_instance {
   my ($self, %data) = @_;

   my @jiffy_data;

   push(@jiffy_data, "name" => $data{"name"}, "planid" => $data{"plan_id"}, "distribution" => $data{"image_id"});

   if(exists $data{"password"}) {
      push(@jiffy_data, "password" => $data{"password"});
   }

   if(exists $data{"key"}) {
      push(@jiffy_data, "use_sshkey" => $data{"key"});
   }

   if(exists $data{"metadata"}) {
      push(@jiffy_data, "metadata" => $data{"metadata"});
   }

   my $data = $self->_do_request("POST", "jiffyBoxes", @jiffy_data);
   my $instance_id = $data->{"result"}->{"id"};

   my $sleep_countdown = 5;
   sleep $sleep_countdown; # wait 5 seconds

   ($data) = grep { $_->{"id"} eq $instance_id } $self->list_instances();

   while($data->{"state"} ne "READY") {
      ($data) = grep { $_->{"id"} eq $instance_id } $self->list_instances();

      sleep $sleep_countdown;

      --$sleep_countdown;

      if($sleep_countdown <= 0) {
         $sleep_countdown = 3;
      }
   }

   $self->start_instance(instance_id => $instance_id);

}

sub start_instance {
   my ($self, %data) = @_;

   my $instance_id = $data{"instance_id"};
   Rex::Logger::debug("Starting instance $instance_id");
   $self->_do_request("PUT", "jiffyBoxes/$instance_id", status => "START");

}


sub terminate_instance {
   my ($self, %data) = @_;

   my $instance_id = $data{"instance_id"};
   Rex::Logger::debug("Terminating instance $instance_id");
   $self->_do_request("DELETE", "jiffyBoxes/$instance_id");

}

sub stop_instance {
   my ($self, %data) = @_;

   my $instance_id = $data{"instance_id"};
   Rex::Logger::debug("Stopping instance $instance_id");
   $self->_do_request("PUT", "jiffyBoxes/$instance_id", status => "SHUTDOWN");

}


sub list_instances {
   my ($self) = @_;

   my @ret;
   my $data = $self->_do_request("GET", "jiffyBoxes");

   for my $instance_id (keys %{$data->{"result"}}) {
      push(@ret, {
         ip => $data->{"result"}->{$instance_id}->{"ips"}->{"public"}->[0],
         id => $instance_id,
         architecture => undef,
         type => $data->{"result"}->{$instance_id}->{"plan"}->{"name"},
         dns_name => "j$instance_id.servers.jiffybox.net",
         state => $data->{"result"}->{$instance_id}->{"status"},
         launch_time => undef,
         name => $data->{"result"}->{$instance_id}->{"name"},
      });
   }

   return @ret;
}

sub list_running_instances { Rex::Logger::debug("Not implemented"); }


1;