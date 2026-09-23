# Wire 契约（T02）

源：`9252fdf` 的 `RecordJSON.swift`、`RecordArchive.swift`、12 类实体、`RecordSchemaCompatibilityTests.swift`。

版本独立：**wire = 6**（接受 1…6）；本地档案文件（`RecordLocalFile`）的 `schemaVersion` 跟随 wire；fixture 协议 v1；sync envelope 尚未创建。D-13：Android 不使用 Room 业务表。

## 1. 用户导出信封 `RecordJSONDocument`

当前导出恒为 `schemaVersion: 6`。`exportedAtMs` 为 Unix **毫秒**。民用日为 `YYYY-MM-DD`（实现用 `uuuu-MM-dd` / `ISO_LOCAL_DATE`，禁止 Java `YYYY`/`DD`）。

| JSON key | 类型 | 可空 | 缺省 | 首次 | v6 导出 |
|---|---|---|---|---|---|
| schemaVersion | Int | 否 | — | 1 | 6 |
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

拒绝：`schemaVersion ∉ 1...6` → `unknownSchemaVersion`；坏 JSON → `invalidDocument`。v2 可解码，历史从未写出，形状按最后 v1。

## 2. 版本增量（来自源测试头注释）

| 写出的 schema | 新增顶层 | 行内新字段 |
|---|---|---|
| 1 | 核心六类 + lifeProfile；同版本后期加入 per-row TZ 与 focus 数组 | — |
| 2 | **无构建写出** | 按 v1 |
| 3 | recordsStartedOn | 观测 edit 戳；人生 partial/sleep；Focus 图标/收藏/模板/会话 kind 等 |
| 4 | focusPlanningConfiguration | — |
| 5 | syncedPreferences | 人生 workHistoryMode / 薪资经历 / futureIncomeDecline |
| 6 | extendedSchedule, rosterDays | — |

降级剥离规则与 `downgraded(_:to:)` 一致，生成器 `scripts/android-synthetic-archives.mjs` 复制该逻辑。

## 3. 十二类实体

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

## 4. 不进用户 v6 的本地/同步层

`RecordLocalFile`：schemaVersion, document(嵌入备份字节), erased[], sync?。  
`ErasedDTO`：entityType, logicalKey, erasedAtMs, editCount?。  
`RecordEntityType` raw：careerPeriod, scheduleSnapshot, calendarException, dayOverride, workObservation, lifeProfile, focusTask, focusSession, focusPlanningConfiguration, syncedPreferences, extendedSchedule, rosterDay。  
`SyncLocalState`：accountID, generation, syncEnabled, engineState, rows, conflicts, deletingCloud, entityTypeRevision。  
**购买凭据、StoreKit/Play token、JWS、isPlus 授权一律不在备份。** 薪资数字是用户数据，不是购凭证。

## 5. 导入

模式：`skipErased`（默认）、`restoreErased`（UUID 重映射并改写引用）、`resolveByEditStamp`。  
`recordsStartedOn` 取本地与导入的较早者。  
建议上限 25 MiB（产品保护，可按真实档案调整）。v7 不得当 v6 忽略字段导入。

## 6. 字段抽样勾选

| 家族 | 合成样本 | 含购凭证？ | 备注 |
|---|---|---|---|
| CareerPeriod | v1–v6 | 否 | label Current |
| ScheduleSnapshot | 全版本（测试 fullState 无，合成补了一条） | 否 | configurationData 为示意 JSON 的 base64 |
| CalendarException | 同上补一条 `2026-08-26#user` | 否 | |
| DayOverride | v1–v6 | 否 | customSegments 8h |
| WorkObservation | v1–v6 | 否 | v1 无 edit 戳 |
| LifeProfile | v1–v6 | 否 | 有薪资经历，非 IAP |
| FocusTask/Session | v1–v6 | 否 | |
| FocusPlanningConfiguration | v4–v6 | 否 | |
| SyncedPreferences | v5–v6 | 否 | salaryAmount 字符串 |
| ExtendedSchedule / RosterDay | 仅 v6 | 否 | |

## 7. 合成档案

`docs/android/synthetic-archives/`。非法：v0、v7、非 JSON、`2026-02-30`、注入 `purchaseToken`/`isPlus`（用于证明**不得授 Plus**）。  
检查：`node scripts/android-synthetic-archives.mjs --check`。  
Kotlin/Room 往返 **NOT_RUN**。
