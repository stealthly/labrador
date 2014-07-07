echo "RUN THIS compute=Fog::Compute.new :provider => 'AWS', :region => 'us-east-1'"
export FOG_RC=./conf/fog_rc
export FOG_CREDENTIAL=sysops_account
fog
