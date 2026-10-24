{{- define "observability.logParsers" -}}
- type: container
  id: container-parser
  max_log_size: 102400
- type: json_parser
  id: json-body
  if: 'body matches "^\\{"'
  on_error: send_quiet
- type: key_value_parser
  id: logfmt-body
  if: 'body matches "^time="'
  on_error: send_quiet
- type: add
  id: structured-level
  if: "attributes.level != nil or attributes.severity != nil or attributes.severity_text != nil or (attributes.c != nil and attributes.s != nil)"
  field: attributes.parsed_level
  value: EXPR(attributes.level ?? attributes.severity ?? attributes.severity_text ?? attributes.s)
- type: regex_parser
  id: timestamp-level
  if: 'attributes.parsed_level == nil and body matches "^(\\x1b\\[[0-9;]*m)*\\[?[0-9]{4}[-.]"'
  regex: '(?i)^(?:\x1b\[[0-9;]*m)*\[?\d{4}[-.]\d{2}[-.]\d{2}[T ][0-9:.,]+Z?(?:\x1b\[[0-9;]*m|\s)*(?P<parsed_level>trace|debug|info|warn(?:ing)?|error|fatal|panic)\b'
  on_error: send_quiet
- type: regex_parser
  id: klog-level
  if: 'attributes.parsed_level == nil and body matches "^[IWEF][0-9]{4}\\s"'
  regex: '^(?P<parsed_level>[IWEF])\d{4}\s'
  on_error: send_quiet
- type: regex_parser
  id: clickhouse-level
  if: 'attributes.parsed_level == nil and body matches "^[0-9]{4}\\."'
  regex: '^\d{4}\.\d{2}\.\d{2} [0-9:.]+ \[\s*\d+\s*\] \{[^}]*\} <(?P<parsed_level>\w+)>'
  on_error: send_quiet
- type: regex_parser
  id: redis-level
  if: 'attributes.parsed_level == nil and body matches "^[0-9]+:[A-Z] "'
  regex: '^\d+:[A-Z] \d{2} \w{3} \d{4} [0-9:.]+ (?P<parsed_level>[.*#-]) '
  on_error: send_quiet
- type: severity_parser
  id: normalized-level
  if: "attributes.parsed_level != nil"
  parse_from: attributes.parsed_level
  overwrite_text: true
  mapping:
    debug: [D, D1, D2, D3, D4, D5, '.', '-']
    info: [I, '*']
    warn: [W, '#']
    error: [E]
    fatal: [F]
  on_error: send_quiet
- type: remove
  id: remove-parsed-level
  if: "attributes.parsed_level != nil"
  field: attributes.parsed_level
- type: trace_parser
  id: json-trace
  if: "attributes.trace_id != nil"
  trace_id:
    parse_from: attributes.trace_id
  span_id:
    parse_from: attributes.span_id
  on_error: send_quiet
- type: move
  id: json-msg
  if: "attributes.msg != nil"
  from: attributes.msg
  to: body
{{- end -}}
