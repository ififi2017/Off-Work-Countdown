# 01 · DoneAt Android 产品需求文档

## 1. 产品定义

DoneAt 是让用户看清当前班次剩余有效工作时间、阶段进度、预计收入，并回顾与规划工作时间的本地优先工具。Android 版保留产品能力，使用 Android 原生交互重新表达，不逐像素复制 iOS Liquid Glass，也不把原本的记录和专注删成一个简单时钟。[R01], [R11]

**用户目标**：打开就知道“现在在哪个阶段、还要工作多久、接下来做什么”；修改班次后全应用一致；退出应用不丢失计时；换机不丢历史；不因通知权限或购买网络异常失去基本使用能力。

**非目标**：企业考勤与工资结算、法定退休/劳动法计算、实时汇率、健康诊断、位置打卡、工资上传分析、社交账号、广告、后台保活工具、桌面端悬浮窗照搬。收入和人生数字必须用“预计/估算”语义，不能宣称等于真实发薪或法定退休待遇。

## 2. 首发范围与用户类型

建议最低 Android 8.0 / API 26（D-04）；手机、平板、可折叠窗口均支持；首发从 Google Play 分发。无 Google Play 服务的设备至少能运行本地核心，支付应展示能力不可用，而不是崩溃（首发无 Drive 同步）。是否专门维护中国大陆商店、厂商支付和无 GMS 云同步为另一个发行项目，不在本次默认范围。

用户状态：新用户、从 iOS 导入用户、免费用户、有效月/年订阅用户、终身用户、待支付用户、宽限期用户、失效用户、已开启同步用户、仅本地用户。权限状态与购买状态相互独立，不创建“授权一次就默认全部权限”的捷径。

## 3. 功能需求总表

下表为完整移植的追踪主键。优先级“必须”指正式完整版，不意味着第一个开发迭代必须同时完成。

| ID | 能力 | 要求与边界 | 优先级 |
|---|---|---|---|
| FR-01 | 首次启动与恢复 | 新建、恢复 JSON、选择性云端恢复；不得上传欢迎默认值覆盖旧数据 | 必须 |
| FR-02 | 固定排班 | 上下班、工作星期、手动模式、跨夜、班中休息、排班时区 | 必须 |
| FR-03 | 扩展排班 | 多班型、工作/休息班型、周期、大小周、轮换、自定义、手排、继承与清空 | 必须 |
| FR-04 | 计时与当天调整 | 未开始/工作/休息/加班/已结束/休息日/未排班；提前结束、撤销及继续加班按源码 | 必须 |
| FR-05 | 薪资与隐私 | 月/日薪、平均工作日、年终奖参数、当前累计、隐藏与身份确认 | 必须 |
| FR-06 | 记录与可视化 | 日详情、周/月/年、实际与预计、来源标记、免费窗口、编辑入口 | 必须 |
| FR-07 | 历史编辑 | 确认按计划、未工作、自定义时间、请假/补班/清除修正；历史快照不漂移 | 必须 |
| FR-08 | 人生 | 阶段、职业经历、空档、退休年龄、历史/未来收入、未来固定比例调整 | 必须 |
| FR-09 | 专注 | 时间画布、任务、番茄钟、休息、模板、收藏、放置/排序、重启恢复 | 必须 |
| FR-10 | 提醒 | 进度/班次/休息/微休息/周期总结/专注；权限与调度降级 | 必须 |
| FR-11 | 系统持续展示 | 普通通知的当前阶段及适当系统计时；不承诺等同灵动岛 | 必须，允许平台差异 |
| FR-12 | 桌面小组件 | 多尺寸、状态与下一阶段、点击直达、薪资隔离、过期态 | 必须，刷新受系统约束 |
| FR-13 | 分享与链接 | 无工资卡片、班次链接、Android Sharesheet、链接导入确认 | 必须 |
| FR-14 | JSON 备份与迁移 | v1–v6 导入、v6 导出、预检、冲突预览、原子提交、失败可恢复 | 必须 |
| FR-15 | 换机恢复与同步 | 首发：系统备份/设备转移恢复业务数据 + v6 文件迁移；后续：Android 私有同步替代 CloudKit（恢复、开关、冲突、删除语义不丢） | 首发必须换机恢复；Drive 同步为后续阶段（D-02 修订） |
| FR-16 | Plus 与 Play Billing | 月/年/终身、适用优惠、恢复、取消/宽限/过期/撤销、客户端 Play 查询与签名校验 | 必须；D-01 模式已确认，价格/优惠待配置；D-08 修订：首发无自建服务 |
| FR-17 | 设置与应用服务 | 主题、语言、记录时区、通知、数据、Plus、关于、反馈、评价 | 必须 |
| FR-18 | 19 语言与无障碍 | 完整文案/复数/RTL/大字体/TalkBack/键盘/触控替代操作 | 必须 |
| FR-19 | 自适应布局 | 四个主导航（计时/专注/记录/设置）、手机横竖屏、平板分栏、折叠/分屏状态恢复 | 必须 |
| FR-20 | 发布与隐私 | Release/AAB、签名、数据申报、政策、测试轨道、回滚预案 | 必须 |
| FR-21 | Wear OS 扩展 | 同源纯 Kotlin 规则、离线排班、无薪资传输、表盘复杂功能 | D-05 已确认延后，不在首发范围 |

FR-02～FR-09 的细小开关、菜单与参数必须在 M0 从现有路由、设置模型、翻译 key、测试枚举成子条目。文件名不能证明某个功能已移植；只有可执行用例与结果能证明。

## 4. 免费与 Plus 矩阵

按当前代码而不是旧营销描述定义。[R05], [R09], [R12]

| 行为 | 从未购买的免费用户 | 有效 Plus / 终身 | 权益失效后 |
|---|---|---|---|
| 基础排班、主倒计时、基础收入显示 | 可用 | 可用 | 保留基础使用 |
| 新工作观测 | 继续采集，服务免费窗口 | 继续采集 | 当前基线停止新增；D-07 可另行修订 |
| 最近七个自然日记录 | 可查看允许的明细 | 可查看 | 不删除数据；显示范围由统一访问策略处理 |
| 图表、人生、记录页编辑、专注 | Plus 门禁 | 可用 | 门禁恢复；不销毁数据 |
| 初次开启同步、周期结束总结开关 | Plus 门禁 | 可开启 | 不自行推断“关闭所有已经开启的同步”；按源调用点和 D-02 冻结规则 |
| 恢复已有备份/云端数据 | 不能要求先重新购买才恢复 | 可用 | 保留恢复路径；恢复不等于获得付费编辑权限 |
| 导出自己的数据、删除自己的数据 | 可用，必要时身份确认 | 可用 | 仍可用 |
| 小组件 | 基础投影可用 | 可用 | 不塞入付费数据泄漏 |
| Watch 的现行产品定位 | 当前源码说明 Watch App 和两种复杂功能免费 | 同左 | 不自行改为 Plus |

针对“失效后已开启同步”的具体门禁，M0 必须检查当前同步引擎及测试；只看到 UI 上的“开启需 Plus”不等于后续每次同步都要 Plus。Android 推荐保留已开启同步的安全运行与用户数据控制；D-02 只确认提供商、默认关闭及（修订后的）后续阶段范围，不自动批准修改权益到期后的规则。本条在首发不适用（首发无同步）。M0 仍需冻结源行为，确需产品变更时记录补充决策，不能靠缓存布尔值偶然决定。[R01], [R12]

免费门禁不是透明度为 0 的覆盖层。受保护页面的 UiState 不得带被遮挡的工资、历史值和任务内容；Semantics、复制、截图分享、通知投影同样不能泄露。

## 5. 信息架构

按源 `AppTab` 维持四个主入口：**计时、专注、记录、设置**（平板为侧栏自适应四入口；见 docs/android/conflicts.md C-09）。记录中的“人生”是记录尺度/入口，不与主页竞争。[R11]

```text
欢迎 / 恢复
└─ 主壳（计时 | 专注 | 记录 | 设置，各自保留导航栈）
   ├─ 计时 → 当天调整 / 排班 / 分享
   ├─ 专注 → 专注画布 / 任务 / 模板
   ├─ 记录 → 日详情 / 周 / 月 / 年 / 人生 → 编辑 / 职业经历
   └─ 设置 → 排班、薪资、提醒、健康提醒、主题、语言、记录时区
             Plus、数据管理（导入/导出）、冲突中心、关于（同步入口在后续阶段加入）
```

Android 新增的“通知渠道/精确提醒状态/Google Play 管理订阅”属于平台适配入口。不得保留“打开 iCloud 设置”“App Store 恢复购买”等失效操作。

## 6. 逐页交互与状态

### 6.1 欢迎与首次恢复（FR-01）

首屏可选择开始设置或从文件恢复（首发）；系统备份/设备转移恢复由 Android 在安装时完成，应用首启检测到已恢复数据时直接进入主界面并重建提醒与小组件。后续加入 Drive 同步后再提供“从云端恢复”，Google 授权只能在用户选择云功能后请求。基础使用不强制登录、付费或授权通知。已有本地有效设置优先打开主界面，不重复欢迎。

恢复流程：选择来源 → 只读查询 → 完整下载候选副本 → 校验/差异预览 → 用户确认 → 原子提交 → 进入主界面。查询失败、授权取消、超时均不是“云端为空”。新设备恢复不依赖旧设备同时启动。未完成恢复前禁止把默认班次上传为新版本。[R14]

新建流程：班次与工作日 → 休息/收入可跳过 → 提醒可跳过 → 完成。设置存为草稿，最终确认才提交；后台中断后恢复草稿，不生成业务观测或同步编辑版本。Plus 展示可关闭，不阻断免费开始。

### 6.2 主计时（FR-04/05）

顶部：日期、当前班次及次级专注入口。中心：状态标签、主时间、有效进度。下方：预计收入（按隐私设置）、今天摘要、接下来、主要操作。分享、设置等不能比倒计时更抢眼。

| 状态 | 主时间含义 | 附加说明 | 行为 |
|---|---|---|---|
| 未开始 | 距本次开始的时长 | 展示班次起止、下一休息 | 编辑班次/按既有规则开始 |
| 工作中 | 剩余有效工作时间 | 不把未计薪休息当工作时间 | 当天调整、进入专注 |
| 休息中 | 距本次休息结束 | 有效工作累计冻结 | 查看下一工作段；相关设置 |
| 加班中 | 剩余有效延长时间 | 标记加班，收入按原计划时薪延伸 | 调整加班/结束 |
| 已结束 | 完成态，不显示负数 | 下一班次或下一休息日 | 撤销/继续加班按源行为 |
| 休息日 | 明确“今天休息”及下一班次 | 不伪装成 00:00 未开始 | 编辑安排 |
| 未排班 | 明确“尚未安排班次” | 与休息日区分 | 添加排班 |
| 规则/数据异常 | 保留已知有效数据，给出恢复操作 | 不显示虚构薪资/下一班次 | 重试/检查/导出 |

源码 `heroRemainingMs` 在未开始和休息阶段使用对应边界，工作阶段使用有效剩余。因此页面不能一律显示 `endAt - now`。主倒计时、预计结束钟点、专注倒计时必须分别标注，避免把三个时间混为一个。[R02]

今天修改班次时，应展示“应用到今天 / 从下一次开始”的源规则允许选项；当前快照固定与未来规则更新分离。不能因为用户改了常规下班时间就追溯覆盖历史或丢掉正在运行的专注。

### 6.3 排班（FR-02/03）

基础编辑区：时间、工作星期、休息区间、排班模式、时区说明。复杂设置渐进展开，不能强迫简单朝九晚六用户理解轮班模型。

高级编辑区：班型库 + 周期编辑器 + 月历手排。支持 weekly、alternatingWeeks、rotation、custom；周期有锚点日期；一天可以是工作班型、休息班型或未安排。手动赋值、撤销赋值、恢复规则、清空从某日起的自动延续必须是不同动作。[R03], [R04]

已核实约束：班型名去首尾空白后 1–40 字符；时刻 0–1439 分钟；周期 1–366 天；终点早于或等于起点表示次日终点；休息启用时必须有正时长。保留已归档班型供历史解析。输入校验提示就地显示，不保存半合法状态。[R03]

手排优先于周期和继承，但节假日、清空边界、冻结历史、固定快照回退的完整组合应以解析器和 Swift 测试逐分支移植，不能简单拼一个“总优先级列表”覆盖所有层。没有明确分配不是休息日解析成功；无规则月份的按日期继承必须考虑短月、闰月、人工空档及源测试。[R04]

节假日数据本地打包、保留版本和授权；不要自动按系统地区启用法律性质的工作安排，不额外请求位置。数据覆盖之外不猜测下一年假期，显示覆盖范围并允许手工安排。

### 6.4 薪资（FR-05）

支持源码已有月薪/日薪输入及平均工作日、年终奖折算参数；货币显示沿用源配置语义，若源无货币切换不得擅自加入自动换汇。金额为空与 0 不混同；拒绝负数、无限大、溢出和不合格式；读取用户地区小数分隔符，存规范数值，不存格式化文案。

明确两类口径：计时页的今日收入按有效工作段进度；记录页固定月薪按后续确认的自然日口径分摊，不因请假或少记工时扣薪。完整月月基数包含既有年终奖月均份额；日薪仍依工作日规则。两者标签说明一致，不强行用同一个“日工资×天数”函数代替全部业务。[R02], [R10], [R14]

隐藏收入是统一状态，眼睛图标表达点击后动作。隐私确认使用 Android 生物识别/设备凭据能力；失败/取消不揭示、不导出。无设备锁的降级体验需要明确提示而不是假装身份验证成功。[R09]

### 6.5 记录与历史（FR-06/07）

记录页提供日/周/月/年尺度及人生入口；当前选择的日期、尺度、滚动位置在导航和窗口变化后稳定。用源记录时区确定“今天”与免费窗口，不随旅行把记录移动到另一日期。[R05], [R08]

日详情：计划区间、最终解析区间、实际观测/人工确认的来源、休息与加班、收入及计算口径、修改入口。周/月/年：实际与预计分别编码，不重复统计已发生部分。图表下面同时提供文本汇总/可访问列表。

历史最终计划解析链：有效日修正 > 日历例外 > 获胜排班快照；清除修正表示继续向下解析。工作观测不进入这条计划优先级链，它是另一类事实证据。UI 必须区分“按计划推算”“手动确认”“观测所得”“无法解析”。[R08]

编辑日记录支持按源命令确认计划、未工作、自定义上下界、请假/补班/清除；保存失败保持原值与草稿。多层修改同一个数据库事务提交。时间边界调整必须保留计划内休息间隙，不能压成一条连续工作段。[R09]

### 6.6 人生（FR-08）

支持粗略工作起始年，或多段精确职业起止、月/年薪经历；可编辑出生/入学/工作建议与退休年龄，退休默认 60 是产品默认而不是法定判断。源计划后续修订须与当前源模型核验。[R13], [R14]

经历有稳定 ID，选中“已走过/未来推算”不会因重新分段跳到另一个对象。期间重叠应明确拒绝，空档收入为零。不推断涨薪、通胀和投资收益。未来收入调整是从某年龄起一次性降到固定比例并保持到退休，不是每年复利下降；起始年龄已过去则只调整今天之后的预测，历史收入保持原值。[R10], [R14]

未填写资料提供可跳过引导，不制造假数据。图表必须标记用户填写、默认建议、估算三类来源。

### 6.7 专注画布（FR-09）

保留单一画布、多尺度观察、任务卡、可用工作块、恢复块、番茄轮次、收藏和模板。基础用户经付费门禁后应回到原草稿和落位，不丢失“新建后放入下一块”上下文。[R06], [R11], [R05]

默认 25 分钟专注、5 分钟短休息、15 分钟长休息，每 4 轮长休；允许范围分别 10–60、1–15、5–30、2–6。改设置影响下一会话，不重写当前会话计划终点。精确行为以模型/Planner/Store 的分支及测试对齐。[R06]

任务最少包含标题、图标、预计轮数、计划日期/落位、完成与删除状态。收藏不是复制一套无关联内容；模板应用只放得下的完整任务前缀，不能擅自截断一个任务的轮数，也不能因今日短班修改模板本身。

拖动用于排程，但所有拖动都必须提供“移动到/上移/下移/选择时段”的可访问替代；长按不得覆盖点击查看。已有任务冲突、不够时间、未到可开始时间，分别提示，不统一报“错误”。

进入后台后不依赖 UI 协程维持状态；重开依据持久化终点和事件重建。不因恢复、双击按钮、通知动作与前台同时触发而创建重复会话；自动会话保持源确定性 ID。午休、工作结束、主动停止、其他设备胜出分别保留结束原因，不无声删除历史。[R06]

### 6.8 提醒与系统展示（FR-10/11/12）

提醒分类：班次/进度、休息边界、健康微休息、专注结束、周期总结。具体开关/阈值/文案由 `lib/reminders` 和源通知设置枚举，不凭“常见番茄钟”臆造新策略。[R01], [R18]

周期总结仅在已可靠解析到后续休息日时成立；普通进度提醒关闭不必关闭独立总结；同一结束点避免普通完成和总结双响。摘要不得包含薪资。源 iOS 功能的实际通知投递也有独立真机门禁，Android 不能以模拟器成功代替真机。[R15]

Android 13+ 通知被拒绝时，页面可继续使用，设置展示未授权及跳转；不要循环请求。精确提醒需用户授予相应特殊权限时再请求；无权限显示“提醒可能延迟”，不得谎称准点。不能通过申请不相干的前台服务、无障碍或悬浮窗绕过限制。[A10], [A24]

普通持续通知显示当前阶段、结束钟点/可适用的系统倒计时、点击返回。Live Update 的资格和系统呈现受限制，本项目没有已验证的可用性，不把它列为灵动岛的一比一承诺。[A11]

小组件至少提供紧凑计时、中等概览、大尺寸当天/下一阶段三个响应式布局。不能承诺 App 不运行时每秒执行 Kotlin 更新；界面显示结束钟点、正确阶段和必要的更新时间/过期提示。收入不进入小组件数据对象；不用“默认隐藏、点一下显示”变相突破。[R01], [A12]

### 6.9 分享与文件（FR-13/14）

普通分享卡片只含阶段、时长、进度、班次等允许字段；渲染输入是显式安全 DTO，不能截整个收入界面。使用系统 Sharesheet；临时图片经 FileProvider 授予读取，随后清理。分享链接只允许源协议中的起止时间，不加薪资、职业经历、用户 ID 或明文内部文件路径。[R01]

链接进入先解析/验证，再预览是否应用，不自动覆盖用户配置。旧 URL 继续兼容；新 App Links 的域名校验由负责人部署，不要求更改原站点 SEO 路由结构。[A25]

备份导出明确提示包含薪资/职业/专注等个人内容，提供源已有的“排除人生档案”选项。使用系统文档选择器，不索取所有文件访问权。导入先预检，再展示新增/不变/冲突/被拒绝/已删除跳过数量；不会在读取文件途中覆写活跃数据库。[R07], [R09]

### 6.10 换机恢复与同步（FR-15）

**首发（D-02 修订，2026-09-23）**：业务数据随 Android Auto Backup 与设备转移恢复（Android 9+ 设锁屏时由系统端到端加密；每应用 25MB 上限），与 iOS 主数据随 iCloud 设备备份的行为一致。购买缓存、密钥、令牌与本机权限不在备份内，恢复后重新查询。跨平台仍用 v6 文件。设置页不出现同步开关。

**后续阶段**：采用用户主动授权的 Google Drive 应用专用存储，默认关闭，实现 Android↔Android 自动同步。以下为该阶段的要求。保留没有 DoneAt 账号的产品结构。这是待实现的 Android 替代方案，不是已经部署的服务，也不会自动与 iCloud 互通。[A13]

必备状态：关闭、待授权、首次检查、待选择本地/云端、同步中、已同步、离线待同步、需要重新授权、配额/服务错误、冲突、云端重置待处理。开关显示已提交状态，不以用户刚点的值冒充成功。[R12]

暂停同步、删除云副本、移除此设备数据是三个不同操作。删除云端时防止离线老设备重新上传旧档案；有未同步本地数据先提供导出/审阅。切换 Google 账号不能把前一账号本地记录自动传给后一账号。具体同步协议见 02。

### 6.11 Plus（FR-16）

D-01 已确认提供月订阅、年订阅、终身一次性买断；具体价格、销售地区、优惠/试用期限仍需负责人配置，不属于本次方向确认的已知参数。**终身是非消耗型一次性商品，不是“永久订阅”。**不得硬编码展示价格、试用资格或汇率。[R05], [A06]

购买页应有功能说明、合法获取的本地化价格/周期、到期后收费说明、关闭、恢复购买、隐私和条款。资格不满足或商品读取失败时，不出现可点击但必失败的“免费试用”。待付款不得提前授予权益；取消购买保留原操作草稿。

跨平台权益已确认独立（D-03）；首发不做 iOS/Android 自动同步，业务数据通过 JSON 双向迁移。Apple Universal Purchase 不等于 Google Play 权益；不能凭导入 JSON 的 `isPlus` 授权。需要互通时另行引入可验证跨商店凭据与用户关联方案，由负责人批准账号/隐私/后台成本后实施。

价格/试用未配置时，可继续调试商品接口和权益逻辑，但生产页面不得虚构价格、试用天数或优惠资格。没有已配置且用户符合条件的有效优惠时，不显示免费试用承诺；这不等于负责人已经决定永久不提供试用。

### 6.12 设置、关于与评价（FR-17）

设置分组：工作与收入、提醒、个性化、数据与隐私、Plus、关于。关键危险项有解释、确认和可取消操作；同步/删除页面统一互斥操作锁。

关于包含版本、开源许可证、帮助/隐私、反馈和 Google Play 评价入口。反馈默认不带工资/日志，仅用户主动附加已脱敏诊断。不要硬编码历史邮件地址，从当前项目配置核实负责人指定地址。

Android 评价保留“充分使用之后、不打断完成当下”的原则，但**不照搬 iOS 的评价预询问**：Play In-App Review 指南不允许在卡片前询问意见。自动请求按合适时机与节流执行；手动“评价”按钮直达商店，不绑定可能不弹出的 In-App Review API。[R15], [A15]

## 7. Material 3 Expressive 视觉规范（Android 新设计）

### 7.1 设计方向与可审查标准

识别点保留 DoneAt 橙色与时钟意象；Expressive 用在当前状态、主要操作和必要的状态过渡，不把页面变成彩色海报。不是“给所有卡片加超大圆角”或“换一套主题色”就算完成。遵循官方 Material3 组件、颜色角色、字体层级、形状与 motion scheme。D-12：Release 只用稳定版 Material3，Expressive 的形状/动效/强调由 `:core:designsystem` 的 DoneAt token 实现，不引入 alpha/实验 API。[A01], [A02], [A03]

品牌色方案默认；提供系统动态配色开关（支持平台上才显示），不默认替换用户已经选定的主题。浅色/深色/跟随系统独立于品牌/动态配色模式。保存用户选择，重启和恢复后不闪回另一主题。

### 7.2 组件规格

| 区域 | 组件/实现原则 | 约束 |
|---|---|---|
| 主导航 | Material 自适应 NavigationSuite 方案 | 窄窗底栏，宽窗 rail/适当 drawer，不按机型硬编码 |
| 顶栏 | 原生 Material app bar + 标准图标 | 标题长文本可截/换行，主要操作始终可触达 |
| 主倒计时 | 明确数字层级、等宽数字特性 | 不每秒重新布局整页；TalkBack 不每秒播报 |
| 主操作 | Filled / expressive shape 按钮 | 一屏仅一处最高强调；危险结束与普通开始区别明确 |
| 周期选择 | 标准分段/Toggle group 包装 | 手势只是补充，仍可点击与键盘选择 |
| 排班日历 | 可访问格子 + 明确选中/今天/休息/未排标记 | 不只靠颜色；长按有替代菜单 |
| 记录图表 | Compose 绘制 + 文本等价内容 | 真实/估算用线型或填充差异，不依赖动画传达数据 |
| 专注任务 | 状态明确的可交互块 | 拖动有落点反馈与取消；大字体不把任务标题挤成不可读 |
| 表单 | Material text field、日期/时间选择器 | 原生键盘、IME inset、错误信息、保存防重复 |
| 次要动作 | Text/Outlined/Icon 按钮 | 不新增无语义的图标；Material Symbols 代替 SF Symbols |
| 反馈 | Snackbar、inline error、系统 haptics | 不用全屏弹窗报告每次小保存成功 |

默认版式建议：4dp 间距网格；页面边距紧凑窗 16–24dp；交互触达区至少 48dp；正文约 16sp，辅助约 12–14sp，主数字在窄窗约 56–72sp 起测。以上是待视觉验收的设计 token，不是不可调整的业务常量。200% 字体下允许改变排布和滚动，不能把文字缩回原大小。

主计时线框：

```text
[日期 / 班次]                         [专注]

            [工作中]
             03:25:18
          剩余有效工作时间
       ────── 进度 / 休息标记 ──────
       今天预计收入        [隐藏]

[接下来：休息 / 下班 / 下次班次]
[今天摘要：已工作 / 已休息 / 预计结束]
               [主要操作]

             计时 | 记录 | 设置
```

宽窗不是放大手机：计时与当天详情两栏；记录日历/图表与选中日详情分栏，独立滚动；设置采用列表-详情。使用同一页面状态与路由目标，不为平板再写一套业务计算。[A18]

### 7.3 动效与无障碍

数字变化只影响数字区域；工作→休息→结束可做短过渡，禁止每秒弹跳卡片/震动。购买成功保留明确成功反馈，但不要求 Android 机械复刻 iOS 2.8 秒连续 rigid 触感。系统动画关闭/减少动态效果时去除连续旋转，仍有静态成功状态。

使用 TalkBack 可识别名称、角色、状态与操作；图形有文本替代；隐藏收入在语义树中也隐藏；当前时间无需每秒 live region。阿拉伯语 RTL、硬件键盘、200% 字体、对比度、色觉差异是验收条件，不是发布后的优化。

## 8. 非功能指标（本包建议的验收目标，不是已经测得的结果）

| 编号 | 目标 | 测量方法 |
|---|---|---|
| NFR-01 | 核心业务无网络也可用，进程回收不丢已提交数据 | 飞行模式、进程终止、重启场景 |
| NFR-02 | 前台计时误差显示不因累计 tick 漂移；恢复后立即按绝对时间重算 | 注入时间、长时间运行和休眠后恢复 |
| NFR-03 | 中档参考真机 Release 冷启动 P95 目标 ≤2s；热启动 ≤1s | 明确机型/OS/样本数，Macrobenchmark，不能用 Debug 比 |
| NFR-04 | 60Hz 常见交互大部分帧在 16.7ms 预算，卡顿帧比例目标 <1% | 宏基准与真实图表/长列表，超标给 trace |
| NFR-05 | 15,000 日人生估算、十年记录不阻塞主线程 | 大数据固定档案，取消/缓存验证 |
| NFR-06 | 非使用时无周期性每秒唤醒、无无期限 wakelock/FGS | 日志、系统调度与耗电对比；目标阈值绑定参考设备 |
| NFR-07 | 所有 P0 测试通过，规则 fixture 覆盖输入集合无删减 | CI 实际执行数、报告、差分 |
| NFR-08 | 发布包无调试解锁、测试支付、敏感日志或密钥 | Release APK/AAB 与 manifest 扫描 |
| NFR-09 | 19 语言键、占位符与复数通过自动检查 | 生成报告；中文/英文/阿语/长文本视觉抽检 |
| NFR-10 | 数据写入、导入、迁移失败后保留原数据和可恢复副本 | 故障注入、低空间、途中进程终止 |

## 9. 首发产品验收场景

新用户在不登录、不购买、不授权通知的情况下完成班次设置并正确倒计时；带午休与夜班用户看到正确阶段；从 iOS v6 备份导入后记录、排班、人生与专注保持语义；已购买用户离线/重装/取消自动续费不被错误锁定；数据为空与读取失败界面不同；同一操作经手机/平板/通知入口结果一致；所有平台差异向用户如实解释。


---

## 本文参考网址

- **A01** · [Compose Material 3 发布说明](https://developer.android.com/jetpack/androidx/releases/compose-material3)
- **A02** · [Material 3 in Compose](https://developer.android.com/develop/ui/compose/designsystems/material3)
- **A03** · [Material 3 Expressive 设计入口（网页依赖 JavaScript）](https://m3.material.io/blog/building-with-m3-expressive)
- **A06** · [Play Billing 接入](https://developer.android.com/google/play/billing/integrate)
- **A10** · [AlarmManager 与精确闹钟权限](https://developer.android.com/develop/background-work/services/alarms)
- **A11** · [Live Update 通知及适用范围](https://developer.android.com/develop/ui/views/notifications/live-update)
- **A12** · [Glance 小组件更新与状态](https://developer.android.com/develop/ui/compose/glance/glance-app-widget)
- **A13** · [Google Drive 应用专用数据](https://developers.google.com/workspace/drive/api/guides/appdata)
- **A15** · [Google Play 应用内评价](https://developer.android.com/guide/playcore/in-app-review)
- **A18** · [Compose 自适应导航](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation)
- **A24** · [前台服务类型与适用范围](https://developer.android.com/develop/background-work/services/fgs/service-types)
- **A25** · [Android App Links 校验](https://developer.android.com/training/app-links/verify-applinks)
- **R01** · [仓库根 AGENTS：架构、隐私、规则与本地化契约](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md)
- **R02** · [iOS 快照与主倒计时显示规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift)
- **R03** · [扩展排班数据模型](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift)
- **R04** · [扩展排班解析器](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift)
- **R05** · [Plus 权益与免费窗口](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift)
- **R06** · [专注模型、模板与确定性会话 ID](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift)
- **R07** · [RecordJSON：跨平台备份协议与合并](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift)
- **R08** · [记录日解析优先级](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift)
- **R09** · [记录编辑、导入导出及隐私确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordsActions.swift)
- **R10** · [当前汇总与人生收入规则](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift)
- **R11** · [统一页面路由](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/AppRouteDestination.swift)
- **R12** · [同步设置、恢复与删除交互](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift)
- **R13** · [计划 015：收入、设置同步与用户确认](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md)
- **R14** · [计划 016：后续修订、首次恢复、固定月薪](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md)
- **R15** · [计划 012：周期总结与评价资格](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/012-ios-retention-and-cycle-notifications.md)
- **R18** · [共享提醒规范与测试入口（实施阶段完整复核）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/reminders.ts)

[A01]: https://developer.android.com/jetpack/androidx/releases/compose-material3
[A02]: https://developer.android.com/develop/ui/compose/designsystems/material3
[A03]: https://m3.material.io/blog/building-with-m3-expressive
[A06]: https://developer.android.com/google/play/billing/integrate
[A10]: https://developer.android.com/develop/background-work/services/alarms
[A11]: https://developer.android.com/develop/ui/views/notifications/live-update
[A12]: https://developer.android.com/develop/ui/compose/glance/glance-app-widget
[A13]: https://developers.google.com/workspace/drive/api/guides/appdata
[A15]: https://developer.android.com/guide/playcore/in-app-review
[A18]: https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation
[A24]: https://developer.android.com/develop/background-work/services/fgs/service-types
[A25]: https://developer.android.com/training/app-links/verify-applinks
[R01]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/AGENTS.md
[R02]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/CountdownRules.swift
[R03]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedSchedule.swift
[R04]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/Shared/ExtendedScheduleRules.swift
[R05]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/PlusEntitlement.swift
[R06]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/FocusModels.swift
[R07]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordJSON.swift
[R08]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/DayRecordResolver.swift
[R09]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/RecordsActions.swift
[R10]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Models/SummaryRules.swift
[R11]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/AppRouteDestination.swift
[R12]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Native/Views/RecordsSyncSettingsView.swift
[R13]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/015-device-feedback-life-income-settings-sync.md
[R14]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/016-life-projection-first-run-native-ipad.md
[R15]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/plans/012-ios-retention-and-cycle-notifications.md
[R18]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/lib/reminders.ts
