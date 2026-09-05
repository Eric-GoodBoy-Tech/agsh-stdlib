# en.zsh — English language pack for the AgentShell i18n suite (L1)
#
# Text is the source of truth for the interface: the kernel's built-in
# _agent_*_en functions become the "suite not installed" fallback, and this
# pack carries the same bytes. test/i18n-kernel.bats asserts that equality
# (byte-exact) so the two can never drift apart silently.
#
# Registered through _agsh_pack_def (silent): a pack is sourced on every new
# shell and must not print.

_agsh_pack_meta[id]=en
_agsh_pack_meta[name]='English'

# ─── kernel banner base (order fixed by kernel-slots.zsh) ─────────────────
_agsh_pack_def kernel.banner.credential '  credential - Claim/release a credential'
_agsh_pack_def kernel.banner.pause '  Ctrl+G     - Pause/resume'
_agsh_pack_def kernel.banner.retry '  Ctrl+T     - Retry API'
_agsh_pack_def kernel.banner.help_hint '  Type agent help for the full command list'
_agsh_pack_def kernel.banner.unload '  agent unload - Unload agent-shell'

# ─── kernel credential surfaces ──────────────────────────────────────────
_agsh_pack_def kernel.credential_help 'Usage:
  credential claim <id>   - Claim a credential, load its plugs, start the agent
  credential drop         - Unset the CREDENTIAL env, stop the agent
  credential help         - Show this help
  credential              - Show this help'
_agsh_pack_def kernel.credential_set '[credential] CREDENTIAL set to:'
_agsh_pack_def kernel.credential_cleared '[credential] CREDENTIAL cleared'

# ─── kernel help ─────────────────────────────────────────────────────────
# Structured help: help.zsh owns the layout (sections, order, column widths)
# and the left column; a pack owns the text, one key per item. The bridge key
# `kernel.help` (the whole text under one key) is gone: the renderer builds
# the page from these keys, so a module can add its own row without any pack
# touching a 20-line literal.
_agsh_pack_def kernel.help.header 'agent-shell - terminal-native AI agent'
_agsh_pack_def kernel.help.section.commands 'Commands:'
_agsh_pack_def kernel.help.credential_claim 'Claim a credential and start the agent (switchable anytime)'
_agsh_pack_def kernel.help.credential_drop 'Release the credential and stop the agent'
_agsh_pack_def kernel.help.agent_help 'Show this help'
_agsh_pack_def kernel.help.agent_unload 'Unload agent-shell, restore the original shell'
_agsh_pack_def kernel.help.agent_debug_tail 'Follow the debug log (tail -f)'
_agsh_pack_def kernel.help.agent_debug_cat 'Print the debug log (cat)'
_agsh_pack_def kernel.help.section.keybindings 'Keybindings:'
_agsh_pack_def kernel.help.ctrl_g 'Pause/resume the agent'
_agsh_pack_def kernel.help.ctrl_t 'Retry the last API request'
_agsh_pack_def kernel.help.section.env 'Env:'
_agsh_pack_def kernel.help.env_api_key '(required) API key'
_agsh_pack_def kernel.help.env_base_url 'API endpoint'
_agsh_pack_def kernel.help.env_model 'Model name'
_agsh_pack_def kernel.help.env_exec_delay 'Seconds before auto-executing commands'
_agsh_pack_def kernel.help.env_output_max_length 'Max tool output length (chars)'
_agsh_pack_def kernel.help.env_debug 'Debug logging'
_agsh_pack_def kernel.help.env_exec_timeout 'Command execution timeout (seconds, 0=off)'
_agsh_pack_def kernel.help.env_reasoning_effort 'Reasoning depth'
_agsh_pack_def kernel.help.env_ttft_timeout 'Time-to-first-token timeout (seconds)'
