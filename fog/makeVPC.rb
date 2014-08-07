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
#
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
    opt :block, "cidr block 10.200.0.0/16 for example" , :type => :string , :required  => true
    opt :d_subnet, "dmz subnet 10.200.1.0/24 for example"  , :type => :string, :required  => true
    opt :i_subnet, "intranet subnet 10.200.200.0/24 for example"  , :type => :string, :required  => true
    opt :name, "VPC Name", :type => :string, :required  => true
    opt :region, "Region", :type => :string, :default => 'us-east-1', :required  => true
    opt :vpcID, "vpcID", :type => :string
    opt :nat_node_name, "The nat chef node name", :type => :string, :required => true
    opt :domain, "Subdomain to add dns to in Route53", :type => :string, :require => true
    opt :dns_node_name, "The dns chef node name", :type => :string, :required => true
    opt :key_name, "The ssh keypair name in AWS to use", :type => :string , :required  => true
    opt :key_file_pub, "The ssh public key file to use", :type => :string, :required  => true
    opt :key_file_private, "The ssh private keyfile to use", :type => :string, :required  => true
    opt :centos, "Centos Image to use", :type => :string, :required => true
    opt :flavor, "r3.large t2.medium for example", :type => :string, :required => true
    opt :security_group, "public or private", :type => :string, :default => 'intranet', :required => true
    opt :private_ip_address, "Ip Address to assign", :type => :string
    opt :knife_file, "knife config file", :type => :string, :required => true
    opt :chef_env, "chef environement", :type => :string, :required => true
    opt :zone, "Avail zone", :type => :string, :required => false
end
#p opts

#
# ENVIRONMENT Settings
#
ENV['FOG_RC'] =  $opts[:fogrc]
ENV['DEBUG'] ='true'
ENV['FOG_CREDENTIAL']= $opts[:fog_credential]

compute=Fog::Compute.new(:provider => 'AWS', :region => $opts[:region])
dns=Fog::DNS.new(:provider => 'AWS')

########################################################################################
# MAIN
#
puts "Checking on VPC....\n"
if $opts[:vpcID] 
    vpcID=$opts[:vpcID]
    filters={:'tag-value' => $opts[:name] }
    vpcs=compute.describe_vpcs(filters)
    a=vpcs.body['vpcSet'].select { |vpc| vpc['vpcId'] == vpcID }
    if a.count > 0
        puts "\t exists..."
    else
        abort("Vpc does not exist")
    end
else
    # if not vpcID was specified check if one with provided name exists
    filters={:'tag-value' => $opts[:name] }
    vpcs=compute.describe_vpcs(filters)
    vpcs.body['vpcSet'].each do |vpc|
        puts "\tVPC with the name of "  +vpc['tagSet']['Name']+ " exists:"
        abort("\tAdd --vpcID #{vpc['vpcId']}")
    end
    # else create it and return vpcID
    vpc=compute.vpcs.create({"cidr_block" => $opts[:block] })
    tag=compute.create_tags(vpc.id, {"Name" => $opts[:name]})
    vpcID=vpc.id
    puts "\tVPC created " <<  vpcID
end

gwayID=make_or_get_igw(compute, vpcID)
# Make a route and give route table id to subnet
dmz_route_table_id=make_or_get_routes(compute, vpcID, gwayID, "DMZ_2_INET::#{$opts[:name]}")
# Make a subnet and associate a route
make_or_get_subnets(compute, vpcID, dmz_route_table_id, "DMZ_Subnet::#{$opts[:name]}", 0)
# Make Security groups
make_or_get_security_grps(compute, vpcID, 0)
# Make Nat box
server=make_or_get_nat_node(compute,vpcID)
#bootstrap(server, 'ec2-user', $opts[:nat_node_name], "cb-base,cb-dataCenter::vpnServer", nil)
# Get route table and make subnets, associate subnets with route tables
inet_route_table_id=make_or_get_routes(compute, vpcID, server.id, "INTRA_2_NAT::#{$opts[:name]}")
make_or_get_subnets(compute, vpcID, inet_route_table_id, "INTRANET_Subnet::#{$opts[:name]}", 0)
# Make or fix DNS entry for nat box
create_internet_dns_record(dns, server.public_ip_address, $opts[:nat_node_name], $opts[:domain], 1800)
# Check for dns server, exists?, bootstrapped?, working?
server=get_server(compute, vpcID, "#{$opts[:dns_node_name]}::#{$opts[:name]}")
if server.nil?
    server=make_dns_server(compute, vpcID)
    bootstrap(server, 'ec2-user', $opts[:dns_node_name], "cb-base,cb-base::dnsServer", 'gw')
end
ret=is_dns_setup()
if ret[2] == 0
    puts "\tDNS is working \n#{ret[0]}".bold.blue
else
    puts "\tDNS is NOT working #{ret[0]}".bold.red
    #-c ./conf/knife-prod.rb  -E DEV -x ec2-user --sudo -A --secret-file ./keys/chef_secret --hint=ec2  -N dns01.intra2.dev.medialets.com  -r cb-base,cb-base::dnsServer
    bootstrap(server, 'ec2-user', $opts[:dns_node_name], "cb-base,cb-dataCenter::dnsServer", nil)
end
full_name=$opts[:dns_node_name].split(".")
short_name=full_name.shift
domain=full_name.join(".")
dhcpID=make_dhcp_options(compute, domain, server.private_ip_address)
associate_dhcp_2_vpc(compute, dhcpID, vpcID)
# make a dns02 box
# add it to options set
# make other boxes
#
