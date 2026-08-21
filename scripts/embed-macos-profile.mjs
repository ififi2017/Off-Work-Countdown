import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

// 把 provisioning profile 嵌进已打好的 .app，然后重签外层。
//
// 为什么需要这一步：沙盒应用的 `com.apple.security.application-groups` 属于需要
// 授权的 entitlement——开发阶段由 embedded.provisionprofile 背书，上架后由商店背书。
// 两者都没有时 containermanagerd 会拒绝，`containerURLForSecurityApplicationGroupIdentifier`
// 返回 nil，小组件读不到任何数据。而 Tauri 的 bundle.macOS 配置里**没有**嵌入
// 描述文件的能力（MacConfig 只有 entitlements / signingIdentity 等键），所以只能
// 在打包之后自己补。
//
// 往已签名的 bundle 里加文件会破坏封签，因此必须重签。
const PROFILE_NAME = "embedded.provisionprofile";

/** `.app` 里嵌套的扩展。它们各自签名，外层通过并不代表它们也通过。 */
function pluginBundles(appBundle) {
  const dir = join(appBundle, "Contents/PlugIns");
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((name) => name.endsWith(".appex"))
    .map((name) => join(dir, name));
}
const XCODE_PROFILES = join(
  homedir(),
  "Library/Developer/Xcode/UserData/Provisioning Profiles"
);

const appPath = process.argv[2] ?? defaultAppPath();
const identity = process.env.APPLE_SIGNING_IDENTITY ?? "";

/**
 * 定位刚打好的 .app。
 *
 * 不能写死 `target/release/`：带 `--target` 构建时（Universal 走
 * `--target universal-apple-darwin`）产物在 `target/<triple>/release/` 下，写死会
 * 让这一步安静地跳过——而"跳过"的表现是包里没有描述文件，直到真机上小组件读不到
 * 数据才暴露。
 */
function defaultAppPath() {
  const config = JSON.parse(
    readFileSync("src-tauri/tauri.conf.json", "utf8")
  );
  const name = `${config.productName}.app`;
  const roots = [
    resolve("src-tauri/target/release/bundle/macos"),
    ...(existsSync(resolve("src-tauri/target"))
      ? readdirSync(resolve("src-tauri/target"), { withFileTypes: true })
          .filter((entry) => entry.isDirectory() && entry.name.includes("-apple-darwin"))
          .map((entry) =>
            resolve(`src-tauri/target/${entry.name}/release/bundle/macos`)
          )
      : []),
  ];
  const found = roots
    .map((root) => join(root, name))
    .filter((path) => existsSync(path))
    .sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
  if (found.length === 0) {
    throw new Error(
      `No ${name} found under src-tauri/target/*/release/bundle/macos. ` +
        `Pass the path explicitly if you built somewhere else.`
    );
  }
  return found[0];
}

// ad-hoc / 未签名的本地构建照常跳过：它们只用来验证包结构，本来就拿不到 App Group。
if (!identity || identity === "-") {
  console.log(
    "APPLE_SIGNING_IDENTITY is unset or ad-hoc; skipping provisioning profile embedding."
  );
  process.exit(0);
}

if (!existsSync(appPath)) {
  console.error(`App bundle not found: ${appPath}`);
  process.exit(1);
}

/**
 * 读出 profile 里的 application-identifier，用来确认它属于这个 App ID。
 *
 * 只用 `plutil -extract` 取这一个键，不整份转 JSON：profile 里的
 * DeveloperCertificates 是二进制 NSData，转 JSON 会直接报
 * "Invalid object in plist for JSON format"。键名本身含点号，所以路径要转义。
 */
function profileAppId(path) {
  try {
    const xml = execFileSync("security", ["cms", "-D", "-i", path], {
      encoding: "utf8",
      maxBuffer: 8 * 1024 * 1024,
    });
    return execFileSync(
      "plutil",
      ["-extract", String.raw`Entitlements.com\.apple\.application-identifier`, "raw", "-o", "-", "-"],
      { input: xml, encoding: "utf8" }
    ).trim();
  } catch {
    return null;
  }
}

const bundleId = execFileSync(
  "plutil",
  ["-extract", "CFBundleIdentifier", "raw", "-o", "-", join(appPath, "Contents/Info.plist")],
  { encoding: "utf8" }
).trim();
const teamId = process.env.OWC_APPLE_TEAM_ID ?? "";
const wanted = teamId ? `${teamId}.${bundleId}` : null;

let profile = process.env.OWC_MACOS_PROVISION_PROFILE ?? null;
if (!profile) {
  // 自动发现：在 Xcode 的目录里找 application-identifier 匹配这个 App ID 的那一份。
  const candidates = existsSync(XCODE_PROFILES)
    ? readdirSync(XCODE_PROFILES)
        .filter((name) => name.endsWith(".provisionprofile"))
        .map((name) => join(XCODE_PROFILES, name))
        .filter((path) => {
          const appId = profileAppId(path);
          return appId && (wanted ? appId === wanted : appId.endsWith(`.${bundleId}`));
        })
    : [];
  if (candidates.length === 0) {
    console.error(
      `No provisioning profile found for ${bundleId}.\n` +
        `Install one into ${XCODE_PROFILES} (double-click the downloaded file), ` +
        `or set OWC_MACOS_PROVISION_PROFILE to its path.`
    );
    process.exit(1);
  }
  profile = candidates[0];
}

copyFileSync(profile, join(appPath, "Contents", PROFILE_NAME));

// ⚠️ 不能加 --deep：那会连内嵌的 .appex 一起重签，把它自己那份正确的签名和
// 描述文件覆盖掉。只重签外层，嵌套 bundle 的签名会被原样封进去。
const entitlements = resolve("src-tauri/target/macos-widget/Host.entitlements");
if (!existsSync(entitlements)) {
  console.error(`Host entitlements not found: ${entitlements}`);
  process.exit(1);
}
execFileSync(
  "codesign",
  ["--force", "--sign", identity, "--entitlements", entitlements, "--options", "runtime", appPath],
  { stdio: "inherit" }
);
execFileSync("codesign", ["--verify", "--deep", "--strict", appPath], { stdio: "inherit" });

// ⚠️ 最容易踩、也最难查的一类错误：App Group 声明得没问题、签名没问题，但描述
// 文件根本没授权那个 group。表现极其隐蔽——宿主如果被用户在 TCC 弹窗上点了
// 「允许」就照样能写，而**扩展没有弹窗的能力**，只会静默拿不到容器，小组件永远
// 空态，日志里也查不到拒绝记录。排查过一整轮才定位到。
//
// 根因是两种形式不通用：Mac Development 描述文件授权的是 `<TeamID>.*`，因此
// App Group 必须写成 `<TeamID>.group.…`；不带前缀的 `group.…` 只在 Mac App Store
// 分发时有效。同一个标识符不能两边通用。
const declaredGroups = [
  ...execFileSync("codesign", ["-d", "--entitlements", "-", appPath], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).matchAll(/\[String\]\s+(\S*group\S*)/g),
].map((match) => match[1]);

const allowedGroups = (() => {
  const xml = execFileSync("security", ["cms", "-D", "-i", profile], {
    encoding: "utf8",
    maxBuffer: 8 * 1024 * 1024,
  });
  try {
    return [
      ...execFileSync(
        "plutil",
        ["-extract", String.raw`Entitlements.com\.apple\.security\.application-groups`, "xml1", "-o", "-", "-"],
        { input: xml, encoding: "utf8" }
      ).matchAll(/<string>([^<]*)<\/string>/g),
    ].map((match) => match[1]);
  } catch {
    return [];
  }
})();

const authorizes = (group) =>
  allowedGroups.some((pattern) =>
    pattern.endsWith("*") ? group.startsWith(pattern.slice(0, -1)) : pattern === group
  );

const unauthorized = declaredGroups.filter((group) => !authorizes(group));
if (unauthorized.length > 0) {
  console.error(
    `The embedded provisioning profile does not authorize these App Groups: ${unauthorized.join(", ")}\n` +
      `  profile allows: ${allowedGroups.join(", ") || "(none)"}\n` +
      `  A Mac Development profile allows "<TeamID>.*", so set\n` +
      `  OWC_APP_GROUP_IDENTIFIER=${process.env.OWC_APPLE_TEAM_ID ?? "<TeamID>"}.group.<name> and rebuild.\n` +
      `  Without this the host may still write (if the user grants the TCC prompt) while the\n` +
      `  widget extension is silently denied and shows an empty state forever.`
  );
  process.exit(1);
}
console.log(`Provisioning profile authorizes ${declaredGroups.join(", ")}`);

// 分发构建绝不能带 `get-task-allow`（允许调试器附加，是**开发**签名的标志）。
// 带着它提交会被 Apple 直接拒，而拒信要等上传之后才收到。宿主用的是我们自己的
// entitlements 文件所以本来就没有，但嵌套的 .appex 由 Xcode 签，开发签名会自动
// 加上——因此这里连嵌套 bundle 一起查，而不只查外层。
if (process.env.OWC_WIDGET_SIGNING_MODE === "distribution") {
  const carriers = [appPath, ...pluginBundles(appPath)].filter((bundle) => {
    const entitlements = execFileSync("codesign", ["-d", "--entitlements", "-", bundle], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    return entitlements.includes("get-task-allow");
  });
  if (carriers.length > 0) {
    console.error(
      `These bundles still carry get-task-allow and would be rejected by App Review:\n` +
        carriers.map((bundle) => `  ${bundle}`).join("\n")
    );
    process.exit(1);
  }
  console.log("No bundle carries get-task-allow.");

  // 90886：宿主的**签名**里必须有 application-identifier，且与描述文件一致。
  // Xcode 签嵌套 .appex 时会自动从描述文件补这个键，而宿主是 Tauri 用我们手写的
  // entitlements 文件签的，没人替它补——缺了要等上传后才收到拒信。
  const profileAppIdentifier = execFileSync(
    "plutil",
    ["-extract", String.raw`Entitlements.com\.apple\.application-identifier`, "raw", "-o", "-", "-"],
    {
      input: execFileSync("security", ["cms", "-D", "-i", profile], {
        encoding: "utf8",
        maxBuffer: 8 * 1024 * 1024,
      }),
      encoding: "utf8",
    }
  ).trim();
  const signedAppIdentifier = (
    execFileSync("codesign", ["-d", "--entitlements", "-", appPath], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).match(/application-identifier<\/key>\s*<string>([^<]*)/) ??
    execFileSync("codesign", ["-d", "--entitlements", "-", appPath], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).match(/application-identifier[\s\S]{0,80}?\[String\]\s+(\S+)/)
  )?.[1];
  if (signedAppIdentifier !== profileAppIdentifier) {
    console.error(
      `Signed application-identifier does not match the provisioning profile:\n` +
        `  signed:  ${signedAppIdentifier ?? "(missing)"}\n` +
        `  profile: ${profileAppIdentifier}\n` +
        `  App Store upload rejects this with error 90886.`
    );
    process.exit(1);
  }

  // 90473：扩展的 CFBundleVersion 必须与宿主一致。
  const bundleVersion = (bundle) =>
    execFileSync(
      "plutil",
      ["-extract", "CFBundleVersion", "raw", "-o", "-", join(bundle, "Contents/Info.plist")],
      { encoding: "utf8" }
    ).trim();
  const hostVersion = bundleVersion(appPath);
  const mismatched = pluginBundles(appPath).filter(
    (bundle) => bundleVersion(bundle) !== hostVersion
  );
  if (mismatched.length > 0) {
    console.error(
      `CFBundleVersion mismatch (host is ${hostVersion}); App Store upload rejects this with 90473:\n` +
        mismatched
          .map((bundle) => `  ${bundle} = ${bundleVersion(bundle)}`)
          .join("\n")
    );
    process.exit(1);
  }
  console.log(
    `application-identifier and CFBundleVersion (${hostVersion}) match across bundles.`
  );
}

console.log(`Embedded ${profile}`);
console.log(`Re-signed ${appPath}`);
