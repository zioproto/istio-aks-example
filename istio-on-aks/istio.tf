
resource "helm_release" "istio-base" {
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = "true"
  name             = "istio-base"
  version          = "1.17.1"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  #force_update     = var.force_update
  #recreate_pods    = var.recreate_pods
}

resource "helm_release" "istiod" {
  depends_on        = [helm_release.istio-base]
  name              = "istiod"
  namespace         = "istio-system"
  dependency_update = true
  repository        = "https://istio-release.storage.googleapis.com/charts"
  chart             = "istiod"
  version           = "1.17.1"
  atomic            = true
  lint              = true

  postrender {
    binary_path = "${path.module}/istiod-kustomize/kustomize.sh"
    args        = ["${path.module}"]
  }
  values = [
    yamlencode(
      {
        meshConfig = {
          accessLogFile = "/dev/stdout"
        }
      }
    )
  ]
}

# $ helm install istio-ingress istio/gateway -n istio-ingress --wait

resource "helm_release" "istio-ingress" {
  depends_on        = [helm_release.istio-base, helm_release.istiod, azurerm_kubernetes_cluster_node_pool.ingress]
  name              = "istio-ingress"
  namespace         = "istio-ingress"
  create_namespace  = "true"
  dependency_update = true
  repository        = "https://istio-release.storage.googleapis.com/charts"
  chart             = "gateway"
  version           = "1.17.1"
  atomic            = true
  postrender {
    binary_path = "${path.module}/gateway-kustomize/kustomize.sh"
    args        = ["${path.module}"]
  }
  values = [
    yamlencode(
      {
        labels = {
          app   = ""
          istio = "ingressgateway"
        }
        service = {
          annotations = {
            "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
          }
        }
      }
    )
  ]
  lint = true
}
