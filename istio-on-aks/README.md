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

The Terraform code is organized in 2 distinct projects in the folders `aks-tf`
and `istio-tf`. This means you have to perform 2 `terraform apply` operations
[like it is explained in the Terraform documentation of the Kubernetes
provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#stacking-with-managed-kubernetes-cluster-resources)

```
cd aks-tf
cp tfvars .tfvars #customize anything
terraform init -upgrade
terraform apply -var-file=.tfvars
cd ../istio-tf
az aks get-credentials --resource-group istio-aks --name istio-aks
terraform init -upgrade
terraform apply
```

Note: you need `kubectl` installed for this Terraform code to run correctly.

The AKS cluster was created with 3 nodepools: `system` `user` and `ingress`.
The Istio control plane is scheduled on the `system` nodepool.
The Istio ingress gateway are scheduled on the `ingress` nodepool.
The `user` nodepool will host the other workloads.

The Istio ingressgateway is not exposed directly to the Internet.  It is
possible to [connect Azure Front Door Premium to an internal load balancer
origin with Private Link](Connect Azure Front Door Premium to an internal load
balancer origin with Private Link). Because the internal load balancer that
exposes the istio ingressgateway is created by a Kubernetes Service of type
LoadBalancer, I leveraged the AKS [Azure Private Link Service
Integration](https://cloud-provider-azure.sigs.k8s.io/topics/pls-integration/)

To interact with the control plane you will need a tool called `istioctl`.
You can install it like this:

```
curl -sL https://istio.io/downloadIstioctl | ISTIO_VERSION=1.17.1 sh -
export PATH=$HOME/.istioctl/bin:$PATH
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

This IP is a private IP address from an Internal Load Balancer, because the Kubernetes
Service to expose the istio-ingressgateway Deployment is annotated with [`service.beta.kubernetes.io/azure-load-balancer-internal`](https://github.com/zioproto/istio-aks-example/blob/b75aeba3ac0c80c83f9a07170d5f75a69cfac80c/istio-on-aks/istio-tf/istio.tf#L71).

Even if you had a VM running in the same VNET, trying to connect to this IP
will result in a connection refused, Envoy does not have any configuration and
will not bind to the TCP ports.

Lets configure now a Gateway resource:

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

After doing this we can see the gateway will listen on port 80 and will serve a HTTP 404.

```
istioctl proxy-config listener -n istio-ingress $(kubectl get pod -n istio-ingress -oname| head -n 1)
```
You can test the HTTP 404 from a pod or vm in the same VNET:

```
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

Before Azure Front Door is actually able to deliver traffic to the Istio
ingress gateway we must make sure the Health Check probes are successfull. Our
Terraform deployed the orgin group with the following health probe:

https://github.com/zioproto/istio-aks-example/blob/b75aeba3ac0c80c83f9a07170d5f75a69cfac80c/istio-on-aks/istio-tf/afd.tf#L35-L40

Envoy has a health check probe service on port 15021, let's create a virtual service to forward the Azure Front Door Health Check probes to the envoy port 15021:

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

At this point, we should be able to connect to our Front Door endpoint and see the output of the echoserver pod.

Check if you can reach the echoserver pod:
```
curl -v $(az afd endpoint list -g istio-aks --profile-name MyFrontDoor -o json | jq -r ".[0].hostName")
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

The file [prometheus.tf](prometheus.tf) installs the Helm community chart for
Prometheus and Grafana, and creates the configuration to scrape the Istio
sidecars.

Access the Grafana dashboard:

```
kubectl port-forward svc/prometheus-grafana 3000:80
```
And point your browser to http://127.0.0.1:3000

The default username is `admin` and  the default password is `prom-operator`.
This information is stored in the kubernetes secret:

```
kubectl get secret prometheus-grafana -o json | jq -r '.data."admin-password"' | base64 -d
prom-operator
kubectl get secret prometheus-grafana -o json | jq -r '.data."admin-user"' | base64 -d
admin
```

After logging into the Grafana web interface you can import these dashboards at
the following URL http://127.0.0.1:3000/dashboard/import

* https://grafana.com/grafana/dashboards/7645-istio-control-plane-dashboard/
* https://grafana.com/grafana/dashboards/7639-istio-mesh-dashboard/
* https://grafana.com/grafana/dashboards/7636-istio-service-dashboard/
* https://grafana.com/grafana/dashboards/7630-istio-workload-dashboard/
* https://grafana.com/grafana/dashboards/13277-istio-wasm-extension-dashboard/


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

