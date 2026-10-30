// Render index.html frame by frame with headless Chromium (Playwright) and
// pipe PNG frames into ffmpeg. Usage:
//   node render.js preview 3.2 15 61.5      -> build/preview/t_XXX.png
//   node render.js video [workers]          -> build/video.mp4 (silent) + build/sfx.json
const { chromium } = require("playwright");
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

const FPS = 30, DUR = 180, W = 1920, H = 1080;
const BUILD = path.join(__dirname, "build");
const cues = JSON.parse(fs.readFileSync(path.join(BUILD, "cues.json"), "utf8"));

async function openPage(browser) {
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  await page.goto("file://" + path.join(__dirname, "index.html"));
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate((c) => window.init(c), cues);
  return page;
}

async function preview(times) {
  const browser = await chromium.launch();
  const page = await openPage(browser);
  fs.mkdirSync(path.join(BUILD, "preview"), { recursive: true });
  for (const t of times) {
    await page.evaluate((t) => window.render(t), t);
    await page.screenshot({ path: path.join(BUILD, "preview", `t_${String(t).padStart(6, "0")}.png`) });
  }
  await browser.close();
}

async function segment(browser, f0, f1, out) {
  const page = await openPage(browser);
  const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "png", "-i", "-",
    "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", "-r", String(FPS), out], { stdio: ["pipe", "inherit", "inherit"] });
  for (let f = f0; f < f1; f++) {
    await page.evaluate((t) => window.render(t), f / FPS);
    const buf = await page.screenshot({ type: "png" });
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
    if ((f - f0) % 300 === 0) console.log(`${path.basename(out)}: frame ${f}/${f1}`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("close", r));
  await page.close();
}

async function video(workers) {
  const browser = await chromium.launch();
  const p = await openPage(browser);
  fs.writeFileSync(path.join(BUILD, "sfx.json"), JSON.stringify(await p.evaluate(() => window.SFX), null, 1));
  await p.close();
  const total = FPS * DUR, per = Math.ceil(total / workers), segs = [];
  const jobs = [];
  for (let i = 0; i < workers; i++) {
    const out = path.join(BUILD, `seg${i}.mp4`);
    segs.push(out);
    jobs.push(segment(browser, i * per, Math.min(total, (i + 1) * per), out));
  }
  await Promise.all(jobs);
  await browser.close();
  fs.writeFileSync(path.join(BUILD, "segs.txt"), segs.map((s) => `file '${s}'`).join("\n"));
  await new Promise((r) => spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", path.join(BUILD, "segs.txt"), "-c", "copy", path.join(BUILD, "video.mp4")], { stdio: "inherit" }).on("close", r));
  console.log("wrote build/video.mp4");
}

const [mode, ...args] = process.argv.slice(2);
if (mode === "preview") preview(args.map(Number));
else video(parseInt(args[0] || "4"));
