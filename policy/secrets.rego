package main

import rego.v1

deny contains msg if {
	input.kind == "ClusterSecretStore"
	input.metadata.name != "doppler"
	not tenant_store(input)
	msg := sprintf("ClusterSecretStore %s: only the platform doppler store and doppler-<tenant> stores restricted to that tenant are allowed", [input.metadata.name])
}

tenant_store(store) if {
	tenant := trim_prefix(store.metadata.name, "doppler-")
	tenant != store.metadata.name
	some condition in store.spec.conditions
	condition.namespaceSelector.matchLabels["platform.phuchoang.sbs/tenant"] == tenant
}
