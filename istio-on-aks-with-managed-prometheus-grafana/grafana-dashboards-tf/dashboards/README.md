# Istio Grafana Dashboards

This downloads local json data for the following dashboards:

* https://grafana.com/grafana/dashboards/7645-istio-control-plane-dashboard/
* https://grafana.com/grafana/dashboards/7639-istio-mesh-dashboard/
* https://grafana.com/grafana/dashboards/7636-istio-service-dashboard/
* https://grafana.com/grafana/dashboards/7630-istio-workload-dashboard/
* https://grafana.com/grafana/dashboards/13277-istio-wasm-extension-dashboard/

Run:

```
for id in 7645 7639 7636 7630 13277 ; do curl -s https://grafana.com/api/dashboards/${id}/revisions/latest/download | jq . > ${id}.json ; done

# Fix the json https://github.com/grafana/grafana/issues/10786#issuecomment-1277000930
sed -i  's/${DS_PROMETHEUS}/prometheus-istio-aks/g' *.json # on MacOS use gsed
```
