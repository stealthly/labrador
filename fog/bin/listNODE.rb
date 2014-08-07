#!/usr/bin/ruby
require 'rubygems'
require 'fog'
require 'trollop'
require './libs/foglibs'
require './libs/servers'
require './libs/security'
require './libs/subnets'
require './libs/ssh_cmd'
require './libs/dhcp'
require 'net/ssh'
require 'colored'

# REGIONS
# 
#ap-northeast-1 Asia Pacific (Tokyo) Region
##ap-southeast-1 Asia Pacific (Singapore) Region
##ap-southeast-2 Asia Pacific (Sydney) Region
##eu-west-1 EU (Ireland) Region
##sa-east-1 South America (Sao Paulo) Region
##us-east-1 US East (Northern Virginia) Region
##us-west-1 US West (Northern California) Region
##us-west-2 US West (Oregon) Region
#
# Options
#
$opts = Trollop::options do
    opt :fogrc, "file of fogrc settings http://fog.io/about/getting_started.html", :type => :string, :required => true
    opt :fog_credential, "which credentials to use from fogrc file", :type => :string, :required  => true
    opt :name, "VPC Name", :type => :string, :required  => true
    opt :region, "Region", :type => :string, :default => 'us-east-1', :required  => true
end
#
# ENVIRONMENT Settings
#
ENV['FOG_RC'] =  $opts[:fogrc]
ENV['FOG_CREDENTIAL']= $opts[:fog_credential]
########################################################################################
# MAIN
compute=Fog::Compute.new(:provider => 'AWS', :region => $opts[:region])
puts "Checking VPC...#{$opts[:name]}"
vpcID=get_vpc(compute, $opts[:name])
if vpcID == nil
    abort("I can't find #{$opts[:name]}")
end
puts "\tfound #{vpcID}".bold.blue
server=get_all_servers(compute, vpcID)
