# kernel-slots.zsh — L1: bind the i18n suite to the kernel's text slots
#
# Role: own the two kernel-facing surfaces the suite is allowed to touch, and
# keep them language-aware *at runtime*.
#
#   1. the startup banner  — _AGENT_BANNER_TEXT is a kernel variable that was
#      always a single literal. Here it becomes a composition: five fixed base
#      lines (the kernel's own banner) plus whatever a module registers with
#      _agsh_banner_add. Order is data, not string surgery: a module asks for
#      position 1 instead of prepending to a string it does not own.
#   2. the three text slots — _agsh_help / _agsh_credential_help /
#      _agsh_credential_status are kernel aliases. A pack cannot re-point them
#      per language, because zsh expands an alias when a function body is
#      *parsed* (verified: re-aliasing later does not change an already parsed
#      body). So the aliases point at dispatchers that read _agsh_lang when
#      they run. `agent-lang set <id>` therefore changes the interface in the
#      same shell, with no re-source.
#
# The kernel is not modified and knows nothing about this file. If the suite is
# not sourced, the kernel's own English defaults and aliases stay in place; if
# the suite is sourced but a base text is missing, _agsh_banner_compose refuses
# to overwrite the kernel banner (degrade, never blank it).

(( $+functions[_agsh_t] )) || return 0

# ─── post-unload text resolution ─────────────────────────────────────────────
# Everything below outlives _agsh_unload: the dispatchers are bound into
# agent()/credential() at *parse* time (zsh expands an alias when the enclosing
# function body is read), so restoring the alias in _agsh_kernel_unload cannot
# redirect them, and the banner helpers stay around for diagnosis. Each of them
# therefore resolves text through this one guarded door: when the core is gone
# the key resolves to nothing, every surface falls back to the kernel's own
# English default, and nothing is printed to stderr.
_agsh_kernel_text() {
  (( $+functions[_agsh_t] )) || return 0
  _agsh_t "$@"
}

# ─── banner ──────────────────────────────────────────────────────────────────
# Captured once, before any pack is loaded, so the unload hook can restore
# exactly what the kernel had. Captured once (not on every re-source) because a
# re-source may happen after a module already registered a banner line.
_agsh_kernel_banner_default="${_agsh_kernel_banner_default-${_AGENT_BANNER_TEXT}}"

# The kernel banner, one key per line, in display order. A pack supplies the
# text; this list owns the order.
typeset -ga _agsh_banner_base_keys
_agsh_banner_base_keys=(
  kernel.banner.credential
  kernel.banner.pause
  kernel.banner.retry
  kernel.banner.help_hint
  kernel.banner.unload
)

# Registered extra lines: owner -> "<pos>|<key>" (empty pos = append), plus the
# registration order so the result is deterministic.
typeset -gA _agsh_banner_extras
typeset -ga _agsh_banner_owners

# Base lines only, resolved for the current language. Prints the text; returns
# 1 without printing when a base key has no English text at all (nothing to
# fall back to).
_agsh_banner_base_text() {
  (( $+functions[_agsh_t] )) || return 1
  local k
  for k in "${_agsh_banner_base_keys[@]}"; do
    [[ -n "${_agsh_txt[en.$k]:-}" ]] || return 1
  done
  local -a lines
  for k in "${_agsh_banner_base_keys[@]}"; do
    lines+=("$(_agsh_t "$k")")
  done
  print -r -- "${(F)lines}"
}

# Recompose _AGENT_BANNER_TEXT. Idempotent, and a no-op (return 1) when the
# base text is unavailable.
_agsh_banner_compose() {
  local base
  base="$(_agsh_banner_base_text)" || return 1
  local -a lines
  lines=("${(@f)base}")
  local owner entry pos key text
  for owner in "${_agsh_banner_owners[@]}"; do
    entry="${_agsh_banner_extras[$owner]:-}"
    [[ -n "$entry" ]] || continue
    pos="${entry%%|*}"
    key="${entry#*|}"
    text="$(_agsh_kernel_text "$key")"
    if [[ -z "$pos" ]]; then
      lines+=("$text")
    else
      (( pos < 1 )) && pos=1
      (( pos > ${#lines} + 1 )) && pos=$(( ${#lines} + 1 ))
      lines[$pos,$(( pos - 1 ))]=("$text")
    fi
  done
  # (F) joins with newlines but adds no trailing one; the kernel banner has
  # always ended with a newline, so add it explicitly.
  _AGENT_BANNER_TEXT="${(F)lines}"$'\n'
  return 0
}

# _agsh_banner_add <owner> <key> [pos]
# Register (or move) one extra banner line. Re-registering the same owner is
# idempotent: the entry is replaced, never duplicated.
_agsh_banner_add() {
  local owner="${1:-}" key="${2:-}" pos="${3:-}"
  [[ -n "$owner" && -n "$key" ]] || return 1
  [[ -z "$pos" || "$pos" == <-> ]] || return 1   # position must be a number
  (( ${+_agsh_banner_extras[$owner]} )) || _agsh_banner_owners+=("$owner")
  _agsh_banner_extras[$owner]="${pos}|${key}"
  _agsh_banner_compose
}

_agsh_banner_remove() {
  local owner="${1:-}"
  (( ${+_agsh_banner_extras[$owner]} )) || return 0
  unset "_agsh_banner_extras[$owner]"
  _agsh_banner_owners=("${(@)_agsh_banner_owners:#$owner}")
  _agsh_banner_compose
}

# ─── kernel text slots ───────────────────────────────────────────────────────
# Dispatchers, not pack aliases: they resolve the language when called. The
# kernel originals remain the last resort when the suite has no text for a
# surface (degrade).

_agsh_help_dispatch() {
  if (( $+functions[_agsh_help_render] )); then
    _agsh_help_render
    return
  fi
  local text
  text="$(_agsh_kernel_text kernel.help)"
  if [[ -n "$text" ]]; then
    print -r -- "$text"
  elif (( $+functions[_agent_help_en] )); then
    _agent_help_en
  fi
}

_agsh_credential_help_dispatch() {
  local text
  text="$(_agsh_kernel_text kernel.credential_help)"
  if [[ -n "$text" ]]; then
    print -r -- "$text" >&2
  elif (( $+functions[_agent_credential_help_en] )); then
    _agent_credential_help_en
  fi
}

_agsh_credential_status_dispatch() {
  local text
  case "${1:-}" in
    set)
      text="$(_agsh_kernel_text kernel.credential_set)"
      if [[ -z "$text" ]]; then
        (( $+functions[_agent_credential_status_en] )) && _agent_credential_status_en set
        return
      fi
      print -r -- "$text ${CREDENTIAL}" >&2
      ;;
    cleared)
      text="$(_agsh_kernel_text kernel.credential_cleared)"
      if [[ -z "$text" ]]; then
        (( $+functions[_agent_credential_status_en] )) && _agent_credential_status_en cleared
        return
      fi
      print -r -- "$text" >&2
      ;;
  esac
}

# ─── hooks ───────────────────────────────────────────────────────────────────
_agsh_kernel_apply() {
  _agsh_banner_compose
  alias _agsh_help='_agsh_help_dispatch'
  alias _agsh_credential_help='_agsh_credential_help_dispatch'
  alias _agsh_credential_status='_agsh_credential_status_dispatch'
}

# The dispatchers are deliberately *not* removed here. agent() and credential()
# were parsed with the aliases pointing at them, so the body keeps calling them
# even after the aliases below are restored; removing them would turn the
# post-unload interface into "command not found". They degrade on their own:
# _agsh_kernel_text returns nothing once the core is gone, and each surface then
# calls the kernel's original English implementation.
_agsh_kernel_unload() {
  _AGENT_BANNER_TEXT="$_agsh_kernel_banner_default"
  alias _agsh_help='_agent_help_en'
  alias _agsh_credential_help='_agent_credential_help_en'
  alias _agsh_credential_status='_agent_credential_status_en'
}

[[ " ${_agsh_hooks_apply[*]} " == *" _agsh_kernel_apply "* ]] \
  || _agsh_hooks_apply+=(_agsh_kernel_apply)
[[ " ${_agsh_hooks_unload[*]} " == *" _agsh_kernel_unload "* ]] \
  || _agsh_hooks_unload+=(_agsh_kernel_unload)

# ─── self-check ──────────────────────────────────────────────────────────────
# Assert the packs render the interface byte-for-byte as the pre-suite kernel
# and the pre-migration Chinese pack did. English is compared against the live
# kernel originals; any other language against test/fixtures/legacy/*, the
# oracle captured before the rewrite. Exits 1 and names the surfaces that
# differ; restores the language it started with.
#
# The kernel.help check is skipped once a structured help renderer exists and
# the bridge key is gone (L2) — the renderer has its own tests.
_agsh_i18n_selfcheck() {
  emulate -L zsh
  if (( ! $+functions[_agsh_t] )); then
    print -r -- "[i18n] selfcheck unavailable: the suite is not loaded" >&2
    return 1
  fi
  local lang="${1:-${_agsh_lang:-en}}"
  local saved="${_agsh_lang:-en}"
  local fix="$_agsh_i18n_dir/test/fixtures/legacy"
  local -a problems
  local want got

  _agsh_i18n_load "$lang" >/dev/null 2>&1

  # banner base — the pack's rendering of the five base keys
  want=""
  if [[ "$lang" == en && -n "$_agsh_kernel_banner_default" ]]; then
    want="$(print -r -- "$_agsh_kernel_banner_default")"
  elif [[ -f "$fix/banner-base.$lang.txt" ]]; then
    want="$(<"$fix/banner-base.$lang.txt")"
  fi
  if [[ -n "$want" ]]; then
    got="$(_agsh_banner_base_text)"
    [[ "$got" == "$want" ]] || problems+=("banner-base.$lang")
  fi

  # credential help — the kernel surface, not just the key
  if [[ "$lang" == en ]] && (( $+functions[_agent_credential_help_en] )); then
    want="$(_agent_credential_help_en 2>&1)"
  else
    want="$(<"$fix/cred-help.$lang.txt")"
  fi
  got="$(_agsh_credential_help_dispatch 2>&1)"
  [[ "$got" == "$want" ]] || problems+=("cred-help.$lang")

  # credential status — both states
  if [[ "$lang" == en ]] && (( $+functions[_agent_credential_status_en] )); then
    want="$(CREDENTIAL=testid _agent_credential_status_en set 2>&1)"
  else
    want="$(<"$fix/cred-set.$lang.txt")"
  fi
  got="$(CREDENTIAL=testid _agsh_credential_status_dispatch set 2>&1)"
  [[ "$got" == "$want" ]] || problems+=("cred-set.$lang")

  if [[ "$lang" == en ]] && (( $+functions[_agent_credential_status_en] )); then
    want="$(_agent_credential_status_en cleared 2>&1)"
  else
    want="$(<"$fix/cred-clear.$lang.txt")"
  fi
  got="$(_agsh_credential_status_dispatch cleared 2>&1)"
  [[ "$got" == "$want" ]] || problems+=("cred-clear.$lang")

  # help bridge key — absent once structured help replaced it (L2)
  local bridge=kernel.help
  if [[ -n "${_agsh_txt[en.$bridge]:-}" ]]; then
    if [[ "$lang" == en ]] && (( $+functions[_agent_help_en] )); then
      want="$(_agent_help_en)"
    else
      want="$(<"$fix/help.$lang.txt")"
    fi
    got="$(_agsh_kernel_text kernel.help)"
    [[ "$got" == "$want" ]] || problems+=("help.$lang")
  fi

  _agsh_i18n_load "$saved" >/dev/null 2>&1

  if (( ${#problems} )); then
    print -r -- "[i18n] selfcheck mismatch (lang=$lang): ${(j:, :)problems}" >&2
    return 1
  fi
  return 0
}

# ─── registry ────────────────────────────────────────────────────────────────
# Announce this layer under the id "banner"; a consumer asks _agsh_have banner /
# _agsh_call banner.<member> instead of probing a function name. The id lives
# here, not in registry.zsh.
_agsh_register banner \
  add=_agsh_banner_add remove=_agsh_banner_remove compose=_agsh_banner_compose
