#!/bin/bash
set -u

LOCK_FILE=/run/auto-clean.lock
[ -d /run ] || LOCK_FILE=/var/run/auto-clean.lock
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date '+%F %T') auto-clean is already running; skip."
  exit 1
fi

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
LOG_FILE=/var/log/auto-clean.log
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

size_human() {
  if [ -e "$1" ]; then
    du -sh "$1" 2>/dev/null | awk '{print $1}'
  else
    printf '0'
  fi
}

remove_apt_lists() {
  [ -d /var/lib/apt/lists ] || return 0
  find /var/lib/apt/lists -mindepth 1 -maxdepth 1 \
    ! -name lock ! -name partial \
    -exec rm -rf -- {} + 2>/dev/null || true
}

clean_old_tmp() {
  dir=$1
  [ -d "$dir" ] || return 0

  find "$dir" -xdev -mindepth 1 \
    \( -name 'systemd-private-*' -o -name '.*-unix' \) -prune -o \
    -type f -mtime +7 -print -exec rm -f -- {} + 2>/dev/null || true

  find "$dir" -xdev -mindepth 1 \
    \( -name 'systemd-private-*' -o -name '.*-unix' \) -prune -o \
    -type d -empty -mtime +7 -print -exec rmdir -- {} + 2>/dev/null || true
}

remove_file_if_benchmark() {
  file=$1
  [ -f "$file" ] || return 0
  if grep -IqiE 'nodequality|geekbench|lemonbench|unixbench|superbench|yabs|fio|iperf3|speedtest|bench\.sh|vpsbench|serverreview' "$file" 2>/dev/null; then
    printf '%s\n' "$file"
    rm -f -- "$file" 2>/dev/null || true
  fi
}

clean_benchmark_leftovers() {
  log 'delete benchmark leftovers and benchmark scripts'

  find /root /tmp /var/tmp -xdev -maxdepth 2 \
    \( -type d \( -iname '.nodequality*' -o -iname 'nodequality*' -o -iname 'NodeQuality*' -o -iname '*LemonBench*' -o -iname '*UnixBench*' -o -iname '*Geekbench*' \) \
       -o -type f \( -iname '.gb*_tmp.swap' -o -iname 'gb*_tmp.swap' -o -iname 'geekbench*.tar.gz' -o -iname 'geekbench*.zip' \) \) \
    -print -exec rm -rf -- {} + 2>/dev/null || true

  find /root /tmp /var/tmp -xdev -maxdepth 1 -type f \
    \( -iname 'nodequality*.sh' -o -iname 'NodeQuality*.sh' \
       -o -iname 'yabs.sh' -o -iname 'superbench.sh' -o -iname 'superbench*.sh' \
       -o -iname 'lemonbench*.sh' -o -iname 'unixbench*.sh' -o -iname 'nench.sh' \
       -o -iname 'vpsbench*.sh' -o -iname 'serverreview*.sh' \) \
    -print -delete 2>/dev/null || true

  find /root /tmp /var/tmp -xdev -maxdepth 1 -type f \
    \( -iname 'bench.sh' -o -iname 'benchtest.sh' -o -iname 'ecs.sh' \) \
    -print0 2>/dev/null | while IFS= read -r -d '' file; do
      remove_file_if_benchmark "$file"
    done
}

configure_journald_limit() {
  [ -d /etc/systemd ] || return 0
  mkdir -p /etc/systemd/journald.conf.d
  conf=/etc/systemd/journald.conf.d/99-auto-clean.conf
  tmp=$(mktemp /tmp/auto-clean-journald.XXXXXX)
  cat > "$tmp" <<'JOURNAL'
[Journal]
SystemMaxUse=30M
RuntimeMaxUse=30M
MaxRetentionSec=14day
JOURNAL

  if [ ! -f "$conf" ] || ! cmp -s "$tmp" "$conf"; then
    cat "$tmp" > "$conf"
    rm -f "$tmp"
    systemctl restart systemd-journald >/dev/null 2>&1 || true
  else
    rm -f "$tmp"
  fi
}

trim_clean_log() {
  [ -f "$LOG_FILE" ] || return 0
  tmp=$(mktemp /tmp/auto-clean-log.XXXXXX)
  if tail -n 300 "$LOG_FILE" > "$tmp"; then
    cat "$tmp" > "$LOG_FILE"
  fi
  rm -f "$tmp"
}

log '>>> auto-clean v8.3 start'
DF_BEFORE=$(df -h / | awk 'NR==2 {print $3 "/" $2 " used (" $5 ")"}')
VAR_LOG_BEFORE=$(size_human /var/log)
TMP_BEFORE=$(size_human /tmp)
JOURNAL_BEFORE=$(journalctl --disk-usage 2>/dev/null | sed -n 's/^.*take up //p' || true)
log "before: /=$DF_BEFORE /var/log=$VAR_LOG_BEFORE /tmp=$TMP_BEFORE journal=${JOURNAL_BEFORE:-unknown}"

if command -v apt-get >/dev/null 2>&1; then
  if pgrep -x apt >/dev/null 2>&1 || pgrep -x apt-get >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1 || pgrep -x unattended-upgr >/dev/null 2>&1; then
    log 'skip apt cleanup because apt/dpkg appears active'
  else
    log 'clean apt cache, stale package lists, and auto-removable packages'
    apt-get clean >/dev/null 2>&1 || true
    apt-get autoclean >/dev/null 2>&1 || true
    apt-get autoremove -y >/dev/null 2>&1 || true
    remove_apt_lists
  fi
elif command -v dnf >/dev/null 2>&1; then
  log 'clean dnf cache'
  dnf clean all >/dev/null 2>&1 || true
elif command -v yum >/dev/null 2>&1; then
  log 'clean yum cache'
  yum clean all >/dev/null 2>&1 || true
fi

if command -v journalctl >/dev/null 2>&1; then
  log 'vacuum systemd journal to 30M'
  journalctl --vacuum-size=30M >/dev/null 2>&1 || true
  configure_journald_limit
fi

log 'delete old temp files older than 7 days'
clean_old_tmp /tmp
clean_old_tmp /var/tmp

log 'delete old compressed/rotated web logs older than 30 days'
for d in /var/log/nginx /var/log/apache2 /var/log/httpd; do
  [ -d "$d" ] || continue
  find "$d" -xdev -type f \( -name '*.gz' -o -name '*.xz' -o -name '*.old' -o -name '*.[0-9]' \) -mtime +30 -print -exec rm -f -- {} + 2>/dev/null || true
done

if command -v docker >/dev/null 2>&1 && [ -d /var/lib/docker/containers ]; then
  log 'truncate docker json logs larger than 50M'
  find /var/lib/docker/containers -type f -name '*-json.log' -size +50M -print -exec truncate -s 0 {} \; 2>/dev/null || true
fi

if [ -f /var/log/btmp ] && [ "$(stat -c %s /var/log/btmp 2>/dev/null || echo 0)" -gt 10485760 ]; then
  log 'truncate oversized /var/log/btmp'
  truncate -s 0 /var/log/btmp || true
fi

clean_benchmark_leftovers

log 'delete stale user cache files older than 14 days'
for home in /root /home/*; do
  [ -d "$home/.cache" ] || continue
  find "$home/.cache" -xdev -mindepth 1 -type f -mtime +14 -print -exec rm -f -- {} + 2>/dev/null || true
  find "$home/.cache" -xdev -mindepth 1 -type d -empty -mtime +14 -print -exec rmdir -- {} + 2>/dev/null || true
done

DF_AFTER=$(df -h / | awk 'NR==2 {print $3 "/" $2 " used (" $5 ")"}')
VAR_LOG_AFTER=$(size_human /var/log)
TMP_AFTER=$(size_human /tmp)
JOURNAL_AFTER=$(journalctl --disk-usage 2>/dev/null | sed -n 's/^.*take up //p' || true)
log "after: /=$DF_AFTER /var/log=$VAR_LOG_AFTER /tmp=$TMP_AFTER journal=${JOURNAL_AFTER:-unknown}"
log '>>> auto-clean v8.3 done'

trim_clean_log
