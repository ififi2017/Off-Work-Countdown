# Play 3.2.2 本轮验收证据

实际状态只维护在 [progress.md](../../docs/android/progress.md)。本目录说明证据来源和局限，不建立另一份进度表。

- Android：USB Pixel 10 Pro，Android 17，独立 `com.rainif.doneat.parity322`，合成 v7 档案；正式 Play `com.rainif.doneat` 128 未替换。图中的薪资、生日、记录、余额均为合成数据。
- iOS：固定源 ea3144896caf6595509a8a6fef932d1ac835409a，既有 iPhone 18 Pro Max / iOS 27.0 模拟器，未同时开启第二台。
- 子代理实际使用 GPT-6.1 Sol / High，主代理审查、集成、构建与设备操作。代理完成声明不替代实际门禁。

| 证据 | 来源及覆盖 |
|---|---|
| `pixel/review-entry-*`、`review-about`、`review-access-inactive`、`review-disabled-*`、`review-service-disabled` | Debug32210正常MainActivity真实导航、未激活、格式错误与503关闭服务；只使用32A假码，不含真实凭证。`review-disabled-attempt`是ADB焦点时序少一字符的历史捕获，不当服务拒绝证据；最终`review-service-disabled`为确认32字符后真正503。 |
| `pixel/review-ui-{locale}-1-light`与`review-ui-{en,ar,zh-CN}-2-*` | 同一APK既有只读画廊，19语标题语义与截图；三种200%字号只局部注入，系统fontScale1.0/主题auto保持。主代理直接观察正常英文、阿语、俄语以及英/阿/简中200%截图；不声称19语母语审阅或真实TalkBack朗读。英文200%底栏既有标签出现单字母尾行，待确认最小排版修正。 |
| `play-review-data-safety-draft.png` | 新增Device or other IDs可选、非临时、功能/安全用途；Console显示保存待送审。没有填写有效App access凭证、提交或发布。 |
| `pixel/onboarding-{locale}`，`welcome-sheet-*` | 19语欢迎完成态，首轮隔离Debug32202；gallery只读遮罩不是产品层 |
| `pixel/records-{locale}`，`results-{locale}`，`release-{locale}`，`plus-{locale}` 与对应 `*-sheet-*` | 19语、浅色、局部减少动态效果；隔离Debug32204（英文记录重新采自32205）。分别是月视图、休假样例结果、新介绍、真实不可购买状态；每张标题匹配后逐图审查 |
| `pixel/records-year-en`、`records-life-en`、`records-week-final` | Pixel真实新年/人生/周绘制；Debug权益仅供视觉，不是购买验收 |
| `pixel/a11y-*` | 德文200%记录/付费墙、阿语200%锁定视图；应用内字体覆盖，系统字号不变。uiautomator语义检查不等同真实TalkBack朗读 |
| `pixel/setup-*-final`、`restore-*` | 真实 MainActivity 首启、中断恢复、系统文件选择器预览/取消/确认。restore-confirmed 是已有合成记录时被保护拒绝；restore-success 是空档案+带设置成功；restore-no-settings 是导入记录后继续SCHEDULE |
| `pixel/fix-life-before-mask` / `after-mask` | Debug32207；已滚动到人生分配与收入卡，隐藏前后标题bounds相同，三处金额全部遮罩且不留在语义树 |
| `pixel/fix-life-rotation-*` / `final-life-rotation-*` / `main-life-rotation-*` | 32207/32208缺陷历史：仅返回竖屏恢复，首次横屏失败，不当最终PASS |
| `pixel/nav-life-rotation-*` / `nav-rotation-before` / `nav-*-after-rotation` | Debug32209真实MainActivity修复后的横竖屏、切Focus再回记录和导航返回证据 |
| `pixel/records-wide-columns` / `records-fold-preview` | 1000×900dp局部视口、双列/垂直折叠注入；仅布局证据 |
| `ios/*.jpg` | 固定源真实欢迎/Plus/休假界面对照；StoreKit演示价格不是Play价格证据 |
| `play-*-draft.jpg` | Play Console保存成功的Data safety、英文文案、6张媒体草稿；未送审、未发布 |
| `store/` | 新记录宣传图与来源manifest；只有Records使用新Pixel真实UI，其余5张保持原API36.1来源，不重绘产品UI |
| `artifact/candidate-129.json` | 签名与公开配置核对通过，但后续发现UI问题，已弃用 |
| `artifact/candidate-131.json` / `manifest-131.xml` / `bundle-config-131.json` | b43880ff签名候选131；主代理独立核对签名、公钥、manifest、无Debug、四ABI16KiB通过。最终Play安装与成功回执冷路径未执行 |
| `artifact/billing-*` | 服务部署版本、回滚点、2次无效token拒绝路径CPU。没有成功购买/签名冷路径结论 |
| `artifact/rtdn-audit.json` | 既有Google Cloud会话只读订阅指标，24h最早未确认消息年龄0；无交付数据，不推断真实通知成功 |

所有屏幕录制/截图均为观察实际界面所得，未生成或重绘UI。系统文件选择器含私人账号的临时截图及出现系统剪贴板气泡的截图未纳入交付。临时旋转恢复为0；默认字体1.0及动画比例保持原值。Debug样例价格均明确标识且没有触发实际付款。
