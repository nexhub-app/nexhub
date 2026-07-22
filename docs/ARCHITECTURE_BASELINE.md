# NexHub 架构基准（Architecture Baseline）：共创式 / 源即插件

> 本文件是项目最高优先级架构基准。任何代码改动都不得违反。AI 在动手前必须对照本基准自检。

## 一、基准原则（用户原话，2026-07-19 确立）

> 「我想的是共创式的，我只需提供应用，别人只需导入源即可，他们也可以自己编码（不需要改变应用的代码就能运行并解析内容）。」

**一句话**：应用只提供「引擎」，解析能力全部来自**可导入的源**，社区可以自己写解析逻辑、导入即用，**绝不允许把某个源/站点写死进应用代码**。

## 二、合规判定标准

### 合规（允许）
- 解析逻辑（列表 / 详情 / 章节 / 图片 / 视频嗅探等）全部位于**可导入的源文件**：`plugins/**/*.json`。
  - 源文件内含 `parser.overrides`（内嵌 JS 脚本，给高级贡献者写复杂逻辑），或 `selectors`（声明式 CSS / JSONPath / XPath，给普通贡献者）。
- 通用解析器 `BuiltinResolver` / `ScriptResolver` / `WebViewResolver` 经 `ResolverRegistry` 按源的 `parser.type` 与 hybrid overrides 自动分发；行为完全由源 JSON 决定，app 代码不含任何站点专属逻辑。
- 用户「导入源」即可使用；贡献者改 JSON（或写 JS）即可扩展，无需改 app、无需发版。

### 违规（禁止）
以下任一情形即违反基准，必须驳回/回退：
1. 为某个具体 `source.id`（如 `manga_goda`、`manga_baozimh`、某小说/影视站）在 `lib/` 里写 `if / switch` 特判分支。
2. 在 app 代码里硬编码某站的**域名、API 地址、专属 CSS/XPath 选择器、解密算法**（如把 goda 的章节 API、图片 J7r 解码写进 Dart）。
3. 新建只服务单个源的解析器文件（如 `*_source_resolver.dart`、`*_dart_resolver.dart`）。
4. 把本该进「源 JSON」的解析规则，以「临时兜底 / 稳妥起见」为由塞进 app 代码。

### 例外（不算违规，但需注明）
- **app 集成服务**，非「可导入内容源」：如 DanDanPlay / Bilibili 弹幕匹配 API、可配置的 RSSHub 实例、浏览器搜索等。它们属于产品功能，不是用户贡献的内容源，不在此限。
- ⚠️ 注意：项目另有「禁 Bilibili 源」纪律（禁止把 Bilibili 当作内容源接入）；弹幕服务与该纪律分属不同范畴，本基准不覆盖后者。

## 三、支撑架构（已实现，勿另造轮子）

| 组件 | 职责 | 是否依赖源 JSON |
|------|------|----------------|
| `ResolverRegistry` | 按 `parser.type` + hybrid overrides 选解析器 | 是（读源配置） |
| `BuiltinResolver` | 声明式 CSS/JSONPath/XPath 解析，无脚本依赖 | 是（`selectors`） |
| `ScriptResolver` + `js_context` | 执行源内嵌 JS（flutter_js/quickjs 沙箱） | 是（`parser.overrides`） |
| `WebViewResolver` | 反爬站点走内置浏览器渲染后回灌 | 是（`useWebview`） |
| `plugins/builtin/*.json` | 内置可导入源；用户也可导入自定义源 | — |

> JS 引擎（flutter_js）是「别人自己编码」的共创能力，**必须保证可用**。若某源在真机上 JS 桥接不稳，**正确做法是修桥接层（`js_context.dart`）或修该源的 JSON 脚本**，而不是退化为 app 内硬编码 Dart。

## 四、合规审计记录

### 2026-07-19 审计（首次确立基准时执行）
- **发现并修正 1 项违规**：`lib/core/resolver/goda_dart_resolver.dart` 把 goda 漫画写死进 app（违反基准第二节第 3 条）。
  - 处置：删除该文件；`resolver_registry.dart` 移除其 import 与 `_dartFallbackSourceIds` 入口。
  - goda 回归为可导入源 `plugins/builtin/manga_goda.json`，重写其 `parser.overrides` 的 JS 脚本（纯源改动，零 app 代码），并对照真实站点验证：热门/韩漫各 18、搜索 30、详情正确、章节 3875 话、URL 正确。
  - `flutter analyze lib` → **0 error**。
- **全量扫描 `lib/`**：
  - 无按 `source.id` 特判的 `if/switch` 分支；无硬编码内容源域名/专属选择器。
  - 注释中出现 goda/baozimh 仅作举例说明，非逻辑。
  - `lib/` 内全部 `https://` 字面量均为 app 集成服务（Google 搜索、可配置 RSSHub、DanDanPlay/Bilibili 弹幕、项目 GitHub 链接），无内容源写死。
- **审计结论：当前代码符合共创式基准。** ✅

### 后续每次改动前的自检清单
- [ ] 新增/修改解析逻辑是否落在 `plugins/**/*.json`（源文件），而非 `lib/`？
- [ ] 是否出现了针对某个 `source.id` 的特判分支？
- [ ] 是否把某站域名/API/选择器/解密硬编码进了 Dart？
- [ ] 若某源在真机异常，是修「源 JSON / 桥接层」，还是（错误地）退化为 app 硬编码？
