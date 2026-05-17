# M0.5 Prototype Findings

**起：** 2026-05-17
**止：** _(填写)_
**硬件：** _(Looi model / serial / 包装上标识)_
**固件版本：** _(从 GATT Device Information service 读取，或 inspect 推断)_
**iOS 测试设备：** _(iPhone model + iOS version)_

> 此文档伴随 M0.5 probe 同步演化。完成时整合归档，成为 M1 LooiKit spec 的 §2 输入。
> 所有"验证"指：probe app 实测重复成功 ≥ 3 次。

---

## 1. GATT 拓扑

通过 ScanView → 连接 → InspectView → "Discover all services" → "Copy topology as JSON" 导出后，粘贴在下面：

```
(从 InspectView 复制 JSON 到这里)
```

### 服务 UUID 归类

| 服务 UUID | 推断用途 | 来源 |
|---|---|---|
| _(填)_ | _(motion / sensor / config / DIS / GAP / GATT)_ | _(实测推断 / Nordic UART 模式 / ref repo)_ |

---

## 2. 验证有效的命令 ✅

| 命令 | 目标 characteristic | 字节序列 (hex) | 来源 | 实测行为 |
|---|---|---|---|---|
| _(e.g. wave hand)_ | _(uuid)_ | `7e a1 03 00 ff` | andrey-tut | 机器人右臂挥动 1 次 |
| | | | | |

---

## 3. 参考 repo 描述但实测失效的命令 ❌

| 来源 ref 中的命令 | 文档描述 | 我试的字节 | 实测结果 | 推测原因 |
|---|---|---|---|---|
| _(e.g. light pattern from sooper)_ | "rainbow cycle" | `5a 02 ff` | 无响应 | 固件已更新 / characteristic UUID 变了 |
| | | | | |

---

## 4. 行为有偏差的命令 ⚠️

| 命令 | 文档预期 | 实测行为 | 是否可用 |
|---|---|---|---|
| | | | |

---

## 5. 传感事件映射

订阅 notify characteristic 后，物理触发 → 收到 byte 流，反推语义：

### 触摸（touch）

| 物理动作 | characteristic | 收到字节序列 (hex) | 频率 / 持续 |
|---|---|---|---|
| 摸头顶 | _(uuid)_ | _(hex)_ | _(单次 / 持续 / N Hz)_ |
| 摸下巴 | | | |
| 摸背部 | | | |

### 动作（motion / IMU）

| 物理动作 | characteristic | 字节模式 | 推断坐标 |
|---|---|---|---|
| 抬起 / 放下 | | | |
| 左右摇晃 | | | |
| 旋转 | | | |

### 电量 / 状态

| 信号 | characteristic | 字节解读 |
|---|---|---|
| 电量百分比 | | |
| 充电状态 | | |
| 低电量警告 | | |

---

## 6. M1 LooiKit 设计含义

prototype 反过来要怎么影响 M1 spec？逐条记录：

- _(e.g. "MotionController.wave 直接映射到 char X 的字节 Y；不需要 'wave' 抽象层")_
- _(e.g. "SensorStream 的 touch 事件需要 debounce —— 同一次触摸会触发 3-5 个 notify")_
- _(e.g. "电量信号的 update 频率是 5s 一次；UI 显示不要假设高频")_
- _(e.g. "BLE 命令往返延迟实测中位数 X ms / p95 Y ms —— 影响 lipsync 节拍策略")_

---

## 7. 已知未解（M1 / M2 处理）

把没搞定的列在这里，避免遗忘：

- _(e.g. "Light 命令所有 candidate 都无响应；可能要逆向 OEM app 抓 BLE 流量")_
- _(e.g. "找到 6 个 service，3 个用途未明 —— 推后到 M1 prototype 部分继续探测")_
- _(e.g. "BLE 连接偶尔在 iOS 锁屏 30s 后掉 —— background mode 配置 M3 处理")_

---

## 8. 工具链 & 操作记录

为后人 / 未来固件升级时复跑准备：

### 重跑步骤

```
1. 开 Xcode → ulooi.xcodeproj → 选 iPhone target
2. Cmd+R → 装到真机（需在 Settings → General → VPN & Device Management 信任 dev profile）
3. App 启动 → 默认进 DevTools (M0.5 期间)
4. Scan tab → Start Scan → 等 Looi 出现（按 RSSI 排序，最近的在顶）
5. Connect → 跳到 Inspect tab → Discover all services
6. ...
```

### 已知坑

- _(e.g. "iOS 蓝牙权限第一次拒绝后，要去 Settings.app 手动开启")_

---

## 9. 时间日志

| 日期 | 进度 | 卡点 |
|---|---|---|
| 2026-05-17 | scaffold 完成（DevTools 五屏 + BLECentral 雏形）；待上机 | — |
| _(下一日填)_ | | |

---

## 10. 整合 → M1 spec 时的迁移清单

完成 M0.5 后这里列出要带去 M1 spec 的具体条目，避免遗漏：

- [ ] §1 GATT 拓扑 → M1 spec "§2 LooiKit 抽象层 / 命令字典"
- [ ] §2 验证有效命令 → M1 spec "命令字典" 表
- [ ] §5 传感事件映射 → M1 spec "SensorStream 设计"
- [ ] §6 M1 设计含义 → M1 spec 各章节的"prototype-driven decisions"
- [ ] §7 已知未解 → M1 spec "风险与开放问题"
