{{/*
Expand the name of the chart.
*/}}
{{- define "tidb-data-pipeline.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "tidb-data-pipeline.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tidb-data-pipeline.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tidb-data-pipeline.labels" -}}
helm.sh/chart: {{ include "tidb-data-pipeline.chart" . }}
{{ include "tidb-data-pipeline.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tidb-data-pipeline.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tidb-data-pipeline.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component labels
*/}}
{{- define "tidb-data-pipeline.componentLabels" -}}
{{- $component := .component -}}
{{- with .context -}}
{{ include "tidb-data-pipeline.labels" . }}
app.kubernetes.io/component: {{ $component }}
{{- end -}}
{{- end }}

{{/*
Component selector labels
*/}}
{{- define "tidb-data-pipeline.componentSelectorLabels" -}}
{{- $component := .component -}}
{{- with .context -}}
{{ include "tidb-data-pipeline.selectorLabels" . }}
app.kubernetes.io/component: {{ $component }}
{{- end -}}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "tidb-data-pipeline.serviceAccountName" -}}
{{- if .Values.rbac.serviceAccount.create }}
{{- default (include "tidb-data-pipeline.fullname" .) .Values.rbac.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.rbac.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Common pod annotations
*/}}
{{- define "tidb-data-pipeline.podAnnotations" -}}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
prometheus.io/scrape: "true"
{{- with .Values.podAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Common pod security context
*/}}
{{- define "tidb-data-pipeline.podSecurityContext" -}}
{{- if .Values.global.security.podSecurityContext }}
{{ toYaml .Values.global.security.podSecurityContext }}
{{- end }}
{{- end }}

{{/*
Common container security context
*/}}
{{- define "tidb-data-pipeline.containerSecurityContext" -}}
{{- if .Values.global.security.containerSecurityContext }}
{{ toYaml .Values.global.security.containerSecurityContext }}
{{- end }}
{{- end }}

{{/*
Common node selector
*/}}
{{- define "tidb-data-pipeline.nodeSelector" -}}
{{- if .Values.global.nodeSelector }}
{{ toYaml .Values.global.nodeSelector }}
{{- end }}
{{- end }}

{{/*
Common tolerations
*/}}
{{- define "tidb-data-pipeline.tolerations" -}}
{{- if .Values.global.tolerations }}
{{ toYaml .Values.global.tolerations }}
{{- end }}
{{- end }}

{{/*
Common affinity
*/}}
{{- define "tidb-data-pipeline.affinity" -}}
{{- if .Values.global.affinity }}
{{ toYaml .Values.global.affinity }}
{{- else }}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            {{- include "tidb-data-pipeline.selectorLabels" . | nindent 12 }}
        topologyKey: kubernetes.io/hostname
{{- end }}
{{- end }}

{{/*
Image pull secrets
*/}}
{{- define "tidb-data-pipeline.imagePullSecrets" -}}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.global.imagePullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Storage class
*/}}
{{- define "tidb-data-pipeline.storageClass" -}}
{{- if .Values.global.persistence.storageClass }}
{{- if (eq "-" .Values.global.persistence.storageClass) }}
storageClassName: ""
{{- else }}
storageClassName: {{ .Values.global.persistence.storageClass | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Health check probes
*/}}
{{- define "tidb-data-pipeline.livenessProbe" -}}
{{- if .Values.healthChecks.enabled }}
livenessProbe:
  {{- toYaml .Values.healthChecks.livenessProbe | nindent 2 }}
{{- end }}
{{- end }}

{{- define "tidb-data-pipeline.readinessProbe" -}}
{{- if .Values.healthChecks.enabled }}
readinessProbe:
  {{- toYaml .Values.healthChecks.readinessProbe | nindent 2 }}
{{- end }}
{{- end }}

{{/*
PodDisruptionBudget settings
*/}}
{{- define "tidb-data-pipeline.podDisruptionBudget" -}}
{{- $component := .component -}}
{{- $values := .values -}}
{{- with .context -}}
{{- if $values.podDisruptionBudget.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "tidb-data-pipeline.fullname" . }}-{{ $component }}
  labels:
    {{- include "tidb-data-pipeline.componentLabels" (dict "component" $component "context" .) | nindent 4 }}
spec:
  minAvailable: {{ $values.podDisruptionBudget.minAvailable }}
  selector:
    matchLabels:
      {{- include "tidb-data-pipeline.componentSelectorLabels" (dict "component" $component "context" .) | nindent 6 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Resource limits and requests
*/}}
{{- define "tidb-data-pipeline.resources" -}}
{{- if .resources }}
resources:
  {{- toYaml .resources | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Environment variables from ConfigMap and Secret
*/}}
{{- define "tidb-data-pipeline.envFrom" -}}
envFrom:
  - configMapRef:
      name: {{ include "tidb-data-pipeline.fullname" . }}-config
  - secretRef:
      name: {{ include "tidb-data-pipeline.fullname" . }}-secret
      optional: true
{{- end }}

{{/*
Persistent volume claim template
*/}}
{{- define "tidb-data-pipeline.volumeClaimTemplate" -}}
{{- $name := .name -}}
{{- $size := .size -}}
{{- $storageClass := .storageClass -}}
- metadata:
    name: {{ $name }}
  spec:
    accessModes:
      - ReadWriteOnce
    {{- if $storageClass }}
    {{- if (eq "-" $storageClass) }}
    storageClassName: ""
    {{- else }}
    storageClassName: {{ $storageClass | quote }}
    {{- end }}
    {{- end }}
    resources:
      requests:
        storage: {{ $size }}
{{- end }}