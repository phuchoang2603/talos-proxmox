package main

import rego.v1

deny contains msg if {
	input.kind == "ClusterSecretStore"
	input.metadata.name != "doppler"
	msg := sprintf("ClusterSecretStore %s: the platform owns only the doppler store; tenants use namespaced SecretStores", [input.metadata.name])
}
