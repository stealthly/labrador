labrador
========

* fill in the fog_rc file with your credentials
* install fog and trollop Gems
* ./makeVPC.rb -h
Options:
           --fogrc, -f <s>:   file of fogrc settings http://fog.io/about/getting_started.html
  --fog-credential, -o <s>:   which credentials to use from fogrc file
           --block, -b <s>:   cidr block 10.200.0.0/16 for example
        --d-subnet, -d <s>:   dmz subnet 10.200.1.0/24 for example
        --i-subnet, -i <s>:   intranet subnet 10.200.200.0/24 for example
            --name, -n <s>:   VPC Name
          --region, -r <s>:   Region (default: us-east-1)
           --vpcID, -v <s>:   vpcID
                --help, -h:   Show this message


* With --vpcID
./makeVPC.rb -f ./fog_rc --fog-credential sysops_account -b 10.200.0.0/16 -d 10.200.1.0/24 -i 10.200.200.0/24 --name testVPC -r eu-west-1 --vpcID vpc-a3c72cc6
* Without --vpcID
./makeVPC.rb -f ./fog_rc --fog-credential sysops_account -b 10.200.0.0/16 -d 10.200.1.0/24 -i 10.200.200.0/24 --name testVPC -r eu-west-1 
