# Running Istio on AKS

The goal is to look at Istio installation and operation on Azure Kubernetes Service.

Istio is a service mesh that helps you to encrypt, route, and observe traffic
in your Kubernetes cluster. Istio uses Envoy, an HTTP proxy implementation
that can be configured via an API rather than configuration files.

Generally speaking Istio uses Envoy in 2 roles:
* gateways: at the border of the sevice mesh
* sidecars: an envoy container added to an existing pod.

The Envoy containers at boot will register to the control plane: the
`istiod` deployment in the `istio-system` namespace.  The configuration is
expressed with Istio CRDs, that `istiod` will read to push the
proper envoy configuration to the proxies that registered to the control plane.

## Install istio

Running the Terraform code provided in this repo will provision an AKS cluster,
and using the Terraform Helm provider Istio will be installed using the
[helm installation method](https://istio.io/latest/docs/setup/install/helm/).

The Terraform code is organized in 3 distinct projects in the folders `aks-tf`, `istio-tf` and
`grafana-dashboards-tf`. This means you have to perform 3 `terraform apply` operations
[like it is explained in the Terraform documentation of the Kubernetes
provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#stacking-with-managed-kubernetes-cluster-resources).
The reason is that you can't configure the Terraform Grafana provider until the
Grafana instance is deployed. In the same way you cannot configure the Helm
and Kubernetes providers until the AKS cluster is deployed. If you use Terraform
interpolation to configure the providers, intermittent and unpredictable errors
will occur, because of the order in which Terraform itself evaluates the provider
blocks and resources.


```
# Deploy the AKS cluster and the Managed Prometheus and Grafana
cd aks-tf
cp tfvars .tfvars #customize anything
terraform init -upgrade
terraform apply -var-file=.tfvars
# Deploy the additional Grafana Dashboards
cd ../grafana-dashboards-tf
export GRAFANA_NAME=$(az grafana list -g istio-aks -o json | jq -r '.[0].name')
export TF_VAR_url=$(az grafana show -g istio-aks -n $GRAFANA_NAME -o json | jq -r .properties.endpoint)
export TF_VAR_token=$(az grafana api-key create --key `date +%s` --name $GRAFANA_NAME -g istio-aks -r editor --time-to-live 4m -o json | jq -r .key)
terraform apply
# Install Istio
cd ../istio-tf
az aks get-credentials --resource-group istio-aks --name istio-aks --overwrite-existing
terraform init -upgrade
terraform apply
```

Note: you need `kubectl` installed for this Terraform code to run correctly.

The AKS cluster was created with 3 nodepools: `system` `user` and `ingress`.
The Istio control plane is scheduled on the `system` nodepool.
The Istio ingress gateway are scheduled on the `ingress` nodepool.
The `user` nodepool will host the other workloads.

To interact with the control plane you will need a tool called `istioctl`.
You can install it like this:

```
curl -sL https://istio.io/downloadIstioctl | ISTIO_VERSION=1.17.1 sh -
export PATH=$HOME/.istioctl/bin:$PATH
```

You will of course need `kubectl` and you can get credentials for the cluster
with the command:

```
az aks get-credentials --resource-group istio-aks --name istio-aks
```

## Injecting the sidecar

Istio uses the sidecars. The [sidecar
injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/)
means that the API call to create a Pod is intercepted by a [mutating webhook
admission
controller](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
and the sidecar containers are added to the Pod. The are 2 containers added,
the `istio-init` and the `istio-proxy`. When looking at the istio sidecars
remember to look at the Pod with `kubectl get pod -o yaml`. Do not look at the
`deployment`, because there you will not find any information about the
sidecars. The sidecar is injected when the deployment controller makes an API
call to create a Pod.

The `istio-init` container is privileged, because it runs `iptables` rules in
the pod namespace to intercept the traffic. For this reason you cannot use with
Istio the [AKS virtual
nodes](https://learn.microsoft.com/en-us/azure/aks/virtual-nodes).

Later you can read how to configure the sidecars with the crd `sidecars.networking.istio.io`.

To enable all pods in a given namespace to be injected with the sidecar, just label the namespace:

```
kubectl label namespace default istio-injection=enabled
```

Lets run a simple `echoserver` workload in the default namespace:

```
kubectl apply -f - <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echoserver
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      run: echoserver
  template:
    metadata:
      labels:
        run: echoserver
    spec:
      containers:
      - name: echoserver
        image: gcr.io/google_containers/echoserver:1.10
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: echoserver
  namespace: default
spec:
  ports:
  - port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    run: echoserver
EOF
```
Is possible to check if the sidecar registered to the control plan with the command `istioctl proxy-status`.

## Configure a gateway

The Terraform provisioning code created a `istio-ingress` namespace where a `Deployment: istio-ingress` is present.

The [Gateway](https://istio.io/latest/docs/reference/config/networking/gateway/) is an envoy pod at the border of the service mesh.

The `gateways.networking.istio.io` CRD lets you configure the envoy listener.

When you dont have any `gateway` resource in the cluster the envoy configuration will be basically empty.
You can see this with the `istioctl proxy-config` command.

```
istioctl proxy-config listener -n istio-ingress $(kubectl get pod -n istio-ingress -oname| head -n 1)
```

The gateway is exposed with a Kubernetes service with `type: LoadBalancer`, you can get the IP address:

```
kubectl get service -n istio-ingress istio-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

However trying to connect to this IP will result in a connection refused, Envoy
does not have any configuration and will not bind to the TCP ports.

Lets configure now  a Gateway resource:

```
kubectl apply -f - <<EOF
---
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: istio-ingressgateway
  namespace: istio-ingress
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - '*'
EOF
```

After doing this we can see the gateway will listen on port 80 and will serve a HTTP 404:

```
istioctl proxy-config listener -n istio-ingress $(kubectl get pod -n istio-ingress -oname| head -n 1)
curl -v $(kubectl get service -n istio-ingress istio-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

The HTTP 404 response code is expected, because Envoy does not know to which service this request should be routed.

## The virtual service

The `virtualservices.networking.istio.io` describes how a request is routed to a service.

To route requests to the echoserver `ClusterIP` service created in the default namespace,
create the following VirtualService:


```
kubectl apply -f - <<EOF
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: echoserver
  namespace: default
spec:
  hosts:
    - "*"
  gateways:
    - istio-ingress/istio-ingressgateway
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: "echoserver.default.svc.cluster.local"
        port:
          number: 8080
EOF
  ```

Check if you can reach the echoserver pod:
```
curl -v $(kubectl get service -n istio-ingress istio-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

Envoy has a health check probe on port 15021, let's create a virtual service test this:

```
kubectl apply -f - <<EOF
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: healthcheck
  namespace: istio-ingress
spec:
  hosts:
    - "*"
  gateways:
    - istio-ingress/istio-ingressgateway
  http:
  - match:
    - uri:
        prefix: "/probe"
    rewrite:
        uri: "/healthz/ready"
    route:
    - destination:
        host: "istio-ingress.istio-ingress.svc.cluster.local"
        port:
          number: 15021
EOF
  ```
To get more information on how to write a `VirtualService` resource the source of truth is the API docs:
https://pkg.go.dev/istio.io/api/networking/v1beta1

# Use PeerAuthentications to enforce mTLS

With the crd `peerauthentications.security.istio.io` [you can enforce mTLS](https://istio.io/latest/docs/reference/config/security/peer_authentication/).

```
kubectl apply -f - <<EOF
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF
```

It is important to remember that with `PeerAuthentication` you enforce always mTLS at the receiver of the TLS connection.
To enforce at the client you need a [Destination Rule](https://istio.io/latest/docs/reference/config/networking/destination-rule/).

## Destination Rules

The [Destination Rule](https://istio.io/latest/docs/reference/config/networking/destination-rule/) makes possible to apply policies for a destination when a client starts a connection.

For example applying the following `DestinationRule` the mTLS protocol is enforced when any client starts a connection. This means that the istio ingress gateway will not be able to connect to a backend without a sidecar:

```
kubectl apply -f - <<EOF
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: force-client-mtls
  namespace: istio-system
spec:
  host: "*"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF
```

The Destination Rules are also used for Load Balancing.

## Verify that the traffic is encrypted

To verify mTLS you can use tcpdump from an AKS node. To get a privileges shell
in the host namespace of an AKS node the easiest way is to use
[nsenter](https://github.com/alexei-led/nsenter).

```
wget https://raw.githubusercontent.com/alexei-led/nsenter/master/nsenter-node.sh
bash nsenter-node.sh $(kubectl get pod -l run=echoserver -o jsonpath='{.items[0].spec.nodeName}')
tcpdump -i eth0 -n -c 15 -X port 8080
```
## Observability

The file [prometheus.tf](prometheus.tf) configures Azure Managed Prometheus and
Azure Managed Grafana.

Access the Grafana dashboard:

```
az grafana show -g istio-aks --name istio-grafana -o json | jq .properties.endpoint
```
And point your browser to the URL displayed by this command.

The identity that created the infrastructure with Terraform is configured as Grafana Admin.

After logging into the Grafana web interface you should see the following dashboards,
that were installed with Terraform:

* https://grafana.com/grafana/dashboards/7645-istio-control-plane-dashboard/
* https://grafana.com/grafana/dashboards/7639-istio-mesh-dashboard/
* https://grafana.com/grafana/dashboards/7636-istio-service-dashboard/
* https://grafana.com/grafana/dashboards/7630-istio-workload-dashboard/
* https://grafana.com/grafana/dashboards/13277-istio-wasm-extension-dashboard/

If you configured the `PeerAuthentication` to enforce mTLS ( `STRICT` ) you will not
see any traffic in the Grafana dashboards, because the scraping of the metrics is not happening
over mTLS and the envoy sidecars are refusing the scraping connection attempts.
To fix this you can configure the `PeerAuthentication` to `DISABLE` on the specific scraping 15020 TCP port:

```
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: allow-scraping
  namespace: default
spec:
  selector:
    matchLabels:
      run: echoserver
  mtls:
    mode: STRICT
  portLevelMtls:
    15020:
      mode: DISABLE
```

## Authorization Policies

The [authorization policies](https://istio.io/latest/docs/reference/config/security/authorization-policy/) can allow or deny requests
depending on some [conditions](https://istio.io/latest/docs/reference/config/security/conditions/).

Here we just make an example, in the istio-ingress we allow requests to the
istio ingressgateway only if the request is to the nip.io domain.  The
[nip.io](https://nip.io) is a free simple wildcard DNS service for IP address,
that is very convenient for this kind of example.

```
kubectl apply -f - <<EOF
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: probe
  namespace: istio-ingress
spec:
  action: ALLOW
  rules:
  - to:
    - operation:
        hosts: ["*.nip.io"]
  selector:
    matchLabels:
      istio: ingressgateway
EOF
```

When the policy is in place you should get a HTTP 403 for:
`curl -v $(kubectl get service -n istio-ingress istio-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')/`

but if you append the nip.io domain the HTTP request should successfull ( 404 ):
`curl -v $(kubectl get service -n istio-ingress istio-ingress -o=jsonpath='{.status.loadBalancer.ingress[0].ip}').nip.io/`


## Service Entries

Istio uses Kubernetes Services to create Envoy clusters. In case you need to address external services, or if you extended the Service Mesh to VMs outside of kubernetes where you are running legacy workloads, you can use the following CRDs:

* `serviceentries.networking.istio.io`
* `workloadentries.networking.istio.io`
* `workloadgroups.networking.istio.io`

If you are not using VMs you will need just [https://istio.io/latest/docs/reference/config/networking/service-entry/](https://istio.io/latest/docs/reference/config/networking/service-entry/)

# IstioOperator

The crd `istiooperators.install.istio.io` is used to describe the Istio configuration

# TODO

This tutorial still does not cover the following CRDs:

* sidecars.networking.istio.io
* envoyfilters.networking.istio.io
* proxyconfigs.networking.istio.io
* requestauthentications.security.istio.io
* telemetries.telemetry.istio.io
* wasmplugins.extensions.istio.io

