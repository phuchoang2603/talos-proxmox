package main

import rego.v1

deny contains msg if {
	input.kind == "SecretStore"
	msg := sprintf("SecretStore %s: secrets are delivered through a ClusterSecretStore", [input.metadata.name])
}

deny contains msg if {
	input.kind in {"ExternalSecret", "ClusterExternalSecret", "PushSecret"}
	ref := object.get(input.spec, ["externalSecretSpec", "secretStoreRef"], object.get(input.spec, "secretStoreRef", {}))
	object.get(ref, "kind", "SecretStore") != "ClusterSecretStore"
	msg := sprintf("%s %s: secretStoreRef must have kind ClusterSecretStore", [input.kind, input.metadata.name])
}
