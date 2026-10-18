#!/bin/bash
cmd=$(jq -r '.tool_input.command // ""')
if echo "$cmd" | grep -Eq "sf project deploy (start|quick|resume)"; then
  echo "Blocked: deployments require human approval. Use sf project deploy validate instead." >&2
  exit 2
fi
exit 0
