#!/usr/bin/env bash

set -euo pipefail

# Required: set AWS_REGION before running, or export it in your shell.
AWS_REGION="${AWS_REGION:-eu-west-1}"

OWNER_TAG_KEY="DkuOwner"
OWNER_TAG_VALUE="mohamed.hichri@dataiku.com"

NAME_PREFIX="${NAME_PREFIX:-mhichri-}"

VPC_NAME="${VPC_NAME:-${NAME_PREFIX}vpc}"
VPC_CIDR="${VPC_CIDR:-10.10.0.0/16}"

PUBLIC_SUBNET_1_CIDR="${PUBLIC_SUBNET_1_CIDR:-10.10.1.0/24}"
PUBLIC_SUBNET_2_CIDR="${PUBLIC_SUBNET_2_CIDR:-10.10.2.0/24}"
PRIVATE_SUBNET_1_CIDR="${PRIVATE_SUBNET_1_CIDR:-10.10.11.0/24}"
PRIVATE_SUBNET_2_CIDR="${PRIVATE_SUBNET_2_CIDR:-10.10.12.0/24}"

AZ1="${AZ1:-${AWS_REGION}a}"
AZ2="${AZ2:-${AWS_REGION}b}"

PUBLIC_SUBNET_1_NAME="${PUBLIC_SUBNET_1_NAME:-${NAME_PREFIX}public-subnet-1}"
PUBLIC_SUBNET_2_NAME="${PUBLIC_SUBNET_2_NAME:-${NAME_PREFIX}public-subnet-2}"
PRIVATE_SUBNET_1_NAME="${PRIVATE_SUBNET_1_NAME:-${NAME_PREFIX}private-subnet-1}"
PRIVATE_SUBNET_2_NAME="${PRIVATE_SUBNET_2_NAME:-${NAME_PREFIX}private-subnet-2}"

PUBLIC_RT_1_NAME="${PUBLIC_RT_1_NAME:-${NAME_PREFIX}public-rt-1}"
PUBLIC_RT_2_NAME="${PUBLIC_RT_2_NAME:-${NAME_PREFIX}public-rt-2}"
PRIVATE_RT_1_NAME="${PRIVATE_RT_1_NAME:-${NAME_PREFIX}private-rt-1}"
PRIVATE_RT_2_NAME="${PRIVATE_RT_2_NAME:-${NAME_PREFIX}private-rt-2}"

IGW_NAME="${IGW_NAME:-${NAME_PREFIX}igw}"
NAT_GW_1_NAME="${NAT_GW_1_NAME:-${NAME_PREFIX}nat-gw-1}"
NAT_GW_2_NAME="${NAT_GW_2_NAME:-${NAME_PREFIX}nat-gw-2}"
NAT_EIP_1_NAME="${NAT_EIP_1_NAME:-${NAME_PREFIX}nat-eip-1}"
NAT_EIP_2_NAME="${NAT_EIP_2_NAME:-${NAME_PREFIX}nat-eip-2}"

tag_spec() {
  local resource_type="$1"
  local name="$2"
  printf 'ResourceType=%s,Tags=[{Key=Name,Value=%s},{Key=%s,Value=%s}]' \
    "$resource_type" "$name" "$OWNER_TAG_KEY" "$OWNER_TAG_VALUE"
}

echo "Creating VPC in region $AWS_REGION"
VPC_ID=$(aws ec2 create-vpc \
  --region "$AWS_REGION" \
  --cidr-block "$VPC_CIDR" \
  --tag-specifications "$(tag_spec vpc "$VPC_NAME")" \
  --query 'Vpc.VpcId' \
  --output text)

aws ec2 modify-vpc-attribute \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --enable-dns-support

aws ec2 modify-vpc-attribute \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --enable-dns-hostnames

echo "Creating and attaching internet gateway"
IGW_ID=$(aws ec2 create-internet-gateway \
  --region "$AWS_REGION" \
  --tag-specifications "$(tag_spec internet-gateway "$IGW_NAME")" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --region "$AWS_REGION" \
  --internet-gateway-id "$IGW_ID" \
  --vpc-id "$VPC_ID"

echo "Creating public subnets"
PUB_SUBNET_1_ID=$(aws ec2 create-subnet \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PUBLIC_SUBNET_1_CIDR" \
  --availability-zone "$AZ1" \
  --tag-specifications "$(tag_spec subnet "$PUBLIC_SUBNET_1_NAME")" \
  --query 'Subnet.SubnetId' \
  --output text)

PUB_SUBNET_2_ID=$(aws ec2 create-subnet \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PUBLIC_SUBNET_2_CIDR" \
  --availability-zone "$AZ2" \
  --tag-specifications "$(tag_spec subnet "$PUBLIC_SUBNET_2_NAME")" \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 modify-subnet-attribute \
  --region "$AWS_REGION" \
  --subnet-id "$PUB_SUBNET_1_ID" \
  --map-public-ip-on-launch

aws ec2 modify-subnet-attribute \
  --region "$AWS_REGION" \
  --subnet-id "$PUB_SUBNET_2_ID" \
  --map-public-ip-on-launch

echo "Creating private subnets"
PRIV_SUBNET_1_ID=$(aws ec2 create-subnet \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PRIVATE_SUBNET_1_CIDR" \
  --availability-zone "$AZ1" \
  --tag-specifications "$(tag_spec subnet "$PRIVATE_SUBNET_1_NAME")" \
  --query 'Subnet.SubnetId' \
  --output text)

PRIV_SUBNET_2_ID=$(aws ec2 create-subnet \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block "$PRIVATE_SUBNET_2_CIDR" \
  --availability-zone "$AZ2" \
  --tag-specifications "$(tag_spec subnet "$PRIVATE_SUBNET_2_NAME")" \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Allocating Elastic IPs for NAT gateways"
EIP_ALLOC_1=$(aws ec2 allocate-address \
  --region "$AWS_REGION" \
  --domain vpc \
  --tag-specifications "$(tag_spec elastic-ip "$NAT_EIP_1_NAME")" \
  --query 'AllocationId' \
  --output text)

EIP_ALLOC_2=$(aws ec2 allocate-address \
  --region "$AWS_REGION" \
  --domain vpc \
  --tag-specifications "$(tag_spec elastic-ip "$NAT_EIP_2_NAME")" \
  --query 'AllocationId' \
  --output text)

echo "Creating NAT gateways"
NAT_GW_1_ID=$(aws ec2 create-nat-gateway \
  --region "$AWS_REGION" \
  --subnet-id "$PUB_SUBNET_1_ID" \
  --allocation-id "$EIP_ALLOC_1" \
  --tag-specifications "$(tag_spec natgateway "$NAT_GW_1_NAME")" \
  --query 'NatGateway.NatGatewayId' \
  --output text)

NAT_GW_2_ID=$(aws ec2 create-nat-gateway \
  --region "$AWS_REGION" \
  --subnet-id "$PUB_SUBNET_2_ID" \
  --allocation-id "$EIP_ALLOC_2" \
  --tag-specifications "$(tag_spec natgateway "$NAT_GW_2_NAME")" \
  --query 'NatGateway.NatGatewayId' \
  --output text)

aws ec2 wait nat-gateway-available \
  --region "$AWS_REGION" \
  --nat-gateway-ids "$NAT_GW_1_ID" "$NAT_GW_2_ID"

echo "Creating public route tables"
PUB_RT_1_ID=$(aws ec2 create-route-table \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag_spec route-table "$PUBLIC_RT_1_NAME")" \
  --query 'RouteTable.RouteTableId' \
  --output text)

PUB_RT_2_ID=$(aws ec2 create-route-table \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag_spec route-table "$PUBLIC_RT_2_NAME")" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --region "$AWS_REGION" \
  --route-table-id "$PUB_RT_1_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID"

aws ec2 create-route \
  --region "$AWS_REGION" \
  --route-table-id "$PUB_RT_2_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID"

aws ec2 associate-route-table \
  --region "$AWS_REGION" \
  --subnet-id "$PUB_SUBNET_1_ID" \
  --route-table-id "$PUB_RT_1_ID"

aws ec2 associate-route-table \
  --region "$AWS_REGION" \
  --subnet-id "$PUB_SUBNET_2_ID" \
  --route-table-id "$PUB_RT_2_ID"

echo "Creating private route tables"
PRIV_RT_1_ID=$(aws ec2 create-route-table \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag_spec route-table "$PRIVATE_RT_1_NAME")" \
  --query 'RouteTable.RouteTableId' \
  --output text)

PRIV_RT_2_ID=$(aws ec2 create-route-table \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag_spec route-table "$PRIVATE_RT_2_NAME")" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --region "$AWS_REGION" \
  --route-table-id "$PRIV_RT_1_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id "$NAT_GW_1_ID"

aws ec2 create-route \
  --region "$AWS_REGION" \
  --route-table-id "$PRIV_RT_2_ID" \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id "$NAT_GW_2_ID"

aws ec2 associate-route-table \
  --region "$AWS_REGION" \
  --subnet-id "$PRIV_SUBNET_1_ID" \
  --route-table-id "$PRIV_RT_1_ID"

aws ec2 associate-route-table \
  --region "$AWS_REGION" \
  --subnet-id "$PRIV_SUBNET_2_ID" \
  --route-table-id "$PRIV_RT_2_ID"

cat <<EOF
Creation complete.
VPC_ID=$VPC_ID
IGW_ID=$IGW_ID
PUB_SUBNET_1_ID=$PUB_SUBNET_1_ID
PUB_SUBNET_2_ID=$PUB_SUBNET_2_ID
PRIV_SUBNET_1_ID=$PRIV_SUBNET_1_ID
PRIV_SUBNET_2_ID=$PRIV_SUBNET_2_ID
NAT_GW_1_ID=$NAT_GW_1_ID
NAT_GW_2_ID=$NAT_GW_2_ID
PUB_RT_1_ID=$PUB_RT_1_ID
PUB_RT_2_ID=$PUB_RT_2_ID
PRIV_RT_1_ID=$PRIV_RT_1_ID
PRIV_RT_2_ID=$PRIV_RT_2_ID
EOF

