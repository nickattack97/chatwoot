#!/usr/bin/env bash
# Appends one line to the deployment audit log on the host: when, which job, which release, who started it, how it ended.
# GITLAB_USER_LOGIN is whoever started the job; for a manual job it is the person who pressed play.
# Called from after_script, so a failed or cancelled job is recorded too. Append-only; no secrets; never fails the job.
# For production, ship this file to the central log as well: a file on the host is append-only by convention only.
set -uo pipefail

log="${HELPENGINE_AUDIT_LOG:-${DEPLOY_DIR:-.}/deploy-audit.log}"
status="${1:-${CI_JOB_STATUS:-unknown}}"
tag="${CI_COMMIT_TAG:-}"
release="${ROLLBACK_VERSION:-${tag#helpengine-v}}"
# Form fields can carry anything: strip to safe characters so a value cannot forge a second line.
release="$(printf '%s' "$release" | tr -cd 'A-Za-z0-9._-')"

line="$(printf '%s env=%s job=%s status=%s release=%s user=%s pipeline=%s job_id=%s commit=%s' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${CI_ENVIRONMENT_NAME:-none}" "${CI_JOB_NAME:-unknown}" "$status" "$release" \
  "${GITLAB_USER_LOGIN:-unknown}" "${CI_PIPELINE_ID:-unknown}" "${CI_JOB_ID:-unknown}" "${CI_COMMIT_SHORT_SHA:-unknown}")"

echo "AUDIT $line"
( umask 027; printf '%s\n' "$line" >> "$log" ) || echo "WARNING: could not write the audit log $log" >&2
exit 0
