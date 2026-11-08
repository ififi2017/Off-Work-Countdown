# Wire 契约（T02）

源：`9252fdf` 的 `RecordJSON.swift`、`RecordArchive.swift`、12 类实体、`RecordSchemaCompatibilityTests.swift`。

版本独立：**wire = 8**（接受 1…8；v7 由计划 020 加入请假记录；v8 由计划 021 C1 加入工作地点自动化来源摘要）；本地档案文件（`RecordLocalFile`）的 `schemaVersion` 跟随 wire；fixture 协议 v1；sync envelope 尚未创建。D-13：Android 不使用 Room 业务表。

## 1. 用户导出信封 `RecordJSONDocument`

当前导出恒为 `schemaVersion: 8`。`exportedAtMs` 为 Unix **毫秒**。民用日为 `YYYY-MM-DD`（实现用 `uuuu-MM-dd` / `ISO_LOCAL_DATE`，禁止 Java `YYYY`/`DD`）。

| JSON key | 类型 | 可空 | 缺省 | 首次 | v8 导出 |
|---|---|---|---|---|---|
| schemaVersion | Int | 否 | — | 1 | 8 |
| exportedAtMs | Double | 否 | — | 1 | 是 |
| timeZoneIdentifier | String | 否 | IANA | 1 | 是 |
| calendarIdentifier | String | 否 | gregorian / iso8601 | 1 | 是 |
| careerPeriods | [] | 否 | [] | 1 | 是 |
| scheduleSnapshots | [] | 否 | [] | 1 | 是 |
| calendarExceptions | [] | 否 | [] | 1 | 是 |
| dayOverrides | [] | 否 | [] | 1 | 是 |
| workObservations | [] | 否 | [] | 1 | 是 |
| lifeProfile | object? | 是 | null；导出可 `includeLifeProfile:false` 整段去掉 | 1 | 是 |
| focusTasks | []? | 是 | apply 时 ?? [] | 1（无 bump） | 有则写 |
| focusSessions | []? | 是 | ?? [] | 1（无 bump） | 有则写 |
| focusPlanningConfiguration | object? | 是 | null | **4** | 有则写 |
| syncedPreferences | object? | 是 | null；`!isValid` 则拒绝该行 | **5** | 有则写 |
| recordsStartedOn | String? | 是 | null | **3** | 有则写 |
| extendedSchedule | object? | 是 | null；`!isValid` 拒绝 | **6** | 有则写 |
| rosterDays | []? | 是 | [] | **6** | 有则写 |
| leaveBalances | []? | 是 | [] | **7** | 有则写 |
| leaveDays | []? | 是 | [] | **7** | 有则写 |
| workTimeProvenance | []? | 是 | [] | **8** | 有则写 |

拒绝：`schemaVersion ∉ 1...8` → `unknownSchemaVersion`；坏 JSON → `invalidDocument`。v2 可解码，历史从未写出，形状按最后 v1。

## 2. 版本增量（来自源测试头注释）

| 写出的 schema | 新增顶层 | 行内新字段 |
|---|---|---|
| 1 | 核心六类 + lifeProfile；同版本后期加入 per-row TZ 与 focus 数组 | — |
| 2 | **无构建写出** | 按 v1 |
| 3 | recordsStartedOn | 观测 edit 戳；人生 partial/sleep；Focus 图标/收藏/模板/会话 kind 等 |
| 4 | focusPlanningConfiguration | — |
| 5 | syncedPreferences | 人生 workHistoryMode / 薪资经历 / futureIncomeDecline |
| 6 | extendedSchedule, rosterDays | — |
| 7 | leaveBalances, leaveDays | — |
| 8 | workTimeProvenance | — |

降级剥离规则与 `downgraded(_:to:)` 一致，生成器 `scripts/android-synthetic-archives.mjs` 复制该逻辑。

## 3. 十五类实体

合并通例：身份键冲突时更高 `editCount` 胜；平手比较 `editTieBreaker` **UUID 字符串**（统一大小写后的字典序，不用 JVM `UUID.compareTo`）。墙上时钟不决胜。

### 3.1 CareerPeriod `careerPeriods[]` 身份 `id`

id, startsOn, endsBefore?, label?, timeZoneIdentifier?, calendarIdentifier?, createdAtMs, editedAtMs, editCount, editTieBreaker。  
`endsBefore` 必须 `> startsOn` 否则拒行。

### 3.2 ScheduleSnapshot `scheduleSnapshots[]` 身份 `id`

id, periodID→CareerPeriod, effectiveFrom, configurationData (**JSON Data / base64**), fingerprint, editedAtMs, editCount, editTieBreaker。  
`configurationData` 内嵌 `ScheduleHoursConfiguration`：startTime, endTime, workdays[0=Sun], schedule{mode, referenceWeekStartMs?, referenceWeekType?, singleWeekendWorkday?, rotationAnchorMs?, rotationWorkDays?, rotationRestDays?}, breakStartTime?, breakDurationMinutes, extendedContent?。  
运行时 `extendedSchedule` overlay **不进** 该 blob 的 live roster。

### 3.3 CalendarException `calendarExceptions[]` 身份 `dayKey`=`YYYY-MM-DD#origin`

dayKey, date, effect=`rest|work`, origin=`user|bundled`, isCleared, regionIdentifier?, datasetVersion?, label?, editedAtMs, editCount, editTieBreaker, timeZoneIdentifier?。

### 3.4 DayOverride `dayOverrides[]` 身份 `dayKey`

dayKey, kind=`confirmedAsScheduled|customSegments|notWorking|cleared`, segments[{startAtMs,endAtMs}], note?, editedAtMs, editCount, editTieBreaker, timeZoneIdentifier?。  
`customSegments` 必须有不重叠正段；其他 kind 段必须空。

### 3.5 WorkObservation `workObservations[]` 身份 `eventID`

eventID, shiftAnchorDate, occurredAtMs, kind=`timerSurfaceFirstSeen|countdownStarted|countdownStopped|overtimeDeclared`, valueData?, scheduleSnapshotID, schemaVersion（**实体**版本，当前 2，不是 wire）, timeZoneIdentifier?, editedAtMs?, editCount?, editTieBreaker?。  
v1/v2 缺戳：editedAt=occurredAt，editCount=1，tieBreaker=eventID。有效 editCount=`max(1, …)`。

### 3.6 LifeProfile 单例 身份固定 `00000000-0000-0000-0000-00574F524B01`

legacy：birthYear?, workStartedOn?, retirementAge?, averageSleepHours?, hidesExactAges。  
v3：bornOn/schoolStartedOn/workStartedPartial/retirementOn (`PartialCivilDate`{year,month?,day?,precision=`year|day`}), averageSleepMinutes?, sleepSource=`manual|healthSuggested`, sleepSourceUpdatedAtMs?。  
v5：workHistoryMode=`rough|detailed`（缺省 rough）, roughCurrentSalary?{amount,cadence=`monthly|yearly`}, employmentPeriods?[], futureIncomeDecline?{startsAtAge,retirementRatio 0…1}。  
stamps：editedAtMs, editCount, editTieBreaker。apply 后跑 `migrateLegacyFields`。

### 3.7 FocusTask `focusTasks[]` 身份 `id`

id, createdAtMs, plannedForDate?, scheduledStartAtMs?, title, estimatedPomodoros, icon? (`focus|work|code|study|writing|communication|meeting|idea`，缺省 focus), isFavorite?（缺省 false）, completedAtMs?, deletedAtMs?, sortIndex, editedAtMs, editCount, editTieBreaker, templateID?, templateTaskKey?。

### 3.8 FocusSession `focusSessions[]` 身份 `id`

id, taskID?, shiftAnchorDate, startedAtMs, plannedEndAtMs, endedAtMs?, endReason?=`completed|stoppedByUser|stoppedAtBoundary|abandoned|supersededBySync`, editedAtMs, editCount, editTieBreaker, kind?=`focus|shortBreak|longBreak`（缺省 focus）, timeZoneIdentifier?, anchorDayKey?, actualDurationSeconds?（**秒**）, plannedEndReason?。

### 3.9 FocusPlanningConfiguration 单例 逻辑键 `focus-planning`

plans[{dayKey, shiftStartAtMs:Int64, assignments[{blockStartAtMs, kind=`task|breakTime`, taskID?, taskTitle?, taskIcon?}], appliedTemplateID?}], templates[{id,name,slots[{blockIndex,kind,taskKey?,taskTitle?,taskIcon?}],createdAtMs,updatedAtMs}], defaultTemplateID?, autoAppliedDayKeys, focusMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery, editedAtMs, editCount, editTieBreaker。  
导入归一化：10–60 / 1–15 / 5–30 / 2–6。

### 3.10 SyncedPreferences 单例 逻辑键 `preferences`

分钟域 0–1439：startMinutes, endMinutes, lunchStartMinutes。  
workdays[0–7], scheduleMode=`classic|alternating|rotation|off`, alternatingWeekType=`single|double`, alternatingWeekendWorkday, alternatingReferenceWeekStartMs, rotationWorkDays/RestDays, rotationAnchorMs, lunchEnabled, lunchDurationMinutes, recordsTimeZoneIdentifier, salaryAmount（**十进制字符串**）, salaryEnabled, salaryType=`monthly|daily`, monthlyWorkingDays, annualBonusEnabled, annualBonusMonths, notificationMode=`off|simple|milestones`, cycleEndSummaryNotificationEnabled, lunchStart/EndReminderEnabled, microBreakEnabled, microBreakIntervalMinutes(1–720), theme=`auto|light|dark`, languageOverride?, editedAtMs, editCount, editTieBreaker。  
`editedAt` Date 仅解码遗留，**不编码**。

### 3.11 ExtendedSchedule 单例 逻辑键 `extended-schedule`

isEnabled, shiftTypes[{id,name(trim 1–40),kind=`work|rest`,startMinutes,endMinutes(≤start 表示次日),breakEnabled,breakStartMinutes,breakDurationMinutes,colorHex,isArchived}], rule?{preset=`weekly|alternatingWeeks|rotation|custom`（未知→custom）,anchorDayKey,days[] 1–366}, holidayRegionIdentifier?, clearedFromDayKey?, timeZoneIdentifier, editedAtMs, editCount, editTieBreaker。

### 3.12 RosterDay `rosterDays[]` 身份 `dayKey`

dayKey, shiftTypeID, assignedShiftType?（冻结班型拷贝）, generatedFromPattern?, timeZoneIdentifier, editedAtMs, editCount, editTieBreaker。

### 3.13 LeaveBalance `leaveBalances[]` 身份 `id`

id, kind（`annual|compensatory|custom`，其他字符串读作 custom，不使整份文档失败）, name?（trim 后 ≤40 个字符；custom 必填）, entitledHalfDays, usedHalfDays（均为 0–7320 的半天整数）, validFromDayKey?, validThroughDayKey?（含首尾，起不晚于止）, editedAtMs, editCount, editTieBreaker。`restoreErased` 重映射 id 时同步改写请假日 `uses[].balanceID`。

### 3.14 LeaveDay `leaveDays[]` 身份 `dayKey`（班次起始日）

dayKey, portion（`whole|firstHalf|secondHalf`，字符串；未知值只拒该行）, uses[{balanceID, halfDays>0}]（为空，或各余额不重复且合计等于 portion 的半天数）, planID?, timeZoneIdentifier, editedAtMs, editCount, editTieBreaker。余额从不递减：已采用方案占用的半天数是各请假日 uses 之和。

### 3.15 WorkTimeProvenance `workTimeProvenance[]` 身份 `dayKey`（班次锚定日，计划 021 C1）

iOS 3.3.0 工作地点自动化采用上下班时间时写入的最小来源摘要，与同日 `dayOverrides` 行对应（iCloud 记录名 `prov.<dayKey>` 对 `day.<dayKey>`）。字段：dayKey, boundaries[], timeZoneIdentifier, editedAtMs, editCount, editTieBreaker。每个 boundary：boundary（`start|end`）, timeMs（采用的时间）, source（`nativeGeofence|appIntentAutomation|userConfirmation`）, observedAtMs?, receivedAtMs, appliedAtMs, appliedBy（`automatic|reviewed`）, batchID?（UUID）, rulesVersion（≥1）, evidenceLevel（`systemObservation|callbackReceipt|externalAction|personStatement`）, reasons[String]（≤16 条，每条非空且 ≤64 个字符；未知原因原样保留）。

行有效：dayKey 合法、时区可识别、boundaries 1–8 条且边界类型不重复、各值有限。枚举类字段是字符串：未知值只拒该行，不使文档失败；时间写成字符串、缺少 reasons、rulesVersion 非整数则整份文档无效（`Codable` 语义）。未知字段（如坐标、SSID）读取时丢弃、导出不写。

**不含坐标、SSID、地点名称或围栏标识。** “定位认证”不存储，由 iOS 在显示时比较摘要的采用时间与当前 `DayOverride` 边界得出；清除 `DayOverride` 时保留来源行，用户删除证据时来源行单独写墓碑。iCloud 侧整行胜负（`supportsFieldMerge = false`），实体修订号升到 4。

**Android 3.3.0 只读取并原样保留**：导入、合并、墓碑、本地档案与导出都按上述规则保留该实体，不实现定位功能，也不展示或编辑它。

## 4. 不进用户 v8 的本地/同步层

`RecordLocalFile`：schemaVersion, document(嵌入备份字节), erased[], sync?。  
`ErasedDTO`：entityType, logicalKey, erasedAtMs, editCount?。  
`RecordEntityType` raw：careerPeriod, scheduleSnapshot, calendarException, dayOverride, workObservation, lifeProfile, focusTask, focusSession, focusPlanningConfiguration, syncedPreferences, extendedSchedule, rosterDay, leaveBalance, leaveDay, workTimeProvenance。  
`SyncLocalState`：accountID, generation, syncEnabled, engineState, rows, conflicts, deletingCloud, entityTypeRevision。  
**购买凭据、StoreKit/Play token、JWS、isPlus 授权一律不在备份。** 薪资数字是用户数据，不是购凭证。

## 5. 导入

模式：`skipErased`（默认）、`restoreErased`（UUID 重映射并改写引用）、`resolveByEditStamp`。  
`recordsStartedOn` 取本地与导入的较早者。  
建议上限 25 MiB（产品保护，可按真实档案调整）。v9 不得当 v8 忽略字段导入。

## 6. 字段抽样勾选

| 家族 | 合成样本 | 含购凭证？ | 备注 |
|---|---|---|---|
| CareerPeriod | v1–v8 | 否 | label Current |
| ScheduleSnapshot | 全版本（测试 fullState 无，合成补了一条） | 否 | configurationData 为示意 JSON 的 base64 |
| CalendarException | 同上补一条 `2026-08-26#user` | 否 | |
| DayOverride | v1–v8 | 否 | customSegments 8h |
| WorkObservation | v1–v8 | 否 | v1 无 edit 戳 |
| LifeProfile | v1–v8 | 否 | 有薪资经历，非 IAP |
| FocusTask/Session | v1–v8 | 否 | |
| FocusPlanningConfiguration | v4–v8 | 否 | |
| SyncedPreferences | v5–v8 | 否 | salaryAmount 字符串 |
| ExtendedSchedule / RosterDay | v6–v8 | 否 | |
| LeaveBalance / LeaveDay | v7–v8 | 否 | 半天整数；请假日下半班 |
| WorkTimeProvenance | 仅 v8 | 否 | 上班（地理围栏、人工复核）与下班（快捷指令、自动）各一条；无位置字段 |

## 7. 合成档案

`docs/android/synthetic-archives/`。非法：v0、v9、非 JSON、`2026-02-30`、注入 `purchaseToken`/`isPlus`（用于证明**不得授 Plus**）。  
检查：`node scripts/android-synthetic-archives.mjs --check`。  
Kotlin/Room 往返 **NOT_RUN**。
