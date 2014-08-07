require 'fog'
require 'colored'

# DHCP Options
def get_dhcp_options(compute)
    dhcp=compute.describe_dhcp_options()
    return dhcp
end
def create_dhcp_options(compute, options)
    dhcp=compute.create_dhcp_options(options)
    return dhcp
end

def make_dhcp_options(compute, domains, servers)
    puts "Checking if dhcp options exists..."
    dhcp=get_dhcp_options(compute)
    #{"dhcpOptionsSet"=>[{"dhcpConfigurationSet"=>{"domain-name"=>["eu-west-1.compute.internal"], "domain-name-servers"=>["AmazonProvidedDNS"]}, "tagSet"=>{}, "dhcpOptionsId"=>"dopt-d16a7cb3"}], "requestId"=>"0f316a60-d264-4a03-8189-00e021721d9c"}
    dhcpID=nil
    dhcp.body['dhcpOptionsSet'].each do |dhcpo|
        if dhcpo['tagSet']['Name'] == "dhcp::#{$opts[:name]}"
            puts "\tFound it #{dhcpo['dhcpOptionsId']}".bold.blue
            dhcpID=dhcpo['dhcpOptionsId']
            return dhcpID
        end
    end
    if dhcpID.nil?
        puts "Creating dhcp option set.."
        dhcpo=compute.create_dhcp_options({'domain-name' => domains, 'domain-name-servers' => servers})
        #{"dhcpOptionsSet"=>[{"dhcpConfigurationSet"=>{"domain-name"=>["intra2.medialets.com"], "domain-name-servers"=>["10.32.145.199"]}, "tagSet"=>{}, "dhcpOptionsId"=>"dopt-f3574691"}], "requestId"=>"0ca30af3-2589-4e87-96c5-2770ad9f5439"}
        dhcpID=dhcpo.body['dhcpOptionsSet'].first['dhcpOptionsId']
        loop do
            dhcpo=get_dhcp_options(compute)
            break if dhcpo.body['dhcpOptionsSet'].select {|dh| dh['dhcpOptionsId'] == dhcpID }
            sleep 5
        end
        compute.create_tags(dhcpID, {"Name" => "dhcp::#{$opts[:name]}"})
        puts "\tCreated dhcp options set.".bold.blue 
        return dhcpID
    end
end

def associate_dhcp_2_vpc(compute, dhcpID, vpcID)
    puts "Checking if it's associated..."
    filters={:'tag-value' => $opts[:name] }
    vpcs=compute.describe_vpcs(filters)
    unless vpcs.body['vpcSet'].first['dhcpOptionsId']  == dhcpID
        puts "\tit's not.  #{dhcpID}  it's #{vpcs.body['vpcSet'].first['dhcpOptionsId']}".bold.red
        puts "Creating association.."
        ret=compute.associate_dhcp_options(dhcpID, vpcID)
    end
    vpcs=compute.describe_vpcs(filters)
    if vpcs.body['vpcSet'].first['dhcpOptionsId']  == dhcpID
        puts "\tIt's now #{vpcs.body['vpcSet'].first['dhcpOptionsId']}".bold.blue
    else
        puts "\tIt's now #{vpcs.body['vpcSet'].first['dhcpOptionsId']} and not dhcpID still!".bold.red
    end

end
