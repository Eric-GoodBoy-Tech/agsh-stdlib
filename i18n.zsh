# i18n.zsh — single entry point of the AgentShell i18n suite
#
# Role: load the dependency-free core, then whatever optional layers sit next
# to it, then pick and load a language pack, then run the apply hooks that
# rebuild the kernel-facing surfaces. Sourcing this one file is the whole
# installation; ~/.agshrc needs exactly this line (the modules must not be
# listed there, so the suite stays free to grow).
#
#   source /abs/path/agsh-stdlib/i18n.zsh
#
# Layers, all optional and probed by presence on disk:
#   i18n-core.zsh     (required) text core + registry (_agsh_t/_agsh_tf/_agsh_have)
#   help.zsh          (L2) structured help registry + renderer
#   kernel-slots.zsh  (L1) banner assembler + kernel surface dispatchers
#   lang/<id>.zsh     (L1) language packs
#
# Public surface added here:
#   _agsh_i18n_choose [lang]   resolve a language id (arg > AGSH_LANG > LANG > en)
#   _agsh_i18n_load   [lang]   load a pack and run the apply hooks (idempotent)
#   agent-lang [list|set <id>] inspect or switch the interface language
#   _agsh_unload               run unload hooks, then unload the suite itself
#
# Deviation, deliberate: the kernel command is `agent-lang`, not `agent lang`.
# A subcommand under `agent` would teach the kernel that language packs exist
# and would add a mechanism to it; the kernel stays unaware of this suite.
#
# Lifecycle: the kernel's `agent unload` does not call _agsh_unload (the kernel
# carries no knowledge of this suite). Stdlib extensions live with the shell;
# run `_agsh_unload` explicitly if you want the suite gone before the shell is.

source "${${(%):-%x}:A:h}/i18n-core.zsh"
_agsh_i18n_dir="${${(%):-%x}:A:h}"

# ─── suite-owned text (namespace: i18n.*) ─────────────────────────────────────
# Ownership ruling: i18n.* keys are owned by this file. Its English text
# (written via _agsh_pack_def, silent) and its translations (_agsh_txt[zh.i18n.*])
# are co-located right here — structurally the same as a module keeping its
# own <ns>.* text beside its code (prompt.zsh keeps prompt.* the same way). The
# language packs (lang/<id>.zsh) own kernel.* only; they do not carry i18n.*, and
# a missing non-en entry is harmless — resolution falls back <lang>.* -> en.* ->
# call-site. tools/i18n-lint.zsh enforces "a file X.zsh writes only X.* keys",
# so i18n.zsh writing i18n.* is the owner's privilege, not an exemption.
# The agent-lang row is registered into structured help by the hook below.
_agsh_pack_def i18n.help.agent_lang 'List or switch the interface language'
_agsh_txt[zh.i18n.help.agent_lang]='列出或切换界面语言'

# ─── language selection ──────────────────────────────────────────────────────
# arg > AGSH_LANG > LANG > en; lowercase, strip region/encoding, then require a
# pack on disk. zh_CN.UTF-8 -> zh, zh_CN -> zh, fr_FR -> fr -> (no pack) -> en.
_agsh_i18n_choose() {
  local value="${1:-${AGSH_LANG:-${LANG:-en}}}"
  value="${value:l}"
  value="${value%%[._]*}"
  value="${value%%_*}"
  [[ -n "$value" ]] || value=en
  local dir="${_agsh_i18n_dir:-${${(%):-%x}:A:h}}"
  [[ -f "$dir/lang/$value.zsh" ]] || value=en
  print -r -- "$value"
}

# Load a pack and let the layers rebuild their surfaces. Idempotent: packs
# write plain table entries and every apply hook must tolerate a second run.
# Switching language deliberately does not clear the previous language's keys
# (they are keyed by language and harmless).
_agsh_i18n_load() {
  local lang="${1:-}"
  [[ -n "$lang" ]] || lang="$(_agsh_i18n_choose)"
  lang="${lang:l}"
  lang="${lang%%[._]*}"
  lang="${lang%%_*}"
  local dir="${_agsh_i18n_dir:-${${(%):-%x}:A:h}}"
  [[ -n "$lang" && -f "$dir/lang/$lang.zsh" ]] || lang=en
  source "$dir/lang/$lang.zsh"
  typeset -g _agsh_lang="$lang"
  local hook
  for hook in "${_agsh_hooks_apply[@]}"; do
    (( $+functions[$hook] )) && "$hook"
  done
}

# ─── agent-lang ──────────────────────────────────────────────────────────────
agent-lang() {
  local sub="${1:-list}"
  case "$sub" in
    list|--list|"")
      local file id name mark
      for file in "$_agsh_i18n_dir"/lang/*.zsh(N); do
        id="${${file:t}:r}"
        name="$( (source "$file" >/dev/null 2>&1; print -r -- "${_agsh_pack_meta[name]:-}") )"
        [[ -n "$name" ]] || name="$id"
        mark=' '
        [[ "$id" == "${_agsh_lang:-}" ]] && mark='*'
        printf ' %s %-4s %s\n' "$mark" "$id" "$name"
      done
      ;;
    set|--set)
      if [[ -z "${2:-}" ]]; then
        print -r -- "usage: agent-lang [list|set <id>]" >&2
        return 1
      fi
      _agsh_i18n_load "$2"
      ;;
    *)
      print -r -- "usage: agent-lang [list|set <id>]" >&2
      return 1
      ;;
  esac
}

# Advertise the command in structured help, when that layer is installed.
_agsh_i18n_register_help() {
  _agsh_have help || return 0
  _agsh_help_add Commands 'agent-lang list|set <id>' i18n.help.agent_lang
}
[[ " ${_agsh_hooks_apply[*]} " == *" _agsh_i18n_register_help "* ]] \
  || _agsh_hooks_apply+=(_agsh_i18n_register_help)

# ─── unload ──────────────────────────────────────────────────────────────────
_agsh_unload() {
  local hook
  local -a hooks
  local -i i
  hooks=("${_agsh_hooks_unload[@]}")
  for (( i=${#hooks}; i>0; i-- )); do
    hook="${hooks[i]}"
    (( $+functions[$hook] )) && "$hook"
  done
  unfunction _agsh_def _agsh_pack_def _agsh_lookup _agsh_t _agsh_tf \
             _agsh_register _agsh_have _agsh_call _agsh_none \
             _agsh_i18n_choose _agsh_i18n_load \
             _agsh_i18n_register_help agent-lang _agsh_unload \
             _agsh_banner_add _agsh_banner_remove _agsh_help_add _agsh_help_remove \
             2>/dev/null
  unset _agsh_txt _agsh_fmt_keys _agsh_lang _agsh_pack_meta \
        _agsh_api _agsh_plugins _agsh_hooks_apply _agsh_hooks_unload _agsh_i18n_dir 2>/dev/null
  return 0
}

# ─── optional layers ─────────────────────────────────────────────────────────
[[ -f "$_agsh_i18n_dir/help.zsh" ]] && source "$_agsh_i18n_dir/help.zsh"
[[ -f "$_agsh_i18n_dir/kernel-slots.zsh" ]] && source "$_agsh_i18n_dir/kernel-slots.zsh"

# ─── boot ────────────────────────────────────────────────────────────────────
_agsh_i18n_load "$(_agsh_i18n_choose)"
