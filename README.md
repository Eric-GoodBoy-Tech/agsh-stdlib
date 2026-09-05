# agsh-stdlib

Agent Shell 内核之外的**扩展标准库**。内核(`agent-shell/src/` + `agent.zsh`)自足;
本目录提供可选加载的扩展,内核不依赖其中任何部分。本目录同时是
agent-shell README 中「扩展机制」的 working example(见 agent-shell/README.md §Extensions)。

## 组成与加载方式

| 文件 | 类型 | 职责 | 加载方式 |
|------|------|------|----------|
| `stats.ts` | 扩展 (TS) | 流式响应的 token/速度统计:内核不发 token/进度事件,本扩展包装 `agsh.api.stream`,流结束用 API usage 补发精确 token 事件 | `AGENT_PRELOAD` 环境通道(空格分隔绝对路径,agent.zsh 构建 `--preload`):`AGENT_PRELOAD='/abs/path/agsh-stdlib/stats.ts'` |
| `rprompt.zsh` | 扩展 (zsh) | 把内核唯一状态变量 `AGENT_STATUS`(JSON)渲染为 RPROMPT 状态图标 | `source /abs/path/agsh-stdlib/rprompt.zsh`(在 `.agshrc` 或 source agent.zsh 之后) |
| `cleanup.zsh` | 扩展 (zsh) | 回收 `${TMPDIR:-/tmp}/agsh-<pid>` 中死 shell 留下的临时目录(跳过当前 PID 与活 PID,一次扁平 glob) | `source /abs/path/agsh-stdlib/cleanup.zsh`(任意位置;source 即执行一次回收) |
| `i18n.zsh` | 扩展 (zsh) / 套件入口 | i18n 套件**唯一入口**:加载 core → 可选 L2/L1 → 选包 → 跑 apply 钩子重建内核表面;另提供 `agent-lang` 与 `_agsh_unload` | `source /abs/path/agsh-stdlib/i18n.zsh`;它自行加载 `i18n-core.zsh` / `help.zsh` / `kernel-slots.zsh` / `lang/<id>.zsh` |
| `i18n-core.zsh` | 套件 L0 | 通用核(依赖无关):文本注册表 + 取词原语;并代 source `registry.zsh` | 由 `i18n.zsh` 加载;可单独 source(幂等,不加载包、不跑钩子) |
| `registry.zsh` | 套件 L0 基座 | 依赖无关的命名空间注册表:提供方自报 `id` 与成员,调用方 `_agsh_have` 软依赖探测、`_agsh_call` 取用(缺席成员走中性默认 `_agsh_none`);**本文件零 id 知识** | 由 `i18n-core.zsh` 代 source(幂等);任何 source 了 core 的模块自动获得 |
| `lang/en.zsh` | 套件 L1 | 英文全量语言包(含 `kernel.*`) | 由 `i18n.zsh` 自动加载,**勿直接 source** |
| `lang/zh.zsh` | 套件 L1 | 中文语言包(overlay,先 source `en.zsh` 作回落) | 同上 |
| `kernel-slots.zsh` | 套件 L1 | 内核表面适配:banner 组装器 + 三个内核文本槽 dispatcher | 由 `i18n.zsh` 加载 |
| `help.zsh` | 套件 L2 | 结构化 help 注册表 + 渲染器(界面与文档同源) | 由 `i18n.zsh` 加载 |
| `prompt.zsh` | 扩展 (zsh) | `prompt <id> <content> [parent]` 在 `$AGENT_NODES_PATH` 下建节点(mkdir + `context` + `parent`);自带文本 guard,**不依赖套件** | `source /abs/path/agsh-stdlib/prompt.zsh`。`i18n.zsh` 可选:先加载则 banner 行与 help 行被翻译;不加载则纯英文 + 旧式字符串 prepend |
| `bootstrap.zsh` | 扩展 (zsh) | 首次运行自动建 root(仅当 `$AGENT_NODES_PATH/root` 缺失) | `source /abs/path/agsh-stdlib/bootstrap.zsh`,**建议最后**(见下文 §bootstrap) |

工具与测试(**非运行时扩展**,不 source 进 shell):

| 文件 | 类型 | 职责 | 用法 |
|------|------|------|------|
| `tools/i18n-lint.zsh` | 工具 | 静态 lint(读源码、不 source):非 en 键必有 en 配对 / 键前缀 = 文件名 stem / 无重复定义 / `fmt` 声明与 `%` 一致 | `zsh tools/i18n-lint.zsh [stdlib-dir]`;退出码 0 干净、1 违例、2 非本目录 |
| `tools/help-readme.zsh` | 工具 | 从结构化 help 注册表导出 markdown 表,供 README 粘贴 | `zsh tools/help-readme.zsh [lang]` |
| `test/run.sh` + `test/*.bats` | 测试 | 套件 bats 测试(核心 / 注册表 / 内核表面 / 结构化 help / 插件契约) | `bash test/run.sh [name.bats ...]`(无参数 = 全部) |

## i18n 套件(三层)

`i18n.zsh` 是唯一入口;三层各自**可缺席**,缺席即优雅降级(按文件是否存在探测,不在 `.agshrc` 里逐个列模块,套件才能自由生长)。

### L0 `i18n-core.zsh` + `registry.zsh` — 通用核(依赖无关)

- 注册表 `_agsh_txt`(全局关联数组),键 `<lang>.<key>`;当前语言 `_agsh_lang`;动态键表 `_agsh_fmt_keys`。
- **一处英文文本**:`_agsh_def <key> '<text>' [fmt]` 写 `en.<key>` 并回显文本(调用点可顺带内联);语言包用 `_agsh_pack_def`(静默,不能在新 shell 里打印)。
- 取词:`_agsh_t <key> [fallback...]` → `print -r`(**文本永远是数据,绝不当格式串**);`_agsh_tf <key> [printf 参数...]` → 仅对显式声明 `fmt` 的键走 `printf`,非 fmt 键在 `AGSH_I18N_STRICT=1` 时告警并降级为 `print -r`。
- 跨组件调度 `registry.zsh`(零 id 知识、零依赖、幂等,由 core 代 source):提供方自报身份与成员 `_agsh_register <id> [member=impl ...]`,调用方 `_agsh_have <id>` 探测(0/1)、`_agsh_call <id.member> [args...]` 取用 —— 缺席成员转发到中性默认 `_agsh_none`(存在即调,缺席即无事)。套件自身也走这条路:`kernel-slots.zsh` 注册 `banner.add/remove/compose`,`help.zsh` 注册 `help.add/remove/render/readme`。
- 降级:**探测而非要求**。调用点只问 `_agsh_have banner|help`,provider 缺席时其服务函数(`_agsh_banner_add` / `_agsh_help_add` 等)**根本不存在**(没有占位 no-op),调用方据此走纯英文/legacy 分支。
- 归属:`i18n-core.zsh` + `registry.zsh` **属于 i18n 套件**,不是模块的必带库。写文本的模块自带通道 A guard(见 §依赖关系),套件在则由 core 接管(通道 B)。**不要把 core 当成模块的底座、进而把模块的 guard 当作 DRY 违例优化掉** —— 那是刻意机制,不是重复代码(架构基线 `i18n-arch-target-v2` F1)。
- 键命名空间:键首段 = 所有者(`kernel.` / `prompt.` / `i18n.` …);模块文件 `X.zsh` 只写 `X.*`,`lang/*.zsh` 豁免。由 `tools/i18n-lint.zsh` 强制。
- 归属特权:`i18n.*` 由 `i18n.zsh` 自带(英文及其翻译就地共置),与模块自带 `<ns>.*` 同构(`prompt.zsh` 同样自带 `prompt.*`);语言包 `lang/<id>.zsh` 只拥有 `kernel.*`,不翻译 `i18n.*`。`i18n.zsh` 写 `i18n.*` 是所有者特权,不是循例豁免。

### L1 `kernel-slots.zsh` + `lang/*.zsh` — 内核表面适配

- banner 组装器:`_agsh_banner_add <owner> <key> [pos]` / `_agsh_banner_remove <owner>` / `_agsh_banner_compose`。**顺序是数据,不是字符串手术**:模块申请位置 1,而不是去 prepend 一个不属于自己的字符串;重复注册同一 owner 幂等;任一基座键取不到文本 → 不覆写内核 banner(降级,绝不空白)。
- 三个内核文本槽 `_agsh_help` / `_agsh_credential_help` / `_agsh_credential_status` 指向 **dispatcher**,在**运行期**读 `_agsh_lang`——zsh 在函数体*解析*时展开 alias,语言包无法按语言重指,故用 dispatcher;`agent-lang set <id>` 因此同一 shell 即时生效,无需 re-source。
- `lang/en.zsh` 承载**全量**英文文本(含 `kernel.*`),内核 `_agent_*_en` 降为「未装套件时的原版」;`_agsh_i18n_selfcheck [lang]` 断言 en 包与内核原版逐字节一致,`lang/zh.zsh` 则对 `test/fixtures/legacy/` 迁移前 oracle 比对。

### L2 `help.zsh` — 结构化 help(插件服务)

- `_agsh_help_section <name> <field-width>`(声明分组/顺序/列宽)、`_agsh_help_add <section> <command> <key>`(注册/替换一行)、`_agsh_help_remove <command>`、`_agsh_help_render [--base] [lang]`、`_agsh_help_readme [lang]`。
- 内核 help 与各语言包 help 由**同一渲染器**生成(按显示宽度 `${(m)#}` 对齐,复现迁移前版式);模块自己加一行即可(`prompt.zsh` 就是这样让自己出现在 `agent help` 里);`--base` 只渲染内核行,供与迁移前 oracle 逐字节比对。
- `tools/help-readme.zsh` 从同一注册表导出 markdown 表:界面与文档不会漂移。

### 语言选择与回落

- 选择优先级:参数 > `AGSH_LANG` > `LANG` > `en`;小写化后剥地区/编码(`zh_CN.UTF-8` → `zh_CN` → `zh`),无对应包则回落 `en`。
- 取词回落链:`<lang>.<key>` → `en.<key>` → 调用点兜底 → 空。`AGSH_I18N_STRICT=1` 时缺键向 stderr 打 `[i18n] missing key: <key> (lang=<id>)`,**返回文本不变**。
- 命令:`agent-lang list` / `agent-lang set <id>`。刻意不叫 `agent lang`:那要求内核知道语言包存在并为它新增子命令机制(内核零扩展知识)。
- 生命周期:`agent unload` 不调用 `_agsh_unload`(内核不知道本套件);需要提前卸掉套件时显式执行 `_agsh_unload`(逆序跑 unload 钩子,再卸自身)。

### 未装套件时

内核**零改动**:不 source `i18n.zsh` 时,内核英文 banner / help / credential 原版照常。
模块**自足**:只 source `prompt.zsh` 即可用 —— 即便 `i18n-core.zsh` / `registry.zsh` 整个缺位(通道 A guard 接管),`prompt` 仍能建节点、给英文 usage,stderr 0 字节;套件缺席时 banner 走旧式字符串 prepend、`agent help` 无 prompt 行,均为设计内降级,不报错。

## 依赖关系(谁依赖谁)

一句话:**模块自带最小机制;套件提供可选策略;跨组件调用一律探测;缺席路径必须完整且纯英文。**

| 依赖方 | 依赖对象 | 类型 | 缺席时 |
|--------|----------|------|--------|
| 模块(如 `prompt.zsh`) | 内核原语(`mkdir` + `echo`) | 功能 | 不适用(内核总在) |
| 模块 | 自带通道 A guard(文本) | 机制,**随模块自带** | 不适用(与模块同生共死) |
| 模块 | `_agsh_have banner` / `_agsh_have help`(可选服务) | 软依赖 | 走纯英文 / legacy 分支,不报错、不阻断 |
| `i18n-core.zsh`(套件 L0) | `registry.zsh` | 套件内部 | 不适用 |
| i18n 套件任意层 | 零外部依赖 | — | 可缺席;缺席即优雅降级 |

- **模块 → 内核原语**:功能只用内核原语,永不经过 i18n。摘掉整个套件,模块功能照常(P4)。
- **模块 → 自带 guard**:英语文本由模块自己拥有(单一来源,P3);guard 只在「套件不在」时提供最小解析(通道 A)。
- **模块 → `_agsh_have`**:可选服务(banner / help)经注册表探测;provider 缺席时其函数根本不存在,调用点据此降级(通道 B 的服务侧)。
- **套件 → 零依赖**:`i18n-core.zsh` / `registry.zsh` 零外部依赖;`i18n.zsh` 是唯一入口,其三层各自可缺席。

### 新模块照抄的 guard 模板

凡写 `<ns>.*` 文本的模块,文件顶部照抄以下 guard —— **必须位于本文件任何 `_agsh_def` / `_agsh_t` / `_agsh_tf` 调用点之前**:

```zsh
typeset -gA _agsh_txt _agsh_fmt_keys
typeset -g  _agsh_lang="${_agsh_lang:-en}"
if ! (( $+functions[_agsh_t] )); then        # 通道 A:套件不在 → 模块自带最小解析
  _agsh_def()  { _agsh_txt[en.$1]="$2"; (( $# > 2 )) && _agsh_fmt_keys[$1]=1; print -r -- "$2" }
  _agsh_t()    { local t="${_agsh_txt[${_agsh_lang}.$1]:-${_agsh_txt[en.$1]:-${2:-}}}"; print -r -- "$t" }
  _agsh_tf()   { local t="${_agsh_txt[${_agsh_lang}.$1]:-${_agsh_txt[en.$1]:-}}"; printf -- "$t" "${@:2}" }
  _agsh_have() { return 1 }                  # 无注册表 ⇒ 可选服务一律缺席 ⇒ 走降级
fi
[[ -f "${${(%):-%x}:A:h}/i18n-core.zsh" ]] \
  && source "${${(%):-%x}:A:h}/i18n-core.zsh"   # 通道 B:套件在 → 真实现覆盖 guard
```

次序自洽:模块「缺则定义」,core「无条件定义」⇒ core 先则模块跳过;模块先则 core 到达即覆盖。
本模板即架构基线 `i18n-arch-target-v2` 的 guard;`prompt.zsh` 顶部 seam 是它的实例(`_agsh_t` / `_agsh_tf` 展开成多行,语义相同)。
`tools/i18n-lint.zsh` 断言:**写文本的模块必须带这段 guard**(套件层 `i18n-core.zsh` / `registry.zsh` / `i18n.zsh` / `kernel-slots.zsh` / `help.zsh` 与 `lang/*.zsh` 豁免),否则退出码 1。

## 边界(什么不属于本库)

本库**只收扩展,不收通用开发工具**:开发工具(如原驻留的 DeepSeek token 代理
`token-proxy.ts`,已迁至母仓库 `tools/`)与运行数据/日志一律不入库。
例外:`tools/` 与 `test/` 收的是**本套件自身的校验工具与测试**——它们校验本目录的契约
(键命名空间、与迁移前 oracle 的逐字节一致性),随套件一起走,不构成通用工具集。
分发出去的就是库本身——本目录的嵌套 `.git` 即分发仓库,内容必须纯净。

## 布局

运行时扩展刻意保持**平铺**:加载路径(`AGENT_PRELOAD`、`source`、测试脚本、文档引用)把文件名
当契约,平铺使引用方零改动(agent-shell README en/zh、AGENTS.md、test-shell
tmux-e2e-* 共 12+ 处引用均直接指向顶层文件名)。引入新运行时扩展时保持平铺,除非引用的
路径语义整体重构(需同步全部引用方 + 用户 `.agshrc`)。
`lang/`、`tools/`、`test/` 是套件的支持目录(语言包 / 工具 / 测试),不属于「顶层扩展」这一层。

## 维护规则(什么能进)

**可以进**:可复用、与内核解耦、行为稳定的**扩展**——有明确职责、
有明确加载方式、有使用说明。

**禁止进**:

- 通用开发工具与脚本(归母仓库 `tools/`;本套件自身的 `tools/`、`test/` 除外,见 §边界)
- 运行数据/日志(token 用量记录、proxy 日志等一次性产物,产生即删,勿入库,勿提交)
- 一次性实验、临时文件、`.DS_Store`、`.agsh/`

## Git 治理

正常开发**使用母目录仓库的 git**(`/Users/zic/agent-demo`,根仓库已跟踪本目录
全部文件)。本目录下的嵌套 `.git/` 是**分发时使用的实际仓库**(用户分发域),
不参与日常开发提交;嵌套仓库内的提交与历史改写由用户自行管理,开发流程
(包括本文件)一律不触碰、不依赖它。

## bootstrap(自动建 root)

`bootstrap.zsh` 把「首次运行自动建 root」这条便利放回扩展层:内核原先在 `agent.zsh` 末尾内联执行,现由本文件在 `.agshrc` 期执行。

加载方式(建议顺序:在 i18n / prompt 之后):

```zsh
source /abs/path/agsh-stdlib/bootstrap.zsh
```

行为:每个新 shell 执行一次;仅当 `$AGENT_NODES_PATH/root` 缺失时创建;`agsh init` 幂等,stdout 消息原样留在终端,stderr 丢弃;
`AGENT_PRELOAD` 条目按 `--preload` 转发给子进程(与内核原自动 init 一致),因此插件对 `agsh.init.protocol` 的覆盖在首建路径同样生效。

与内核原自动 init 的行为差异(已声明):

1. `Root node created` 消息出现在 banner **之前**(仅首建时)。消息来自 `~/.agshrc` 期的子进程 stdout,内核 banner 之后才打印,无钩子可重排;消息内容与退出码不变。
2. `AGENT_PRELOAD` 转发已恢复(见上)。
3. 项目级 `.agshrc` 覆盖 `AGENT_NODES_PATH` 时,`~/.agshrc`(本文件)先执行,root 已建到默认路径。补救:在项目 `.agshrc` 末尾再 `source /abs/path/agsh-stdlib/bootstrap.zsh`(此时 `AGENT_NODES_PATH` 已是项目值),或显式执行 `agsh init`。

生命周期:stdlib 扩展随 shell 生命周期;`agent unload` 只卸载内核表面,不调用 `_agsh_unload`,需要时显式调用。
