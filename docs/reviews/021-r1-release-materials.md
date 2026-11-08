# 021 R1 · 3.3.0 工作地点自动化发布材料草稿

- **状态**：DRAFT（2026-11-09）。待 P0 真机结论与所有者审定后才能发布；本文件不授权提交审核、不修改官网或 App Store Connect。
- **适用范围**：iOS 3.3.0 的工作地点自动化（[Plan 021](../../plans/iOS/021-workplace-automation.md)）。Android／Siri／Wi-Fi 不在本版。
- **依据**：main 上的 P1／I1／C1／U1、#376（定位认证标识与移除来源）、#377（I2 原生监控）与 #380（删除自动化数据）。提交审核前须按最终 archive 再核对本文件一次。
- **官网**：长文由官网仓库维护，只有英文与简体中文两版（`lib/content-locales.ts`）。下文是交给官网 PR 的源文案，沿用 [Android 隐私补充](../android/privacy-policy-addition.md) 的做法；不要直接把本文件当作已发布政策。

## 0. 发布前必须解决或确认的事项

| # | 事项 | 原因 |
|---|---|---|
| B1 | P0 结论写入 `docs/reviews/021-workplace-automation-capability.md`，确认关闭 App、冷启动与锁屏时能否收到到离事件 | 定位用途说明与审核备注都写了 “即使 App 已关闭”；若划掉 App 后不可靠，20 个 `InfoPlist.strings` 与本文件须一并改写 |
| B2 | 决定 Release 是否显示设置入口（`WorkplaceAutomation.showsSettingsEntry`） | 目前只在 DEBUG 显示；审核员看不到入口就无法复现，提交前必须打开 |
| B3 | 是否需要 `UIBackgroundModes` 的 `location` | I3 要求只按实际依赖配置；`CLMonitor` + `CLServiceSession` 预期不需要，以 P0 结果为准，并在 PR 写明 |
| B4 | ✅ 已由 #380 加入“删除自动化数据”（原为：缺少该入口） | 现在只能逐个删除工作地点（移除坐标）；已记录的到离事件与未采用建议只在 90 天后自动清理，关闭自动化不会删除。隐私页的删除说明会因此不完整。建议在设置页加入“删除自动化数据”（清空本机自动化文件、移除系统监控条件，不动已采用工时与其来源） |
| B5 | ✅ #376、#377 已合入 | 隐私页提到的“移除来源详情”和到离通知来自这两个 PR |
| B6 | 最终 archive 核对 | 确认没有新增 SDK、网络请求或诊断上传，App 隐私标签结论才成立（§3） |

## 1. 官网隐私页源文案

### English source copy

**Update “Last updated”.**

**Update “This typically includes”:** add a bullet: “Workplace Automation (iPhone, optional): saved workplaces, arrival and departure events, and the source details of work times you adopt — see below.”

**Insert after “Optional iCloud sync”:**

### Workplace Automation on iPhone

Workplace Automation is off by default and is part of DoneAt Plus. When you turn it on and allow location access, iOS watches the areas around up to five workplaces you save and tells DoneAt when you arrive at or leave one, including when DoneAt isn't open. DoneAt does not record your route or your position over time; it receives only these arrivals and departures. Your position is determined by Apple's Location Services under Apple's policies. DoneAt does not send location information to DoneAt servers or to any other service.

The following stay only on that iPhone and are excluded from iCloud sync, backup exports and device backups: each workplace's name, coordinates and range; arrival and departure events; whether you are currently inside a workplace; and detected times waiting for your review. Detected times you don't adopt, and the events behind them, are deleted after 90 days.

A detected time changes your hours only when you adopt it, or when you turn on automatic apply. An adopted time becomes part of your work records like any other edit. DoneAt also saves a short summary of where it came from: whether it was a start or end, whether it came from location, a Shortcuts automation or your own confirmation, when it was observed, received and adopted, how it was adopted, and the rule version and reasons used. This summary never contains coordinates, workplace names, addresses or Wi-Fi names. It syncs with your records when iCloud sync is on and is included in backup exports. You can remove a day's source details in Records; the work times stay.

“Location verified” means your device's location supports the start or end time you adopted. It is not approval by an employer, an exact entry time or proof that you worked the whole day.

Shortcuts actions for arriving and leaving work don't use DoneAt's location access; the Shortcuts automation you set up decides when to run them. Notifications about arrivals, departures and questions never include a workplace name, an address or pay.

**Update “Deleting your data”:** add: “On iPhone, deleting a workplace removes its location from DoneAt. Delete Automation Data in Workplace Automation settings removes saved workplaces, events, pending times and days away from the office from the device and turns automation off. Turning Workplace Automation off stops monitoring. Adopted work times and their source details stay in your records until you change or delete them; uninstalling removes everything stored on the device.”

**Update “Third-party services”, Apple bullet:** add “, and Location Services for Workplace Automation when you turn it on”.

**Update “Widgets, Live Activities and device protection” (optional):** “Workplace Automation notifications follow the same rule: no workplace name, address or pay.”

### 简体中文源文案

**更新“最后更新”日期。**

**“通常包括”列表新增：**“工作地点自动化（iPhone，可选）：已保存的工作地点、到达与离开事件，以及你所采用工时的来源摘要，详见下文。”

**在“可选的 iCloud 同步”之后加入：**

### iPhone 上的工作地点自动化

工作地点自动化默认关闭，属于 DoneAt Plus。开启并允许定位后，iOS 会留意你保存的最多五个工作地点周围的范围，并在你到达或离开时通知 DoneAt，即使 DoneAt 没有打开。DoneAt 不记录你的行动路线，也不持续记录你的位置，只接收这些到达与离开。位置由 Apple 定位服务按 Apple 的政策确定；DoneAt 不会把位置信息发送到 DoneAt 服务器或任何其他服务。

以下内容只保存在那部 iPhone 上，不参与 iCloud 同步、备份导出或设备备份：每个工作地点的名称、坐标与范围；到达和离开事件；你目前是否在工作地点内；以及等待你复核的检测时间。未采用的检测时间及其事件会在 90 天后删除。

检测到的时间只有在你采用后（或开启自动应用时）才会改变工时。采用后的时间与其他手动修改一样成为工作记录的一部分；DoneAt 同时保存一份简短的来源摘要：是上班还是下班、来自定位、快捷指令自动化还是你的确认、观察／收到／采用的时间、采用方式，以及使用的规则版本和原因。来源摘要不包含坐标、工作地点名称、地址或 Wi-Fi 名称；开启 iCloud 同步时随记录同步，也包含在备份导出中。你可以在记录中移除某一天的来源详情，工时保持不变。

“定位认证”表示设备位置支持你所采用的上班或下班时间，不代表雇主审核、精确的门禁时间，也不证明全天都在工作。

上班与下班的快捷指令动作不使用 DoneAt 的定位权限，由你设置的快捷指令自动化决定何时执行。到达、离开与询问的通知不包含工作地点名称、地址或薪资。

**“删除你的数据”新增：**“在 iPhone 上，删除工作地点会从 DoneAt 移除它的位置。工作地点自动化设置中的“删除自动化数据”会从设备上移除已保存的工作地点、事件、待复核时间与不在办公室的日子，并关闭自动化。关闭工作地点自动化会停止监控。已采用的工时及其来源摘要会保留在记录中，直到你修改或删除；卸载会移除设备上保存的所有内容。”

**“第三方服务”的 Apple 一项补充：**“，以及你开启工作地点自动化时使用的定位服务”。

## 2. App Store Connect

### 2.1 What's New 草稿（3.3.0）

内容以最终合入、且 Release 可见的功能为准；若 B2 决定本版不开放入口，删去自动化相关条目。

**en-US**

> Let DoneAt notice when you arrive at and leave work.
> • Workplace Automation (Plus): save up to five workplaces. Arrivals and departures are noted for you to review, or applied automatically if you choose. Early arrivals, extra visits and late starts get a gentle question instead of a guess.
> • Mark days for field work, business trips or working from home, so leaving the office doesn't end your day.
> • Shortcuts actions for arriving and leaving work, no location access needed.
> • Days with adopted times show where they came from, including “Location verified”.
> • Workplace locations stay on your iPhone.

**zh-CN**

> DoneAt 现在可以留意你何时到达和离开工作地点。
> • 工作地点自动化（Plus）：最多保存五个工作地点。到达与离开会先记下供你复核，也可以选择自动应用；早到、额外到访和晚到会温和地问你一句，而不是替你猜。
> • 可为外勤、出差或居家办公的日子做标记，离开办公室不会结束当天的工作。
> • 新增上班与下班的快捷指令动作，无需定位权限。
> • 已采用时间的日子会显示来源，包括“定位认证”。
> • 工作地点的位置只保存在你的 iPhone 上。

**zh-TW**

> DoneAt 現在可以留意你何時抵達和離開工作地點。
> • 工作地點自動化（Plus）：最多儲存五個工作地點。抵達與離開會先記下供你複核，也可以選擇自動套用；早到、額外到訪和晚到會溫和地問你一句，而不是替你猜。
> • 可為外勤、出差或居家辦公的日子做標記，離開辦公室不會結束當天的工作。
> • 新增上班與下班的捷徑動作，不需要定位權限。
> • 已採用時間的日子會顯示來源，包括「定位認證」。
> • 工作地點的位置只會儲存在你的 iPhone 上。

其余 16 个商店语言在定稿后再翻译，并按 `docs/APP-STORE-CONNECT-SYNC.md` 建立 `app-store-connect/ios/3.3.0.json`。描述、关键词与截图是否需要更新另行决定（现有 204 张截图不含自动化界面）。

### 2.2 App Review 备注草稿（英文）

`asc:sync` 不填写审核备注（`docs/APP-STORE-CONNECT-SYNC.md`），需在 App Store Connect 手动粘贴。

> **Workplace Automation and “Always” location access**
>
> DoneAt is a work-hours countdown and records app. In 3.3.0, an optional Plus feature, Workplace Automation, records the times a person arrives at and leaves the workplaces they saved, so their work records match when they really started and finished.
>
> Why “Always”: arrivals and departures usually happen while the app is closed (walking into the office, leaving in the evening). The app uses Core Location region monitoring (`CLMonitor` with circular conditions, held by a `CLServiceSession` with always authorization) for at most five saved workplaces, two circles each. It does not use continuous location updates, background audio or VoIP to stay running, and it does not record routes. “While Using” is enough to save the current position as a workplace; “Always” is requested only after the person turns Workplace Automation on, with the purpose explained in the app first.
>
> Data: workplace coordinates, events and pending times stay on the device, excluded from iCloud and device backups. Only adopted work times and a short source summary without any location join the person's private iCloud sync if they enabled it. Nothing is sent to our servers; the app has no account system.
>
> How to review:
> 1. Open the app's Settings → Workplace Automation. The feature requires DoneAt Plus; a sandbox purchase unlocks it.
> 2. Turn on Workplace Automation and allow location access, choosing “Always” when iOS asks.
> 3. Tap Add Workplace → Use Current Location → Save. The status under location access shows that DoneAt is watching for arrivals and departures.
> 4. Leaving the area (about 300 m) and returning produces a departure and an arrival. With “Apply Detected Times Automatically” off (default), they appear under Times to Review and in a quiet notification; adopting one updates that day in Records, which then shows its source.
> 5. Without moving: the Shortcuts app offers “Record Arrival at Work” and “Record Leaving Work” (plus “Confirm Work Started” and “Confirm Work Finished”), which run the same recording path without location access.
>
> To turn it off: switch off Workplace Automation (monitoring stops and all regions are removed), or delete a workplace, or revoke location access in iOS Settings. Existing records are kept.
>
> To delete everything automation keeps on the device, use Delete Automation Data at the bottom of the same page.
>
> [B2 定稿后补：入口位置；若提供审核演示视频，须为真实 Release 行为，不使用调试注入。]

## 3. App 隐私标签复核

依据 Apple “App Privacy Details” 的定义：只在设备上处理、不传给开发者或第三方的数据不算“收集”。逐项结论：

| 数据 | 去向 | 是否“收集” |
|---|---|---|
| 工作地点坐标、范围、名称 | 仅本机自动化文件，排除 iCloud 与设备备份 | 否 |
| 到离事件、在场状态、待复核建议、待基线条件 | 同上，90 天清理 | 否 |
| 用户位置 | 由 Apple 定位服务在设备上判定；DoneAt 只收到到达／离开 | 否（Precise Location 不申报） |
| 已采用工时与来源摘要（无位置） | 用户自选的私人 CloudKit 数据库；DoneAt 无法访问 | 否，与现有 iCloud 同步的判定一致 |
| 备份导出文件 | 用户自行保存或分享 | 否 |
| 通知内容 | 本地通知，不含地点或薪资 | 否 |

**结论（草稿）**：在 B6 确认最终 archive 没有新的网络传输、SDK 或诊断上传的前提下，iOS 可维持现有 “Data Not Collected”。注意 Plan 021 §6 的提醒：使用定位不自动意味着可以维持这一结论，必须以实际数据流为准；若之后加入任何服务器、分析或崩溃上报，须重新申报。Android 的 Data safety 不照搬此结论。

## 4. 其他发布检查

- 应用内文案已审：定位用途说明（20 个 `InfoPlist.strings`）、设置页隐私说明（`automationUIPrivacy`）、定位认证说明（`recordsVerifyNote`）与通知文案均不含工资、地点名称或地址。
- 提交后按 3.2.5 的格式写 `app-store-connect/ios/3.3.0/submission.md`，记录 build、审核提交与已知缺口。
- 发布前在 `plans/iOS/021-workplace-automation.md` §9 分别记录：代码完成、自动化通过、真机通过、审核材料完成、发布授权。
