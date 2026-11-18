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
# Needs: jq, mikefarah yq v4
set -euo pipefail

# Kept out on purpose:
#   bindings - written by the scheduler; a Fail webhook could block pod scheduling
#   events   - Capsule's own matchConditions ignore events
#   leases   - leader election / node heartbeats; AKS calls these out for stop/start
EXCLUDE='^(bindings|events|leases)$'

if [[ $# -ge 1 ]]; then input=$(cat "$1"); else
  input=$(kubectl api-resources --namespaced=true --verbs=create -o name); fi

# "deployments.apps" -> resource=deployments group=apps ; "pods" -> group=""
pairs=$(awk -F. '{r=$1; g=substr($0, length($1)+2); print r"\t"g}' <<<"$input" \
  | awk -F'\t' -v ex="$EXCLUDE" '$1 !~ ex')

export API_GROUPS=$(cut -f2 <<<"$pairs" | sort -u | jq -R . | jq -sc .)
export RESOURCES=$(cut -f1 <<<"$pairs" | sort -u | jq -R . | jq -sc .)

yq -n '
  .x = {"apiGroups": env(API_GROUPS), "apiVersions": ["*"], "resources": env(RESOURCES)} |
  .cud = ["CREATE","UPDATE","DELETE"] | .cu = ["CREATE","UPDATE"] |
  .webhooks.hooks.generic.rules = [.x * {"operations": .cu, "scope": "Namespaced"}] |
  .webhooks.hooks.globalresourcequotas.rules = [
     .x * {"operations": .cu, "scope": "Namespaced"},
     {"apiGroups": ["capsule.clastix.io"], "apiVersions": ["v1beta2"], "operations": .cu,
      "resources": ["globalresourcequotas"], "scope": "Cluster"}] |
  .webhooks.hooks.cordoning.rules = [.x * {"operations": .cud, "scope": "Namespaced"}] |
  .webhooks.hooks.managed.rules = [
     .x * {"operations": .cud, "scope": "Namespaced"},
     {"apiGroups": [""], "apiVersions": ["v1"], "operations": .cud,
      "resources": ["namespaces"], "scope": "Cluster"},
     {"apiGroups": ["capsule.clastix.io"], "apiVersions": ["v1beta2"], "operations": .cud,
      "resources": ["globalresourcequotas"], "scope": "Cluster"}] |
  .webhooks.hooks.replications.rules = [.x * {"operations": .cud, "scope": "*"}] |
  .webhooks.hooks.metadata.rules = [.x * {"operations": .cu, "scope": "Namespaced"}] |
  .webhooks.hooks.customresources.enabled = false |
  del(.x, .cud, .cu)
'
