# https://medium.com/microsoftazure/deploying-azure-managed-prometheus-with-azapi-ef17e15acac8

# azure monitor workspace for prometheus
resource "azapi_resource" "prometheus" {
  type      = "microsoft.monitor/accounts@2021-06-03-preview"
  name      = "prometheus-istio-aks"
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location

  response_export_values = ["*"]
}

# data collection endpoint
resource "azapi_resource" "dataCollectionEndpoint" {
  type      = "Microsoft.Insights/dataCollectionEndpoints@2021-09-01-preview"
  name      = "MSProm-EUS-istio-aks"
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location

  body = jsonencode({
    kind       = "Linux"
    properties = {}
  })
}

resource "azapi_resource" "dataCollectionRule" {
  schema_validation_enabled = false

  type      = "Microsoft.Insights/dataCollectionRules@2021-09-01-preview"
  name      = "MSProm-EUS-istio-aks"
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location

  body = jsonencode({
    kind = "Linux"
    properties = {
      dataCollectionEndpointId = azapi_resource.dataCollectionEndpoint.id
      dataFlows = [
        {
          destinations = ["MonitoringAccount1"]
          streams      = ["Microsoft-PrometheusMetrics"]
        }
      ]
      dataSources = {
        prometheusForwarder = [
          {
            name               = "PrometheusDataSource"
            streams            = ["Microsoft-PrometheusMetrics"]
            labelIncludeFilter = {}
          }
        ]
      }
      destinations = {
        monitoringAccounts = [
          {
            accountResourceId = azapi_resource.prometheus.id
            name              = "MonitoringAccount1"
          }
        ]
      }
    }
  })
}

# associate our AKS cluster with this Azure Monitor workspace using the Data Collection Endpoint and Rule
resource "azapi_resource" "dataCollectionRuleAssociation" {
  schema_validation_enabled = false
  type                      = "Microsoft.Insights/dataCollectionRuleAssociations@2021-09-01-preview"
  name                      = "MSProm-EUS-istio-aks"
  parent_id                 = module.aks.aks_id

  body = jsonencode({
    scope = module.aks.aks_id
    properties = {
      dataCollectionRuleId = azapi_resource.dataCollectionRule.id
    }
  })
}



resource "azurerm_dashboard_grafana" "this" {
  name                              = "istio-grafana"
  resource_group_name               = azurerm_resource_group.this.name
  location                          = azurerm_resource_group.this.location
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true

  azure_monitor_workspace_integrations  {
      resource_id = azapi_resource.prometheus.id
    }


}