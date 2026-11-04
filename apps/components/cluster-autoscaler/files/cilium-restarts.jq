[
  .items[] as $cilium
  | $nodes[0].items[]
  | select(.metadata.name == $cilium.metadata.name)
  | select(.metadata.labels["talos.dev/nodepool"] != "controlplane")
  | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"
      and (($now - (.lastTransitionTime | fromdateiso8601)) > 120)))
  | [.status.addresses[]? | select(.type == "InternalIP") | .address][0] as $ip
  | [$cilium.spec.addresses[]? | select(.type == "InternalIP") | .ip][0] as $old
  | select($ip != null and $old != null and $old != $ip)
  | .metadata.name as $node
  | $pods[0].items[]
  | select(.spec.nodeName == $node and .metadata.deletionTimestamp == null)
  | select(.status.phase == "Running")
  | select(any(.status.containerStatuses[]?; .name == "cilium-agent"
      and .state.running.startedAt != null
      and (($now - (.state.running.startedAt | fromdateiso8601)) > 120)))
  | {node: $node, pod: .metadata.name, uid: .metadata.uid,
      version: .metadata.resourceVersion, ip: $ip, old: $old}
] | sort_by(.node) | .[0] // empty
