# Dear Home（亲爱的房子）产品架构交底 v0.1

- 产品名：Dear Home / 亲爱的房子（与房子对话）
- Bundle 建议：`com.s2.dearhome`（与 Dear Earth `com.s2.dearearth` 同前缀）
- App Group（共享本地大模型）：`group.com.robotzero.shared.ai`（白皮书）兼兼容 `group.com.s2.dearuniverse` 探测
- 参考工程：`/Users/David1/Future/DearEarth`（已提交成功；本交底要求复用其对话引擎 / Hippocampus-CLS / 共享 LLM）
- 手稿 UI 五 Tab：Dear Earth（对话入口）· Space · Memories · Evolution · Setting
- 交底人：Miles / 大向 · 执行：千里眼

## 1. 产品定位（三核一体）

1. **陪伴智能体**：把住宅拟人化为有灵魂、有记忆的生命体与家庭大管家；用户可情感倾诉、日常闲聊（借鉴 Dear Earth Companion / LocalDialogueEngine）。
2. **HomeKit 控制入口**：关联 Apple 智能家居，读写/建议控制场景与设备（suggest-only 优先；实际控制经 HomeKit 授权）。
3. **家庭传话筒（MQTT）**：主人设备 = MQTT 网关主机；家人设备 = 终端。抽取对话/家居事件中的「家庭信息」经网关共享；同步模式：**每日 00:00** 或 **实时**（主人设定）。

人格递变：各成员 Dear Home 共享家庭事实记忆，但每日 ≤1% 演化向量递变（受各自沟通对象影响）→ 人格不同、混合型记忆大致同步。

## 2. 信息架构（对齐手稿）

| Tab | 职责 |
|---|---|
| Dear Earth / Home Chat | 与「房子」对话主界面；气泡可标注来源（Apple Home / 家人 APP / 本机 Agent） |
| Space | 空间/房间拓扑与设备态；事件时间线（客厅/餐厅…） |
| Memories | CLS 记忆：热周 7 天 + 30 天循环池 + 日/周蒸馏 + .md 导出 |
| Evolution | 12D（或 Home 特化）演化曲线；家庭人格差异对比（只读自家） |
| Setting | HomeKit、MQTT 角色（主人/家人）、同步策略、共享 LLM 状态、订阅 |

事件日志示例（手稿）：
- 客厅空调 25°C / 湿度 60% / 风速 1 档 @07:00（来自 Apple 智能家居）
- 07:05 主人开吊灯（来自爸爸 APP）
- 07:15 墙开关键灯（来自 Smart Home Agent）
- 餐厅 11:15 女儿语音开灯

## 3. 模块划分（SwiftUI / iOS 17+ / Swift 6）

```
DearHome/
  App/                 # DearHomeApp, AppModel, RootTabView
  Core/
    Companion/         # 复用 Dear Earth CompanionPipeline 模式
    Engine/            # LocalDialogueEngine / SkillRetriever（Home SKILL）
    Hippocampus/       # CLS：日 00:00 蒸馏、周固化、30 天环、PendingDistillation
    LLM/               # EcosystemModelCenter 绿色通道 + LlamaRuntime
    Evolution/         # ≤1% 向量递变（绑定「沟通对象」因子）
    HomeKit/           # HMHomeManager 桥、场景/设备只读+控制、事件归一化
    MQTT/              # 主人 Broker/网关 · 家人 Client · 家庭信息信封 · 日切/实时同步
    FamilyGraph/       # 成员角色、权限、人格分叉状态
    Storage/           # Application Support/DearHome/ 沙盒
  Features/
    Chat/ Space/ Memories/ Evolution/ Settings/
  Resources/           # 默认 Home SOUL + 家居 SKILL 种子
```

## 4. 数据与同步

- 本地沙盒：`Application Support/DearHome/`（对齐 Dear Earth DistilledEarth 隔离思路，单 Home 智能体 + 家庭共享层）
- CLS（附件一）：日 00:00 → 300 字对话要点 + 300 字家居/日程总结 + ≤1% 演化；周一 00:00 周固化加权标签；30 天 FIFO；无模型则 PendingDistillation
- MQTT 信封（建议）：`familyId / msgId / ts / kind(fact|event|digest) / room / source / payload / syncMode`
- 日同步：各端攒本地 `pending_family_facts`，00:00 与网关交换日摘要；实时：发布即投递
- 隐私：原始私密倾诉默认不上 MQTT；仅「家庭信息抽取器」白名单字段出域

## 5. 复用 Dear Earth 的优先清单

必须对齐/移植模式：
- `Core/Hippocampus/*`（MemoryLifecycleCoordinator, MidnightDailyScheduler, WeeklyMondayConsolidator…）
- `Core/LLM/EcosystemModelCenter` + App Group 共享
- `Core/Evolution/MidnightEvolutionEngine`（1% clamp）
- `Core/Companion/*` + `Core/Engine/LocalDialogueEngine`
- `project.yml` / XcodeGen / bundle `com.s2.*` / DEVELOPMENT_TEAM

Home 新增（Dear Earth 无）：
- HomeKit 桥、MQTT 家庭总线、Space 房间时间线、家庭信息抽取器

## 6. MVP 分期

**MVP-1（本轮脚手架）**
- XcodeGen 工程 `DearHome`、五 Tab 壳、品牌主题
- Home SOUL 种子 + 本地对话引擎可聊
- Hippocampus CLS 骨架（调度器 + 模型协议 + Pending 队列）
- HomeKit 权限与房间/设备只读列表 + 事件写入 Space 时间线（模拟源可切换）
- MQTT：角色选择、局域网发现占位、日/实时同步开关、信封编解码单元测试
- Settings：共享 LLM 状态条、同步模式

**MVP-2**
- 真 MQTT broker（主人端嵌入或外置）+ 家人扫码/二维码入网
- 家庭信息抽取 LLM/规则双通道
- 演化页曲线 + 多成员人格分叉可视化

**MVP-3**
- HomeKit 写控制与 Siri/场景联动、订阅门闸、App Store 元数据

## 7. 成功标准（本轮）

- 仓库可 `xcodegen generate` 出工程；五 Tab 可运行（Simulator）
- 单元测试覆盖：演化 1% clamp、MQTT 信封编解码、日/实时同步状态机 stub
- README 写明如何对照 Dear Earth 复用与差异
- 不提交 llama.xcframework / 模型权重；沿用 Dear Earth 下载+共享方案
