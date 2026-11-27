package main

import rego.v1

deny contains msg if {
	input.kind == "AppProject"
	object.get(input.metadata, ["labels", "platform.phuchoang.sbs/tenant"], "") != ""
	count(object.get(input.spec, "clusterResourceWhitelist", [])) > 0
	msg := sprintf("AppProject %s: tenant projects must not allow cluster-scoped resources", [input.metadata.name])
}
