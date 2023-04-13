#!/bin/sh
cd gateway-kustomize
cat > base.yaml
exec kubectl kustomize # you can also use "kustomize build ." if you have it installed.
