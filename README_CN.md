# 下班倒计时

下班倒计时是一个基于Next.js的网页应用,帮助您跟踪工作日结束前的剩余时间。通过简洁互动的界面,该应用提供可视化的倒计时和进度条,让您的工作日更易管理。

![](readme_image/off_CN.JPEG)

## 功能特点

- 设置自定义工作开始和结束时间
- 实时倒计时显示
- 可视化进度条
- 可选的下班前15分钟提醒
- 动画渐变背景选项
- 支持离线使用的渐进式Web应用(PWA)
- 适应各种设备的响应式设计
- 多语言支持(i18n)

## 使用的技术

- Next.js 14 (App Router)
- React
- TypeScript
- Tailwind CSS
- Framer Motion
- next-pwa
- i18next

## 开始使用

1. 克隆仓库:
```bash
git clone https://github.com/ififi2017/Off-Work-Countdown.git
```

2. 安装依赖:
```bash
cd Off-Work-Countdown
npm install
```

3. 配置环境:
```bash
# 创建 .env.local 文件
cp .env.example .env.local

# 编辑 .env.local 并设置您的基础 URL
NEXT_PUBLIC_BASE_URL=http://localhost:3000
```

4. 运行开发服务器:
```bash
npm run dev
```

5. 在浏览器中打开 [http://localhost:3000](http://localhost:3000) 查看结果。

## 配置说明

### 站点配置

站点配置集中在 `config/site.ts` 文件中：

```typescript
export const siteConfig = {
  name: "Off Work Countdown",
  baseUrl: process.env.NEXT_PUBLIC_BASE_URL || 'https://off.rainif.com',
  github: "https://github.com/ififi2017/Off-Work-Countdown",
  themeColor: "#F3F4F6",
} as const;
```

### i18n 配置

语言配置管理在 `i18n-config.ts` 文件中：

```typescript
export const defaultLocale = 'en'
export const locales = ['en', 'zh-CN', 'zh-TW', ...] as const

// 语言代码映射
export const languageMapping = {
  'zh': 'zh-CN',
  'zh-Hans': 'zh-CN',
  // ... 更多映射
}

// 语言显示名称
export const languageNames = {
  'en': 'English',
  'zh-CN': '简体中文',
  // ... 更多名称
}
```

## 使用说明

1. 使用下拉菜单设置您的工作开始和结束时间。
2. 如果您想在下班前15分钟收到通知,请打开提醒开关。
3. 如果需要,启用动画渐变背景。
4. 点击"开始倒计时"开始跟踪您的工作日。
5. 应用将显示剩余时间和进度条。
6. 您可以随时点击"返回"按钮回到设置界面。
7. 使用语言选择器切换可用语言。

## PWA支持

本应用支持渐进式Web应用功能,允许您在设备上安装并离线使用。安装步骤:

1. 在支持的浏览器中打开应用(如Chrome、Edge)。
2. 在地址栏或菜单中查找安装提示。
3. 按照提示在您的设备上安装应用。

## 贡献

欢迎贡献!请随时提交Pull Request。

### 添加语言支持

我们希望扩展应用的语言支持。如果您想贡献翻译:

1. Fork仓库并为您的语言创建一个新分支。
2. 在 `i18n-config.ts` 的 `locales` 数组中添加您的语言代码。
3. 如果需要，添加语言映射和显示名称。
4. 在 `public/locales/[lang]/` 中创建翻译文件：
   - `translation.json` - 用于UI字符串
   - `seo.json` - 用于SEO元数据
5. 使用新语言彻底测试应用。
6. 提交包含您更改的pull request。

## 许可证

本项目是开源的,遵循[MIT许可证](LICENSE)。

## 致谢

特别感谢:
- [@v0.dev](https://v0.dev/) 提供AI辅助的组件设计
- [@cursor.com](https://www.cursor.com/) 提供AI驱动的编码辅助
- [@claude.ai](https://claude.ai/chats) 和 [@chatgpt.com](https://chatgpt.com/) 在开发过程中提供大型语言模型支持
- [@vercel.com](https://vercel.com/) 提供托管和部署服务