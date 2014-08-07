#!/usr/bin/ruby
require 'fog'
require './foglibs'
require 'trollop'
opts = Trollop::options do
    opt :fogrc, "file of fogrc settings http://fog.io/about/getting_started.html", :type => :string, :required => true
    opt :fog_credential, "which credentials to use from fogrc file", :type => :string, :required  => true
    opt :node_name, "The chef node name", :type => :string, :required => true
    opt :ip, "The ip address", :type => :string, :required => true
end
ENV['FOG_RC'] =  opts[:fogrc]
ENV['DEBUG'] ='true'
ENV['FOG_CREDENTIAL']= opts[:fog_credential]
split_name=opts[:node_name].split(".")
short_name=split_name[0]
domain=split_name[1,3].join '.'
dns=Fog::DNS.new(:provider => 'AWS')
create_dns_record(dns, opts[:ip], opts[:node_name], 1800)

