{{/*
Chart name.
*/}}
{{- define "news-explorer.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/*
Resource name. Kept as the plain chart name (not release-name-prefixed) — this chart is
installed exactly once per environment as "news-explorer", never side-by-side with itself
under a different release name.
*/}}
{{- define "news-explorer.fullname" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "news-explorer.labels" -}}
app.kubernetes.io/name: {{ include "news-explorer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels — deliberately a subset of the labels above (no version/managed-by): these
go on spec.selector too, and selectors must stay stable across upgrades that only bump
appVersion or switch managed-by.
*/}}
{{- define "news-explorer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "news-explorer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
