package main

import rego.v1

deny contains msg if {
	walk(input, [path, image])
	path[count(path) - 1] == "image"
	is_string(image)
	endswith(image, ":latest")
	msg := sprintf("%s %s: image %q must not use the latest tag", [input.kind, input.metadata.name, image])
}
