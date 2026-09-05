# bootstrap.zsh — AgentShell first-run bootstrap (stdlib extension)
#
# Role: create the nodes root once per nodes directory, at shell startup.
# This is the auto-init convenience the kernel used to run inline at the end
# of agent.zsh. It is housekeeping over the user's nodes directory, not
# mechanism: the primitive is `agsh init` (an explicit action); doing it
# implicitly on every source is policy — "you probably want a root" — and
# policy is what the kernel deliberately does not carry.
#
# Behaviour:
#   - runs on every shell that sources this file (i.e. every new agent shell)
#   - creates root only when $AGENT_NODES_PATH/root is missing
#   - `agsh init` is idempotent; its stdout message is left on the terminal
#     exactly as the kernel left it; stderr is discarded
#   - forwards AGENT_PRELOAD entries as `--preload` to the child, exactly as
#     the kernel's former auto-init did through _agent_bun_cli
#     (de2e3a6:agent.zsh :264-266, :93-100). This is what makes plugin
#     overrides of `agsh.init.protocol` apply on the first-run path too.
#
# Deltas vs the kernel's former auto-init (declared, see agsh-stdlib/README.md):
#   1. "Root node created" is printed BEFORE the banner, not after it. The
#      message comes from the child's stdout while ~/.agshrc is sourced; the
#      banner is printed later by the kernel. No hook can reorder it. Message
#      content and exit status are unchanged.
#   2. (fixed) AGENT_PRELOAD is forwarded again — see above.
#   3. A project-level .agshrc that overrides AGENT_NODES_PATH is sourced
#      AFTER ~/.agshrc, so bootstrap has already created root under the
#      default path. Remedy: re-source this file at the end of the project
#      .agshrc (AGENT_NODES_PATH is then the project value), or run
#      `agsh init` / `bun run "$AGENT_ROOT/src/cli.ts" init` explicitly.
#
# Usage: add to ~/.agshrc (agent.zsh sources it while loading layers, before
# its own function bodies are parsed):
#   source /abs/path/agsh-stdlib/bootstrap.zsh

_agsh_bootstrap_root() {
  local nodes="${AGENT_NODES_PATH:-.agsh/nodes}"
  # The kernel absolutises AGENT_NODES_PATH only after ~/.agshrc, so resolve
  # it here against the current directory. Pass the absolute path to the child
  # only (scoped env); the kernel's own absolutisation is left untouched.
  [[ "$nodes" != /* ]] && nodes="$PWD/$nodes"

  [[ -d "$nodes/root" ]] && return 0
  [[ -n "${AGENT_ROOT:-}" && -f "$AGENT_ROOT/src/cli.ts" ]] || return 0

  # Forward the preload channel the same way _agent_bun_cli does. This file
  # runs while ~/.agshrc is sourced, i.e. before agent.zsh defines that helper
  # (it lives below the `source ~/.agshrc` line), so the arguments are
  # assembled here rather than by calling it.
  local -a preload_args=()
  local p
  for p in ${=AGENT_PRELOAD:-}; do
    preload_args+=(--preload="$p")
  done

  AGENT_NODES_PATH="$nodes" bun run "${preload_args[@]}" "$AGENT_ROOT/src/cli.ts" init 2>/dev/null
}

_agsh_bootstrap_root
