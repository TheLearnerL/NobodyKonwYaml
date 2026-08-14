# Shadowrocket 中国域名规则维护说明

> 本文是公开规则产物的独立说明。完整本地配置库另有《Shadowrocket 中国直连、其余代理、防泄漏配置维护手册》，记录威胁模型、规则顺序、更新审查、真机验证和交接要求；该手册不是公开自动更新的必需文件。

## 文件用途

- `v2fly-geolocation-cn-shadowrocket.list` 是严格版，从 V2Fly 官方 `dlc.dat_plain.yml` 中提取并展开 `geolocation-cn`；当前转换结果约 8000 条。
- `metacubex-geosite-cn-shadowrocket.list` 是广泛版，将 MetaCubeX `geo/geosite/cn.list` 的 `+.domain` 逐条转换为 Shadowrocket `DOMAIN-SUFFIX`；当前转换结果约 11 万条。
- `THIRD_PARTY_NOTICES.md` 记录广泛版转换产物的 MetaCubeX 来源与 GPL-3.0 许可边界。
- 两个文件都不含策略名称，可作为 Shadowrocket `RULE-SET`；严格版还供 Mihomo 的 `classical + text` provider 使用。
- Shadowrocket 广泛版使用固定批准的 GitHub Raw URL 远程加载 `metacubex-geosite-cn-shadowrocket.list`；严格版继续内嵌 `v2fly-geolocation-cn-shadowrocket.list` 的快照。

两个上游的分类语义不同，广泛版只是总体规模更大，并不是严格版的数学超集；不得把两份 `DIRECT` 规则合并使用。

不要把 V2Fly 原始 `data/geolocation-cn` / `dlc.dat_plain.yml`、Mihomo `.mrs`，或 MetaCubeX 原始 `+.domain` 列表直接填入 Shadowrocket `RULE-SET`。这些格式都必须先由转换工具生成 Shadowrocket 的明确规则类型。

## 完整本地配置库的候选重建与验证

在 `Yaml` 目录执行：

```bash
cp "shadowrocket-CNIP和8000常用域名名单-其他全代理.conf" \
  /tmp/shadowrocket-strict.candidate.conf
cp shadowrocket-cn-direct-anti-leak.conf \
  /tmp/shadowrocket-broad.candidate.conf

ruby tools/build_shadowrocket_cn_rules.rb \
  --profile strict \
  --rules-output /tmp/v2fly-geolocation-cn-shadowrocket.candidate.list \
  --config /tmp/shadowrocket-strict.candidate.conf

ruby tools/build_shadowrocket_cn_rules.rb \
  --profile broad \
  --source https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/667c61b40dc4aae6d0e82c7a80b34f96a36102a3/geo/geosite/cn.list \
  --expected-sha256 1de88bc8a57adbd6aa236c281d1a3b18f557a5934ca20b234747068543907b8d \
  --rules-output /tmp/metacubex-geosite-cn-shadowrocket.candidate.list \
  --config /tmp/shadowrocket-broad.candidate.conf \
  --remote-url https://raw.githubusercontent.com/TheLearnerL/NobodyKonwYaml/refs/heads/main/generated/metacubex-geosite-cn-shadowrocket.list

ruby tools/validate_shadowrocket_config.rb \
  /tmp/shadowrocket-broad.candidate.conf \
  /tmp/metacubex-geosite-cn-shadowrocket.candidate.list

ruby tools/validate_shadowrocket_config.rb \
  /tmp/shadowrocket-strict.candidate.conf \
  /tmp/v2fly-geolocation-cn-shadowrocket.candidate.list

ruby tools/validate_shadowrocket_pair.rb \
  /tmp/shadowrocket-broad.candidate.conf \
  /tmp/shadowrocket-strict.candidate.conf
```

严格版默认下载 V2Fly 最新编译产物和官方 SHA-256 校验文件，只接受校验一致的源文件，并跳过无法安全等价转换的正则表达式规则。上面的广泛命令用已审批的固定 MetaCubeX 提交重建当前基线；日常更新由 GitHub Actions 先解析当时的 `meta` 提交，再用该固定提交 URL 和实际 SHA-256 生成候选文件。候选差异审查与手动回滚步骤以维护手册第 8 节为准。

## 广泛版远程发布与自动更新

广泛版成品只允许下面这条经验证器锁定的 HTTPS URL，位置在所有境外强制代理规则之后：

```ini
RULE-SET,https://raw.githubusercontent.com/TheLearnerL/NobodyKonwYaml/refs/heads/main/generated/metacubex-geosite-cn-shadowrocket.list,DIRECT
```

不得同时启用广泛和严格两个 `DIRECT` RULE-SET，否则实际结果会变成两表并集。OpenAI、Claude、Google、TikTok、Lark、AliExpress 等 `PROXY` 覆盖必须继续位于远程规则之前，`GEOIP,CN` 和 `FINAL,PROXY` 必须位于其后。严格版 Shadowrocket 成品不使用该 URL，仍从本地内嵌区读取规则。

`.github/workflows/update-metacubex-shadowrocket.yml` 每周一 `12:23`（`Asia/Taipei`）定时运行，并支持 `workflow_dispatch` 手动触发；首次上传或以后修改 Workflow/两个公开工具时也会触发一次。`push` 路径过滤不包含生成产物，所以自动提交不会形成循环。任务把 MetaCubeX `meta` 解析为固定提交，下载并计算 SHA-256，只接受 `+.domain`，并执行 10–20 万条总量门限、总量变化门限、规则集合新增/删除 5% 加 100 条门限、`tools/validate_shadowrocket_ruleset.rb` 公开产物验证和 `git diff --check`。上游内容未变时不会提交；任何步骤失败时不覆盖、不推送候选文件，Raw URL 继续提供上一版产物。

`main` 是可变 URL：一旦新产物发布且 Shadowrocket 刷新缓存，上游新增的误分类也可能自动获得 `DIRECT` 权限。Actions 发布周期不等于 Shadowrocket 的实际刷新时间；必须在目标 iPhone 验证首次下载、后续刷新、离线启动、HTTP `404` 和缓存失效行为。公开 Raw 必须可未登录读取；私有仓库不会把浏览器登录态传给 Shadowrocket，不得把 GitHub Token 写入配置。

完整本地配置库含非空 controller `secret`，不能直接公开。公开自动更新子集只包含 Workflow、`tools/build_shadowrocket_cn_rules.rb`、`tools/validate_shadowrocket_ruleset.rb` 和 `generated/` 产物；完整配置与本地双版验证不是公开 Workflow 的依赖。如果默认分支的 Branch Protection/Ruleset 或 Actions 的 Workflow permissions 禁止 `GITHUB_TOKEN` 写入，自动任务会在推送阶段失败并保留旧产物；应修正仓库权限或改为审批后合并，不应使用明文 PAT 绕过。

## 上游许可

`metacubex-geosite-cn-shadowrocket.list` 是对 MetaCubeX `meta-rules-dat` 数据的机械格式转换。上游仓库声明为 GPL-3.0；生成文件会保留固定来源、源 SHA-256 和许可证链接，具体归属见 `THIRD_PARTY_NOTICES.md`。公开仓库根目录的其他许可证不能把该第三方转换产物重新声明为公共领域。

## Mihomo / OpenClash 双 CN provider 模式

四份 Mihomo/OpenClash 成品配置同时定义广泛版与严格版 CN provider，并分别使用独立缓存路径。严格名单必须使用 `raw.githubusercontent.com` 原始文件地址，不能使用 GitHub `blob` 网页地址：

```yaml
cn-domain-broad:
  <<: *rule-provider-defaults
  behavior: domain
  path: ./ruleset/cn-domain.mrs
  url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/cn.mrs"

cn-domain-strict:
  <<: *rule-provider-classical-defaults
  path: ./ruleset/v2fly-geolocation-cn-shadowrocket.list
  url: "https://raw.githubusercontent.com/TheLearnerL/NobodyKonwYaml/refs/heads/main/generated/v2fly-geolocation-cn-shadowrocket.list"
```

两个 provider 都通过 `家宽` 组下载并按各自的 `path` 缓存。广泛版成品只引用 `cn-domain-broad`，严格版成品只引用 `cn-domain-strict`；不得把两条 `RULE-SET` 同时指向 `直连`。当前严格名单跟随 `main` 更新，若需要版本完全固定，应把 URL 改为已审查的提交 SHA。

GitHub 仓库和目标文件必须允许未登录访问。Mihomo 不会继承浏览器登录状态；私有仓库即使能在已登录浏览器中打开，`raw.githubusercontent.com` 对规则提供器仍会返回 `404`。若需要保持仓库私有，应改用可公开读取的自托管地址，不要把 GitHub Token 明文写进配置。

Google、OpenAI、Claude、TikTok、流媒体、游戏等专用规则必须位于当前启用的 CN `RULE-SET` 之前；`proxy-domain` 和最终 `MATCH,家宽` 必须位于 CN 之后。`dns.nameserver-policy` 必须与主规则启用同一个 CN provider。
