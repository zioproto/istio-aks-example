# Grafana Dashboards

Configure the Grafana URL, and generate a Token that expires in 4 minutes:
```
export TF_VAR_url=$(az grafana list -g istio-aks -o json | jq -r '.[0].properties.endpoint')
export GRAFANA_NAME=$(az grafana list -g testing-observability-rg -o json | jq -r '.[0].name')
export TF_VAR_token=$(az grafana api-key create --key `date +%s` --name $GRAFANA_NAME -g istio-aks -r editor --time-to-live 4m -o json | jq -r .key)
```

Run Terraform

```
terraform apply
```
