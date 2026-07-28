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

{{/*
Postgres connection env vars — shared between deployment.yaml and migrate-job.yaml so the two
can't drift apart (a Job talking to a different DB than the app it migrated for defeats the
point). See values.yaml's postgres.* comment for what each value points at.
*/}}
{{- define "news-explorer.postgresEnv" -}}
- name: POSTGRES_HOST
  value: {{ .Values.postgres.host | quote }}
- name: POSTGRES_PORT
  value: {{ .Values.postgres.port | quote }}
- name: POSTGRES_DB_NAME
  value: {{ .Values.postgres.dbName | quote }}
- name: POSTGRES_USER
  value: {{ .Values.postgres.user | quote }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgres.existingSecret }}
      key: {{ .Values.postgres.secretPasswordKey }}
{{- end -}}
