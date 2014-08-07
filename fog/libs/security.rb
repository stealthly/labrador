require 'fog'
def get_security_group(compute, vpcID, security_group_name)
    security_groups=compute.describe_security_groups()
    security_groups.body['securityGroupInfo'].each do |sg|
    # "groupId"=>"sg-6377a006", "groupName"=>"default", "groupDescription"=>"default VPC security group", "vpcId"=>"vpc-0f996d6a"}
        if sg['vpcId'] == vpcID and sg['groupName'] == security_group_name
            return sg['groupId']
        end
    end
    return nil
end
