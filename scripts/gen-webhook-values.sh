#!/usr/bin/env bash
# Generate Capsule 0.15.2 webhook rule overrides with NO wildcards, so
# `az aks stop` accepts the cluster.
#
# Builds one rule per hook from the namespaced resources the cluster serves:
#   apiGroups = every API group that has namespaced resources
#   resources = every namespaced resource name (explicit, no * or */*)
#
# Usage: scripts/gen-webhook-values.sh [api-resources.txt] > helm/values-capsule-webhooks.yaml
#   With no file it runs: kubectl api-resources --namespaced=true --verbs=create -o name
# Needs: jq
set -euo pipefail

# Kept out on purpose:
#   bindings - written by the scheduler; a Fail webhook could block pod scheduling
#   events   - Capsule's own matchConditions ignore events
#   leases   - leader election / node heartbeats; AKS calls these out for stop/start
EXCLUDE='^(bindings|events|leases)$'

if [[ $# -ge 1 ]]; then input=$(cat "$1"); else
  input=$(kubectl api-resources --namespaced=true --verbs=create -o name); fi
input=$(tr -d '\r' <<<"$input")

# "deployments.apps" -> resource=deployments group=apps ; "pods" -> group=""
pairs=$(awk -F. -v ex="$EXCLUDE" '$1 !~ ex {g=substr($0, length($1)+2); print $1"\t"g}' <<<"$input")

G=$(cut -f2 <<<"$pairs" | sort -u | jq -R . | jq -sc .)
R=$(cut -f1 <<<"$pairs" | sort -u | jq -R . | jq -sc .)

cat <<YAML
webhooks:
  hooks:
    generic:
      rules:
        - apiGroups: &groups $G
          apiVersions: ["*"]
          operations: ["CREATE", "UPDATE"]
          resources: &resources $R
          scope: Namespaced

    globalresourcequotas:
      rules:
        - apiGroups: *groups
          apiVersions: ["*"]
          operations: ["CREATE", "UPDATE"]
          resources: *resources
          scope: Namespaced
        - apiGroups: ["capsule.clastix.io"]
          apiVersions: ["v1beta2"]
          operations: ["CREATE", "UPDATE"]
          resources: ["globalresourcequotas"]
          scope: Cluster

    cordoning:
      rules:
        - apiGroups: *groups
          apiVersions: ["*"]
          operations: ["CREATE", "UPDATE", "DELETE"]
          resources: *resources
          scope: Namespaced

    managed:
      rules:
        - apiGroups: *groups
          apiVersions: ["*"]
          operations: ["CREATE", "UPDATE", "DELETE"]
          resources: *resources
          scope: Namespaced
        - apiGroups: [""]
          apiVersions: ["v1"]
          operations: ["CREATE", "UPDATE", "DELETE"]
          resources: ["namespaces"]
          scope: Cluster
        - apiGroups: ["capsule.clastix.io"]
          apiVersions: ["v1beta2"]
          operations: ["CREATE", "UPDATE", "DELETE"]
          resources: ["globalresourcequotas"]
          scope: Cluster

    replications:
      rules:
        - apiGroups: *groups
          apiVersions: ["*"]
          operations: ["CREATE", "UPDATE", "DELETE"]
          resources: *resources
          scope: "*"

    metadata:
      rules:
        - apiGroups: *groups
          apiVersions: ["*"]
          operations: ["CREATE", "UPDATE"]
          resources: *resources
          scope: Namespaced

    # Rules are hard-coded as wildcards in the chart, so this can't be narrowed.
    # Only needed for legacy tenant-annotation custom resource quotas.
    customresources:
      enabled: false
YAML
