# DoneAt · TikTok 三个开头实验

三条中文短片，每条 21 秒、1080×1920、9:16、60 fps。前三秒不同，3 秒之后共用同一段内容。

| 版本 | 开头 | 假设 |
| --- | --- | --- |
| `progress` | 下班，原来可以看进度条。 | 用产品特写直接说明价值 |
| `office` | 今天第 8 次看时间了。 | 用人物、时钟和情境建立共鸣，1.65 秒切到产品 |
| `woodfish` | 等下班，还能敲两下。 | 用即时敲击反馈建立兴趣，同时保留倒计时语境 |

共用主体：3–5.6 秒完整 App；5.6–8.4 秒小组件与灵动岛；8.4–10.8 秒午休暂停；10.8–13.8 秒木鱼；13.8–16.8 秒归零倒计时；16.8–17.8 秒下班庆祝；17.8–21 秒稳定 CTA。

## 文件与对比

- `index.html`：三版播放器、同步静音比较、旧版参考入口。
- `preview.mjs`：本机比较页面服务，复用项目已有静态文件发送器，支持视频分段读取。
- `scene.html`：确定性时间轴；`?variant=office&play` 播放，`?variant=progress&t=2&safe` 查看安全区。
- `render.mjs`：无头 Chrome 抓帧、ffmpeg H.264/AAC 输出。
- `audio.mjs`：复用旧版合成音效配方，重新编排轻配乐与声画切点，不含人声。
- `assets/office.png`：本次通过内置 ImageGen 生成的办公室人物素材；提示词见 `assets/office-prompt.txt`。
- `out/<variant>/doneat-<variant>-zh-60fps-music.mp4`：完整配乐版。
- `out/<variant>/doneat-<variant>-zh-60fps.mp4`：纯音效版，便于在平台另选音乐。

原版 `../scene.html`、`../render.mjs`、`../audio.mjs` 和 `../out/` 均保留原样。新片通过本地 iframe 复用原版的设备框、UI、滚动数字及图标；没有改动 App 代码或重新启动 iOS 模拟器。办公室采用生成的静态场景，加镜头剪辑和小幅推近，人物本身没有逐帧表演动画。

## 生成

需要本机 Google Chrome、ffmpeg 和支持 WebSocket 的 Node.js（项目推荐 Node 24）。不增加 npm 依赖。

运行 `node scripts/marketing-shots/promo-video/tiktok-v2/preview.mjs`，打开输出的本机地址即可对比播放。普通不支持 HTTP Range 的静态服务器可能使 WebKit 视频停在首帧。

```sh
node scripts/marketing-shots/promo-video/tiktok-v2/render.mjs --variant progress
node scripts/marketing-shots/promo-video/tiktok-v2/render.mjs --variant office
node scripts/marketing-shots/promo-video/tiktok-v2/render.mjs --variant woodfish
```

`FPS=30` 可输出 30 fps；`WORKERS=4` 控制并发。三个版本依次渲染，避免复用同一组 Chrome 调试端口。`index.html` 默认链接 60 fps 版本。

```sh
node scripts/marketing-shots/promo-video/tiktok-v2/render.mjs --variant office --stills 0,0.9,1.3,2.2,18.5
node scripts/marketing-shots/promo-video/tiktok-v2/render.mjs --variant office --check
```

`--check` 检查每个剪辑切点能否渲染，以及标题、辅助文案、品牌与 CTA 的范围。网页预览尊重减少动态效果偏好；正常视频输出保留镜头与庆祝动作。

## TikTok 构图与实验

保留 9:16；主信息使用 x=64–920、y=190–1500 的保守编辑区域，预留右侧交互区和底部说明区。这是本片采用的构图范围，并非对所有广告样式统一适用的官方像素模板。投放前用具体广告格式的预览复核，尤其是长说明和附加卡片。

参考：[TikTok 创意指南](https://ads.tiktok.com/resources/help/article/creative-best-practices?lang=en)、[In-Feed 视频规格与安全区](https://ads.tiktok.com/resources/help/article/tiktok-auction-in-feed-ads?lang=en)（2026-09-28 查阅）。

比较时保持主体、CTA、受众和投放条件接近，统一三秒留存的分母，同时看六秒留存、完播和下载点击。纯音效版若另配平台音乐，应给三个版本使用同一首、同一音量。先比较开头，再单独测试配乐或文案，避免一次改变太多变量。

## 原版校验值

保留这些 SHA-256，便于确认原脚本和成片没有被本次工作覆盖：

```text
c737fad185a7eea10989d5ce878ed3538da53297b132df76dc61382440243a13  ../scene.html
11a4df91d9d9190bd12f24a07098d0871f56f8be2a2a57601877b1ad1f76f060  ../render.mjs
879aac6696e92ac72c36dbf2ca8b9a2117d79475aa12845615d1ee62ba24f125  ../audio.mjs
091133669fbb7000d317e6c8b4685397ba7d2a3537e2a7781c906ac430db33f1  ../out/doneat-promo-60fps-music.mp4
66e56da1bf7d8774844bfde4a5d9cac2b62741b30c299a0b145c393aa3b8d58a  ../out/doneat-promo-60fps.mp4
```
