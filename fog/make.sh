#!/bin/bash

#./makeDR.sh dr-cr{}.site4.medialets.com subnet-25c99e63 ami-e687e3d6 m1.medium 'role[medialets_linux],role[r-haproxy]'
# AMI's
# ami-f032acc0 -- Amazon NAT Device
# ami-90fe72a0  \
# ami-e687e3d6
# Subnets
DOMAIN=`dnsdomainname`
USER=root
CONNECT_ATTR=private_ip_address
if [ $DOMAIN == 'stg.medialets.com' ]; then
	CHEF_SERVER="http://10.100.6.206:4000"
	REGION=us-east-1
	SSHKEY=acqant-keypair.pem
	SSH_KEY_NAME=acqant-keypair
	ENVIRONMENT=Staging_and_Shakedown
fi
if [ $DOMAIN == 'site3.medialets.com' ]; then
	CHEF_SERVER="http://pos01.medialets.com:4000"
	REGION=us-west-2
	SSHKEY=aws-west.pem
	SSH_KEY_NAME=aws-west
	ENVIRONMENT=Production_Site4
fi
OPTIND=1         # Reset in case getopts has been used previously in the shell.
while getopts "h?n:s:a:f:r:e:y:z:" opt; do
    case "$opt" in
    h|\?)
	echo "-n NAME -s [DMZ|INTRANET] -a  AMI -f m1-small -r 'r-creative' -e EIP -y AccessKey -z SecretKey"
        exit 0
        ;;
    n)  NAME=$OPTARG
        ;;
    s)  echo $OPTARG
	if [ $OPTARG == "DMZ" ]; then
		if [ $DOMAIN == 'stg.medialets.com' ]; then
			SUBNET=subnet-9be407ec
			SG=sg-95b13bf0
			
		fi
		if [ $DOMAIN == 'site4.medialets.com' ]; then
			SUBNET=subnet-25c99e63
		fi
	fi
        if [ $OPTARG == "INTRANET" ]; then
		if [ $DOMAIN == 'stg.medialets.com' ]; then
			SUBNET=subnet-9ce407eb
			SG=sg-94b13bf1
		fi
		if [ $DOMAIN == 'site4.medialets.com' ]; then
			SUBNET=subnet-b42573f2
		fi
	fi
        ;;
    a)  AMI=$OPTARG
		if [ $AMI == 'ami-f032acc0' ] || [ $AMI == 'ami-ad227cc4' ]
		then
			USER=ec2-user
		fi
        ;;
    f)  FLAVOR=$OPTARG
        ;;
    r)  ROLES=$OPTARG
        ;;
    e)  EIP=$OPTARG
		CONNECT_ATTR=ip_address
        ;;
    y)  AKEY=$OPTARG
	;;
    z)  SKEY=$OPTARG
    esac
done
shift $((OPTIND-1))
[ "$1" = "--" ] && shift
echo "$NAME $SUBNET $AMI $FLAVOR $ROLES $EIP $AKEY $SKEY Leftovers: $@"

#############################################################
knife client show $NAME 1>/dev/null
if [ $? == 0 ]; then
	echo "Exit, we already have that node name."
	exit
fi
if [ ! -z $EIP ];then
	if [ $EIP == 'yes' ]; then
		echo "Provisioning new ip: $EIP <-cmd line option"
		EIP=`./eip.rb create`
		EXTRA_ARGS=" --associate-eip $EIP"
		# provision new ip
	else
		echo "Allocate new ip"
		# allocate the ip
		EXTRA_ARGS=" --associate-eip $EIP"
	fi
fi
CMD="knife ec2 server create -V \
	-A $AKEY \
	-K $SKEY \
	-i ./$SSHKEY -S $SSH_KEY_NAME \
	-r "$ROLES" \
	-I $AMI  \
	-g $SG \
	-N $NAME \
	-s $SUBNET \
	--flavor $FLAVOR \
	--region $REGION \
	--ssh-user $USER \
	--bootstrap-version 11.8.2 \
	--bootstrap-protocol ssh \
	--server-connect-attribute $CONNECT_ATTR
	-k ./validation.pem $EXTRA_ARGS \
	-E $ENVIRONMENT"
	#--server-url $CHEF_SERVER \
echo $CMD
eval $CMD
if [ $? == 0 ]; then
	curl "http://chef/cgi-bin/registernode?node=$NAME&role=medialets_linux"
	curl "http://chef/cgi-bin/registernode?node=$NAME&role=$ROLE_AFTER_RUN"
	IP=`knife exec -E   "nodes.find(:name => \"$NAME\") { |n| puts \"#{n.ipaddress}\" }"`
	/usr/local/medialets_bin/scripts/automation/deploy/dns/pdns.py commit $IP macaddy ${NAME}
else
	#chef has to run cleanly or this will clean up after itself
	IID=`knife ec2 server list -A AKIAIKP3YZVLQSY2DEQQ  -K $KEY  --region us-west-2| grep $NAME | awk '{print $1}'`
	knife ec2 server delete -y $IID -A AKIAIKP3YZVLQSY2DEQQ  -K $KEY -P --region us-west-2 --node-name $NAME
	if [ ! -x $EIP ]; then
		/usr/local/medialets_bin/scripts/automation/deploy/bootstrap_ec2/eip.rb release  $EIP
	fi
	
fi
