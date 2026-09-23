{{/*
Selector labels
*/}}
{{- define "pccs.selectorLabels" -}}
app: {{ .Release.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "pccs.labels" -}}
{{ include "pccs.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Secret holding the PCCS server certificate (tls.crt / tls.key), mounted into
the pod. Defaults to the chart's cert-manager Certificate.
*/}}
{{- define "pccs.serverTlsSecret" -}}
{{- if .Values.tls.serverSecretName -}}
{{ .Values.tls.serverSecretName }}
{{- else if .Values.certManager.enabled -}}
{{ printf "%s-tls" (.Release.Name | default "pccs") }}
{{- else -}}
{{ fail "certManager.enabled is false: set tls.serverSecretName to a Secret holding the PCCS server certificate (keys tls.crt and tls.key)" }}
{{- end -}}
{{- end -}}

{{/*
Secret holding the certificate the ingress controller serves for
ingress.host. Defaults to the chart's cert-manager Certificate.
*/}}
{{- define "pccs.ingressTlsSecret" -}}
{{- if .Values.ingress.tlsSecretName -}}
{{ .Values.ingress.tlsSecretName }}
{{- else if .Values.certManager.enabled -}}
{{ printf "%s-ingress-tls" (.Release.Name | default "pccs") }}
{{- else -}}
{{ fail "certManager.enabled is false: set ingress.tlsSecretName to a Secret holding the certificate for ingress.host" }}
{{- end -}}
{{- end -}}

{{/*
Secret whose ca.crt the ingress controller uses to verify the PCCS server
certificate on the backend connection. Empty means no CA is available.
*/}}
{{- define "pccs.backendCaSecret" -}}
{{- if .Values.tls.caSecretName -}}
{{ .Values.tls.caSecretName }}
{{- else if and .Values.certManager.enabled (eq .Values.certManager.issuer.type "selfSigned") (not .Values.tls.serverSecretName) -}}
{{ printf "%s-tls" (.Release.Name | default "pccs") }}
{{- end -}}
{{- end -}}
