# 验收任务：iOS Swift 清理分支（claude/swift-codebase-review-8hn9pr）

你在一台装有 Xcode 的 macOS 机器上。这个分支上的所有 Swift 改动**从未被编译过** ——
它们是在一个没有 Xcode 的 Linux 容器里写的。你的任务是编译、跑测试、做验收，
并修掉编译错误。TypeScript 侧（`npm test` / `lint` / `check:ios`）在提交前已经跑通。

## 分支与基线

```bash
git fetch origin
git checkout claude/swift-codebase-review-8hn9pr
```

**基线不是 `main`**，是 `origin/codex/ios-011-release-remediation`
（PR #98 和 #99 都已合入它）。截至交接时它领先 `main` 10 个 commit、
+30,823 行，**尚未合入 `main`**，也没有开着的对 `main` 的 PR。
本分支 = 那条分支 + 4 个 commit。若基线又有新提交，先 rebase 再验收：

```bash
git rebase origin/codex/ios-011-release-remediation
```

若届时 011 已经并入 `main`，改成 `git rebase origin/main`。

四个 commit，按依赖顺序：

1. `fix(ios): source Records income from the shared rules bundle`
2. `refactor(ios): give money one output and one derivation`
3. `refactor(ios): one crossing of the JavaScriptCore boundary`
4. `chore(ios): remove a state machine that could not run`

## 第一步：必须先生成规则 bundle

`CountdownRules.js` 不入库。**commit 1 改了生成器**，所以必须重新生成，
否则 App 跑的是旧规则，Records 收入会以 `invalidResult` 失败或返回旧值：

```bash
npm install
npm run build:ios-native-rules
npm run check:version
npm run check:ios
npm test
npm run lint
```

## 第二步：编译与单元测试

```bash
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

`xcrun simctl list devices available` 查可用模拟器；名字对不上就换一个。

### 最可能出问题的地方（按概率排序，编译错误优先看这些）

1. **`callRule` 的泛型推断**（`CountdownRules.swift`）。7 个 rule 方法现在写成
   `return try callRule(context, "snapshot", input)`，`Response` 靠返回值类型推断。
   若某处推断不出来，显式标注：`let out: NativeShiftSnapshot = try callRule(...)`。
2. **`CountdownRulesError.invalidResult` 现在带关联值** `(rule: String)`。
   若基线上还有别处构造或 `case .invalidResult` 模式匹配，需要补上参数。
3. **`NativeSummaryInput` 新增了 `var periodStartMs: Double? = nil`，位置在 `period`
   之后**。memberwise init 参数顺序随之改变。跳过带默认值的参数是合法的，
   但若基线上有别的构造点按位置传参，会报错。
4. **`RecordsMetrics.summarize` 去掉了 `dailySalary` / `salaryEnabled` / `asOf` 三个参数**，
   `RecordsPeriodMetrics` 去掉了 `estimatedIncome` / `usesCurrentSalary` 两个字段。
   基线上若有别的调用方（我只找到 store 和两个测试文件），需要一起改。
5. **`store.recordsMetrics(for:)` 去掉了 `asOf` 参数。**

### 新增/改动的测试

- `OffWorkStoreTests.recordsIncomeMatchesTheSharedSummaryRule` —— **这条是本次修复的核心回归**。
  它断言周三下午的 Records 收入 = `(2 + payRatio) * dailySalary`，且与计时页
  `periodSummary("week", ...)` 完全一致。**它挂了不要改断言，是代码有问题。**
- `OffWorkStoreTests.recordsIncomeAbsentWithoutSalary`
- `RecordsMetricsTests` 删掉了一条只测已删除公式的用例，其余用例去掉了薪资参数。
- `OffWorkStoreTests` 中三条测试删掉了对空实现 `dismissCompletedShift` 的调用。

一个已知的脆弱点：`recordsIncomeMatchesTheSharedSummaryRule` 固定用 2026-09-02（周三）
且工作日为周一至周五，所以无论周起始是周一还是周日，"已完成天数"都是 2。
如果它在某个区域设置下仍然挂了，先打印 `store.recordsChartWindow(for: .week)` 再判断。

## 第三步：真机/模拟器上的人工验收

四项，都要在**浅色和深色**下看，并至少覆盖一个长英文标签的语言。

### 1. 两个 Tab 的钱必须一致（本次主要修复）

设置里开启薪资（月薪 22000 / 22 天）。在**工作日班次进行中**（不是下班后）：

- 计时页 → "本周" 那一行的金额
- 记录页 → 图表页 → "按当前薪资估算的收入"

**两个数字必须相同。** 修复前记录页会少一天多的钱（整天数 × 日薪，
不计当天已完成的比例）。宣告加班后再看一次，两边仍应一致。

同样检查月 / 年两个周期能正常显示（这条路径以前不走 bundle，现在走了）。

### 2. 隐藏收入必须对记录页生效（本次第二个修复）

点任意位置的眼睛图标关闭收入显示，然后进记录页图表。
**收入那一格必须显示 `••••`。** 修复前它照常显示金额。
再打开眼睛，数字应恢复。计时页、iPad 侧栏、横屏、设置页的薪资预览也各看一眼，
它们全部改走同一个 `store.moneyText`，不应有任何一处行为变化。

### 3. 结算态不可被撤销（删除空实现后的回归确认）

上班中途点"提前下班" → 应进入结算态。切 Tab、切到后台再回来、
改设置里明天的工时 —— **都不应该把结算态弹回设置页**。
然后点"撤销"，应回到运行中。这条路径删掉了一整套从未生效的状态，
需要确认没有连带影响。

### 4. 规则桥仍然正常

冷启动、切换排班模式（经典 / 单双休 / 轮班）、开关午休、跨夜班次，
都不应出现规则错误横幅。若出现，横幅文案应与以前**完全一致**
（错误里新增的 rule 名是给日志用的，故意不显示给用户）。

## 第四步：报告

请回报：

- `xcodebuild build` 和 `test` 的结果，失败的话贴原始报错。
- 你为了让它编译过而做的任何修改（我看不到编译器，很可能有需要补的地方）。
- 上面四项人工验收逐条的结论，钱不一致或掩码失效的话请附截图。
- 你认为不该合并的任何一个 commit，以及原因。

## 明确不在本次范围内（不要顺手做）

- 三套布局（竖屏 / iPad / 横屏）各自重算派生值的去重（`RunningTimerModel`）。
- `OffWorkStore` 里 13 个 `presentation*` / `effective*` 成员的 `#if DEBUG` 收敛。
- 67 处内联 `Calendar(identifier: .gregorian)` 的收敛。

这三项都会与 codex 分支大面积冲突，等它并入 `main` 之后单独做。
