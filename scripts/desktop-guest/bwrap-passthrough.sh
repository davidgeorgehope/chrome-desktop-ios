#!/bin/sh
# Run the command bubblewrap would have launched, without unshare/seccomp.
# UML/Darwin does not provide the namespaces glycin's sandbox expects.
while [ "$#" -gt 0 ]; do
  a=$1
  case "$a" in
    --chdir|--uid|--gid|--hostname|--seccomp|--exec-label|--file-label|--lock-file|--sync-fd|--info-fd|--json-status-fd|--cap-add|--cap-drop|--pidns-fd|--userns|--userns-block-fd|--userns-fd|--dir|--size|--perms|--dev|--proc|--tmpfs|--mqueue|--remount-ro|--bind-data|--ro-bind-data|--overlay-src)
      shift 2 2>/dev/null || shift
      continue
      ;;
    --ro-bind|--ro-bind-try|--bind|--bind-try|--dev-bind|--dev-bind-try|--symlink|--chmod|--chown|--setenv|--file|--overlay|--tmp-overlay)
      shift 3 2>/dev/null || shift
      continue
      ;;
    --unshare-*|--die-with-parent|--as-pid-1|--new-session|--clearenv|--disable-*|--help|--version|--args|--assert-*)
      shift
      continue
      ;;
    --*=*)
      shift
      continue
      ;;
    /*)
      if [ -f "$a" ] && [ -x "$a" ]; then
        exec "$@"
      fi
      shift
      continue
      ;;
    *)
      shift
      continue
      ;;
  esac
done
echo "bwrap-passthrough: no command in argv" >&2
exit 127
