apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ .Values.tunnel.existingSecret }}
  namespace: {{ .Release.Namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  refreshInterval: {{ .Values.tunnel.refreshInterval }}
  secretStoreRef:
    kind: ClusterSecretStore
    name: doppler
  target:
    name: {{ .Values.tunnel.existingSecret }}
  data:
    - secretKey: {{ .Values.tunnel.existingSecretKey }}
      remoteRef:
        key: {{ .Values.tunnel.dopplerKey }}
