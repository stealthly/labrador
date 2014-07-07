#!/usr/bin/ruby
require 'rubygems'
require 'fog'
require 'trollop'
require './foglibs'
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
opts = Trollop::options do
    opt :fogrc, "file of fogrc settings http://fog.io/about/getting_started.html", :type => :string, :required => true
    opt :fog_credential, "which credentials to use from fogrc file", :type => :string, :required  => true
    opt :block, "cidr block 10.200.0.0/16 for example" , :type => :string , :required  => true
    opt :d_subnet, "dmz subnet 10.200.1.0/24 for example"  , :type => :string, :required  => true
    opt :i_subnet, "intranet subnet 10.200.200.0/24 for example"  , :type => :string, :required  => true
    opt :name, "VPC Name", :type => :string, :required  => true
    opt :region, "Region", :type => :string, :default => 'us-east-1', :required  => true
    opt :vpcID, "vpcID", :type => :string
    opt :node_name, "The chef node name", :type => :string, :required => true
    opt :key_name, "The ssh keypair name in AWS to use", :type => :string , :required  => true
    opt :key_file_pub, "The ssh public key file to use", :type => :string, :required  => true
    opt :key_file_private, "The ssh private keyfile to use", :type => :string, :required  => true
end
#p opts

#
# ENVIRONMENT Settings
#
ENV['FOG_RC'] =  opts[:fogrc]
ENV['DEBUG'] ='true'
ENV['FOG_CREDENTIAL']= opts[:fog_credential]

compute=Fog::Compute.new(:provider => 'AWS', :region => opts[:region])
dns=Fog::DNS.new(:provider => 'AWS')

########################################################################################
# MAIN
#
puts "Checking on and Making....\n"
puts "VPC....\n"
if opts[:vpcID] 
    vpcID=opts[:vpcID]
    filters={:'tag-value' => opts[:name] }
    vpcs=compute.describe_vpcs(filters)
    a=vpcs.body['vpcSet'].select { |vpc| vpc['vpcId'] == vpcID }
    if a.count > 0
        puts "\tVPC exists..."
    else
        abort("Vpc does exist")
    end
else
    # if not vpcID was specified check if one with provided name exists
    filters={:'tag-value' => opts[:name] }
    vpcs=compute.describe_vpcs(filters)
    vpcs.body['vpcSet'].each do |vpc|
        puts "\nAdd --vpcID to continue."
        puts "VPC with the name of "  +vpc['tagSet']['Name']+ " exists:"
        abort("VPC ID: #{vpc['vpcId']}")
    end
    # else create it and return vpcID
    vpc=compute.vpcs.create({"cidr_block" => opts[:block] })
    tag=compute.create_tags(vpc.id, {"Name" => opts[:name]})
    vpcID=vpc.id
    puts "\tVPC created " <<  vpcID
end

gwayID=make_or_get_igw(compute, vpcID, opts)
# Make a route and give route table id to subnet
dmz_route_table_id=make_or_get_routes(compute, vpcID, gwayID, "DMZ_2_INET::#{opts[:name]}", opts)
# Make a subnet and associate a route
make_or_get_subnets(compute, vpcID, dmz_route_table_id, "DMZ_Subnet::#{opts[:name]}", 0, opts)
# Make Security groups
make_or_get_security_grps(compute, vpcID, 0, opts)
# Make Nat box
server=make_or_get_nat_node(compute,vpcID, opts)
pp server
inet_route_table_id=make_or_get_routes(compute, vpcID, server.id, "INTRA_2_NAT::#{opts[:name]}", opts)
make_or_get_subnets(compute, vpcID, inet_route_table_id, "INTRANET_Subnet::#{opts[:name]}", 0, opts)
create_dns_record(dns, server.public_ip_address, opts[:node_name], 1800)
#make_or_get_eip(compute,vpcID)
