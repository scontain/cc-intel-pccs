{{/*
Selector labels
*/}}
{{- define "pccs.selectorLabels" -}}
app: {{ .Release.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Require independent SHA-512 token hashes; never accept the published examples. */}}
{{- define "pccs.tokenHash" -}}
{{- $hash := required (printf "pccsConfig.%s must be set to the SHA-512 hash of a randomly generated token" .name) .value | toString | lower -}}
{{- if not (regexMatch "^[0-9a-f]{128}$" $hash) -}}
{{- fail (printf "pccsConfig.%s must contain exactly 128 hexadecimal characters" .name) -}}
{{- end -}}
{{- if or (eq $hash "31a556961f3438f9f632ca27812d22228e98e5083eea2bf9b78d0bb374d44deb0dc4d1bc16ab64127eb74e8452ea6902d97937c28310a7ab62a9ae1c15d96d69") (eq $hash "6ae2d3bfb3b95517b358fcdb29f7743246101ebf13f797d8244df795eec2d1d769a41c059dc37beadac8e40cecab4352764336a90302920ddeb1a6c6df4e8a00") -}}
{{- fail (printf "pccsConfig.%s uses a published example token; generate and configure a new token" .name) -}}
{{- end -}}
{{- $hash -}}
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
{{- else if and .Values.certManager.enabled (eq .Values.certManager.issuer.type "acme") -}}
{{ fail "certManager.issuer.type is acme, which cannot issue the PCCS server certificate: its names (<release>.<namespace>.svc, ...) exist only inside the cluster, so no public ACME CA will sign them and the pods would wait for it forever. Set tls.serverSecretName to a Secret holding it (keys tls.crt and tls.key); acme still issues the ingress certificate." }}
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
Secrets whose ca.crt the ingress controller uses to verify the PCCS server
certificate on the backend connection, as a JSON list. Empty means no CA is
available.

With the chart's own CA, "<release>-ca" always holds the current CA
certificate; the ca.crt copy in "<release>-tls" is only refreshed when the
server certificate is reissued, so it can expire first. "<release>-tls" stays
in the list for releases whose CA was re-keyed by an earlier chart version
and whose server certificate was signed with the old key.
*/}}
{{- define "pccs.backendCaSecrets" -}}
{{- $release := .Release.Name | default "pccs" -}}
{{- if .Values.tls.caSecretName -}}
{{ list .Values.tls.caSecretName | toJson }}
{{- else if and .Values.certManager.enabled (eq .Values.certManager.issuer.type "selfSigned") (not .Values.tls.serverSecretName) -}}
{{ list (printf "%s-ca" $release) (printf "%s-tls" $release) | toJson }}
{{- else -}}
[]
{{- end -}}
{{- end -}}
