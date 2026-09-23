# 源入口盘点（T01）

固定提交 `9252fdfdc66aab88b4acb7493684f11991fd773d`。路径均相对该树。未把「文件名存在」当成功能已移植。

## 1. 主导航

`AppTab`（`Native/Models/SceneState.swift`）：`timer`、`focus`、`records`、`settings`。  
壳：`AdaptiveAppShellView`（`Native/Views/TabletDesignView.swift`），`.tabViewStyle(.sidebarAdaptable)`。

| Tab | path | destination |
|---|---|---|
| timer | `scene.timerPath: [AppRoute]` | `AppRouteDestination` |
| focus | `scene.focusPath: [AppRoute]` | 同上 |
| records | `scene.recordsPath: [RecordsRoute]` | `RecordsDesignView.recordsDestination` |
| settings | `scene.settingsPath: [AppRoute]` | `AppRouteDestination` |

`presentedRoute`：`.focus`/`.focusPlan` 切 Focus Tab；在 timer/focus 则 append 对应 path；否则切 settings 再 append。

## 2. `AppRoute` → 视图

| case | 视图 | 备注 |
|---|---|---|
| schedule | `ScheduleSettingsView` | |
| lunch | 同上 | 兼容深链 |
| salary | `SalaryDesignView` | |
| notifications | `NotificationDesignView` | |
| health | `HealthReminderSettingsView` | |
| theme | `ThemeSettingsView` | |
| language | `LanguageSettingsView` | |
| recordsTimeZone | `RecordsTimeZoneSettingsView` | |
| plus | `PlusSettingsView` | |
| iCloudSync | `RecordsSyncSettingsView` | Android 文案改为 Drive |
| recordsData | `RecordsDataSettingsView` | |
| recordsConflicts | `RecordsConflictCenter` | |
| focus / focusPlan | `FocusCanvasView` | 已合并 |
| appleWatch | `AppleWatchSettingsView` | 仅 iPhone 设置列表；纯说明 |
| about | `AboutView` | DEBUG 长按进 `DebugMenuView` |

## 3. `RecordsRoute`

`.allRecords`、`.yearList`、`.monthList`、`.day`、`.conflictCenter`。  
日编辑是 Root sheet：`scene.dayEditor` → `RecordDayEditView`。

## 4. Root 门禁与 sheet（`RootView.swift`）

1. `!onboardingComplete` → `OnboardingView`
2. `!hasSeenPlusIntro && !showsReleaseNotes` → `PlusIntroView`
3. 否则 `AdaptiveAppShellView`

Sheet / cover：`PaywallView`、`RecordDayEditView`、`ShareComposerView`、`OvertimeSheet`、`FocusQuickCreateSheet`、`WhatsNewView`、`FirstRunRecoveryView`、人生引导、评价提示。

Phone 横屏：`PhoneLandscapePresentationPolicy` 在计时 Tab 根叠加 immersive overlay，不换 Tab。

平板：窄窗 <620pt 回退手机计时布局；设置 <720pt 单列。

## 5. 深链

`Info.plist` scheme：`offworkcountdown`。无 Universal Links。

| URL | 行为 |
|---|---|
| `offworkcountdown://timer` | 计时 Tab，清空 path |
| `offworkcountdown://focus` | Focus Tab |
| `offworkcountdown://focus?action=&start=` | 确认后执行 Focus 动作 |
| `offworkcountdown://{AppRoute}` | 设置栈打开该路由 |
| `https://off.rainif.com/?s=HHmm-HHmm&…` | 分享；只含偏好起止 |

Widget / Live Activity 默认 `://timer`；Focus 动作用 `://focus?…`。

## 6. 设置键去向

### 6.1 `SyncedPreferences`（进备份 schema 5+）

| 字段 | UI |
|---|---|
| start/endMinutes, workdays, scheduleMode, alternating*, rotation* | `ScheduleSettingsView` |
| lunch* | 同上（含 `.lunch` 深链） |
| recordsTimeZoneIdentifier | `RecordsTimeZoneSettingsView` |
| salary* / monthlyWorkingDays / annualBonus* | `SalaryDesignView` |
| notificationMode, lunch*Reminder, cycleEndSummary* | `NotificationDesignView`（周期总结 Plus） |
| microBreak* | `HealthReminderSettingsView` |
| theme | `ThemeSettingsView` + 计时工具栏快切 |
| languageOverride | `LanguageSettingsView` |
| editedAtMs, editCount, editTieBreaker | 无 UI（合并元数据） |

写入：`applyPreferences` → archive。

### 6.2 `PreferencesStore` UserDefaults（多数不同步）

| Key | UI / 流程 | 在设置栈？ |
|---|---|---|
| `ios.native.onboardingComplete` | Onboarding | 否 |
| `ios.native.debugAlwaysOnboarding` | DEBUG | DEBUG only |
| `hideEarnings` | 薪资页 + 计时眼睛 | 薪资页 |
| `ios.native.liveActivityEnabled` / `liveActivityLead` | 通知页 | 是 |
| `ios.native.focusLiveActivityEnabled` | Focus 计时设置 sheet | 否（Focus 内） |
| `ios.native.recordsScale` | 记录页尺度 | 否 |
| `ios.native.releaseNotesSeen` | WhatsNew | 否 |
| `ios.native.lifeSetupPromptDismissed` | 人生引导 | 否 |
| `ios.native.lunchEdgesEnabled` | 迁移 | **无 UI** |
| `didApplyOnboardingReminderDefaults` | 内存 | **无 UI** |
| `systemLanguageCode` / `systemTimeZoneIdentifier` | 运行时 | **无 UI** |

### 6.3 其他存储

| 项 | 位置 | UI |
|---|---|---|
| `sync.syncEnabled` | Record archive | 同步页；开启需 Plus |
| 扩展排班 / 手排 / 人生 / Focus 任务 | archive | 排班 / 数据 / Focus |
| Plus 购买 | StoreKit / PlusEntitlement | Paywall；**不进备份** |
| `ios.native.focusNotificationsEnabled` / `focusTimerSettings.v1` | FocusStore | Focus sheet |
| `ios.native.selectedTab` | SceneState | Tab |
| `ios.native.appReviewPrompt.v1` | ShiftSessionStore | 评价 |
| `ios.native.plusHasSeenIntro` | PlusEntitlement | PlusIntro |

设置栈没有对应 PreferencesStore 键的行：同步、导入导出删除、Watch 说明、关于外链、评分、Plus 购买。它们不是遗漏的 preference，是操作或外部状态。

## 7. 计时动作（FR-04）

`TimerVisualPhase`：unscheduled / rulesError / completed / rest / clockIn / lunch / overtime / running。  
`heroRemainingMs`：未开始→距开始；休息→距休息结束；否则有效剩余。

动作（多数 5s 二次确认）：提前上班/撤销、提前下班/撤销、休息日开始、取消手动计时、加班/清除、分享。

## 8. 记录命令（FR-07）

语义在 `RecordsActions`，不在 `RecordCommand` 队列类型：`saveCustomHours`、`confirmDayAsScheduled`、`markDayNotWorking`、休息日/补班 exception、`clearDayOverride`。全部需 Plus + 非 `blocksWrites`。

计划链：override > calendar exception > snapshot。观测不进该链。

## 9. Plus 门控（FR-16）

产品：`com.rainif.offworkcountdown.plus.{monthly,yearly,lifetime}`。Android 商品 ID 另配，不照抄上架。

`RecordsPaidCapability`：charts、life、recordsPageEdit、focus、enableSync。  
`RecordsScale.requiresPlus`：year、life。week/month 免费。  
免费日：`canRevealDay` = 已授权或 7 自然日窗。

Paywall 原因：intro / charts / life / historyEdit / sync / focus / cycleEndSummaryNotifications。  
`PlusPendingAction` 购买后重放一次。

## 10. 首次恢复（FR-01）

`FirstRunRecoveryPhase`：checking / empty / needsSetup / failed / localDataNeedsReview / restoring。  
可：继续本地、云恢复、先导出再覆盖、重试、恢复购买。未完成前不得把欢迎默认值上传。

## 11. Focus（FR-09）

默认 25/5/15、每 4 轮长休；范围 10–60 / 1–15 / 5–30 / 2–6。  
模板只放完整任务前缀。写操作全 Plus。健康微休息接管需开关 + Plus。

## 12. 提醒 / 系统面（FR-10–12）

班次：milestone、breakStart/End、microBreak。周期总结可替换 100% body。  
Focus 独立通知。Live Activity 是 iOS 增强。  
小组件：systemSmall/Medium/Large/ExtraLarge + accessory circular/rectangular。投影无薪资。

## 13. DEBUG，禁止进 Release

`DebugMenuView`、QA UserDefaults（`ios.native.qa*`）、`debugPlusAuthorized`、`debugWatchEntitlement`、`debugAlwaysShowOnboarding`。About 在 Release 的 debug 闭包是 `EmptyView`。

## 14. 测试文件（AppTests，该 SHA）

见 `feature-parity.md` 映射。Watch* 测试属 FR-21，首发不执行、不删除。

## 15. 19 语言

`public/locales/`：ar de en es fr hi-IN id it ja ko mr-IN pt ru th tr vi zh-CN zh-HK zh-TW。  
iOS 权威表：`Localizable.xcstrings`（T05 转换）。本轮未逐 key 枚举 2.7MB 目录。
