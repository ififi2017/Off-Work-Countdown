# 2026-09-19 排班设置个人重做与月历配色走查

用户否定上一版页面，要求依照 Apple HIG 亲自重做，并追加要求每日配色与记录页月历对齐。本轮设计、实现和模拟器检查均由主代理完成，未使用子代理。此记录取代节假日验收文档中旧版页面的视觉结论；规则、数据和发布范围仍以原验收文档为准。

## 设计与实现

- 页面保持月历主导，下面依次为规则及必要设置、节假日入口、所选日期与班次。使用行内导航标题、系统菜单和弹层；编辑时隐藏底部导航，返回设置后恢复。
- 月历、规则设置、班次选择形成三个清楚的组，采用现有语义背景、22 pt 卡片、14 pt 控件。常驻的说明与重复班次文字收起，班次详情通过省略号进入弹层。
- 日期格沿用记录页的靛蓝工作色、浅灰休息色、8 pt 圆角和 2 pt 橙色选中边框。未排班为空白，今天通过数字强调；选中不覆盖班次底色。短班次文字仍可辨认，完整名称和时间保留在日期下方。
- 配色表示计划的工作／休息类别，整页不通过颜色深浅虚构实际工时或加班。与记录页共用颜色、计划强度及星期排列来源，未复制排班算法。
- 日期格点击区域扩展到间隙，每日只有一个按钮。点日期只选择，选班次才修改；周规则、逐日安排和清除都会即时更新草稿月历。
- 地区弹层顶部显示当前或建议地区，支持搜索及关闭。建议地区不打已启用勾选；打开、取消或重复选择当前地区不修改草稿。保存仍统一提交。
- 轮班当前周期位置增加左侧标签；缺少年份提示使用无千位分隔符的年份格式。设置入口的摘要读取扩展排班模式，避免把自由排班误显示成固定星期。

参考 Apple HIG 的 [布局](https://developer.apple.com/design/human-interface-guidelines/layout)、[选择器](https://developer.apple.com/design/human-interface-guidelines/pickers)、[动效](https://developer.apple.com/design/human-interface-guidelines/motion) 与 [触感](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)：通过分组、对齐、语义层级和渐进展示减少干扰，沿用系统控件行为，反馈对应实际操作。

## 动效与触感

- 按压使用已有 `OWCMotion.press`（140 ms），轻微缩放至 0.97 并改变透明度。
- 日期选择和赋班使用 `OWCMotion.selection`（180 ms），选中边框连续转移；跨月保持网格即时切换，仅月份标题淡变，避免整个日历飞动。
- 日期／月份变化、实际赋班／清除和地区改变触发一次 selection；重复选择不额外触发。系统 Picker／Menu 保留自身反馈，保存成功沿用 success。
- Reduce Motion 关闭位移和缩放；系统弹层沿用系统过渡。未以模拟器替代真机触感确认，也未宣称完成帧率测量。

## 验证记录

个人实际点击确认：六周月份、固定星期／单双休／轮班／自由／手动入口及预览；周三改休息后整月对应日期变灰；单独指定一天白班后仅该日变靛蓝；清除恢复周期；放弃修改回到设置，底部导航恢复；地区取消保持草稿未修改。

- 完整 iOS 串行回归实际执行 **802 tests / 51 suites**，全部通过。日志：`/Users/zhengyuxuan/Library/Developer/XcodeBuildMCP/workspaces/Off-Work-Countdown-bbef3647a545/logs/test_sim_2026-09-19T13-29-05-990Z_pid45720_2e10389a.log`，末尾确认 `Test run with 802 tests in 51 suites passed`，没有用零测试的成功横幅作为证据。
- lint、`check:ios`、`check:ios-strings` 和 `git diff --check` 通过。最后的对比度调整只改变月历文字语义色，并继续构建和截图复验。
- iPhone 18 Pro 中文浅色：最终版地区弹层显示当前中国大陆；重复选择当前地区后保存按钮仍禁用。六周 2027 年 1 月显示完整月历、规则和常用设置，缺少年份提示准确显示 `2027`，不猜测未公布安排。
- iPhone 17e 英文深色 Accessibility Large：月份自然换行，日期格保留大字号；规则、建议地区、完整班次名称及时间均可滚动查看。地区弹层显示 Off 勾选和未开启的建议地区，取消后仍无草稿修改。小班次文字改为系统 secondary，避免深色底上的有色文字对比不足。

- iPhone 17e 阿拉伯语浅色默认字号：RTL 日期、星期、月份方向、规则菜单、地区行及班次选择显示正常；日期格保留短名，完整名称在下方可读。
- iPhone 18 Pro 最终版追加检查：轮班位置左侧“今天是”与右侧周期日明确对应；单双休切换第二周后周六显示白班；六周月份完整显示相应周期颜色。放弃测试草稿后，设置摘要恢复“自由排班”，四个底部导航入口均恢复。
- iPad Pro 13 英寸中文默认字号：竖屏视觉检查通过，居中的月历和两组设置完整显示。再次发出横屏请求后截图仍是竖屏，**横屏未验证**；没有把这张截图记为横屏通过。iPad 辅助操作接口未返回可用目标，未宣称完成该设备的点击回归。
- 最后一次模拟器构建通过，最终对比度修订已在手机上重新安装并截图；没有新增文案键或修改共享排班算法。

最终主界面原始分辨率截图为 `iphone18pro-zh-light-october.png`。其他证据包括 `iphone18pro-six-week-calendar.jpg`、`iphone18pro-rotation.jpg`、`iphone18pro-alternating.jpg`、`iphone17e-en-dark-axlarge-top.jpg`、`iphone17e-en-dark-axlarge-settings.jpg`、`iphone17e-en-dark-axlarge-picker.jpg`、`iphone17e-ar-light-rtl.jpg` 和 `ipad13-zh-portrait.jpg`。手机均有实际点击及滚动验证，不以静态图片替代保存链路测试。

本轮临时改班均未保存，iPhone 18 Pro 最后经放弃修改返回设置；三个检查设备的 App 已停止、模拟器已关闭。外观、语言、字号通过进程启动参数指定，未改模拟器系统设置。

截图存放于 `/private/tmp/owc-schedule-redesign/`，属于本地验收产物，不加入 App 或发布包。

真机触感、真人 VoiceOver 听读和 Watch 真机门禁仍分别验收；本轮不上传或发布，也不表示整个 018／019 已完成。
