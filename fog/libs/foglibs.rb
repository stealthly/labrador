#!/usr/bin/ruby
require 'fog'
require 'pp'
require 'colored'
# VPC
def get_vpc(compute, vpcName)
    # returns vpcID or nil
    puts "Checking for vpc with name #{$opts[:name]}".bold.yellow
    filters={:'tag-value' => $opts[:name] }
    vpcs=compute.describe_vpcs(filters)
    ts=vpcs.body['vpcSet'].select {|ig| ig['tagSet']['Name'] == $opts[:name] }
    if ts.count > 0 and ts.count < 2
        return ts.first['vpcId']
    else
        return nil
    end
end
# INTERNET GATEWAY
def make_or_get_igw(compute, vpcID)
    puts "Internet gway... #{vpcID}\n"
    if vpcID == nil
        abort("No VPC ID!")
    end
    created=0
    igw=compute.internet_gateways
    gatewayID=nil
    igw.each do |gway|
        #puts "\tGatewayID #{gway.id}"
        if vpcID == gway.attachment_set['vpcId']
            gatewayID=gway.id
            created=1
            puts "\tInternet gway id #{gatewayID} for vpc exists and is attached #{vpcID}".bold.blue
        end
    end
    #
    if created == 0
        gway=compute.create_internet_gateway()
        gatewayID=gway.body['internetGatewaySet'][0]['internetGatewayId']
        puts "\tInternet gway #{gatewayID} created for vpc #{vpcID}"
        #
        loop do
            #igws=compute.internet_gateway({:'internet-gateway-id' => gatewayID})
            igws=compute.internet_gateways.all('internet-gateway-id' => [gatewayID])
            puts igws
            sleep 5
            break if igws.select {|ig| ig.id == gatewayID }
        end

        compute.attach_internet_gateway(gatewayID, vpcID)
        puts "\tInternet gway #{gatewayID} attached for vpc #{vpcID}"
        compute.create_tags(gatewayID, {"Name" => "#{$opts[:name]}::InetGway"})
    end
    return gatewayID
end

#  ROUTES
def make_or_get_routes(compute, vpcID, target, name)
    puts "Routes....\n"
    created=0
    routes=compute.describe_route_tables()
    rti=nil
    routes.body['routeTableSet'].each do |route|
        #each one of these is a route
        if route['tagSet']['Name']== name
            #TODO:  check if routeTable has correct info for pub and private
            created=1
            rti=route['routeTableId']
            puts "\tFound route #{rti} for: #{$opts[:name]}".bold.blue
            puts "\tNeed to add check for valid route table entries".bold.red
        end
    end
    #
    if created == 0
        new_route=compute.create_route_table(vpcID)
        rti=new_route.body['routeTable'][0]['routeTableId']
        # LOOP until shitty AWS is ready with our stuff
        loop do
            routes=compute.describe_route_tables()
            sleep 5
            break if routes.body['routeTableSet'].select {|associationSet|  associationSet['routeTableId'] == rti }
        end
        tag=compute.create_tags(new_route.body['routeTable'][0]['routeTableId'], {"Name" => name})
        rti=new_route.body['routeTable'][0]['routeTableId']
        if target =~ /igw/
            compute.create_route(rti, '0.0.0.0/0', internet_gateway_id = target, instance_id = nil, network_interface_id = nil)
            # The DMZ needs a route back to logicworks or the correct place out the nat/vpn device
            #compute.create_route(rti, '10.10.0.0/16', internet_gateway_id = nil, instance_id = target, network_interface_id = nil)
        end
        if target =~ /i-/
            compute.create_route(rti, '0.0.0.0/0', internet_gateway_id = nil, instance_id = target, network_interface_id = nil)
        end
        puts "\tRoutes created #{rti}"
    end
    return rti
end
def make_or_get_subnets(compute, vpcID, route_table_id, subnetName, get)
    puts "Subnets...\n"
    created=0
    subnets=compute.describe_subnets()
    return subnets if get == 1
    subnets.body['subnetSet'].each do |subnet|
        #puts "\tchecking for #{subnetName} against #{subnet['tagSet']['Name']}"
        if subnetName == subnet['tagSet']['Name'].to_s
            created=created+1
            #TODO
            #check associations!
            #pp subnet
            puts "\tSubnet #{subnet['tagSet']['Name']} exist for VPC #{vpcID}".bold.blue
            puts "\tNeed to check for valid associations".bold.red
        end
    end
    if created < 1
        if subnetName == "INTRANET_Subnet::#{$opts[:name]}"
            puts "\tcreating INTRANET_Subnet::#{$opts[:name]}"
            si=compute.create_subnet(vpcID, $opts[:i_subnet])
            loop do
                subnets=compute.describe_subnets()
                sleep 5
                break if subnets.body['subnetSet'].select {|subnetSet| subnetSet['subnetId'] == si.body['subnet']['subnetId']}
            end
            compute.create_tags(si.body['subnet']['subnetId'], {"Name" => "INTRANET_Subnet::#{$opts[:name]}"})
            compute.associate_route_table(route_table_id, si.body['subnet']['subnetId'])
            puts "\tSubnet #{si.body['subnet']['subnetId']} created but not associated for VPC #{vpcID}"
        end
        if subnetName == "DMZ_Subnet::#{$opts[:name]}"
            puts "\tcreating DMZ_Subnet::#{$opts[:name]}"
            sd=compute.create_subnet( vpcID, $opts[:d_subnet])
            loop do
                subnets=compute.describe_subnets()
                sleep 5
                break if subnets.body['subnetSet'].select {|subnetSet| subnetSet['subnetId'] == sd.body['subnet']['subnetId']}
            end
            compute.create_tags(sd.body['subnet']['subnetId'], {"Name" => "DMZ_Subnet::#{$opts[:name]}"})
            compute.associate_route_table(route_table_id, sd.body['subnet']['subnetId'])
            puts "\tSubnet #{sd.body['subnet']['subnetId']} created for VPC #{vpcID}"
        end
    end

    #return hash of subnets Name and Id
end

# SECURITY GROUPS
def make_or_get_security_grps(compute, vpcID, get)
    security_groups=compute.describe_security_groups()
    return security_groups if get == 1
    puts "Security Groups...\n"
    # get sg
    created=0
    group_to_check=['public', 'private']
    security_groups.body['securityGroupInfo'].each do |info|
        if info['vpcId'] == vpcID
            if group_to_check.include?(info['groupName'])
                # are the ports correct????
                group_to_check.delete(info['groupName'])
                created=created+1
                puts "\tSecurity group exists #{info['groupName']}".bold.blue
            end
        end
    end

    if created < 2 
        group_to_check.each do |group|
         #CREATE PRIVATE all access group
         if group == 'private'
            sg_private=compute.create_security_group('private', 'closed to inet' , vpc_id = vpcID)
            brk=false
            loop do
                break if brk == true
                sleep 2
                security_groups=compute.describe_security_groups()
                security_groups.body['securityGroupInfo'].each do |gi| 
                    if gi['groupId'] == sg_private.body['groupId']
                        puts "\tTagging  security group...."
                        compute.create_tags(gi['groupId'], {"Name" => "Private_SG::#{$opts[:name]}"})
                        brk=true
                    end
                end
            end
            # need to make the iprange encompass the other end of the vpn too and not 0.0.0.0
            private_permission = {
                    'IpPermissions' => [
                    {
                        'IpProtocol' => -1,
                        'IpRanges' => [{ 'CidrIp' => '0.0.0.0/0' }]
                    }
                    ]}
            options = private_permission.clone
            options['GroupId'] = sg_private.body['groupId']
            asg_private=compute.authorize_security_group_ingress(options)
            puts "\tSecurity group #{sg_private.body['groupId']} created for vpc: #{vpcID}"
         end
         # CREATE PUBLIC port 22 and 33333
         if group == 'public'
            sg_public=compute.create_security_group('public', 'open to inet' , vpc_id = vpcID)
            brk=false
            loop do
                break if brk == true
                sleep 2
                security_groups=compute.describe_security_groups()
                puts "\tWaiting for security group...."
                security_groups.body['securityGroupInfo'].each do |gi|
                     if gi['groupId'] == sg_public.body['groupId']
                        puts "\tTagging  security group...."
                        compute.create_tags(gi['groupId'], {"Name" => "Public_SG::#{$opts[:name]}"})
                        brk=true
                     end
                end
                #break if security_groups.body['securityGroupInfo'].select {|groupID| groupID['groupID'] == sg_public.body['groupId']}
            end
            puts "\tSecurity group #{sg_public.body['groupId']} created and tagged for vpc: #{vpcID}"
            # Any SSH
            public_permission = {
                    'IpPermissions' => [
                    {
                        'IpProtocol' => 6,
                        'FromPort' => 22,
                        'ToPort' => 22,
                        'IpRanges' => [{ 'CidrIp' => '0.0.0.0/0' }]
                    },
                    {
                        'IpProtocol' => 6,
                        'FromPort' => 80,
                        'ToPort' => 80,
                        'IpRanges' => [{ 'CidrIp' => '0.0.0.0/0' }]
                    },
                    {
                        'IpProtocol' => 6,
                        'FromPort' => 443,
                        'ToPort' => 443,
                        'IpRanges' => [{ 'CidrIp' => '0.0.0.0/0' }]
                    },
                    {
                        'IpProtocol' => 6,
                        'FromPort' => 33333,
                        'ToPort' => 33333,
                        'IpRanges' => [{ 'CidrIp' => '0.0.0.0/0' }]
                    },
                    {
                        'IpProtocol' => 17,
                        'FromPort' => 1195,
                        'ToPort' => 1195,
                        'IpRanges' => [{ 'CidrIp' => '209.81.83.0/24'}]
                    },
                    {
                        'IpProtocol' => -1,
                        'IpRanges' => [{ 'CidrIp' => $opts[:block] }]
                    },
                    {
                        'IpProtocol' => 1,
                        'FromPort' =>  -1,
                        'ToPort' => -1,
                        'IpRanges' => [{ 'CidrIp' => '0.0.0.0/0' }]
                    }]
                }
            options = public_permission.clone
            options['GroupId'] = sg_public.body['groupId']
            asg_public=compute.authorize_security_group_ingress(options)
       end
      end
    end
end

# ELASTIC IPS
def make_or_get_eip(compute, vpcID)
    #puts "Not creating eip until you tell me who to associate it to.. not implimented"
    eips=compute.describe_addresses()
    eips.body['addressesSet'].each do |address|
        if address['domain'] == 'vpc'
            if address['instanceId'].nil?
                p "This is available " << address.to_s
                return address['allocationId']
            end
        end
    end
    #eip=compute.allocate_address(domain = 'vpc')
end

# NAT BOX
def make_or_get_nat_node(compute, vpcID)
    puts "Checking on NAT Box..."
    # 
    # Is the Amazon nat instance running?
    #
    servers=compute.servers
    #  List image ID, architecture and location
    servers.each do |server|
        if server.tags['Name'] == "NAT::#{$opts[:name]}" and server.state == 'running'
            puts  "\t#{$opts[:name]}\t\t#{server.tags['Name']} #{server.state}".bold.blue
            return server
        end
    end
    puts "Making NAT BOX.."
    # 
    # get security groups and set to public id for nat box
    security_groups=make_or_get_security_grps(compute, vpcID, 1, $opts)
    public_groupID=nil
    security_groups.body['securityGroupInfo'].each do |info|
        if info['vpcId'] == vpcID
            if info['groupName'] == 'public'
                public_groupID=info['groupId']
            end
        end
    end
    puts "Public Security Group: " << public_groupID
    # get subnets and set to DMZ id
    subnetID=nil
    subnets=make_or_get_subnets(compute, vpcID, nil, nil, 1, $opts)
    subnets.body['subnetSet'].each do |subnet|
        if subnet['tagSet']['Name'] == "DMZ_Subnet::#{$opts[:name]}"
            subnetID=subnet['subnetId']
        end
    end
    keyName='eu-sysops-deploy'
    #  Find the amazon nat instance
    offerings=compute.describe_images({:'name' => 'amzn-ami-vpc-nat-pv-2013.03.1.x86_64-ebs'})
    image_id=nil
    offerings.body['imagesSet'].each do |offering|
        image_id=offering['imageId']
    end
    if image_id.nil?
        abort("Didn't find a amzn-ami-vpc-nat-pv-2013.03.1.x86_64-ebs image")
    else
        puts "Found a nat image #{image_id}"
    end
    # set server attr
    server_attributes = {
        :vpc_id => vpcID,
        :flavor_id => m3.medium,
        :key_name => $opts[:key_name],
        :private_key_path => $opts[:key_file_private],
        :public_key_path => $opts[:key_file_pub],
        :image_id => image_id,
        :tags => {'Name' => "NAT::#{$opts[:name]}"},
        :network_interfaces   => [{
            'DeviceIndex'               => '0',
            'SubnetId'                  => subnetID, 
            'AssociatePublicIpAddress'  => true,
            'SecurityGroupId'           => [public_groupID]
                               }]
    }
    # bootstrap server
    server = compute.servers.create(server_attributes)
    server.username='ec2-user'
    puts "Waiting for server sshable..."
    server.wait_for { sshable? }
    server.ssh(['pwd'])
    compute.modify_instance_attribute(server.id, {'SourceDestCheck.Value' => 'false'})
    puts "Public IP Address: #{server.public_ip_address}"
    puts "Private IP Address: #{server.private_ip_address}"
    return server
end
#
# DNS
#
def get_zones(dns)
    return dns.zones
end
def get_records_for_zone(dns, zone)
    return dns.records('zone' => zone)
end
def get_zone_record_for_name(dns, zoneID, name)
    return dns.list_resource_record_sets(zoneID, {:name => name, :type => 'A'})
end
def create_internet_dns_record(dns, ip, name, domain, ttl)
    puts "DNS... ip: #{ip} name: #{name} ttl: #{ttl}"
    zones=get_zones(dns)
    found=0
    correct_ip=0
    zone_object=nil
    zoneID=nil
    wrong_ip=nil
    wrong_type=nil
    wrong_name=nil
    zones.each do |zone|
        puts "\tchecking for #{domain} against #{zone.domain}"
        if zone.domain == domain + "."
            puts "\tfound zone #{zone.id}"
            zone_object=zone
            zoneID=zone.id
            records=get_records_for_zone(dns, zone)
            records.each do |record|
                if record.type == 'A' and record.name == name + "."
                    puts "\tFound DNS zone for #{domain}, #{zoneID} and record for nat box #{record.value}".bold.blue
                    found=1
                    record.value.each do |r_ip| 
                        if r_ip == ip
                            correct_ip=1
                            puts "\tRoute53 Ip matches, nothing to do."
                        else
                            puts "\tWrong record\n\t"
                            #p record
                            wrong_ip=record.value
                            wrong_type=record.type
                            wrong_name=record.name
                        end
                    end
                end
            end
        end
    end
    if found == 0
        zone_object.records.create(:value => ip, :name => name, :type => 'A', :ttl => ttl)
        puts "\tcreated dns for name: #{name} with ip: #{ip}"
    end
    if found == 1 and correct_ip == 0
        change_batch_options = [
          {
            :action => "DELETE",
            :name => wrong_name,
            :type => wrong_type,
            :ttl => ttl,
            :resource_records =>  wrong_ip 
          },
          {
            :action => "CREATE",
            :name => name,
            :type => "A",
            :ttl => ttl,
            :resource_records => [ ip ]
          }
        ]
        #p change_batch_options
        dns.change_resource_record_sets(zoneID, change_batch_options)
        puts "\tRecord ip changed"
    end
    #zoneID.records.create(:value => ip, :name => name, :type => 'PTR', :ttl => ttl)
end

# Volumes
def make_volume(compute, server)
    puts "Creating Volume..."
    if ! $opts[:volume_size].to_s.empty? # false, it's not empty
        if $opts[:volume] == 'io1'
            if $opts[:volume_iops].to_s.empty? # true, it is empty
                abort("You need to define iops value --volume-iops")
            else
                options={'VolumeType' => $opts[:volume], 'Iops' => $opts[:volume_iops]}
                volume=compute.create_volume($opts[:zone], $opts[:volume_size], options)
            end
        else   
                volume=compute.create_volume($opts[:zone], $opts[:volume_size])
        end
    else
        return("ERROR: You need to define a size --volume-size")
    end
    loop do
        v=compute.describe_volumes(:'attachment.status' => 'detached')
        if volume.body.seletct {|id| id['volumeId']  == volume.body['volumeId'] }
            tag=compute.create_tags(volume.body['volumeId'], {"Name" => "#{$opts[:node_name]}::#{$opts[:name]}"})
        end
    end
    return volume
end
def attach_volume(compute, server, volume)
   puts "Attaching volume for #{server.id} and volume #{volume.id}"
   compute.attach_volume(server.id, volume.id, "/dev/sdc")
end

