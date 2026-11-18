package main

import rego.v1

test_secret_store_denied if count(deny) == 1 with input as {"kind": "SecretStore", "metadata": {"name": "s"}}

test_cluster_secret_store_allowed if count(deny) == 0 with input as {"kind": "ClusterSecretStore", "metadata": {"name": "doppler"}}

test_external_secret_cluster_store_allowed if count(deny) == 0 with input as {
	"kind": "ExternalSecret",
	"metadata": {"name": "e"},
	"spec": {"secretStoreRef": {"kind": "ClusterSecretStore", "name": "doppler"}},
}

test_external_secret_default_kind_denied if count(deny) == 1 with input as {
	"kind": "ExternalSecret",
	"metadata": {"name": "e"},
	"spec": {"secretStoreRef": {"name": "doppler"}},
}

test_external_secret_namespaced_store_denied if count(deny) == 1 with input as {
	"kind": "ExternalSecret",
	"metadata": {"name": "e"},
	"spec": {"secretStoreRef": {"kind": "SecretStore", "name": "doppler"}},
}
