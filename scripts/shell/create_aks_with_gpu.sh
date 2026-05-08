RG="mhichri-rg-3"
CLUSTER="myAKSCluster"
LOCATION="eastus"
TAG="DkuOwner=mohamed.hichri@dataiku.com"

az group create \
  --name $RG \
  --location $LOCATION \
  --tags $TAG


az aks create \
  --resource-group $RG \
  --name $CLUSTER \
  --tier free \
  --node-count 1 \
  --node-vm-size Standard_B2s \
  --node-osdisk-size 32 \
  --os-sku AzureLinux \
  --tags $TAG \
  --generate-ssh-keys

#check aks cluster creation completed : 
az aks show \
  --resource-group $RG \
  --name $CLUSTER \
  --query "provisioningState" \
  --output tsv


az aks nodepool add \
  --resource-group $RG \
  --cluster-name $CLUSTER \
  --name gpunp \
  --node-count 0 \
  --node-vm-size Standard_NC4as_T4_v3 \
  --node-osdisk-size 32 \
  --os-sku AzureLinux \
  --node-taints sku=gpu:NoSchedule \
  --enable-cluster-autoscaler \
  --min-count 0 \
  --max-count 1 \
  --tags $TAG


az aks get-credentials \
  --resource-group $RG \
  --name $CLUSTER

# Once a GPU pod is scheduled and node spins up:
kubectl get nodes -o wide
kubectl describe node <gpu-node-name> | grep -A 10 "Allocatable"
