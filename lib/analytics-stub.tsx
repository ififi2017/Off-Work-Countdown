// 桌面构建下替换 @vercel/analytics 与 @vercel/speed-insights 的空实现。
//
// 仅靠「构建期常量 + 条件渲染」不够：分支虽是死代码不会执行，模块本身仍会被
// 打进产物。对一个宣称「数据不出本机」的桌面应用来说，包里存在第三方埋点代码
// 本身就是问题——审计的人不会去逐行确认它没被调用。
//
// 因此在 next.config.mjs 里用 resolve.alias 把这两个模块整体换掉，
// 让它们压根不进入桌面产物。

export function Analytics() {
  return null;
}

export function SpeedInsights() {
  return null;
}

/**
 * ShareDialog 从裸包名 `@vercel/analytics` 引入的 `track`。
 *
 * Web 端的分享漏斗埋点在桌面端没有意义（静态导出里没有对应端点），桌面构建把整个
 * 模块换成这份空实现，产物里因此不含任何第三方埋点代码。
 */
export function track(..._args: unknown[]): void {}
