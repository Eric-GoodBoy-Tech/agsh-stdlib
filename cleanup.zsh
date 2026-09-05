# cleanup.zsh — AgentShell temp-dir maintenance (stdlib extension)
#
# Role: reap stale per-shell temp state left behind by shells that died
# without running their EXIT trap. Two sweeps, one pass:
#
#   1. Current location — the per-shell dir ${TMPDIR:-/tmp}/agsh-<pid>.
#      These dirs (and the poll/state FIFOs inside them) are created by
#      agent.zsh's _agent_init_infra and removed on clean exit; reaping
#      dead shells' dirs keeps the shared tmp namespace tidy.
#
#   2. Legacy location — the in-repo .agsh/tmp/ used by versions before
#      b725970, which wrote agent_poll_fifo_<pid>, agent_timeout_fifo_<pid>
#      and agent_fifo_<pid>_state straight into the project tree. A FIFO
#      inside the tree hangs `grep -r`/`rg`/`find`, so old litter must
#      still be swept even though new runtimes no longer write there.
#
# Why this lives in the stdlib and not the kernel:
#   - Self-cleanup on normal exit is the kernel's own lifecycle duty: the
#     EXIT trap removes its own $_AGENT_TMP_DIR. That stays in agent.zsh.
#   - Reaping OTHER dead shells' leftovers is housekeeping over the whole
#     tmp namespace, not mechanism: without it no Agent capability is
#     harmed (stale dirs live outside the repo and are inert — they only
#     occupy disk). The kernel's boundary is its own session lifecycle;
#     sweeping the street is not.
#
# Usage: add to ~/.agshrc (after sourcing agent.zsh, or anywhere):
#   source /abs/path/agsh-stdlib/cleanup.zsh
#
# Sourcing runs one reap pass immediately. Safe to source in every new
# shell: skips the current PID and any live PID; flat globs, no recursion,
# no heuristic. The legacy sweep root is CWD-relative `.agsh/tmp` — exactly
# what the former kernel used — and may be pointed elsewhere for tests via
# $AGSH_LEGACY_TMP.

_agsh_reap_stale_tmp() {
  local d pid f base
  # Current location: per-shell dirs keyed by shell PID under ${TMPDIR:-/tmp}
  for d in "${TMPDIR:-/tmp}"/agsh-*(N/); do
    pid="${d##*agsh-}"
    [[ "$pid" == <-> ]] || continue
    [[ "$pid" == "$$" ]] && continue
    kill -0 "$pid" 2>/dev/null && continue
    rm -rf "$d" 2>/dev/null
  done
  # Legacy location: FIFOs written inside the project tree by pre-b725970
  # versions. Base dir is CWD-relative (as the former kernel used); tests can
  # point it elsewhere with $AGSH_LEGACY_TMP.
  local legacy_tmp="${AGSH_LEGACY_TMP:-.agsh/tmp}"
  local fifos=(
    "$legacy_tmp"/agent_poll_fifo_*(N)
    "$legacy_tmp"/agent_timeout_fifo_*(N)
    "$legacy_tmp"/agent_fifo_*_state(N)
  )
  for f in "${fifos[@]}"; do
    base="${f:t}"
    case "$base" in
      agent_poll_fifo_*)    pid="${base#agent_poll_fifo_}" ;;
      agent_timeout_fifo_*) pid="${base#agent_timeout_fifo_}" ;;
      agent_fifo_*_state)   pid="${base#agent_fifo_}"; pid="${pid%_state}" ;;
      *) continue ;;
    esac
    [[ "$pid" == <-> ]] || continue
    [[ "$pid" == "$$" ]] && continue
    kill -0 "$pid" 2>/dev/null && continue
    rm -f "$f" 2>/dev/null
  done
}

_agsh_reap_stale_tmp
