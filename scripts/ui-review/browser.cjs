// One task-owned WebKit context. Exercise the isolated checkout, never the service.
const path = require("node:path");
const os = require("node:os");
const assert = require("node:assert/strict");
const { mkdir, mkdtemp } = require("node:fs/promises");

const failures = {board: 10, inspector: 11, composer: 12, settings: 13};
let screen = "board";

async function review(browser, url) {
  const ctx = await browser.newContext({ reducedMotion: "reduce" });
  try {
    const page = await ctx.newPage();
    page.setDefaultTimeout(8000);
    const errors = [];
    page.on("pageerror", e => errors.push(e.message));
    page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
    const origin = new URL(url).origin;
    await ctx.addCookies([{ name: "board_locale", value: "pt-BR", url: origin }]);
    await ctx.route("**/*", route => new URL(route.request().url()).origin === origin
      ? route.continue() : route.abort());
    await mkdir("tmp/ui-review", { recursive: true });
    const evidence = await mkdtemp("tmp/ui-review/run-");
    console.log("Browser evidence:", evidence);
    for (const [width, height] of [[1440, 900], [375, 812]]) {
      const capture = async screen => {
        assert.ok(await page.locator(".phx-connected").count(), "LiveView disconnected");
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1),
          screen + ": horizontal overflow");
        assert.deepEqual(errors, [], "Browser errors: " + errors.join("; "));
        await page.screenshot({ path: path.join(evidence, width + "-" + screen + ".png") });
      };
      await page.setViewportSize({ width, height });
      await page.emulateMedia({ colorScheme: width === 375 ? "dark" : "light" });
      screen = "board";
      await page.goto(url);
      await page.locator(".phx-connected").first().waitFor();
      const task = page.locator('#sec-now [phx-click="open"]').filter({ hasText: "Review fixture task" });
      await capture("board");
      screen = "inspector";
      await task.focus();
      await page.keyboard.press("Enter");
      await page.locator("#conversation-title").getByText("Review fixture task", {exact: true}).waitFor();
      await capture("inspector");
      await page.locator('#conversation button[phx-click="close"]').press("Enter");
      await page.locator("#conversation").waitFor({ state: "hidden" });

      screen = "composer";
      await page.goto(url + "&panel=composer");
      const input = page.locator("#composer-text");
      await input.fill("Review fixture: check the keyboard interaction");
      assert.match(await input.inputValue(), /keyboard interaction/);
      await capture("composer");

      screen = "settings";
      await page.goto(url + "&panel=settings&section=system");
      await page.locator("#settings-system-title").waitFor();
      await capture("settings");

      await page.goto(url + "&panel=settings&section=projects");
      const project = page.locator(".ab-project--tracked").filter({hasText: "ui-fixture/"});
      await project.getByRole("button", {name: /ui-fixture\//, expanded: false}).click();
      const checks = project.locator("details[id$='-stages']");
      await checks.locator("summary").click();
      const example = checks.locator("input[value='npm-test']");
      await example.check();
      assert.ok(await example.isChecked());
      await capture("project-stages");
      await example.uncheck();
    }
    assert.deepEqual(errors, [], "Browser console or page errors: " + errors.join("; "));
  } finally {
    await ctx.close();
  }
}

(async () => {
  let browser;
  try {
    const modulePath = process.env.SUPERBOARD_PLAYWRIGHT || require.resolve("playwright", {
      paths: [__dirname, path.join(os.homedir(), ".local/share/agent-tools/playwright-mcp")]
    });
    browser = await require(modulePath).webkit.launch({ headless: true });
  } catch (e) {
    console.error("WebKit unavailable:", e.message);
    process.exitCode = 2;
    return;
  }
  try {
    await review(browser, process.argv[2]);
    console.log("WebKit passed: board, inspector, composer and settings at 1440 and 375 px.");
  } finally {
    await browser.close();
  }
})().catch(e => { console.error(e.message); process.exitCode = failures[screen]; });
