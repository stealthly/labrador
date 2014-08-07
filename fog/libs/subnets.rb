require 'fog'

def get_subnet(compute, subnet_name)
    subnets=compute.describe_subnets()
    subnets.body['subnetSet'].each do |sub|
        #puts subnet.to_yaml
        #puts "#{sub['tagSet']['Name']} --  #{subnet_name}::#{$opts[:name]}"
        if sub['tagSet']['Name'] == "#{subnet_name}::#{$opts[:name]}"
            #print "FOUND"
            subnet=sub
            return subnet
        end
    end
    return nil
end
