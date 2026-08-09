import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const result = spawnSync(
  process.execPath,
  [resolve("node_modules/next/dist/bin/next"), "build"],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      BUILD_TARGET: "desktop",
    },
  }
);

if (result.error) throw result.error;
process.exit(result.status ?? 1);
