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
    opt :name, "VPC Name", :type => :string, :required  => true
    opt :node_name, "Node Name", :type => :string, :required  => true
    opt :region, "Region", :type => :string, :default => 'us-east-1', :required  => true
    opt :key_name, "The ssh keypair name in AWS to use", :type => :string , :required  => true
    opt :key_file_pub, "The ssh public key file to use", :type => :string, :required  => true
    opt :key_file_private, "The ssh private keyfile to use", :type => :string, :required  => true
    opt :d_subnet, "dmz subnet 10.200.1.0/24 for example", :type => :bool, :default => false
    opt :i_subnet, "intranet subnet 10.200.200.0/24 for example", :type => :bool, :default => false
    opt :centos5, "centos 5.8", :type => :bool, :default => false
    opt :centos6, "centos 6.5", :type => :bool, :default => false
    opt :volume, "ebs volume type standard or io1", :type => :string
    opt :volume_size, "volume size in GB", :type => :int 
    opt :volume_iops, "volume iops 1 to 4000", :type => :int
    opt :zone, "Avail zone", :type => :string, :required => true
end
#pp opts

#
# ENVIRONMENT Settings
#
ENV['FOG_RC'] =  opts[:fogrc]
ENV['FOG_CREDENTIAL']= opts[:fog_credential]
compute=Fog::Compute.new(:provider => 'AWS', :region => opts[:region])
########################################################################################
# MAIN
#
#
# get vpcid
vpcID=get_vpc(compute, opts[:name], opts)
if vpcID == nil
    abort("I can't find #{opts[:name]}")
end
# find an image
offerings=nil
if opts[:centos5] == true
    offerings=compute.describe_images({ :'name' => 'RightImage_CentOS_5.8_x64_v5.8.8.3_EBS',  :'architecture' => 'x86_64'})
elsif opts[:centos6] == true
    offerings=compute.describe_images({ :'name' => 'CentOS-6.5-GA-03.3*',   :'owner-id' => '679593333241', :'architecture' => 'x86_64'})
else
    abort("Need to say centos5 or centos6")
end
imageID=offerings.body['imagesSet'].first['imageId']
if imageID !~ /ami/
    abort("Did not find an ami image")
end
# get subnet
subnets=compute.describe_subnets()
our_subnets={}
subnets.body['subnetSet'].each  do |subnet|
    name=subnet['tagSet']['Name']
    id=subnet['subnetId']
    our_subnets.merge!({name => id}) 
end
#get security group
sgroups=compute.describe_security_groups({:'vpc-id' => vpcID})
our_sgroups={}
pp sgroups
sgroups.body['securityGroupInfo'].each do |sg|
    name=sg['groupName']
    id=sg['groupId']
    our_sgroups.merge!({name => id}) 
end
# Setup requirements for server
groupID=nil
subnetID=nil
true_or_false=nil
if opts[:i_subnet] == true
    subnetID=our_subnets['INTRANET']  
    groupID=our_sgroups['private']
    true_or_false=false
elsif opts[:d_subnet] == true
    subnetID=our_subnets['DMZ']  
    groupID=our_sgroups['public']
    true_or_false=true
else
    abort("What subnet does this box goes in? ")
end
server_attributes = {
    :vpc_id => vpcID,
    :flavor_id => 'm1.medium',
    :key_name => opts[:key_name],
    :private_key_path => opts[:key_file_private],
    :public_key_path => opts[:key_file_pub],
    :image_id => imageID,
    :tags => {'Name' => "#{opts[:node_name]}::#{vpcID}::#{subnetID}"},
    :network_interfaces   => [{
        'DeviceIndex'               => '0',
        'SubnetId'                  => subnetID,
        'AssociatePublicIpAddress'  => true_or_false,
        'SecurityGroupId'           => [groupID]
                           }]
}
server = compute.servers.create(server_attributes)
puts "Waiting for server ready..."
server.wait_for { ready? }
puts "Private IP Address: #{server.private_ip_address}"
#
# Create a volume and attach it
#
if ! opts[:volume].to_s.empty? # false, it's not empty
    puts "Creating Volume..."
    if ! opts[:volume_size].to_s.empty? # false, it's not empty
        if opts[:volume] == 'io1'
            if opts[:volume_iops].to_s.empty? # true, it is empty
                abort("You need to define iops value --volume-iops")
            else 
                options={'VolumeType' => opts[:volume], 'Iops' => opts[:volume_iops]} 
                volume=compute.create_volume(opts[:zone], opts[:volume_size], options)
            end
        else
                volume=compute.create_volume(opts[:zone], opts[:volume_size])
        end
    else
        abort("You need to define a size --volume-size")
    end
    if ! volume.to_s.empty?
       loop do
            v=compute.describe_volumes(:'attachment.status' => 'detached')
            if volume.body.select {|id| id['volumeId']  == volume.body['volumeId'] }
                tag=compute.create_tags(volume.body['volumeId'], {"Name" => "#{opts[:node_name]}::#{opts[:name]}"})
                volume.attach(server.id,"vdc")
                break
            else
                volume.body.each do |volume|
                    p volume['volumeId']
                end
            end
            sleep 5 
        end
    else
        abort("Volume creation failed")
    end
end

#
# setup DNS
#
create_dns_record(dns, public_ip, opts[:node_name], 1800)

