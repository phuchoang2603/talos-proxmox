{{- define "tenants.namespaces" -}}
{{- range .purposes }}{{ ternary $.id (printf "%s-%s" $.id .) (eq . "") }} {{ end -}}
{{- end -}}

{{- define "tenants.secretReader" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
rules:
  - apiGroups: [""]
    resources: [secrets]
    resourceNames: [{{ .secret | quote }}]
    verbs: [get]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ .name }}
subjects:
  - kind: ServiceAccount
    name: {{ .name }}
    namespace: {{ .namespace }}
{{- end -}}

{{- define "tenants.kubernetesStore" -}}
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
spec:
  provider:
    kubernetes:
      remoteNamespace: {{ .remoteNamespace }}
      server:
        url: https://kubernetes.default.svc
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
      auth:
        serviceAccount:
          name: {{ .serviceAccount }}
          namespace: {{ .remoteNamespace }}
{{- end -}}
