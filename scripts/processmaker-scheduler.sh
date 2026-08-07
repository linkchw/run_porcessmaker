#!/usr/bin/env bash
set -euo pipefail

app_root=${PROCESSMAKER_ROOT:-/opt/processmaker}
workspace=${PM_WORKSPACE:-workflow}
interval=${PM_SCHEDULER_INTERVAL_SECONDS:-60}
timezone=${PHP_DATE_TIMEZONE:-UTC}
bin_dir="$app_root/workflow/engine/bin"
bootstrap=/opt/nitel/processmaker-cron-bootstrap.php

if [[ ! "$workspace" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "scheduler: invalid PM_WORKSPACE" >&2
  exit 2
fi

if [[ ! "$interval" =~ ^[0-9]+$ ]] || ((interval < 10 || interval > 3600)); then
  echo "scheduler: PM_SCHEDULER_INTERVAL_SECONDS must be an integer from 10 to 3600" >&2
  exit 2
fi

if [[ ! "$timezone" =~ ^[A-Za-z0-9_+./-]+$ ]]; then
  echo "scheduler: invalid PHP_DATE_TIMEZONE" >&2
  exit 2
fi

if [[ ! -f "$bootstrap" ]]; then
  echo "scheduler: missing PHP compatibility bootstrap $bootstrap" >&2
  exit 2
fi

cron_scripts=(
  cron.php
  timereventcron.php
  messageeventcron.php
  sendnotificationscron.php
)

for script in "${cron_scripts[@]}"; do
  if [[ ! -f "$bin_dir/$script" ]]; then
    echo "scheduler: missing ProcessMaker command $bin_dir/$script" >&2
    exit 2
  fi
done

stop_requested=0
child_pid=

request_stop() {
  stop_requested=1
  if [[ -n "$child_pid" ]]; then
    kill -TERM "$child_pid" 2>/dev/null || true
  fi
}

trap request_stop INT TERM

run_cron() {
  local script=$1
  local exit_code
  local output_file

  echo "scheduler: starting $script for workspace $workspace"
  output_file=$(mktemp /tmp/nitel-scheduler-output.XXXXXX)
  php \
    -d "date.timezone=$timezone" \
    -d "auto_prepend_file=$bootstrap" \
    -f "$bin_dir/$script" "+w$workspace" +force \
    >"$output_file" 2>&1 &
  child_pid=$!
  if wait "$child_pid"; then
    exit_code=0
  else
    exit_code=$?
  fi
  child_pid=
  cat "$output_file"

  if ((stop_requested)); then
    rm -f "$output_file"
    return 0
  fi

  # ProcessMaker catches some fatal cron errors and still exits zero. Require
  # the launcher's completion marker and reject its known error markers.
  if ((exit_code != 0)) || \
    ! grep -Fq "Finished 1 workspaces processed" "$output_file" || \
    grep -Eq 'ID_EXCEPTION_LOG_INTERFAZ|Undefined constant|Problem in workspace:' "$output_file"; then
    echo "scheduler: $script did not complete successfully (status $exit_code)" >&2
    rm -f "$output_file"
    return 1
  fi

  rm -f "$output_file"
  echo "scheduler: finished $script"
}

echo "scheduler: running ProcessMaker tasks every ${interval}s"

while ((stop_requested == 0)); do
  cycle_failed=0
  for script in "${cron_scripts[@]}"; do
    if ! run_cron "$script"; then
      cycle_failed=1
    fi
    if ((stop_requested)); then
      break
    fi
  done

  if ((stop_requested)); then
    break
  fi

  if ((cycle_failed)); then
    echo "scheduler: cycle completed with one or more command failures" >&2
  else
    echo "scheduler: cycle completed successfully"
  fi

  sleep "$interval" &
  child_pid=$!
  if ! wait "$child_pid"; then
    :
  fi
  child_pid=
done

echo "scheduler: stopped"
