# 07 · 可执行验收案例目录

**状态：本文件是测试规范，所有案例均为 NOT_RUN。它不是已经通过的测试报告。**

1.2 范围：首发 126 条；后续阶段 14 条——QA-110～QA-122（D-02 修订，Drive 同步）与 QA-137（D-05，Wear）。新增 QA-138～QA-140（系统备份与换机恢复）。后续条目不阻塞首发、不删除、不标为已通过。方向批准不能改变任何测试的 NOT_RUN 状态。

用例中的确定性数字为本包独立设计；`ORACLE` 行必须先取得固定提交的真实 TS/Swift 输出，不能把本表描述当作已运行输出。完整移植还需补齐 M0 从所有源设置、调用点和源测试发现的子用例。

层级：JVM=纯规则单元测试；DB=数据库/事务/迁移；UI=Compose及无障碍；DEVICE=真机平台；SYNC=至少两端+真实云；PLAY=真实Play测试轨道/许可证测试；SEC=安全与隐私；PERF=Release性能；CI=构建流水线；WEAR=可选手表范围。未有权限/设备/服务时明确记为 NOT_RUN 或 BLOCKED。

每个执行结果记录 caseId、源SHA、Android提交、设备/OS/语言、输入文件哈希、实际输出、命令、测试数量及报告路径。对D项的批准修改必须注明决策ID和预期变更，不直接删掉不方便的案例。

## 基线与工程门禁

对应需求：FR-20。依据/相关资料：[R01], [A01], [A04], [A22]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-001 / CI | 全新检出固定SHA，工作区另有用户未提交文件 | 执行T00并创建Android分支 | 记录SHA和未提交文件；不reset、不覆盖、不以main最新内容混入固定基线。 |
| QA-002 / CI | 空Android工程，锁定所有依赖版本 | 构建Debug与启用R8的Release | 两种构建实际成功；报告实际版本、JDK和依赖树，无动态+版本。 |
| QA-003 / UI | 稳定版 Material3（1.4.x）+ DoneAt 自有形状/动效/颜色 token 探针（D-12） | 编译Debug与R8 Release并在目标设备交互 | Release依赖树不含alpha/beta的Compose或Material3；Expressive风格通过designsystem token实现；不引入实验API后再用@OptIn掩盖。 |
| QA-004 / CI | AGP9内置Kotlin的候选工程 | 检查Android和纯JVM模块插件 | Android不重复应用冲突的旧kotlin-android插件；domain独立无android.*依赖。 |
| QA-005 / CI | 原仓库TS/Swift fixtures与新增Android fixtures | 改规则但不更新生成文件，执行检查 | 检测源哈希/生成差异并失败；实际测试数量大于零，不接受空报告。 |
| QA-006 / SEC | Release APK/AAB与合并manifest | 扫描Debug gate、token、私钥、权限和测试地址 | 无调试解锁入口、测试支付适配器或密钥；无不相干敏感权限。 |
| QA-007 / CI | Android相关改动以及未修改的Web/Desktop/iOS | 执行原仓库适用检查与Android检查 | 报告真实回归结果；不能以Android成功替代其他目标保护。 |

## 有效时间段、跨日与时区

对应需求：FR-02, FR-04, FR-05。依据/相关资料：[R01], [R02], [R10]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-008 / JVM | 09–12、13–18；原计划8h；日薪80；现在08:00 | evaluateShift | elapsed=0、remaining=8h，主时间为距开始1h；收入0，非已工作。 |
| QA-009 / JVM | 同上；现在09:00 | evaluateShift | 工作开始边界正确；remaining=8h；无负数/NaN。 |
| QA-010 / JVM | 同上；现在11:00 | evaluateShift | 已工作2h，剩余6h，进度25%，收入20。 |
| QA-011 / JVM | 同上；现在12:00与12:30 | 分别evaluateShift | 进入休息；12:30 elapsed=3h、remaining=5h、hero=30min、收入30。 |
| QA-012 / JVM | 同上；现在13:00 | evaluateShift | 休息结束；hero切为有效剩余5h，不残留0秒休息态。 |
| QA-013 / JVM | 同上；现在18:00及18:05 | evaluateShift | 完成态；remaining=0；不自动把晚到的5分钟算加班。 |
| QA-014 / JVM | 同上延长末段到20:00；现在19:00 | evaluateShift | 当前总长10h、planned8h、elapsed9h、remaining1h、进度90%、payRatio1.125、收入90。 |
| QA-015 / JVM | 工作段09–10、11–12、14–16，now10:30 | 计算有效累计与当前间隙 | elapsed1h、remaining3h；休息hero直到11:00；不累计多个空隙。 |
| QA-016 / JVM | 22:00–次日06:00；now次日01:00；无休息 | 计算并查询日记录归属 | 已工作3h、剩余5h；班次归起始日，不在午夜生成第二份班次。 |
| QA-017 / JVM | 09:00–09:00合法班型，无休息 | 展开一日班次 | 依源定义终点在次日而非0h；仍执行源有效段校验。 |
| QA-018 / JVM | 空段、0长度段、倒序段、重叠段或非法时间 | 执行校验及恢复读取 | 按冻结源规范归一化或拒绝；绝不出现负长、重复累计、NaN或静默默认白班。 |
| QA-019 / JVM | now精确等于每个segment起止毫秒 | 逐边界计算 | 使用半开区间语义；每个瞬间只计入一次；显示舍入与源oracle一致。 |
| QA-020 / JVM | 周期锚点、跨年周、闰年2028-02-29 | 按民用日展开 | 日期连续且身份唯一；不是每次加86400000毫秒。 |
| QA-021 / ORACLE | America/Los_Angeles夏令时跳过/重复时刻，含夜班 | TS/Swift与Kotlin同输入比较 | 与源缺失/重叠时刻选择一致；未生成源输出前不得猜测Java默认行为。 |
| QA-022 / JVM | 历史记录时区Asia/Shanghai，设备改America/Los_Angeles | 重开记录及免费窗口 | 历史dayKey和原时区语义不变；设备时区不静默覆盖记录时区。 |
| QA-023 / JVM | 同一前台时钟暂停tick90秒，然后恢复 | 重新evaluate而非循环补tick | 立即显示当前正确状态；不将缓存remaining减1作为长期事实。 |
| QA-024 / DEVICE | 运行班次中修改系统时间/时区再重启 | 重新计算和重建调度 | 执行已冻结的时钟变更语义；不重复完成/提醒；UI与历史分类一致。 |
| QA-025 / ORACLE | 关闭自动模式、空工作日、无法解析下一班次 | 比较源规则输出 | 准确区分手动可开始、休息与未排班；无下一班次不构造虚假的明天。 |

## 排班、历史冻结与输入约束

对应需求：FR-02, FR-03, FR-04, FR-07。依据/相关资料：[R03], [R04], [R08], [R09]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-026 / JVM | 班型名为空、仅空白、40与41个字符 | 保存班型 | 与源trim/长度单位一致；临界Unicode组合字符另做对照，不直接等同UTF-16长度。 |
| QA-027 / JVM | 周期长度0、1、366、367；未知新preset | 读取/保存规则 | 合法长度1–366；已定义的未知preset回退custom；不可保存空周期。 |
| QA-028 / JVM | 三天周期锚点2026-09-21，查看锚点前一天 | 解析周期位置 | 使用floorMod得到最后一项，不以负数数组索引崩溃。 |
| QA-029 / JVM | 周期为工作，某日手动设休息 | 解析该日再撤销手排 | 手排覆盖；撤销恢复下层规则，不把撤销保存为永久休息。 |
| QA-030 / JVM | 手排引用尚未下载到的班型ID | 先到RosterDay后到类型 | 前者安全显示未分配；后者恢复正确班型，不改写原ID。 |
| QA-031 / JVM | 过去一天存assignedShiftType冻结值；未来一天只指类型ID | 修改该班型名称/起止 | 过去保持冻结值；未来按源实时类型规则更新。 |
| QA-032 / JVM | 历史使用扩展排班；当前关闭扩展排班 | 读取历史图表与日详情 | 仍以历史extendedContent/冻结覆盖解析，不回退当前固定班而改变过去。 |
| QA-033 / ORACLE | 无规则月继承前月，含31→30→28/29日和手工月份 | 与Swift测试逐组合比较 | 严格匹配源继承/人工空档规则，不凭简单日数复制补齐不存在日期。 |
| QA-034 / ORACLE | holidayRegion=nil、空串、合法地区及clearedFromDayKey | 组合解析跨清空边界日期 | 保留nil与空串语义；清空后不会重启又自动填回；手排/节假日组合依源测试。 |
| QA-035 / JVM | 已归档班型被历史引用 | 从新建选择器与历史分别读取 | 不能新选的归档类型仍能解释旧记录；不级联删除历史。 |
| QA-036 / JVM | 今天正在工作；修改常规班次 | 分别选应用今天/从下一次开始 | 按源允许项固定当前快照/未来规则；不回写过去或无理由改当前专注终点。 |
| QA-037 / JVM | 同一天有效override、user exception、bundled exception和snapshot并存 | 解析，再逐层cleared | override优先；清除后正确回退；观测不参与计划优先链。 |
| QA-038 / JVM | 多个同effectiveFrom快照，乱序查询返回 | 解析并反转数据库返回顺序 | 按editCount/tieBreaker/ID确定同一胜者，而非最后一行。 |
| QA-039 / JVM | 历史09–12、13–18，将上下界改10–17 | 保存自定义工时 | 得到10–12、13–17；保留休息洞，不生成10–17连续7h。 |
| QA-040 / DB | 一天编辑需同时写override与exception，中途故障 | 故障注入并重开 | 全部提交或全部回滚；草稿保留，不显示半成功。 |

## 记录、收入与人生

对应需求：FR-05, FR-06, FR-07, FR-08。依据/相关资料：[R05], [R08], [R10], [R13], [R14]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-041 / JVM | 金额空、0、负数、极大值、NaN/Infinity及逗号小数地区 | 校验输入和反序列化 | 空与0按源区分；非法值明确拒绝，不截断为另一个合法工资。 |
| QA-042 / ORACLE | 固定月薪完整月，分别少记录工时、请假、正常出勤 | 生成记录月汇总 | 依当前后续规则月基数不因请假扣减；年终奖份额与源一致。 |
| QA-043 / ORACLE | 一周横跨两个不同天数月份；月薪不变 | 生成周已过/剩余汇总 | 分别按所在月自然日分摊；不使用统一21.75或单月工作日作分母。 |
| QA-044 / ORACLE | 日薪模式与固定月薪相同日历输入 | 比较收入调用路径 | 日薪仍按源工作日/进度规则；不能套用固定月薪自然日口径。 |
| QA-045 / JVM | 同一天已有实际，未来仍有计划 | 计算实际+预计 | 对同一语义时间区间无重复计算；明细来源与汇总可对账。 |
| QA-046 / JVM | 记录时区今天2026-09-21 | 免费用户分别查看09-15/09-14/09-22 | 09-15至09-21是七个自然日窗口；09-14和未来不因数组条数而进入。 |
| QA-047 / JVM | 从未购买与已订阅后到期两类用户 | 产生新工作观测 | 默认基线前者继续后者停止；D-07变更必须连同预期显式修订。 |
| QA-048 / SEC | 免费/过期用户打开受限图表/人生/专注 | 检查UiState、Semantics和分享 | 受限真实值不传给隐藏布局；不能从可访问树、剪贴板或日志获取。 |
| QA-049 / UI | 周/月相同结构图表、已选日、滚动位置 | 切换尺度/返回/旋转 | 保持合理选择与位置；数字不重复跳动；宽窗两栏滚动互不抢占。 |
| QA-050 / JVM | 两段职业之间有一年空档 | 人生收入汇总 | 空档零收入；不延伸上一个工资自动填满。 |
| QA-051 / JVM | 职业区间重叠或终点早于起点 | 保存资料 | 清晰拒绝/展示校验；不能双算工资或静默抹除原经历。 |
| QA-052 / ORACLE | 未来收入从45岁起60%，退休60岁 | 计算跨45岁前后预测 | 45岁后一次性变60%并保持；不是逐年乘0.6，也不是线性递减。 |
| QA-053 / ORACLE | 收入调整起始年龄已过去，存在历史收入 | 重新估算 | 历史不变；只从当前预测起点应用比例。 |
| QA-054 / JVM | 职业跨闰年及不同长度的部分月 | 按月/年薪计算 | 部分月按本月实际日数；不统一按30天；终点排他性依源fixture。 |
| QA-055 / UI | 选择原职业阶段，时间推进或刷新导致展示切段 | 重新渲染人生画布 | 选中身份基于稳定阶段ID，不跳到另一段/数组位置。 |
| QA-056 / PERF | 15000日人生和十年真实/预计记录 | 快速切换日期再离开页面 | 后台计算可取消；主线程不遍历全档案；旧结果不覆盖较新的选择。 |

## 专注任务与会话恢复

对应需求：FR-09。依据/相关资料：[R06], [R11]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-057 / JVM | 全新专注设置 | 读取默认并输入超范围数值 | 默认25/5/15/4；规范化到10–60/1–15/5–30/2–6。 |
| QA-058 / JVM | 专注已启动并保存plannedEnd | 修改专注时长 | 当前plannedEnd不变，下一会话使用新设置。 |
| QA-059 / JVM | 固定任务UUID及start/end毫秒 | 生成自动会话ID | 匹配acceptance_examples的SHA256/位设置结果；禁止MD5或SHA1替代。 |
| QA-060 / DB | 前台和通知动作同时启动同一块，随后重复回调 | 并发执行两次命令 | 一个逻辑会话和一次状态转移；重复触发返回已处理结果。 |
| QA-061 / DEVICE | 专注进行中进程被回收；20分钟后重开 | 恢复本地会话 | 用持久时间重建，不从满时长重新开始；历史写入幂等。 |
| QA-062 / JVM | 专注到期后到午休/下班边界 | 重建计划和通知 | 遵循源停止/恢复策略；不越过不可工作边界虚构专注成果。 |
| QA-063 / JVM | 模板任务轮数2、3、1，仅剩4个工作块 | 应用模板 | 只放完整首任务2轮；不放第二任务部分，不跳过第二任务去塞第三任务。 |
| QA-064 / JVM | 同模板分别应用长班与短班 | 检查模板本体 | 模板轮数/任务不被短班裁剪永久覆盖。 |
| QA-065 / UI | 放入下一块操作触发Plus购买 | 成功后回到原操作 | 保留草稿及原落位，至多执行一次；取消购买仍可继续编辑草稿。 |
| QA-066 / UI | 拖动任务到非法/冲突位置后取消 | 查看原任务与计划 | 原任务位置保留；明确冲突原因；TalkBack可通过非拖动动作完成同类操作。 |
| QA-067 / SYNC | 两台设备自动启动相同时间块，离线后重连 | 先通过v6导出/导入合并（首发）；Drive同步阶段再以自动重连复测 | 相同确定性ID合一；真正竞争会话按源规则保留supersededBySync历史。 |
| QA-068 / JVM | 停止、自然完成、边界停止与废弃四种操作 | 查询会话记录 | 各自保留对应结束原因；不删除或统统改为completed。 |

## 数据持久化、导出与跨端兼容

对应需求：FR-01, FR-14, FR-17。依据/相关资料：[R07], [R09], [R14]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-069 / DB | iOS导出的schema1、2、3、4、5、6合法备份各一份 | 逐个导入 | 全部支持既定旧版本默认/迁移；不得仅改版本号假装兼容。 |
| QA-070 / DB | iOS v6包含12类实体、nil/空串、冻结手排、专注模板 | Android导入→导出→iOS重新导入 | 业务字段和身份语义无丢失；差分只含明确允许的导出时间/排序。 |
| QA-071 / DB | schema7、错误根类型、截断JSON、非法时区/日期 | 预览导入 | 整文档不支持/格式错误与行级拒绝按源策略区分；活跃库未被覆盖。 |
| QA-072 / SEC | 超大数组、极深嵌套、重复身份、巨大金额/时间 | 解析不可信导入文件 | 有限制与明确错误，不无限内存、不溢出、不绕过类型校验。 |
| QA-073 / DB | 本地和导入文件同ID不同内容 | 默认导入预览并取消 | 展示冲突；默认不无提示覆盖本地；取消后状态不变。 |
| QA-074 / DB | 本地有ErasedID墓碑，导入旧备份含同ID | 默认skipErased | 记录不复活，报告跳过数量；不能把墓碑仅当普通垃圾清理。 |
| QA-075 / DB | 明确restoreErased，涉及阶段/快照/任务依赖 | 执行恢复 | UUID身份依源规则重新分配并重映射引用；自然键保留合法语义。 |
| QA-076 / DB | 相同实体两份editCount相同、tieBreaker不同；系统时钟反向 | 双向合并 | 结果与源固定比较一致；不根据editedAt或Drive modifiedTime选择。 |
| QA-077 / DB | 导入合法大档案，在提交前后分别模拟崩溃/低空间 | 重开应用 | 保留旧完整状态或新完整状态；没有半份导入与伪保存成功。 |
| QA-078 / SEC | 用户导出含收入档案与排除人生档案两种模式 | 检查输出JSON和权限 | 仅实际v6导出字段；不带Play权益、OAuth token、本机权限或内部sync state。 |
| QA-079 / DEVICE | 通过SAF选云文档/只读URI/取消保存 | 导入和导出 | 不用全盘文件权限；URI错误清晰，可取消；不把文件名当已成功写入。 |
| QA-080 / DB | 每个支持的本地 RecordLocalFile / v1–v6 备份版本 | 读取旧档案并写回、重开 | 按 D-13 单文件归档验证实体、编辑戳、关系、墓碑；写失败不发布部分状态，损坏或更新版本不销毁数据。 |
| QA-081 / DEVICE | 新用户无有效配置，欢迎草稿中途重启 | 继续欢迎后完成 | 草稿可恢复；确认前不生成dirty业务设置或工作观测。 |
| QA-082 / DEVICE | 用户导入自己的数据但无Plus或已过期 | 执行恢复/导出/删除 | 数据控制不要求重新付费；恢复不会伪造Plus或获得付费编辑权限。 |

## Android 调度、通知与小组件

对应需求：FR-10, FR-11, FR-12。依据/相关资料：[R01], [R15], [A10], [A11], [A12]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-083 / DEVICE | Android13+拒绝通知；基础班次正常 | 完成欢迎并倒计时 | 本地功能可用；状态如实提示未授权，不重复强迫请求。 |
| QA-084 / DEVICE | 精确提醒权限未授予/被拒绝 | 启用普通提醒 | 有明确延迟降级；不调用无权限API致崩溃，不改用违规USE_EXACT_ALARM。 |
| QA-085 / DEVICE | 已授权并排好未来提醒；运行中撤销精确权限 | 返回应用并检查系统任务 | 重新检查能力并重建合法任务；不把旧已取消闹钟当仍有效。 |
| QA-086 / DEVICE | 班次编辑/时区改变/重启/应用更新 | 重建未来提醒 | 旧计划失效；新提醒去重；不在重启后补发已错过的一串通知。 |
| QA-087 / ORACLE | 普通进度关闭，Plus周期总结开启；后一天可靠休息 | 生成提醒列表 | 仍有周期总结；同结束点普通兜底不重复响。 |
| QA-088 / ORACLE | 后一天排班解析失败或节假日覆盖不足 | 计算周期末 | 不把未知当休息，不发送虚构周期总结。 |
| QA-089 / DEVICE | 同一通知按钮连续点击；主界面也点相同操作 | 执行命令 | 持久去重且及时更新通知；不重复结束/新增会话。 |
| QA-090 / DEVICE | 工作日跨午休，显示持续通知计时 | 进入休息并回到工作 | 不把全天end-now称为有效剩余；阶段/计时含义一致，受限时显示正确结束钟点。 |
| QA-091 / DEVICE | 普通工作计时不符合Live Update展示资格 | 检查前台/锁屏 | 普通通知回退可用；不宣称每台机都有灵动岛等效UI。 |
| QA-092 / DEVICE | 桌面小组件缩放为紧凑/中/大，切主题与语言 | 查看工作/休息/未排/过期 | 各布局内容准确可触达；无工资字段，过期不伪装实时。 |
| QA-093 / DEVICE | 进程已死或设备Doze，桌面停留30分钟 | 观察小组件和耗电/系统任务 | 不每秒调Worker；系统允许时刷新，不能承诺精确边界刷新；计时增强先过设备探针。 |
| QA-094 / SEC | 恶意外部Intent调用内部receiver/service或错误PendingIntent | 尝试执行修改命令 | 非公开组件不可外部调用；公开动作校验数据，无工资URI、可变Intent注入。 |

## 购买、恢复与服务端证据

对应需求：FR-16, FR-20。依据/相关资料：[R05], [A05], [A06], [A07], [A08]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-095 / PLAY | 实际可购月/年/终身商品，不同币种与offer资格 | 加载付费页 | 价格/周期/试用来自ProductDetails；不硬编码或以月价乘12伪年价。 |
| QA-096 / PLAY | 商品加载失败/无GMS/用户无可购offer | 打开付费页 | 基础应用不阻断；失败与无资格区分，无必失败的试用按钮。 |
| QA-097 / PLAY | PENDING购买，超过24小时仍待付款 | 刷新与重装恢复 | 不授予Plus，也不套Apple AskToBuy24小时自动清除规则。 |
| QA-098 / PLAY | 月订阅成功且验证正常，重复回调 | 确认权益并处理pending action | 客户端只确认一次逻辑购买（acknowledge幂等）；原操作至多一次；真实价格与商品可追溯。 |
| QA-099 / SEC | 伪造isPlus、本地purchaseState、包名/商品/签名，或通过v6导入/Auto Backup恢复带入权益 | 本地恢复与重启 | 权益只来自当次Play查询及Billing签名校验（Play公钥）；不能靠本地布尔、备份或导入文件解锁。 |
| QA-100 / PLAY | 用户取消自动续费但订阅未来才到期 | 恢复购买和重启 | 权益保持到真实截止；不因cancel标记立即撤销。 |
| QA-101 / PLAY | 平台宽限、account hold、暂停、恢复、到期 | 用Play许可测试订阅周期推进，并调用queryPurchasesAsync | 宽限期内仍授予；account hold/暂停/到期时查询不再返回即停止；不按purchaseTime+30天推断。 |
| QA-102 / PLAY | 网络失败或一个未验证条目，已有合法未到期缓存 | 刷新 | 保留合法缓存及期限；失败不等于完整确认无权益。 |
| QA-103 / PLAY | 可靠完整查询确认为无权益/已退款撤销 | 应用刷新 | 回收对应权利但保留用户数据与导出；不被旧cache永久覆盖。 |
| QA-104 / PLAY | 已持有终身，当前网络断开 | 进入原付费功能 | 遵守已验证终身缓存策略；不会因网络问题当免费；在线撤销证据可更新。 |
| QA-105 / PLAY | 购买成功但客户端acknowledge失败/进程被杀 | 下次启动或回到前台重试 | 持久化待确认标记并在3天窗口内重试确认；终身绝不consume；未确认前不重复授予或重复扣款。 |
| QA-106 / PLAY | 升级/替换订阅（月↔年），旧token仍在本地缓存 | queryPurchasesAsync刷新 | 只以当次查询返回的有效购买为准，不出现旧新双份权益。RTDN/linkedPurchaseToken服务端处理属后续验证服务阶段（D-08修订）。 |
| QA-107 / PLAY | 已订阅用户购买终身 | 完成后查看管理入口 | 不谎称原订阅自动取消；明确管理路径，避免重复付费。 |
| QA-108 / DEVICE | 付款页面旋转/退后台/进程恢复并再点购买 | 检查BillingClient及请求次数 | 无多个客户端重复流程；购买/恢复互斥，UI重组不重复launch。 |

## 同步、删除及新设备恢复

**1.2（D-02 修订）**：QA-109 仍属首发（首发不请求任何 Google 授权）；QA-110～QA-122 属首发后的 Drive 同步阶段，不阻塞首发、不删除。首发换机恢复见“系统备份与换机恢复”。

对应需求：FR-01, FR-09, FR-15。依据/相关资料：[R07], [R12], [R14], [A13]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-109 / SYNC | 首发不含任何Google授权；全新安装 | 完成本地使用并检查网络 | 不请求Google登录/OAuth，不上传工资/默认设置；网络仅用于Play Billing与用户主动分享等已记录功能。 |
| QA-110 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。云端已有完整档案，旧设备关闭；新安装 | 授权并首次恢复 | 完整分页下载→预览→原子应用；不依赖旧设备上线发送当前快照。 |
| QA-111 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。首次查询超时/401/配额错误 | 进入恢复选择 | 显示未知/失败，不作为空云创建并上传欢迎默认值。 |
| QA-112 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。设备A改日期甲，设备B离线改日期乙 | 恢复联网并双向同步 | 两天修改都保留；不是最后整文件上传者抹除另一台。 |
| QA-113 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。同ID并发编辑、时钟错误且网络乱序 | 重复合并批次 | 按编辑戳稳定收敛；不看墙钟/文件modifiedTime。 |
| QA-114 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。一台删除，另一台持旧行，之后重连 | 同步墓碑 | 旧行不复活；合法显式重新创建使用更高版本规则。 |
| QA-115 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。上传成功但本地未确认即崩溃，云上同名文件多份 | 恢复重试并拉取 | 按batchId/hash去重，不以文件名唯一性假设创建重复业务。 |
| QA-116 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。用户删除云端，老设备离线持旧generation | 老设备晚到上传旧批次 | fence阻止旧数据复活；有未同步本地内容先审阅/导出。 |
| QA-117 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。两台设备并发reset | 重新读取所有fence/batch | 固定有序规则选唯一新generation；输的一方不复活旧批次。 |
| QA-118 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。用户在Drive外部删整个应用数据空间，旧机还配对 | 自动同步触发 | 暂停并请求选择；不能自动新建云空间把已删工资重新上传。 |
| QA-119 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。Google账号A已同步，切到B | 打开同步设置 | 旧本地数据不自动流入B；明确解除配对/导出/选择状态。 |
| QA-120 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。依次暂停同步、删除云副本、移除此设备数据 | 检查三个作用范围 | 行为不同且明确；暂停不删数据，本机移除不误删云；危险操作互斥。 |
| QA-121 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。页数多、批次大、未知格式或哈希错误、恢复中断 | 拉取全部后合并 | 无静默漏页；错误候选不污染本地；重新执行可恢复且幂等。 |
| QA-122 / SYNC | D-02修订：Drive同步延至首发后；同步阶段启动后执行。数据同步收到主题/语言/薪资，也收到伪权限/权益字段 | 映射业务和本机状态 | 只接受协议内业务字段；通知权限、生物识别授权、Play权益不跨设备复制。 |

## 隐私、UI、语言与 Play 发布

对应需求：FR-05, FR-13, FR-17, FR-18, FR-19, FR-20, FR-21。依据/相关资料：[R01], [R09], [R21], [A09], [A14], [A15], [A16], [A17], [A18]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-123 / SEC | 隐藏工资，生物识别取消/失败或无设备锁 | 请求显示/导出敏感内容 | 失败/取消不泄露；无设备锁有明确降级说明，不假装验证成功。 |
| QA-124 / SEC | 页面含工资、任务和职业信息，切后台/最近任务 | 检查截图/任务缩略图/TalkBack | 执行D-09批准策略；普通安全卡片分享不通过解除整个窗口保护实现。 |
| QA-125 / SEC | 生成普通分享卡和班次链接 | 检查图片、元数据、URL、日志 | 无工资/职业/身份/token；不截图整个屏幕。 |
| QA-126 / DEVICE | 班次分享链接、应用显式通知和快捷入口 | 分享后检查 URL；打开各应用入口 | 分享链接只带起止时间并在网页版打开；应用不注册外部 https / 自定义 scheme 的接收器。显式入口仅接受计时/专注/记录/设置等已知路由，不改设置。 |
| QA-127 / SEC | 系统cloud backup和device transfer分别启用 | 备份/恢复应用数据 | 业务库/秘密/购买缓存按显式规则排除；不能仅凭无上传代码声称数据未出设备。 |
| QA-128 / UI | 19locale，包含阿拉伯语、长德语、简繁中及占位符 | 自动资源检查及重点页视觉操作 | 无遗漏key/坏复数/格式崩溃；RTL可用，香港台湾资源不误丢。 |
| QA-129 / UI | 系统字体200%、小窗320dp、键盘弹出 | 编辑班次/工资/任务/付费页 | 信息可读且所有操作可滚动到；不缩文字或挡保存按钮。 |
| QA-130 / UI | 窄窗→平板分屏→折叠展开；各主入口不同导航栈 | 连续resize、返回、旋转 | 选择/草稿/栈不丢；无按设备名创建另一套规则；宽窗内容合理分栏。 |
| QA-131 / UI | TalkBack开启、仅键盘/方向导航、减少动画 | 使用日历、图表和专注拖放替代 | 语义角色/状态完整；不每秒播倒计时；所有功能无需拖动也能完成。 |
| QA-132 / DEVICE | 已完成计时后的合适启动与手动评价按钮 | 触发评价流程 | 无评分/满意度预询问；系统不弹不循环；手动按钮直达Play页。 |
| QA-133 / PLAY | 真实Play账号类型与创建日期已确认 | 创建测试/申请生产访问 | 仅适用账号执行12人连续14日要求；完成后还需生产访问审核，不承诺自动通过。 |
| QA-134 / PLAY | Release AAB含全部依赖与可能的native .so | 检查target、签名、Billing和16KB兼容 | 以实际包为准；API/库符合发布当日要求；native依赖不能因主语言Kotlin被忽略。 |
| QA-135 / PLAY | 首发实现含Play Billing与Auto Backup/设备转移，不含Drive授权或自建验证服务 | 逐项填写Data safety/隐私/删除入口 | 按真实离设备流向填写（系统备份由Google处理、端到端加密条件如实描述）；不照搬iOS Data Not Collected；后续加Drive或验证服务时重做申报。 |
| QA-136 / PLAY | Android真实手机/平板截图和各语言商店文案 | 检查商店素材及审核操作说明 | 不放iOS截图/假功能；审核员能访问合法测试流程，不提供工资真数据或暗门。 |
| QA-137 / WEAR | D-05已确认延后；仅后续Wear阶段获准启动并具备手机/手表环境后执行，手机离线/关机 | Watch端解析缓存排班并刷新复杂功能 | 复用同一无薪资规则；离线可延续排班；具体版本/发布独立验证。当前保留NOT_RUN并从首发阻塞集合排除，不删除该用例或标PASS。 |

## 系统备份与换机恢复（1.2 新增，首发）

对应需求：FR-01、FR-14、FR-16、FR-17、FR-20。依据/相关资料：[A16], [A28]

| ID / 层级 | 输入或前置条件 | 操作 | 必须满足的预期 |
|---|---|---|---|
| QA-138 / DEVICE | 旧机有完整记录/排班/专注/偏好，已设锁屏；新机登录同一 Google 账号 | 通过设备转移及云端 Auto Backup 分别恢复 | D-13 原子档案和显示设置完整恢复；首次启动完成档案读取后再展示业务界面，并重建提醒/小组件；会话、购买缓存与授予权限不从备份继承。 |
| QA-139 / SEC | 旧机持有Plus缓存、待确认购买标记、Keystore密钥、通知/精确闹钟授权 | 恢复到新机并启动 | 购买缓存、密钥与令牌不在备份内；权益重新经Play查询得出；权限状态按新机实际查询，不从备份恢复成已授予。 |
| QA-140 / DB | 档案原子替换写入中备份；或恢复较新版本本地档案 | 故障注入、重开及恢复启动 | D-13 备份读取到完整旧版或新版档案，不出现半份 JSON；更新版本或损坏档案阻断写入并保留原文件，不静默重建。 |

## 结果与阻塞登记

所有必选案例通过，仍不自动代表完整产品通过：还需要源功能盘点没有遗漏、规则fixtures没有删减、生产权限/云/支付验收证据齐备。Wear只有负责人明确排除后才可不纳入首发分母。

```text
case: QA-xxx
status: PASS | FAIL | NOT_RUN | BLOCKED
sourceCommit:
androidCommit:
build / device / OS / locale:
input / fixture hash:
command and actual test count:
expected vs actual:
evidence path:
related decision / approved deviation:
owner / reviewedAt:
```

本目录共 **140** 条独立案例；机器可读版本见 `test-catalog.json`。数字为计划数量，不是已执行数量。


---

## 本文参考网址

- **A01** · [Compose Material 3 发布说明](https://developer.android.com/jetpack/androidx/releases/compose-material3)
- **A04** · [Google Play 目标 API 政策](https://support.google.com/googleplay/android-developer/answer/11926878)
- **A05** · [Play Billing 废弃周期](https://developer.android.com/google/play/billing/deprecation-faq)
- **A06** · [Play Billing 接入](https://developer.android.com/google/play/billing/integrate)
- **A07** · [Play Billing 安全及服务端验证](https://developer.android.com/google/play/billing/security)
- **A08** · [订阅生命周期](https://developer.android.com/google/play/billing/lifecycle/subscriptions)
- **A09** · [新个人开发者账户的测试要求](https://support.google.com/googleplay/android-developer/answer/14151465)
- **A10** · [AlarmManager 与精确闹钟权限](https://developer.android.com/develop/background-work/services/alarms)
- **A11** · [Live Update 通知及适用范围](https://developer.android.com/develop/ui/views/notifications/live-update)
- **A12** · [Glance 小组件更新与状态](https://developer.android.com/develop/ui/compose/glance/glance-app-widget)
- **A13** · [Google Drive 应用专用数据](https://developers.google.com/workspace/drive/api/guides/appdata)
- **A14** · [Google Play Data safety 申报](https://support.google.com/googleplay/android-developer/answer/10787469)
- **A15** · [Google Play 应用内评价](https://developer.android.com/guide/playcore/in-app-review)
- **A16** · [Android 数据备份默认行为](https://developer.android.com/identity/data/backup)
- **A28** · [Android Auto Backup 排除规则](https://developer.android.com/identity/data/autobackup)
- **A17** · [16 KB 内存页兼容](https://developer.android.com/guide/practices/page-sizes)
- **A18** · [Compose 自适应导航](https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation)
- **A22** · [AGP 9 内置 Kotlin](https://developer.android.com/build/migrate-to-built-in-kotlin)
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
- **R21** · [iOS 翻译目录（已核实路径，实施阶段转换完整文件）](https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Localizable.xcstrings)

[A01]: https://developer.android.com/jetpack/androidx/releases/compose-material3
[A04]: https://support.google.com/googleplay/android-developer/answer/11926878
[A05]: https://developer.android.com/google/play/billing/deprecation-faq
[A06]: https://developer.android.com/google/play/billing/integrate
[A07]: https://developer.android.com/google/play/billing/security
[A08]: https://developer.android.com/google/play/billing/lifecycle/subscriptions
[A09]: https://support.google.com/googleplay/android-developer/answer/14151465
[A10]: https://developer.android.com/develop/background-work/services/alarms
[A11]: https://developer.android.com/develop/ui/views/notifications/live-update
[A12]: https://developer.android.com/develop/ui/compose/glance/glance-app-widget
[A13]: https://developers.google.com/workspace/drive/api/guides/appdata
[A14]: https://support.google.com/googleplay/android-developer/answer/10787469
[A15]: https://developer.android.com/guide/playcore/in-app-review
[A16]: https://developer.android.com/identity/data/backup
[A28]: https://developer.android.com/identity/data/autobackup
[A17]: https://developer.android.com/guide/practices/page-sizes
[A18]: https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation
[A22]: https://developer.android.com/build/migrate-to-built-in-kotlin
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
[R21]: https://github.com/ififi2017/Off-Work-Countdown/blob/9252fdfdc66aab88b4acb7493684f11991fd773d/src-mobile/ios/App/App/Localizable.xcstrings
