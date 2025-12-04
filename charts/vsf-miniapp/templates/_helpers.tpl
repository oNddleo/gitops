{{/*
Expand the name of the chart.
*/}}
{{- define "vsf-miniapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We include serviceName to differentiate between services using the same chart.
*/}}
{{- define "vsf-miniapp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- printf "%s-%s" .Release.Name .Values.serviceName | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s-%s" .Release.Name $name .Values.serviceName | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "vsf-miniapp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vsf-miniapp.labels" -}}
helm.sh/chart: {{ include "vsf-miniapp.chart" . }}
{{ include "vsf-miniapp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.serviceName }}
service: {{ .Values.serviceName }}
{{- end }}
{{- if .Values.language }}
language: {{ .Values.language }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vsf-miniapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vsf-miniapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Values.serviceName }}
service: {{ .Values.serviceName }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vsf-miniapp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (printf "%s" .Values.serviceName) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
