#!/usr/bin/ruby
require 'fog'
require 'pp'
# INTERNET GATEWAY
def make_or_get_igw(compute, vpcID, opts)
    puts "Internet gway... #{vpcID}\n"
    if vpcID == nil
        abort("No VPC ID!")
    end
    created=0
    igw=compute.internet_gateways()
    gatewayID=nil
    igw.each do |gway|
        if vpcID == gway.attachment_set['vpcId']
            gatewayID=gway.id
            created=1
            puts "\tInternet gway id " +gatewayID+ " for vpc exists " +vpcID
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
            igws=compute.internet_gateways()
            sleep 5
            break if igws.select {|ig| ig.id == gatewayID }
        end

        compute.attach_internet_gateway(gatewayID, vpcID)
        puts "\tInternet gway #{gatewayID} attached for vpc #{vpcID}"
        compute.create_tags(gatewayID, {"Name" => "#{opts[:name]}::InetGway"})
    end
    return gatewayID
end

#  ROUTES
def make_or_get_routes(compute, vpcID, gwayID, opts)
    puts "Routes....\n"
    created=0
    routes=compute.describe_route_tables()
    rti=nil
    routes.body['routeTableSet'].each do |route|
        #each one of these is a route
        if route['tagSet']['Name']== opts[:name]
            created=1
            rti=route['routeTableId']
            puts "\tFound route #{rti} for: #{opts[:name]}"
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
        tag=compute.create_tags(new_route.body['routeTable'][0]['routeTableId'], {"Name" => opts[:name]})
        rti=new_route.body['routeTable'][0]['routeTableId']
        compute.create_route(rti, '0.0.0.0/0', internet_gateway_id = gwayID, instance_id = nil, network_interface_id = nil)
        puts "\tRoutes created #{rti}"
    end
    return rti
end
def make_or_get_subnets(compute, vpcID, route_table_id, get, opts)
    puts "Subnets...\n"
    created=0
    check_for=['INTRANET', 'DMZ']
    subnets=compute.describe_subnets()
    return subnets if get == 1
    subnets.body['subnetSet'].each do |subnet|
        if check_for.include?(subnet['tagSet']['Name'].to_s)
            check_for.delete(subnet['tagSet']['Name'].to_s)
            created=created+1
        end
    end
    if created < 2
        si=compute.create_subnet(vpcID, opts[:i_subnet])
        loop do
            subnets=compute.describe_subnets()
            sleep 5
            break if subnets.body['subnetSet'].select {|subnetSet| subnetSet['subnetId'] == si.body['subnet']['subnetId']}
        end
        compute.create_tags(si.body['subnet']['subnetId'], {"Name" => "INTRANET"})
        compute.associate_route_table(route_table_id, si.body['subnet']['subnetId'])
        #
        sd=compute.create_subnet( vpcID, opts[:d_subnet])
        loop do
            subnets=compute.describe_subnets()
            sleep 5
            break if subnets.body['subnetSet'].select {|subnetSet| subnetSet['subnetId'] == sd.body['subnet']['subnetId']}
        end
        compute.create_tags(sd.body['subnet']['subnetId'], {"Name" => "DMZ"})
        compute.associate_route_table(route_table_id, sd.body['subnet']['subnetId'])
        puts "\tSubnets created for VPC " << vpcID
    else
        puts "\tSubnets created for VPC " << vpcID
    end

    #return hash of subnets Name and Id
end

# SECURITY GROUPS
def make_or_get_security_grps(compute, vpcID, get, opts)
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
                puts "\tSecurity group exists #{info['groupName']}"
            end
        end
    end

    if created < 2 
        group_to_check.each do |group|
         #CREATE PRIVATE all access group
         if group == 'private'
            sg_private=compute.create_security_group('private', 'closed to inet' , vpc_id = vpcID)
            loop do
                security_groups=compute.describe_security_groups()
                sleep 5
                break if security_groups.body['securityGroupInfo'].select {|groupID| groupID['groupID'] == sg_private.body['groupId']}
            end
            private_permission = {
                    'IpPermissions' => [
                    {
                        'IpProtocol' => -1,
                        'IpRanges' => [{ 'CidrIp' => opts[:block] }]
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
            loop do
                security_groups=compute.describe_security_groups()
                sleep 5
                puts "\tWaiting for security group...."
                break if security_groups.body['securityGroupInfo'].select {|groupID| groupID['groupID'] == sg_public.body['groupId']}
            end
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
                        'FromPort' => 33333,
                        'ToPort' => 33333,
                        'IpRanges' => [{ 'CidrIp' => '0.0.0.0/0' }]
                    }

                    ]}
            options = public_permission.clone
            options['GroupId'] = sg_public.body['groupId']
            asg_public=compute.authorize_security_group_ingress(options)
            puts "\tSecurity group #{sg_public.body['groupId']} created for vpc: #{vpcID}"
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
def make_or_get_nat_node(compute, vpcID, opts)
    puts "NAT Box..."
    # 
    # Is the Amazon nat instance running?
    #
    instances = compute.describe_instances
    puts "\n###################################################################################"
    puts "\nVpcID\t\tTagName\n"
    #  List image ID, architecture and location
    have_a_nat_box=0
    instances.body['reservationSet'].each do |instance|
        if instance['instancesSet'].first['instanceState']['name'] == 'running'
            if instance['instancesSet'].first['tagSet']['Name'] =~ /NAT::#{opts[:name]}/
                have_a_nat_box=1
                puts  instance['instancesSet'].first['vpcId'] + "\t" + instance['instancesSet'].first['tagSet']['Name'] 
            end
        end
    end
    puts "\n###################################################################################"
    if have_a_nat_box == 1
        puts "We have a nat box... returning"
        return 1
    end
    # 
    # get security groups and set to public id for nat box
    security_groups=make_or_get_security_grps(compute, vpcID, 1, opts)
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
    subnets=make_or_get_subnets(compute, vpcID, nil, 1, opts)
    subnets.body['subnetSet'].each do |subnet|
        if subnet['tagSet']['Name'] == 'DMZ'
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
    p image_id
    if image_id.nil?
        abort("Didn't find a amzn-ami-vpc-nat-pv-2013.03.1.x86_64-ebs image")
    end
    # set server attr
    server_attributes = {
        :vpc_id => vpcID,
        :flavor_id => 'm1.medium',
        :key_name => opts[:key_name],
        :private_key_path => opts[:key_file_private],
        :public_key_path => opts[:key_file_pub],
        :image_id => image_id,
        :tags => {'Name' => 'NAT::'+vpcID+'::'+subnetID},
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
    puts "Public IP Address: #{server.public_ip_address}"
    puts "Private IP Address: #{server.private_ip_address}"
end
