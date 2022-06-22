# Multicluster Istio on AKS

## Deploy Kubernetes clusters

The Terraform code in this repository is a demo that will deploy 2 AKS clusters in the regions westeurope and eastus.
The Azure Virtual Networks are going to be connected with a Virtual Network Peering.
The AKS clusters have multiple Node Pools and each node pools has a dedicated subnet.
The Istio CA is managed offline and the cluster certificates are stored in Azure Key Vault.

To run the Terraform code:

```
cp  tfvars .tfvars
vim .tfvars #customize if needed
terraform init -upgrade && terraform apply -var-file=.tfvars
```

Get clusters credentials:

```
az aks get-credentials --resource-group istio-aks-westeurope --name westeurope-aks
az aks get-credentials --resource-group istio-aks-eastus --name eastus-aks
```

Test credentials:

```
kubectl --context=eastus-aks get nodes
kubectl --context=westeurope-aks get nodes

```

## Istio CA

By default the Istio installation creates a self signed CA. Two Istio installations with two different self-signed CA cannot trust each other.
For this reason the first step to deploy Istio in multicluster is to create a Certification Authority that will be trusted by both clusters.

This is documented in detail here:
https://istio.io/latest/docs/tasks/security/cert-management/plugin-ca-cert/

Short summary:

```
git clone git@github.com:istio/istio.git
cd istio
mkdir certs
cd certs
make -f ../tools/certs/Makefile.selfsigned.mk root-ca
make -f ../tools/certs/Makefile.selfsigned.mk westeurope-aks-cacerts
make -f ../tools/certs/Makefile.selfsigned.mk eastus-aks-cacerts
```

This will create a Root CA and certificate per each cluster.

## Istio CA with Key Vault

Now we want to store the cluster certificates we created at the previous step into Azure Key Vault.

Store the CA Certificate first: we are going to store only the certificate and not the private key that we want to keep offline:

```
export keyvaultname=$(az keyvault list -g keyvault-rg -o json |jq -r '.[0].name')
az keyvault secret set --vault-name $keyvaultname --name root-cert -f root-cert.pem
```

Combine the cluster certificate and the key in a single file and upload the certificate to Azure Key Vault:
```
for cluster in eastus-aks westeurope-aks ; do
( cd $cluster &&
cat ca-cert.pem ca-key.pem > ca-cert-and-key.pem &&
az keyvault secret set --vault-name $keyvaultname --name $cluster-cert-chain --file cert-chain.pem &&
az keyvault certificate import --vault-name $keyvaultname -n $cluster-ca-cert -f ca-cert-and-key.pem );
done
```

Now we create the Service Provider Class that will allow us to consume secrets from the Azure Key Vault.
The Service Provider Class needs to stay in the istio-system namespace that we create now:

```
for cluster in eastus-aks westeurope-aks ; do kubectl create --context=$cluster namespace istio-system; done
terraform output -raw secret-provider-class-eastus | kubectl --context=eastus-aks -n istio-system apply -f -
terraform output -raw secret-provider-class-westeurope | kubectl --context=westeurope-aks -n istio-system apply -f -
```

## Install Istio in the clusters

Lets create the `istio-ingress` namespace to install the Istio Ingressgateways for the North/South traffic, and lets enable injection in this namespace.

```
kubectl create --context=eastus-aks ns istio-ingress
kubectl label --context=eastus-aks ns istio-ingress istio.io/rev=1-14-1
kubectl create --context=westeurope-aks ns istio-ingress
kubectl label --context=westeurope-aks ns istio-ingress istio.io/rev=1-14-1
```

We are now ready to install istio on both clusters:


```
(cd istio-installation &&
istioctl install -y \
  --context=eastus-aks \
  --set profile=minimal \
  --revision=1-14-1 \
  --set tag=1.14.1 \
  -f 001-accessLogFile.yaml \
  -f 002-multicluster-eastus.yaml \
  -f 003-istiod-csi-secrets.yaml \
  -f 004-ingress-gateway.yaml &&
istioctl install -y \
  --context=westeurope-aks \
  --set profile=minimal \
  --revision=1-14-1 \
  --set tag=1.14.1 \
  -f 001-accessLogFile.yaml \
  -f 002-multicluster-westeurope.yaml \
  -f 003-istiod-csi-secrets.yaml \
  -f 004-ingress-gateway.yaml
)
```

# Configure the remote endpoints secret

This step configures in each cluster the secret to reach the other one. Note that the Kubernetes secret contains also the cluster endpoint, it is like a `kubectl configuration`.

```
istioctl x create-remote-secret --context=westeurope-aks --name=westeurope-aks | k apply -f - --context=eastus-aks
istioctl x create-remote-secret --context=eastus-aks --name=eastus-aks | k apply -f - --context=westeurope-aks
```

# Validate

At this point verify that the clusters are connected and synced:

```
$ istioctl remote-clusters --context=eastus-aks
NAME               SECRET                                              STATUS     ISTIOD
westeurope-aks     istio-system/istio-remote-secret-westeurope-aks     synced     istiod-1-14-1-689c9f5f7-n9r4p

$ istioctl remote-clusters --context=westeurope-aks
NAME           SECRET                                          STATUS     ISTIOD
eastus-aks     istio-system/istio-remote-secret-eastus-aks     synced     istiod-1-14-1-67d5b5fdfc-nm6w5
```

Let's deploy a echoserver and let's access it from the other cluster.

We are going to create a deployment `echoserver` only in westeurope. The service `echoserver` will be created in both regions, because this will make possible to resolve the DNS name echoserver.

```
kubectl create --context=eastus-aks ns echoserver
kubectl label --context=eastus-aks ns echoserver istio.io/rev=1-14-1
kubectl create --context=westeurope-aks ns echoserver
kubectl label --context=westeurope-aks ns echoserver istio.io/rev=1-14-1
kubectl apply --context=westeurope-aks -n echoserver -f istio-installation/echoserver.yaml -f istio-installation/echoserver-svc.yaml
kubectl apply --context=eastus-aks -n echoserver -f istio-installation/echoserver-svc.yaml
```

Now lets access the echoserver from the remote cluster in eastus:

```
kubectl run --context=eastus-aks -ti curlclient --image=nicolaka/netshoot /bin/bash
$ curl echoserver:8080
```
