#!/usr/bin/ruby
require 'rubygems'
require 'fog'
require 'trollop'

#ap-northeast-1 Asia Pacific (Tokyo) Region
##ap-southeast-1 Asia Pacific (Singapore) Region
##ap-southeast-2 Asia Pacific (Sydney) Region
##eu-west-1 EU (Ireland) Region
##sa-east-1 South America (Sao Paulo) Region
##us-east-1 US East (Northern Virginia) Region
##us-west-1 US West (Northern California) Region
##us-west-2 US West (Oregon) Region

opts = Trollop::options do
    opt :fogrc, "file of fogrc settings http://fog.io/about/getting_started.html", :type => :string
    opt :fog_credential, "which credentials to use from fogrc file", :type => :string
    opt :block, "cidr block 10.200.0.0/16 for example" , :type => :string 
    opt :d_subnet, "dmz subnet 10.200.1.0/24 for example"  , :type => :string
    opt :i_subnet, "intranet subnet 10.200.200.0/24 for example"  , :type => :string
    opt :name, "VPC Name", :type => :string
    opt :region, "Region", :type => :string, :default => 'us-east-1'
    opt :vpcID, "vpcID", :type => :string
end
#p opts
ENV['DEBUG']='true'
ENV['FOG_RC'] =  opts[:fogrc]
ENV['FOG_CREDENTIAL']= opts[:fog_credential]
compute=Fog::Compute.new(:provider => 'AWS', :region => opts[:region])

if opts[:vpcID] 
    vpcID=opts[:vpcID]
else
    vpc=compute.vpcs.create({"cidr_block" => opts[:block] })
    tag=compute.create_tags(vpc.id, {"Name" => opts[:name]})
    vpcID=vpc.id
end
#
def make_or_get_igw(compute, vpcID)
    created=0
    igw=compute.internet_gateways()
    igw.each do |gway|
        if vpcID = gway.attachment_set['vpcId']
            created=1
            puts "Internet Gateway for vpc exists " << vpcID
            return gway
        end
    end
    puts created
    if created == 0
        gway=compute.create_internet_gateway()
        compute.create_tags(gway.body['internetGatewaySet'][0]['internetGatewayId'], {"Name" => "InetGway"})
        compute.attach_internet_gateway(gway.body['internetGatewaySet'][0]['internetGatewayId'], vpcID)
        return gway
    end
end
#
def make_or_get_routes(compute, vpcID, gway)
    created=0
    routes=compute.describe_route_tables()
    route_table_id=routes.body['routeTableSet'][0]['routeTableId']
    routes.body['routeTableSet'].each do |ras|
        if vpcID == ras['vpcId'] 
            created=1
        end
        #p ras['associationSet']
    end
    if created == 0
        compute.create_route(route_table_id, '0.0.0.0/0', internet_gateway_id = gway.body['internetGatewaySet'][0]['internetGatewayId'], instance_id = nil, network_interface_id = nil)
    end
    return route_table_id
end
def make_or_get_subnets(compute, vpcID, route_table_id)
    created=0
    check_for=['INTRANET', 'DMZ']
    subnets=compute.describe_subnets()
    subnets.body['subnetSet'].each do |subnet|
        if check_for.include?(subnet['tagSet']['Name'].to_s)
            check_for.delete(subnet['tagSet']['Name'].to_s)
            created=created+1
        end
    end
    if created < 2
        abort("stop here")
        si=compute.create_subnet(vpcID, opts[:i_subnet])
        compute.create_tags(si.body['subnet']['subnetId'], {"Name" => "INTRANET"})
        sd=compute.create_subnet( vpcID, opts[:d_subnet])
        compute.create_tags(sd.body['subnet']['subnetId'], {"Name" => "DMZ"})
        compute.associate_route_table(route_table_id, si.body['subnet']['subnetId'])
        compute.associate_route_table(route_table_id, sd.body['subnet']['subnetId'])
    else
        puts "All subnets created for VPC " << vpcID
    end
end
def make_or_get_security_grps(compute, vpcID)
    # get sg
    created=0
    group_to_check=['public', 'private']
    security_groups=compute.describe_security_groups()
    security_groups.body['securityGroupInfo'].each do |info|
        if info['vpcId'] == vpcID
            if group_to_check.include?(info['groupName'])
                group_to_check.delete(info['groupName'])
                created=created+1
            end
        end
    end
    if created < 2 
        sg_private=compute.create_security_group('private', 'closed to inet' , vpc_id = vpcID)
        private_permission = {
                'IpPermissions' => [
                {
                    'IpProtocol' => -1,
                    'IpRanges' => [{ 'CidrIp' => opts[:block] }]
                }
                ]}
        options = private_permission.clone
        options['GroupId'] = sg_private.body['groupId']
        sg_private=compute.authorize_security_group_ingress(options)

        sg_public=compute.create_security_group('public', 'open to inet' , vpc_id = vpcID)
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
    else
        puts "All Security groups created " << vpcID.to_s
    end
end
#
def make_or_get_eip(compute, vpcID)
    puts "Not creating eip until you tell me who to associate it to.. not implimented"
    #eip=compute.allocate_address(domain = 'vpc')
end
gway=make_or_get_igw(compute, vpcID)
route_table_id=make_or_get_routes(compute, vpcID, gway)
make_or_get_subnets(compute, vpcID, route_table_id)
make_or_get_security_grps(compute,vpcID)
make_or_get_eip(compute,vpcID)

# Can you search for a AMI?
# ami-f3e30084

