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

  azure_monitor_workspace_integrations {
    resource_id = azapi_resource.prometheus.id
  }

  identity {
    type = "SystemAssigned"
  }
}

data "azurerm_subscription" "current" {}

# Give Managed Grafana instances access to read monitoring data in current subscription.
resource "azurerm_role_assignment" "monitoring_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

# https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-grafana
resource "azurerm_role_assignment" "monitoring_data_reader" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.this.identity[0].principal_id
}

data "azurerm_client_config" "current" {}

# Give current client admin access to Managed Grafana instance.
resource "azurerm_role_assignment" "grafana_admin" {
  scope                = azurerm_dashboard_grafana.this.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "kubectl_manifest" "ama_metrics_prometheus_config_configmap" {
  yaml_body  = <<YAML
# https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-scrape-configuration
# https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-scrape-validate#apply-config-file
# https://github.com/Azure/prometheus-collector/blob/main/otelcollector/configmaps/ama-metrics-prometheus-config-configmap.yaml
---
kind: ConfigMap
apiVersion: v1
data:
  prometheus-config: |-
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: 'kubernetes-pods'

        kubernetes_sd_configs:
        - role: pod

        relabel_configs:
        # Scrape only pods with the annotation: prometheus.io/scrape = true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true

        # If prometheus.io/path is specified, scrape this path instead of /metrics
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)

        # If prometheus.io/port is specified, scrape this port instead of the default
        - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
          action: replace
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: $1:$2
          target_label: __address__

        # If prometheus.io/scheme is specified, scrape with this scheme instead of http
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scheme]
          action: replace
          regex: (http|https)
          target_label: __scheme__

        # Include the pod namespace as a label for each metric
        - source_labels: [__meta_kubernetes_namespace]
          action: replace
          target_label: kubernetes_namespace

        # Include the pod name as a label for each metric
        - source_labels: [__meta_kubernetes_pod_name]
          action: replace
          target_label: kubernetes_pod_name

        # [Optional] Include all pod labels as labels for each metric
        - action: labelmap
          regex: __meta_kubernetes_pod_label_(.+)
metadata:
  name: ama-metrics-prometheus-config
  namespace: kube-system

YAML
}