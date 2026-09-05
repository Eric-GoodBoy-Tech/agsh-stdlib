# rprompt.zsh — AgentShell RPROMPT renderer (example extension)
#
# Role: render the kernel's state truth — the AGENT_STATUS single-variable
# JSON — into RPROMPT. The kernel never sets RPROMPT itself; rendering
# happens only in this extension.
#
# Usage: after .agshrc or sourcing agent.zsh:
#   source /abs/path/agsh-stdlib/rprompt.zsh
#
# How it works:
#   - The kernel writes AGENT_STATUS (JSON: state ∈ idle/paused/streaming/
#     api_done/error/fatal; while streaming it also carries reasoning/speed;
#     without the stats extension loaded those fields are absent);
#   - Pull model: this extension sets RPROMPT to the command substitution
#     $(_agsh_rprompt_text); every promptsubst expansion (including the
#     0.1 s poll's _agent_render → zle reset-prompt) re-runs it, so the
#     display stays live with no precmd and no intermediate variables;
#   - _agsh_rprompt_text is a pure function (command substitution runs in a
#     subshell, assignments never reach the parent shell), so all display
#     data comes from the current AGENT_STATUS only, with no cross-call
#     caching;
#   - On kernel unload AGENT_STATUS is unset: the function detects the
#     vanished variable and prints the user's saved RPROMPT text to restore
#     the display (a subshell cannot write variables back, so the template
#     stays).

# Save the user's original RPROMPT at source time (if any)
_AGSH_RPROMPT_SAVED="${RPROMPT:-}"

_agsh_rprompt_text() {
  # Kernel unload unsets AGENT_STATUS; ${AGENT_STATUS+x} distinguishes an
  # empty value from a vanished variable. Once it is gone, only print the
  # saved RPROMPT text to restore the display — this function runs via
  # command substitution in a subshell, so assignments cannot reach the
  # parent and the RPROMPT template must stay unchanged.
  if [[ -z "${AGENT_STATUS+x}" ]]; then
    print -r -- "$_AGSH_RPROMPT_SAVED"
    return
  fi

  [[ -z "$AGENT_STATUS" ]] && return

  local s reasoning speed message usage_reasoning
  s="$(jq -r '.state // "idle"' <<< "$AGENT_STATUS" 2>/dev/null)"
  reasoning="$(jq -r '.reasoning // 0' <<< "$AGENT_STATUS" 2>/dev/null)"
  speed="$(jq -r '.speed // 0' <<< "$AGENT_STATUS" 2>/dev/null)"
  message="$(jq -r '.message // ""' <<< "$AGENT_STATUS" 2>/dev/null)"
  usage_reasoning="$(jq -r '.usage.reasoning_tokens // 0' <<< "$AGENT_STATUS" 2>/dev/null)"

  # Fallback: when the status line carries no reasoning field, use
  # usage.reasoning_tokens (a native field of the TS done event)
  [[ "$reasoning" == "0" ]] && reasoning="$usage_reasoning"

  local icon=""
  local text=""
  case "$s" in
    idle)      icon="◇" ;;
    paused)    icon="●" ;;
    streaming) icon="◌"; text="${reasoning}r ${speed}t/s" ;;
    api_done)  icon="◀"; text="${reasoning}r ${speed}t/s" ;;
    error)     icon="✗"; text="${reasoning}r ${speed}t/s" ;;
    fatal)     icon="⚠"; text="${message:-internal error}" ;;
    *)         icon="" ;;
  esac

  print -r -- "${icon:+$icon }$text"
}

# promptsubst is enabled by the kernel (setopt promptsubst in agent.zsh);
# this extension only sets RPROMPT.
RPROMPT='$(_agsh_rprompt_text)'
