# zh.zsh — Chinese language pack for the AgentShell i18n suite (L1)
#
# Same key set as en.zsh, one text per key; the suite resolves
# <lang>.<key> -> en.<key> -> call-site fallback, so a partial pack degrades
# to English instead of printing nothing. test/i18n-kernel.bats compares
# every key against test/fixtures/legacy/* (the pre-migration oracle).

# A pack is an overlay on the English base: load it first so the resolution
# chain <lang>.<key> -> en.<key> always has its fallback, even when the
# loader selected a non-English language (one pack is sourced per load).
source "${${(%):-%x}:A:h}/en.zsh"

_agsh_pack_meta[id]=zh
_agsh_pack_meta[name]='简体中文'

# ─── kernel banner base (order fixed by kernel-slots.zsh) ─────────────────
_agsh_txt[zh.kernel.banner.credential]='  credential - 申领/释放凭证'
_agsh_txt[zh.kernel.banner.pause]='  Ctrl+G     - 暂停/恢复'
_agsh_txt[zh.kernel.banner.retry]='  Ctrl+T     - 重试 API'
_agsh_txt[zh.kernel.banner.help_hint]='  输入 agent help 查看完整命令'
_agsh_txt[zh.kernel.banner.unload]='  agent unload - 卸载 agent-shell'

# ─── kernel credential surfaces ──────────────────────────────────────────
_agsh_txt[zh.kernel.credential_help]='Usage:
  credential claim <id>   - 申领凭证，自动加载插件并启动 agent
  credential drop         - 释放 CREDENTIAL 环境变量，退出 agent
  credential help         - 显示此帮助
  credential              - 显示此帮助'
_agsh_txt[zh.kernel.credential_set]='[credential] CREDENTIAL 已设置为:'
_agsh_txt[zh.kernel.credential_cleared]='[credential] CREDENTIAL 已清除'

# ─── kernel help ─────────────────────────────────────────────────────────
# Structured help: same keys as en.zsh, resolved through the renderer in
# help.zsh. `kernel.help` (the old bridge key) is gone.
_agsh_txt[zh.kernel.help.header]='agent-shell - 终端原生 AI Agent'
_agsh_txt[zh.kernel.help.section.commands]='Commands:'
_agsh_txt[zh.kernel.help.credential_claim]='申领凭证，启动 agent（支持随时切换）'
_agsh_txt[zh.kernel.help.credential_drop]='释放凭证，退出 agent'
_agsh_txt[zh.kernel.help.agent_help]='显示此帮助'
_agsh_txt[zh.kernel.help.agent_unload]='卸载 agent-shell，恢复原始 shell'
_agsh_txt[zh.kernel.help.agent_debug_tail]='查看调试日志 (tail -f)'
_agsh_txt[zh.kernel.help.agent_debug_cat]='查看调试日志 (cat)'
_agsh_txt[zh.kernel.help.section.keybindings]='Keybindings:'
_agsh_txt[zh.kernel.help.ctrl_g]='暂停/恢复 agent'
_agsh_txt[zh.kernel.help.ctrl_t]='重试上次 API 请求'
_agsh_txt[zh.kernel.help.section.env]='Env:'
_agsh_txt[zh.kernel.help.env_api_key]='(必填) API 密钥'
_agsh_txt[zh.kernel.help.env_base_url]='API 端点'
_agsh_txt[zh.kernel.help.env_model]='模型名称'
_agsh_txt[zh.kernel.help.env_exec_delay]='自动执行建议命令前的延迟（秒）'
_agsh_txt[zh.kernel.help.env_output_max_length]='工具输出最大长度（字符）'
_agsh_txt[zh.kernel.help.env_debug]='调试日志'
_agsh_txt[zh.kernel.help.env_exec_timeout]='命令执行超时（秒，0=禁用）'
_agsh_txt[zh.kernel.help.env_reasoning_effort]='推理深度'
_agsh_txt[zh.kernel.help.env_ttft_timeout]='首 token 超时（秒）'
