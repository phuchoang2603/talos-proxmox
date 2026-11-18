package main

import rego.v1

helm_test if contains(input.metadata.annotations["helm.sh/hook"], "test")

deny contains msg if {
	not helm_test
	walk(input, [path, image])
	path[count(path) - 1] == "image"
	is_string(image)
	endswith(image, ":latest")
	msg := sprintf("%s %s: image %q must not use the latest tag", [input.kind, input.metadata.name, image])
}
