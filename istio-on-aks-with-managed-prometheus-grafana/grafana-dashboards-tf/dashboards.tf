# https://grafana.com/grafana/dashboards/7645-istio-control-plane-dashboard/
resource "grafana_dashboard" "istio_control_plane_dashboard" {
  config_json = file("dashboards/7645.json")
}

# https://grafana.com/grafana/dashboards/7639-istio-mesh-dashboard/
resource "grafana_dashboard" "istio_mesh_dashboard" {
  config_json = file("dashboards/7639.json")
}

# https://grafana.com/grafana/dashboards/7636-istio-service-dashboard/
resource "grafana_dashboard" "istio_service_dashboard" {
  config_json = file("dashboards/7636.json")
}

# https://grafana.com/grafana/dashboards/7630-istio-workload-dashboard/
resource "grafana_dashboard" "istio_workload_dashboard" {
  config_json = file("dashboards/7630.json")
}

# https://grafana.com/grafana/dashboards/13277-istio-wasm-extension-dashboard/
resource "grafana_dashboard" "istio_wasm_extension_dashboard" {
  config_json = file("dashboards/13277.json")
}