labrador
========

    gem install fog; 
    gem install trollop

2) Configure a fog_rc file
```
:sysops_account:
  :aws_access_key_id: some_key
  :aws_secret_access_key: some_secret
```

3) put your ssh keys in keys/ dir    
4) run makeVPC.rb -h

This makes a VPC called test VPC with a 10.200/16 network, one external to internet 10.200.1 and one internal only 10.200.200    

This also make two security groups with port 22 and 33333 open to 10.200.1 hosts.    

This also searches for the Amazon NAT ami images, boots it, tags it and logs in.    

./makeVPC.rb -f ./fog_rc --fog-credential sysops_account -b 10.200.0.0/16 -d 10.200.1.0/24 -i 10.200.200.0/24 --name testVPC -r eu-west-1    


```
└─> ./makeVPC.rb -f ./fog_rc --fog-credential sysops_account -b 10.200.0.0/16 -d 10.200.1.0/24 -i 10.200.200.0/24 --name testVPC -r eu-west-1 --vpcID vpc-a3c72cc6
Internet Gateway for vpc exists vpc-a3c72cc6
All subnets created for VPC vpc-a3c72cc6
All Security groups created vpc-a3c72cc6

###################################################################################

VpcID           TagName
vpc-a3c72cc6    NAT::vpc-a3c72cc6::subnet-8c43abfb

###################################################################################
We have a nat box... returning
```
#
# 
#
```
./makeVPC.rb -f ./fog_rc --fog-credential sysops_east -b 10.200.0.0/16 -d 10.200.1.0/24 -i 10.200.200.0/24 --name testVPC -r eu-west-1  --key-name eu-sysops-deploy --key-file-pub ./eu-west.pub --key-file-private ./eu-west.pem  --vpcID vpc-2647ac43 
or
./makeVPC.rb -f ./fog_rc --fog-credential sysops_east -b 10.32.148.0/24 -d 10.32.148.0/25 -i 10.32.148.128/25 --name devVPC -r eu-east-1  --key-name east-sysops-deploy --key-file-pub ./key/east-sysops-deploy.pub --key-file-private ./key/east-sysops-deploy.pem  
then
knife  bootstrap  -c knife-shakedown.rb 54.88.167.212 -N nat01.dev.medialets.com -E DEV  --no-host-key-verify  --ssh-user ec2-user -i keys/east-sysops-deploy.pem --sudo  -r cb-base
```

