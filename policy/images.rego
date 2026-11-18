package main

import rego.v1

pod_specs contains input.spec if input.kind == "Pod"

pod_specs contains input.spec.template.spec if input.kind in {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}

pod_specs contains input.spec.jobTemplate.spec.template.spec if input.kind == "CronJob"

containers contains container if {
	some spec in pod_specs
	some key in {"containers", "initContainers", "ephemeralContainers"}
	some container in spec[key]
}

helm_test if input.metadata.annotations["helm.sh/hook"] == "test"

pinned(image) if regex.match(`@sha256:[a-f0-9]{64}$`, image)

pinned(image) if {
	regex.match(`:[^/:@]+$`, image)
	not endswith(image, ":latest")
}

deny contains msg if {
	not helm_test
	some container in containers
	container.image != "auto"
	not pinned(container.image)
	msg := sprintf("%s %s: image %q needs an explicit non-latest tag or a digest", [input.kind, input.metadata.name, container.image])
}
