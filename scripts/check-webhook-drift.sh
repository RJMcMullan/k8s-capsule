#!/usr/bin/env bash
# Check whether Capsule and the AKS admissions enforcer are fighting over
# capsule-dynamic-webhook (projectcapsule/capsule#2233).
#
# A generation that keeps climbing between two reads means the webhook is
# being rewritten in a loop. A stable generation means the fight has stopped.
#
# Usage: scripts/check-webhook-drift.sh [seconds-between-reads]   (default 20)
set -euo pipefail

WAIT=${1:-20}
NAME=capsule-dynamic-webhook

for kind in validatingwebhookconfiguration mutatingwebhookconfiguration; do
  echo "== $kind/$NAME"
  g1=$(kubectl get "$kind" "$NAME" -o jsonpath='{.metadata.generation}')
  sleep "$WAIT"
  g2=$(kubectl get "$kind" "$NAME" -o jsonpath='{.metadata.generation}')
  echo "generation: $g1 -> $g2 (+$((g2 - g1)) in ${WAIT}s)"
  if (( g2 > g1 )); then echo "STILL CHANGING: Capsule and AKS are likely fighting"; else echo "stable"; fi

  echo "namespaceSelector per webhook:"
  kubectl get "$kind" "$NAME" \
    -o jsonpath='{range .webhooks[*]}  {.name}: {.namespaceSelector}{"\n"}{end}'
  echo
done
