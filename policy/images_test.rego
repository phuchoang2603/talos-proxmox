package main

import rego.v1

deployment(image) := {
	"kind": "Deployment",
	"metadata": {"name": "app"},
	"spec": {"template": {"spec": {"containers": [{"name": "c", "image": image}]}}},
}

test_tag_allowed if count(deny) == 0 with input as deployment("ghcr.io/org/app:v1.2.3")

test_registry_port_without_tag_denied if count(deny) == 1 with input as deployment("localhost:5000/app")

test_digest_allowed if count(deny) == 0 with input as deployment("app@sha256:0000000000000000000000000000000000000000000000000000000000000000")

test_untagged_denied if count(deny) == 1 with input as deployment("busybox")

test_latest_denied if count(deny) == 1 with input as deployment("busybox:latest")

test_init_container_checked if count(deny) == 1 with input as {
	"kind": "StatefulSet",
	"metadata": {"name": "app"},
	"spec": {"template": {"spec": {
		"containers": [{"name": "c", "image": "app:v1"}],
		"initContainers": [{"name": "i", "image": "busybox"}],
	}}},
}

test_cronjob_checked if count(deny) == 1 with input as {
	"kind": "CronJob",
	"metadata": {"name": "app"},
	"spec": {"jobTemplate": {"spec": {"template": {"spec": {"containers": [{"name": "c", "image": "app"}]}}}}},
}

test_helm_test_hook_exempt if count(deny) == 0 with input as {
	"kind": "Pod",
	"metadata": {"name": "t", "annotations": {"helm.sh/hook": "test"}},
	"spec": {"containers": [{"name": "c", "image": "busybox"}]},
}

test_injected_sidecar_placeholder_allowed if count(deny) == 0 with input as deployment("auto")
