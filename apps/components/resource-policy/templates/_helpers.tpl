{{- define "resource-policy.memory" -}}
variables.{{ . }}.map(c,
  has(c.resources.limits) && 'memory' in c.resources.limits ? c.resources.limits['memory'] :
  has(c.resources.requests) && 'memory' in c.resources.requests ? c.resources.requests['memory'] : '')
{{- end -}}

{{- define "resource-policy.patches" -}}
{{- $f := .field -}}
{{- $m := printf "variables.%s" .memory -}}
{{- $l := printf "variables.%s" .list -}}
lists.range(size({{ $l }})).map(i,
  (has({{ $l }}[i].resources.limits) && 'cpu' in {{ $l }}[i].resources.limits
    ? [JSONPatch{op: 'remove', path: '/spec/{{ $f }}/' + string(i) + '/resources/limits/cpu'}] : []) +
  ({{ $m }}[i] != '' && !(has({{ $l }}[i].resources.requests) && 'memory' in {{ $l }}[i].resources.requests && {{ $l }}[i].resources.requests['memory'] == {{ $m }}[i])
    ? [has({{ $l }}[i].resources.requests)
        ? JSONPatch{op: 'add', path: '/spec/{{ $f }}/' + string(i) + '/resources/requests/memory', value: {{ $m }}[i]}
        : JSONPatch{op: 'add', path: '/spec/{{ $f }}/' + string(i) + '/resources/requests', value: {'memory': {{ $m }}[i]}}] : []) +
  ({{ $m }}[i] != '' && !(has({{ $l }}[i].resources.limits) && 'memory' in {{ $l }}[i].resources.limits)
    ? [has({{ $l }}[i].resources.limits)
        ? JSONPatch{op: 'add', path: '/spec/{{ $f }}/' + string(i) + '/resources/limits/memory', value: {{ $m }}[i]}
        : JSONPatch{op: 'add', path: '/spec/{{ $f }}/' + string(i) + '/resources/limits', value: {'memory': {{ $m }}[i]}}] : [])
).flatten()
{{- end -}}
