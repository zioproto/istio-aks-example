#helm install alb-controller oci://mcr.microsoft.com/application-lb/charts/alb-controller \
#     --version 0.4.023971 \
#     --set albController.podIdentity.clientID=$(az identity show -g $RESOURCE_GROUP -n azure-alb-identity --query clientId -o tsv)

data azurerm_user_assigned_identity azure_alb_identity {
    name                = "azure-alb-identity"
    resource_group_name = "istio-aks"
}

resource "helm_release" "alb-controller" {
  chart            = "alb-controller"
  namespace        = "azure-alb-system"
  create_namespace = "true"
  name             = "alb-controller"
  version          = "1.3.7"
  repository       = "oci://mcr.microsoft.com/application-lb/charts/"
  atomic           = "true"
  values = [
    yamlencode({
      albController = {
        podIdentity = {
          clientID = data.azurerm_user_assigned_identity.azure_alb_identity.client_id
        }
      }
    })
  ]
}
