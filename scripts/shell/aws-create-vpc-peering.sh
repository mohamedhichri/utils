#!/usr/bin/env bash

set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-1}"

OWNER_TAG_KEY="DkuOwner"
OWNER_TAG_VALUE="mohamed.hichri@dataiku.com"
NAME_PREFIX="${NAME_PREFIX:-mhichri-}"

OLD_VPC_ID="${OLD_VPC_ID:-vpc-0352f09c865980a53}"
NEW_VPC_ID="${NEW_VPC_ID:-vpc-049706996019e55cf}"
PEERING_NAME="${PEERING_NAME:-${NAME_PREFIX}vpc-peering}"

old_cidr=$(aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --vpc-ids "$OLD_VPC_ID" \
  --query 'Vpcs[0].CidrBlock' \
  --output text)

new_cidr=$(aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --vpc-ids "$NEW_VPC_ID" \
  --query 'Vpcs[0].CidrBlock' \
  --output text)

if [[ "$old_cidr" == "None" || -z "$old_cidr" ]]; then
  echo "Could not determine CIDR for old VPC: $OLD_VPC_ID" >&2
  exit 1
fi

if [[ "$new_cidr" == "None" || -z "$new_cidr" ]]; then
  echo "Could not determine CIDR for new VPC: $NEW_VPC_ID" >&2
  exit 1
fi

if [[ "$old_cidr" == "$new_cidr" ]]; then
  echo "VPC CIDRs are identical: $old_cidr" >&2
  exit 1
fi

echo "Old VPC: $OLD_VPC_ID ($old_cidr)"
echo "New VPC: $NEW_VPC_ID ($new_cidr)"

PCX_ID=$(aws ec2 create-vpc-peering-connection \
  --region "$AWS_REGION" \
  --vpc-id "$OLD_VPC_ID" \
  --peer-vpc-id "$NEW_VPC_ID" \
  --tag-specifications "ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=$PEERING_NAME},{Key=$OWNER_TAG_KEY,Value=$OWNER_TAG_VALUE}]" \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)

aws ec2 accept-vpc-peering-connection \
  --region "$AWS_REGION" \
  --vpc-peering-connection-id "$PCX_ID" \
  --query 'VpcPeeringConnection.Status.Code' \
  --output text >/dev/null

mapfile -t old_route_tables < <(aws ec2 describe-route-tables \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$OLD_VPC_ID" \
  --query 'RouteTables[].RouteTableId' \
  --output text)

mapfile -t new_route_tables < <(aws ec2 describe-route-tables \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$NEW_VPC_ID" \
  --query 'RouteTables[].RouteTableId' \
  --output text)

if [[ ${#old_route_tables[@]} -eq 0 ]]; then
  echo "No route tables found for old VPC: $OLD_VPC_ID" >&2
  exit 1
fi

if [[ ${#new_route_tables[@]} -eq 0 ]]; then
  echo "No route tables found for new VPC: $NEW_VPC_ID" >&2
  exit 1
fi

for route_table_id in "${old_route_tables[@]}"; do
  if ! aws ec2 create-route \
    --region "$AWS_REGION" \
    --route-table-id "$route_table_id" \
    --destination-cidr-block "$new_cidr" \
    --vpc-peering-connection-id "$PCX_ID" >/dev/null 2>&1; then
    echo "Skipping route creation in $route_table_id for $new_cidr (already exists or conflicts)"
  else
    echo "Added route in $route_table_id to $new_cidr"
  fi
done

for route_table_id in "${new_route_tables[@]}"; do
  if ! aws ec2 create-route \
    --region "$AWS_REGION" \
    --route-table-id "$route_table_id" \
    --destination-cidr-block "$old_cidr" \
    --vpc-peering-connection-id "$PCX_ID" >/dev/null 2>&1; then
    echo "Skipping route creation in $route_table_id for $old_cidr (already exists or conflicts)"
  else
    echo "Added route in $route_table_id to $old_cidr"
  fi
done

cat <<EOF
Peering complete.
PCX_ID=$PCX_ID
OLD_VPC_ID=$OLD_VPC_ID
OLD_VPC_CIDR=$old_cidr
NEW_VPC_ID=$NEW_VPC_ID
NEW_VPC_CIDR=$new_cidr
EOF

