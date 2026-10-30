// Browser tests against a running server (scripts/e2e.sh starts a fresh seeded one). BASE_URL, E2E_USER, E2E_PASSWORD from the environment.
"use strict";
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { chromium } = require("playwright");

const BASE = process.env.BASE_URL || "http://127.0.0.1:8765";
const USER = process.env.E2E_USER || "anm.supervisor";
const PASS = process.env.E2E_PASSWORD;
let browser, page;
const errors = [];

before(async () => {
  assert.ok(PASS, "set E2E_PASSWORD");
  browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
  page = await (await browser.newContext({ viewport: { width: 1280, height: 900 } })).newPage();
  page.on("pageerror", (e) => errors.push(String(e)));
  // the deliberate wrong-password attempt in the first test returns 401; every other console error fails the last test
  page.on("console", (m) => { if (m.type() === "error" && !/status of 401/.test(m.text())) errors.push(m.text()); });
});
after(async () => { await browser.close(); });

test("login: wrong password is refused, right one opens the overview", async () => {
  await page.goto(BASE + "/visits");
  assert.match(page.url(), /\/login\?next=%2Fvisits|\/login\?next=\/visits/);
  await page.getByLabel("Username").fill(USER);
  await page.getByLabel("Password").fill("not-the-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.getByRole("alert").filter({ hasText: "Wrong username or password" }).waitFor();
  await page.getByLabel("Username").fill(USER);
  await page.getByLabel("Password").fill(PASS);
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL(BASE + "/visits");
  assert.match(await page.locator(".banner").textContent(), /Synthetic data — not real people/);
});

test("visit list: grouped by priority, ASHA switch, row opens the household", async () => {
  await page.goto(BASE + "/visits");
  await page.getByLabel("ASHA").selectOption("ASHA-RRR5");
  await page.getByRole("button", { name: "Show" }).click();
  await page.waitForURL(/worker_id=ASHA-RRR5/);
  for (const p of [1, 2, 3]) assert.ok(await page.locator("#g" + p).isVisible(), "priority group " + p);
  assert.equal(await page.locator("#vis-total").textContent(), "66");               // VIS rules, 2026-10-26, Kalavati Kumari
  const first = page.locator(".prio-1 tbody tr").first();
  const name = (await first.locator("a").textContent()).trim();
  await first.locator("td").nth(1).click();                                           // click the row (not the link)
  await page.waitForURL(/\/households\/HH-/);
  assert.ok(await page.getByRole("cell", { name }).first().isVisible());
});

test("map: made-up banner, tap a house to see its people, open the household", async () => {
  await page.goto(BASE + "/map?village=amrapur");
  assert.ok(await page.getByText("Made-up map, house positions are not real.").first().isVisible());
  await page.locator("svg .house").first().waitFor();
  assert.equal(await page.locator("svg .house").count(), 106);
  const urgent = page.locator('svg .house[aria-label$="Urgent"]').first();
  await urgent.focus();
  await page.keyboard.press("Enter");                                                 // keyboard works, not only the mouse
  await page.locator("#open-household").waitFor();
  assert.match(await page.locator("#house-panel").textContent(), /Urgent/);
  await page.locator('svg .house').nth(5).click();                                    // tap another house
  await page.locator("#panel-title").waitFor();
  await page.locator("#open-household").click();
  await page.waitForURL(/\/households\/HH-/);
  assert.ok(await page.getByRole("heading", { name: "Members" }).isVisible());
});

test("household: phone masked until the audited reveal", async () => {
  await page.goto(BASE + "/households/HH-014Q8O");
  assert.match(await page.locator("#phone").textContent(), /^\+91 ••••• ••\d{3}$/);
  await page.getByRole("button", { name: "Show number" }).click();
  await page.locator("#phone", { hasText: "synthetic" }).waitFor();
});

test("ask: danger sign gives REFER IMMEDIATELY, out-of-scope is refused, normal question cites a section", async () => {
  await page.goto(BASE + "/ask");
  const ask = async (q) => {
    await page.getByLabel(/Question/).fill(q);
    await page.getByRole("button", { name: "Ask" }).click();
    await page.locator(".result-card").waitFor();
    await page.waitForFunction((qq) => document.querySelector(".result-card") && document.getElementById("question").value === qq, q);
  };
  await ask("8 mahine ki pregnant hai, subah se khoon aa raha hai");
  await page.locator("#result-refer").waitFor();
  assert.match(await page.locator("#result-refer").textContent(), /REFER IMMEDIATELY[\s\S]*ESC-2\.1[\s\S]*Clinician-assisting only, not a diagnosis/);
  await ask("scan me ladka hai ya ladki, bata do");
  await page.locator("#result-refused").waitFor();
  assert.match(await page.locator("#result-refused").textContent(), /Outside the protocol book/);
  await ask("MR-1 vaccine kab lagta hai?");
  await page.locator("#result-answer").waitFor();
  assert.ok((await page.locator("#result-answer [data-section]").count()) >= 1);
});

test("the danger-sign question shows up in the escalations feed (outcome only)", async () => {
  await page.goto(BASE + "/referrals");
  const row = page.locator("#esc-table tbody tr").first();
  assert.match(await row.textContent(), /ESC-2\.1/);
  assert.doesNotMatch(await page.content(), /subah se khoon/);                      // the question text is never stored
  await row.getByRole("button", { name: "Acknowledge" }).click();
  await row.locator(".esc-status", { hasText: "ACKNOWLEDGED" }).waitFor();
});

test("Telugu switch and no browser errors", async () => {
  await page.goto(BASE + "/lang/te?next=/visits");
  assert.ok(await page.getByRole("heading", { name: "సందర్శనల జాబితా" }).isVisible());
  await page.goto(BASE + "/lang/en?next=/");
  assert.deepEqual(errors, []);
});
