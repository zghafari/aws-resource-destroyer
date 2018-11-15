profile=$1

#set -e

virtualInterfaces=( $(aws directconnect --profile $profile describe-virtual-interfaces --query virtualInterfaces[*].virtualInterfaceId --output text) )

if [ -n "$virtualInterfaces" -a "$virtualInterfaces" != "None" ]; then   
    for vif in ${virtualInterfaces[@]}; do
        echo "DELETING VIRTUAL INTERFACES - $vif"
        aws directconnect --profile $profile delete-virtual-interface --virtual-interface-id $vif
    done
fi

dcgs=( $(aws directconnect --profile $profile describe-direct-connect-gateways --query directConnectGateways[*].directConnectGatewayId --output text) )

if [ -n "$dcgs" -a "$dcgs" != "None" ]; then   
    for dcg in ${dcgs[@]}; do
        virtualgateways=( $(aws directconnect --profile $profile describe-direct-connect-gateway-associations --direct-connect-gateway-id $dcg --query directConnectGatewayAssociations[*].virtualGatewayId --output text) )
        if [ -n "$virtualgateways" -a "$virtualgateways" != "None" ]; then   
            for vg in ${virtualgateways[@]}; do
                echo "DELETING DIRECT CONNECT ASSOS - $vg & $dcg"
                aws directconnect --profile $profile delete-direct-connect-gateway-association --direct-connect-gateway-id $dcg --virtual-gateway-id $vg
            done
        fi
    done
fi

vpcL=( $(aws ec2 --profile $profile describe-vpcs --query Vpcs[*].VpcId --output text) )

vpcPeerL=( $(aws ec2 --profile $profile describe-vpc-peering-connections --query VpcPeeringConnections[*].VpcPeeringConnectionId --output text) )
if [ -n "$vpcPeerL" -a "$vpcPeerL" != "None" ]; then
    for vpcPeerId in ${vpcPeerL[@]}; do
        echo "DELETE VPC PEERING - $vpcPeerId"
        aws ec2 --profile $profile delete-vpc-peering-connection --vpc-peering-connection-id $vpcPeerId
    done
fi

nats=( $(aws ec2 --profile $profile describe-nat-gateways --query NatGateways[*].NatGatewayId --output text) )
if [ -n "$nats" -a "$nats" != "None" ]; then   
        for nat in ${nats[@]}; do
            echo "DELETING NAT GATEWAY- $nat"
            aws ec2 --profile $profile delete-nat-gateway --nat-gateway-id $nat
        done
fi

addresses=( $(aws ec2 --profile $profile describe-addresses --filters "Name=domain,Values=vpc" --query Addresses[*].AllocationId --output text) )
if [ -n "$addresses" -a "$addresses" != "None" ]; then   
        for address in ${addresses[@]}; do
            echo "RELEASING ADDRESS - $address"
            aws ec2 --profile $profile release-address --allocation-id $address
        done
fi

for vpcId in ${vpcL[@]}; do
    defaultNacl=( $(aws ec2 --profile $profile describe-network-acls --filter Name="default",Values="true" Name="vpc-id",Values="$vpcId" --query NetworkAcls[*].NetworkAclId --output text) )
    nDefNacl=( $(aws ec2 --profile $profile describe-network-acls --filter Name="default",Values="false" Name="vpc-id",Values="$vpcId" --query NetworkAcls[*].Associations[*].NetworkAclAssociationId --output text) )    
    
    if [ -n "$nDefNacl" -a "$nDefNacl" != "None" ]; then
        for assoId in ${nDefNacl[@]}; do
            echo "UNASSOCIATE NETWORK ACL FROM SUBNET TO DEFAULT FOR VPC - $vpcId"
            aws ec2 --profile $profile replace-network-acl-association --association-id $assoId --network-acl-id $defaultNacl
        done
    fi

    nonDefaultNacl=( $(aws ec2 --profile $profile describe-network-acls  --filter Name="default",Values="false" Name="vpc-id",Values="$vpcId" --query NetworkAcls[*].NetworkAclId  --output text) )
    if [ -n "$nonDefaultNacl" -a "$nonDefaultNacl" != "None" ]; then
        for naclId in ${nonDefaultNacl[@]}; do
            echo "DELETING NETWORK ACL - $naclId"
            aws ec2 --profile $profile delete-network-acl --network-acl-id $naclId
        done
    fi

    internetGateway=( $(aws ec2 --profile $profile describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpcId" --query InternetGateways[0].InternetGatewayId --output text) )
    if [ -n "$internetGateway" -a "$internetGateway" != "None" ]; then   
        echo "DETACHING INTERNET GATEWAY - $internetGateway"
        aws ec2 --profile $profile detach-internet-gateway --internet-gateway-id $internetGateway --vpc-id $vpcId

        echo "DELETING INTERNET GATEWAY - $internetGateway"
        aws ec2 --profile $profile delete-internet-gateway --internet-gateway-id $internetGateway 
    fi

    vpnGateway=( $(aws ec2 --profile $profile describe-vpn-gateways --filters "Name=attachment.vpc-id,Values=$vpcId" --query VpnGateways[0].VpnGatewayId --output text) )
    if [ -n "$vpnGateway" -a "$vpnGateway" != "None" ]; then   
        echo "DETACHING VPN GATEWAY - $vpnGateway"
        aws ec2 --profile $profile detach-vpn-gateway --vpn-gateway-id $vpnGateway --vpc-id $vpcId

        echo "DELETING VPN GATEWAY - $vpnGateway"
        aws ec2 --profile $profile delete-vpn-gateway --vpn-gateway-id $vpnGateway 
    fi

    echo "ASSOCIATING VPC - $vpcId TO DEFAULT DHCP"
    aws ec2 --profile $profile associate-dhcp-options --dhcp-options-id default --vpc-id $vpcId

done

subnets=( $(aws ec2 --profile $profile describe-subnets --query Subnets[*].SubnetId --output text) )
if [ -n "$subnets" -a "$subnets" != "None" ]; then
    for s in ${subnets[@]}; do
        echo "DELETING SUBNET - $s"   
        aws ec2 --profile $profile delete-subnet --subnet-id $s
    done
fi

routeTables=( $(aws ec2 --profile $profile describe-route-tables --filters --query 'RouteTables[?Associations[0].Main == null].RouteTableId' --output text) )
if [ -n "$routeTables" -a "$routeTables" != "None" ]; then
    for rt in ${routeTables[@]}; do
        echo "DELETING ROUTE TABLE - $rt"   
        aws ec2 --profile $profile delete-route-table --route-table-id $rt
    done
fi

dhcpOptions=( $(aws ec2 --profile $profile describe-dhcp-options --query DhcpOptions[*].DhcpOptionsId --output text) )
if [ -n "$dhcpOptions" -a "$dhcpOptions" != "None" ]; then   
    for dhcp in ${dhcpOptions[@]}; do
        echo "DELETING DHCP - $dhcp"
        aws ec2 --profile $profile delete-dhcp-options --dhcp-options-id $dhcp
    done
fi

flowLogs=( $(aws ec2 --profile $profile describe-flow-logs --query FlowLogs.FlowLogId --output text) )
if [ -n "$flowLogs" -a "$flowLogs" != "None" ]; then   
    for flowLog in ${flowLogs[@]}; do
        echo "DELETING FLOW LOG - $flowLog"
        aws ec2 --profile $profile delete-flow-logs --flow-log-id $flowLog
    done
fi 

if [ -n "$dcgs" -a "$dcgs" != "None" ]; then   
    for dcg in ${dcgs[@]}; do
        echo "DELETING VPN DIRECT CONNECT GATEWAY - $dcg"
        aws directconnect --profile $profile delete-direct-connect-gateway --direct-connect-gateway-id $dcg
    done
fi

if [ -n "$vpcL" -a "$vpcL" != "None" ]; then   
    for vpcId in ${vpcL[@]}; do
        echo "DELETING VPC - $vpcId"
        aws ec2 --profile $profile delete-vpc --vpc-id $vpcId
    done
fi

trails=(  $(aws cloudtrail --profile $profile describe-trails --query trailList[*].TrailARN --output text) )
if [ -n "$trails" -a "$trails" != "None" ]; then   
    for trail in ${trails[@]}; do
        echo "DELETING CLOUDTRAIL - $trail"
        aws cloudtrail --profile $profile delete-trail --name $trail
    done
fi

topics=( $(aws sns --profile $profile list-topics --query Topics[*].TopicArn --output text) )
if [ -n "$topics" -a "$topics" != "None" ]; then   
    for topic in ${topics[@]}; do
        echo "DELETING SNS TOPICS - $trail"
        aws sns --profile $profile delete-topic --topic-arn $topic
    done
fi

configAggrs=( $(aws configservice --profile $profile describe-configuration-aggregators --query ConfigurationAggregators[*].ConfigurationAggregatorName --output text) )
if [ -n "$configAggrs" -a "$configAggrs" != "None" ]; then   
    for agg in ${configAggrs[@]}; do
        echo "DELETING AWS CONFIG AGGREGATOR - $trail"
        aws configservice --profile $profile delete-configuration-aggregator --configuration-aggregator-name $agg
    done
fi

detectors=( $(aws guardduty --profile $profile list-detectors --query DetectorIds --output text) )
if [ -n "$detectors" -a "$detectors" != "None" ]; then   
    members=( $(aws guardduty --profile $profile list-members --detector-id $detectors --query Members[*].AccountId --output text) )
    if [ -n "$members" -a "$members" != "None" ]; then   
        for mem in ${members[@]}; do
            echo "DISASSOCIATE MEMBERS - $mem"
            aws guardduty --profile $profile disassociate-members --detector-id $detectors --account-ids $mem

            echo "DELETING MEMBERS - $mem"
            aws guardduty --profile $profile delete-members --detector-id $detectors --account-ids $mem
        done
    fi
fi

if [ -n "$detectors" -a "$detectors" != "None" ]; then   
    for det in ${detectors[@]}; do
        echo "DELETING DETECTORS - $det"
        aws guardduty --profile $profile delete-detector --detector-id $det
    done
fi

configRecorders=( $(aws configservice --profile $profile describe-configuration-recorders --query ConfigurationRecorders[*].name --output text) )
if [ -n "$configRecorders" -a "$configRecorders" != "None" ]; then   
    for configName in ${configRecorders[@]}; do
        echo "STOPPING RECORDER - $configName"
        aws configservice --profile $profile stop-configuration-recorder --configuration-recorder-name $configName

        echo "DELETING RECORDER - $configName"
        aws configservice --profile $profile delete-configuration-recorder --configuration-recorder-name $configName
    done
fi

delChannels=( $(aws configservice --profile $profile describe-delivery-channels --query DeliveryChannels[*].name --output text) )
if [ -n "$delChannels" -a "$delChannels" != "None" ]; then   
    for chan in ${delChannels[@]}; do
        echo "DELETING DELIVERY CHANNEL - $chan"
        aws configservice --profile $profile delete-delivery-channel --delivery-channel-name $chan
    done
fi

aggs=( $(aws configservice --profile $profile describe-configuration-aggregators --query ConfigurationAggregators[*].ConfigurationAggregatorName --output text) )
if [ -n "$aggs" -a "$aggs" != "None" ]; then   
    for configAggName in ${aggs[@]}; do
        echo "DELETING AGGREGATORS - $configAggName"
        aws configservice --profile $profile delete-configuration-aggregator --configuration-aggregator-name $configAggName
    done
fi

s3BucketNames=( $(aws s3api --profile $profile list-buckets --query Buckets[*].Name --output text) )
if [ -n "$s3BucketNames" -a "$s3BucketNames" != "None" ]; then   
    for bucket in ${s3BucketNames[@]}; do
        echo "SUSPENDING VERSIONING - $bucket"
        aws s3api --profile $profile put-bucket-versioning --bucket $bucket --versioning-configuration Status=Suspended

        echo "GETTING VERSIONS AND DELETE MARKERS - $bucket"
        OBJECT_VERSIONS=$(aws --profile $profile --output text s3api list-object-versions --bucket $bucket | grep -E '^VERSIONS|^DELETEMARKERS')
        while read OBJECT_VERSION; do
            if [[ $OBJECT_VERSION == DELETEMARKERS* ]]; then
                KEY=$(echo $OBJECT_VERSION | awk '{print $3}')
                VERSION_ID=$(echo $OBJECT_VERSION | awk '{print $5}')
            else
                KEY=$(echo $OBJECT_VERSION | awk '{print $4}')
                VERSION_ID=$(echo $OBJECT_VERSION | awk '{print $8}')
            fi
            echo "DELETING OBJECTS - $bucket"
            aws s3api --profile $profile delete-object --bucket $bucket --key $KEY --version-id $VERSION_ID
        done <<< "$OBJECT_VERSIONS"

        echo "DELETING BUCKET - $bucket"
        aws s3 --profile $profile rb s3://$bucket --force
    done
fi

cloudStacks=( $(aws cloudformation --profile $profile describe-stacks --query Stacks[*].StackId --output text) )
if [ -n "$cloudStacks" -a "$cloudStacks" != "None" ]; then   
    for stack in ${cloudStacks[@]}; do
        echo "DELETING STACK - $stack"
        aws cloudformation --profile $profile delete-stack --stack-name $stack 
    done
fi

echo "Hasta la vista, baby."