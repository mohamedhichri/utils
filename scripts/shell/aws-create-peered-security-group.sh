#!/usr/bin/env bash

set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-1}"
NEW_VPC_ID="${NEW_VPC_ID:-vpc-049706996019e55cf}"
OLD_SG_ID="${OLD_SG_ID:-sg-054b3a7e0a6d40bfe}"
PCX_ID="${PCX_ID:-pcx-0c686953d7167c245}"

OWNER_TAG_KEY="DkuOwner"
OWNER_TAG_VALUE="mohamed.hichri@dataiku.com"
NAME_PREFIX="${NAME_PREFIX:-mhichri-}"

NEW_SG_NAME="${NEW_SG_NAME:-${NAME_PREFIX}allow-old-vpc-instance}"
NEW_SG_DESCRIPTION="${NEW_SG_DESCRIPTION:-Allow all inbound traffic from old VPC EC2 security group}"
ADD_EGRESS_RULE="${ADD_EGRESS_RULE:-true}"

echo "Creating security group in VPC $NEW_VPC_ID in region $AWS_REGION"
NEW_SG_ID=$(aws ec2 create-security-group \
  --region "$AWS_REGION" \
  --vpc-id "$NEW_VPC_ID" \
  --group-name "$NEW_SG_NAME" \
  --description "$NEW_SG_DESCRIPTION" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$NEW_SG_NAME},{Key=$OWNER_TAG_KEY,Value=$OWNER_TAG_VALUE}]" \
  --query 'GroupId' \
  --output text)

echo "Created security group: $NEW_SG_ID"

echo "Authorizing inbound traffic from source security group $OLD_SG_ID via peering $PCX_ID"
aws ec2 authorize-security-group-ingress \
  --region "$AWS_REGION" \
  --group-id "$NEW_SG_ID" \
  --ip-permissions "IpProtocol=-1,UserIdGroupPairs=[{GroupId=$OLD_SG_ID,VpcPeeringConnectionId=$PCX_ID,Description=\"All traffic from old VPC EC2 SG\"}]"

if [[ "$ADD_EGRESS_RULE" == "true" ]]; then
  echo "Authorizing outbound traffic back to source security group $OLD_SG_ID via peering $PCX_ID"
  aws ec2 authorize-security-group-egress \
    --region "$AWS_REGION" \
    --group-id "$NEW_SG_ID" \
    --ip-permissions "IpProtocol=-1,UserIdGroupPairs=[{GroupId=$OLD_SG_ID,VpcPeeringConnectionId=$PCX_ID,Description=\"All traffic to old VPC EC2 SG\"}]"
fi

cat <<EOF
Security group creation complete.
NEW_SG_ID=$NEW_SG_ID
NEW_SG_NAME=$NEW_SG_NAME
NEW_VPC_ID=$NEW_VPC_ID
OLD_SG_ID=$OLD_SG_ID
PCX_ID=$PCX_ID
AWS_REGION=$AWS_REGION
EOF

