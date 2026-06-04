{{/*
Common labels applied to all resources.
*/}}
{{- define "zdrive.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Selector labels for a specific component.
Usage: {{ include "zdrive.selectorLabels" (dict "component" "auth-service" "root" .) }}
*/}}
{{- define "zdrive.selectorLabels" -}}
app.kubernetes.io/name: zdrive
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Full image reference for a service.
Usage: {{ include "zdrive.image" (dict "registry" .Values.image.registry "repository" "zdrive-auth" "tag" .Values.image.tag) }}
*/}}
{{- define "zdrive.image" -}}
{{- if .registry -}}
{{ .registry }}/{{ .repository }}:{{ .tag }}
{{- else -}}
{{ .repository }}:{{ .tag }}
{{- end -}}
{{- end }}
