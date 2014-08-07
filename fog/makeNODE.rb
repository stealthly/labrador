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
    opt :domain, "Subdomain to add dns to in Route53", :type => :string, :require => true
    opt :node_name, "Node Name", :type => :string, :required  => true
    opt :nat_node_name, "Nat Node Name", :type => :string, :required  => true
    opt :region, "Region", :type => :string, :default => 'us-east-1', :required  => true
    opt :key_name, "The ssh keypair name in AWS to use", :type => :string , :required  => true
    opt :key_file_pub, "The ssh public key file to use", :type => :string, :required  => true
    opt :key_file_private, "The ssh private keyfile to use", :type => :string, :required  => true
    opt :subnet, "DMZ or INTRANET", :type => :string, :default => 'intranet', :required => true
    opt :security_group, "public or private", :type => :string, :default => 'intranet', :required => true
    opt :centos, "5,6,6hvm,6haproxy", :type => :string, :default => '6', :required => true
    opt :flavor, "m1-medium r2-whatever", :type => :string , :required => true
    opt :chef_env, "chef environement", :type => :string, :required => true
    opt :knife_file, "knife config file", :type => :string, :required => true
    opt :dns_server, "dns server to register with", :type => :string, :required => true
    opt :run_list, "chef run list", :type => :string, :required => false
    opt :volume, "ebs volume type standard, io1 or gp2", :type => :string
    opt :volume_size, "volume size in GB", :type => :int 
    opt :volume_iops, "volume iops 1 to 4000", :type => :int
    opt :private_ip, "Ip Address to assign", :type => :string
end
#
# ENVIRONMENT Settings
#
ENV['FOG_RC'] =  $opts[:fogrc]
ENV['FOG_CREDENTIAL']= $opts[:fog_credential]

def make_a_server(compute, subnet_name, vpcID, security_group, node_name, ip)
    imageID=get_image(compute)
    unless ! imageID.nil?
        abort("Did not find image!")
    end
    subnet=get_subnet(compute, subnet_name)
    unless ! subnet.nil?
        abort("Did not find subnet!")
    end
    subnetID=subnet['subnetId']
    zone=subnet['availabilityZone']
    #https://github.com/fog/fog/blob/master/lib/fog/aws/requests/compute/run_instances.rb
    security_groupID=get_security_group(compute, vpcID, security_group)
    unless ! security_groupID.nil?
        abort("Did not get security group")
    end
    server_attributes=get_server_attr(vpcID, imageID, node_name, subnetID, security_groupID, security_group, ip, zone)
    puts server_attributes.to_yaml
    server = compute.servers.create(server_attributes)
    puts "Waiting for server ready..."
    server.wait_for { ready? }
    return server
end
#
# Setup some stuff first
#
# Assign a private static ip in VPC
private_ip_address=$opts[:private_ip] || nil
# Figure out the username for the endpoint
case $opts[:centos]
when '6haproxy'
        target_username='ec2-user'
when '6hvm'
    if $opts[:node_name] =~ /cass/ or $opts[:node_name] =~ /db/
        target_username='root'
    else
        #basho boxes use ec2-user and don't work on i2.xlarge instances
        target_username='ec2-user'
    end
else
    target_username='root'
end
#Use a gateway or not? ( we need the nat_node_name to set the dns name 
if $opts[:security_group] == 'private'
    gw=$opts[:nat_node_name] 
else
    gw=nil
end
#Add to default run_list?
if $opts[:run_list].nil?
    run_list='cb-base'
else
    run_list=['cb-base', $opts[:run_list]].join(',')
end
full_name=$opts[:node_name].split(".")
short_name=full_name.shift

########################################################################################
# MAIN
#####################################
compute=Fog::Compute.new(:provider => 'AWS', :region => $opts[:region])
dns=Fog::DNS.new(:provider => 'AWS')
# get vpcid
puts "Checking VPC...#{$opts[:name]}"
vpcID=get_vpc(compute, $opts[:name])
puts "\tfound #{vpcID}".bold.blue
if vpcID == nil
    abort("I can't find #{$opts[:name]}")
end

server=get_server(compute, vpcID, "#{$opts[:node_name]}::#{$opts[:name]}")
if server.nil?
    puts "\t...making server..."
    server=make_a_server(compute, "#{$opts[:subnet]}_Subnet", vpcID, $opts[:security_group], $opts[:node_name], private_ip_address)
end

if $opts[:security_group] == 'private'
    puts "\t...ssh to server..."
    loop do
        puts "\t\ttrying telnet to port 22.."
        command_output=ssh_command($opts[:nat_node_name], 'ec2-user', "nc -zw3 #{server.private_ip_address} 22 && echo 'open' || echo 'closed'")
        puts "\tPort 22 on #{server.private_ip_address} is #{command_output}"
        if command_output[0] =~ /open/
            puts "Breaking..."
            break
        end
        puts "\t\tsleeping..."
        sleep 5
    end
    jumpbox(target_username, 'hostname', server.private_ip_address)
    puts "\t...bootstrap server..."
    puts "\t...adding to dns..."
    jumpbox('ec2-user', "sudo /etc/pdns/makeRecord.rb --name #{$opts[:node_name]} --ip #{server.private_ip_address}", $opts[:dns_server])
    bootstrap(server, target_username, $opts[:node_name], run_list, gw)
else
    puts "\t\t...ssh to #{server.public_ip_address}..."
    server.username=target_username
    server.wait_for { sshable? }
    jumpbox('ec2-user', "sudo /etc/pdns/makeRecord.rb --name #{$opts[:node_name]} --ip #{server.private_ip_address}", $opts[:dns_server])
    create_internet_dns_record(dns, server.public_ip_address, "#{short_name}.#{$opts[:domain]}" , $opts[:domain], '300')
    bootstrap(server, target_username, $opts[:node_name], run_list, gw)
end
