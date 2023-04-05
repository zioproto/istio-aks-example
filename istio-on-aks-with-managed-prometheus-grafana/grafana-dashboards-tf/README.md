# Grafana Dashboards

Configure the Grafana URL, and generate a Token that expires in 4 minutes:
```
export TF_VAR_url=$(az grafana show -g istio-aks -n istio-grafana -o json | jq -r .properties.endpoint)
export TF_VAR_token=$(az grafana api-key create --key `date +%s` --name istio-grafana -g istio-aks -r editor --time-to-live 4m -o json | jq -r .key)
```

Run Terraform

```
terraform apply
```