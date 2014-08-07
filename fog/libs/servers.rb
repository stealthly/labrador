#!/usr/bin/ruby
require 'fog'
require 'pp'
require 'colored'
#
def get_image(compute)
    offerings=nil
    case $opts[:centos]
    when '6haproxy'
        offerings=compute.describe_images({ :'name' => 'CentOS 6.5 bashton1', :'architecture' => 'x86_64'})
    when '5'
        offerings=compute.describe_images({ :'name' => 'RightImage_CentOS_5.8_x64_v5.8.8.3_EBS',  :'architecture' => 'x86_64'})
    when '6'
        offerings=compute.describe_images({ :'name' => 'CentOS-6.5-GA-03.3*',   :'owner-id' => '679593333241', :'architecture' => 'x86_64'})
    when '6hvm'
        if $opts[:node_name] =~ /cass/ or $opts[:node_name] =~ /db/
            offerings=compute.describe_images({ :'name' => 'RightImage_CentOS_6.5_x64_v14.0_HVM_EBS',   :'architecture' => 'x86_64'})
        else 
            offerings=compute.describe_images({ :'name' => 'CentOS 6.5 HVM bashton1',   :'architecture' => 'x86_64'})
        end
    else
        return nil
    end
    imageID=offerings.body['imagesSet'].first['imageId']
    if imageID !~ /ami/
        imageID=nil
        return imageID
        return 
        abort("Did not find an ami image")
    end
    return imageID
end
def get_server(compute, vpcID, server_name)
    puts "Checking for #{server_name}..."
    # return server if running
    found=0
    servers=compute.servers
    servers.each do |server|
        #puts  "#{server_name} -- #{server.tags['Name']}"
        if server.tags['Name'] == server_name and server.state == 'running'
            puts "\tFound #{server_name} in running state".bold.blue
            return server
        end
    end
    return nil
end
def get_all_servers(compute, vpcID)
    servers=compute.servers
    servers.each do |server|
        if server.vpc_id == vpcID and server.state == 'running'
            puts  "#{server.id} -- #{server.private_ip_address} -- #{server.tags['Name']}".bold.blue
        end
    end
end
def get_server_attr(vpcID, imageID, node_name, subnetID, security_groupID, security_group, private_ip_address, zone)
    server_attributes = {
        :vpc_id => vpcID,
        :availability_zone => zone,
        :tags => {'Name' => "#{node_name}::#{$opts[:name]}"},
        :flavor_id => $opts[:flavor],
        :image_id => imageID,
        :private_key_path => $opts[:key_file_private],
        :public_key_path => $opts[:key_file_pub],
        :key_name => $opts[:key_name]
    }
    case security_group
    when 'public'
        server_attributes.merge!(:network_interfaces =>
                [{ 
                    'DeviceIndex'               => '0',
                    'SubnetId'                  => subnetID,
                    'AssociatePublicIpAddress'  => true,
                    'SecurityGroupId'           => [security_groupID]
                 }])
    when 'private'
        server_attributes.merge!(:subnet_id => subnetID, :security_group_ids => [security_groupID])
        if ! $opts[:private_ip_address].nil?
            server_attributes.merge!(:private_ip_address => $opts[:private_ip_address])
        end
    else
        abort("Security group not defined")
    end
    return server_attributes
end
def bootstrap(server, username, node_name, run_list, gw)
    STDOUT.sync = true
    puts "Bootstrapping box...."
    cmd=nil
    if gw.nil?
        puts "\t without gw"
        kvars=" -c #{$opts[:knife_file]}  -E #{$opts[:chef_env]} -x #{username} --sudo -A --secret-file ./keys/chef_secret --hint=ec2"
        cmd="knife bootstrap #{kvars}  -N #{node_name} #{server.public_ip_address} -r #{run_list}"
    else
        puts "\t with gw #{gw}"
        kvars=" -c #{$opts[:knife_file]}  -G ec2-user@#{gw} -E #{$opts[:chef_env]} -x #{username} --sudo -A --secret-file ./keys/chef_secret --hint=ec2"
        cmd="knife bootstrap #{kvars}  -N #{node_name} #{server.private_ip_address} -r #{run_list}"
    end
    puts "\t running #{cmd}"
    IO.popen(cmd) do |output|
        while (line = output.gets) do
            puts "\t#{line}"
        end
    end
    code=$?
    puts "Return code #{code}"
end




### Just makeVPC stuff ######
# DNS BOX
def make_or_get_dns_node(vpcID, dns_server)
    servers=get_server(compute, vpcID, "#{$opts[:node_name]}::#{$opts[:name]}")
    unless servers.is_nill? 
        print "Wat?!"
    end
end
def make_dns_server(compute, vpcID)
    imageID=get_image(compute)
    unless ! imageID.nil?
        abort("Did not find image!")
    end
    subnet=get_subnet(compute, 'INTRANET_Subnet')
    unless ! subnet.nil?
        abort("Did not find subnet!")
    end
    subnetID=subnet['subnetId']
    zone=subnet['availabilityZone']
    #https://github.com/fog/fog/blob/master/lib/fog/aws/requests/compute/run_instances.rb
    security_groupID=get_security_group(compute, vpcID, 'private')
    unless ! security_groupID.nil?
        abort("Did not get security group")
    end
    server_attributes=get_server_attr(vpcID, imageID, $opts[:dns_node_name], subnetID, security_groupID, 'private', $opts[:private_ip_address], zone)
    puts server_attributes.to_yaml
    server = compute.servers.create(server_attributes)
    puts "Waiting for server sshable..."
    server.wait_for { ready? }
    return server
end


