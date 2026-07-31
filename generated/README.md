# Shadowrocket 中国域名规则维护说明

> 项目的目标、威胁模型、规则顺序、更新审查、真机验证和交接要求，请先阅读
> [`Shadowrocket 中国直连、其余代理、防泄漏配置维护手册.md`](<../Shadowrocket 中国直连、其余代理、防泄漏配置维护手册.md>)。

## 文件用途

- `v2fly-geolocation-cn-shadowrocket.list` 是从 V2Fly 官方 `dlc.dat_plain.yml` 中提取并展开的 `geolocation-cn`。
- 文件已经转换为不含策略名称的扁平 `DOMAIN` / `DOMAIN-SUFFIX` 文本；Shadowrocket 可作为 `RULE-SET` 使用，Mihomo 可作为 `classical + text` 本地 rule provider 使用。
- 当前主配置仍内嵌同一份本地快照，因此首次导入和离线启动不依赖远程规则源。

不要把 V2Fly 的原始 `data/geolocation-cn` 或整份 `dlc.dat_plain.yml` 直接填入 Shadowrocket。原始文件分别包含 `include:` 构建语法和多列表 YAML 结构，Shadowrocket 不会替 V2Fly递归展开或提取列表。

## 手动更新

在 `Yaml` 目录执行：

```bash
ruby tools/build_shadowrocket_cn_rules.rb \
  --rules-output generated/v2fly-geolocation-cn-shadowrocket.list \
  --config shadowrocket-cn-direct-anti-leak.conf

ruby tools/validate_shadowrocket_config.rb \
  shadowrocket-cn-direct-anti-leak.conf
```

默认会下载 V2Fly 最新编译产物和官方 SHA-256 校验文件。转换器只接受校验一致的源文件，并跳过无法安全等价转换的正则表达式规则。

## 可选远程模式

把生成的 `.list` 发布到自己控制的 HTTPS 地址后，可以在所有境外强制代理规则之后加入：

```ini
RULE-SET,https://raw.githubusercontent.com/<owner>/<repo>/main/generated/v2fly-geolocation-cn-shadowrocket.list,DIRECT
```

使用远程模式时，应删除配置中的本地生成区，避免重复。OpenAI、Claude、Google、TikTok、Lark、AliExpress 等 `PROXY` 覆盖必须继续位于远程规则之前，`GEOIP,CN` 和 `FINAL,PROXY` 必须位于其后。

直接引用 `main` 分支可以自动获得更新，但上游分类错误也会自动获得 `DIRECT` 权限。隐私优先时，建议先审查更新差异，再将审核后的文件发布到远程地址。

## Mihomo / OpenClash 本地模式

两份 Mihomo 配置把同一份已审查快照作为本地 `cn-domain` provider：

```yaml
cn-domain:
  type: file
  behavior: classical
  format: text
  path: ./generated/v2fly-geolocation-cn-shadowrocket.list
```

部署时必须把 `generated/v2fly-geolocation-cn-shadowrocket.list` 一起复制到 Mihomo 工作目录的对应相对路径。若客户端会把导入的主 YAML 复制到另一个目录，必须同步复制该文件或调整 `path`；缺少本地文件时，CN provider 不会正常加载。

Google、OpenAI、Claude、TikTok、流媒体、游戏等专用规则必须位于 `RULE-SET,cn-domain,直连` 之前；`proxy-domain` 和最终 `MATCH,家宽` 必须位于 CN 之后。
