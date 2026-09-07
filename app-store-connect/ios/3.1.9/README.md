# 3.1.9 App Store Connect 准备包

## 已同步

月订、年订和终身买断的审核截图已上传，Apple 均返回 `COMPLETE`，远端 MD5 与本地相同。随后按上传指令同步了三个商品的审核备注，统一说明 7 天免费查看范围；价格及其他商品属性未变。

- 截图：`app-store-connect/iap/review-paywall.png`
- 验证回执：[iap-screenshot-sync.json](iap-screenshot-sync.json)

## 已上传的填写内容

- [17 种语言复制版](metadata-copy.md)：推广文本、描述、此版本新增内容。
- [审核备注](review-notes.md)：英文填写版与中文参考。审核备注是版本级共享字段，不按语言分别填写；保留现有审核联系人。
- 配置源：[3.1.9.json](../3.1.9.json)。

免费记录查看窗口为今天和前 6 天；超过 7 天的记录需要 Plus。文案与审核备注按此权益边界准备。

17 种语言的推广文本、描述、新增内容和 36 张商店截图已上传并回读匹配；英文审核备注已单独通过 API 同步，联系人和演示账号字段未变。版本仍为 `PREPARE_FOR_SUBMISSION`，未提交审核。此次未上传或替换已有 App Preview 视频。

回执：[完整上传核验](asc-upload-receipt.json) · [审核备注核验](review-note-sync.json)。

## 商店截图

[按语言和设备预览](../../../../scripts/marketing-shots/ios/review-3.1.9/index.html)。成品保存在 `scripts/marketing-shots/ios/out/`。

- 英文、简体中文、繁体中文分别捕获和排版，每种语言各含 6 张 iPhone 与 6 张 iPad 图。
- 场景：倒计时、小组件介绍、午休、年记录、人生、专注。
- iPhone：1320 × 2868，`APP_IPHONE_67`。
- iPad：2064 × 2752，`APP_IPAD_PRO_3GEN_129`。
- 年记录、人生与专注图标注 DoneAt Plus。
- 小组件图使用应用内原生小组件介绍页；所有数据均为模拟器示例，不含本人 iPad 数据。

## 送审前本人确认

- [ ] 确认推广文案与截图排序符合本次发版重点。
- [ ] 核对 ASC 中现有审核联系人与选定的 3.1.9 构建；本次上传没有修改这些信息。

## 验证结果

- 当前源码生成规则包后，Debug 模拟器构建成功。
- `check:version`、`check:ios`、`asc:iap:check` 通过。
- `asc:check -- --config app-store-connect/ios/3.1.9.json`：17 个语言、36 张截图、3 项既有预览引用通过。
- 36 张截图的精确文件集合、尺寸与无 Alpha 通道检查通过；六组联系表已经目视检查。
- [下载准备包](../../../../build/asc-3.1.9-prepared.zip)（20.2 MiB）：36 张商店图、多语复制稿、审核备注、IAP 审核图及同步回执；不含已有 App Preview 视频。
