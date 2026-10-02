// The existing Next.js static-file sender supports byte ranges for WebKit video seeking.
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";
import send from "next/dist/compiled/send/index.js";

const root = fileURLToPath(new URL("../", import.meta.url));
createServer((request, response) => {
  response.setHeader("Cache-Control", "no-store");
  const path = new URL(request.url, "http://127.0.0.1").pathname;
  send(request, path, { root, cacheControl: false }).on("error", error => {
    response.statusCode = error.statusCode || 500;
    response.end("Preview file unavailable");
  }).pipe(response);
}).listen(8765, "127.0.0.1", () => {
  console.log("http://127.0.0.1:8765/tiktok-v2/index.html");
});
