// One task-owned WebKit context. Exercise the isolated checkout, never the service.
const path = require("node:path");
const os = require("node:os");
const assert = require("node:assert/strict");
const { mkdir, mkdtemp } = require("node:fs/promises");

const failures = {board: 10, inspector: 11, composer: 12, settings: 13};
let screen = "board";

async function review(browser, url, blockedId) {
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

      await page.goto(url + "&panel=conversation&task=" + blockedId);
      await page.locator(".phx-connected").first().waitFor();
      const body = page.locator("#inspector-panel-conversa");
      const block = body.locator("#unblock-panel");
      const reply = page.locator("#ask-body");
      const preflight = page.locator(".ab-insp__checks");
      const details = page.locator(".ab-insp__details");
      await block.getByText(/Preciso da sua decisão/).waitFor();
      assert.match(await preflight.locator("summary").innerText(), /mix test · Falhou/);
      assert.equal(await preflight.getAttribute("open"), null);
      const readingArea = async (viewportHeight = height) => {
        const area = await body.boundingBox();
        const field = await reply.boundingBox();
        assert.ok(area.height >= viewportHeight / 3, "Conversation lost its reading area: " + area.height);
        assert.ok(field.y >= area.y + area.height - 1 && field.y + field.height <= viewportHeight, "Reply clipped");
      };
      await readingArea();
      const quote = await block.locator(".ab-unblock__quote p").boundingBox();
      const panel = await body.boundingBox();
      assert.ok(quote.y >= panel.y && quote.y + quote.height <= panel.y + panel.height, "Decision not visible on open");
      await capture("blocked-inspector");
      const [shortWidth, shortHeight] = width === 375 ? [443, 828] : [1280, 720];
      await page.setViewportSize({width: shortWidth, height: shortHeight});
      await readingArea(shortHeight);
      const resized = await body.boundingBox();
      console.log("Blocked inspector reading area:", shortWidth, "×", shortHeight, Math.round(resized.height), "px");
      await page.screenshot({ path: path.join(evidence, shortWidth + "-blocked-inspector.png") });
      await page.setViewportSize({width, height});
      await preflight.locator("summary").press("Enter");
      await preflight.getByText("mix format --check-formatted").waitFor();
      await readingArea();
      await reply.fill("Rascunho local");
      await details.locator("summary").click();
      await details.getByText("Arquivar", {exact:true}).waitFor();
      await block.locator("#open-blocker").click();
      await block.locator("form").waitFor();
      assert.notEqual(await preflight.getAttribute("open"), null, "Update closed checks");
      assert.equal(await reply.inputValue(), "Rascunho local");
      await readingArea();
      await page.locator("#inspector-tab-atividade").click();
      await page.locator("#inspector-panel-atividade").waitFor();
      await page.locator("#inspector-tab-conversa").click();
      await reply.waitFor();

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
      const search = page.locator("#project-directory-query");
      const count = page.locator("#project-directory-filter [role=status]");
      assert.equal(await count.count(), 0);
      await search.fill("no-such-fixture");
      await count.filter({hasText: /^0 \/ /}).waitFor();
      await search.fill("ui-fixture");
      await count.filter({hasText: /^1 \/ /}).waitFor();
      await page.locator(".ab-project--tracked").filter({hasText: "sample/"}).first().waitFor({state:"hidden"});
      const project = page.locator(".ab-project--tracked").filter({hasText: "ui-fixture/"});
      await project.getByRole("button", {name: /ui-fixture\//, expanded: false}).click();
      const checks = project.locator("section[id$='-stages']");
      const edit = checks.getByRole("button", {name: "Editar etapas"});
      await edit.waitFor();
      assert.match(await checks.locator(".ab-quality__summary").innerText(), /1 etapa em toda tarefa · 2 etapas por alteração/);
      assert.equal(await checks.locator("select").count(), 0);
      const merge = project.locator(".ab-merge-body");
      assert.ok((await merge.boundingBox()).y < (await checks.boundingBox()).y);
      await capture("project-summary");
      await edit.press("Enter");
      await checks.locator("select[name=stack]").waitFor();
      assert.equal(await checks.locator("select[name=stack]").inputValue(), "JavaScript / TypeScript");
      const example = checks.locator("select[name='rules[npm-test]']");
      assert.equal(await example.inputValue(), "always");
      assert.equal(await checks.locator("select[name='rules[npm-lint]']").inputValue(), "changed");
      await example.selectOption("off");
      assert.equal(await example.inputValue(), "off");
      await checks.getByRole("button", {name:"Fechar editor"}).click();
      await edit.press("Enter");
      await example.waitFor();
      assert.equal(await example.inputValue(), "always");
      await checks.scrollIntoViewIfNeeded();
      await capture("project-stages");

      await search.fill("sample/project-17");
      const undetected = page.locator(".ab-project--tracked").filter({hasText: "sample/project-17"});
      await undetected.getByRole("button", {name: /sample\/project-17/, expanded: false}).click();
      const editor = undetected.locator("section[id$='-stages']");
      const picker = editor.getByLabel("Tecnologia", {exact: true});
      await editor.getByRole("button", {name:"Escolher tecnologia"}).click();
      await picker.waitFor();
      assert.equal(await picker.inputValue(), "");
      assert.equal((await picker.locator("option:checked").textContent()).trim(), "Tecnologia ainda não detectada");
      assert.equal(await editor.locator("form[id$='-stage-form']").count(), 0);
      await editor.scrollIntoViewIfNeeded();
      await capture("technology-undetected");
      await picker.selectOption("Rust");
      await editor.getByText("cargo test --locked", {exact: true}).waitFor();
      assert.equal(await picker.inputValue(), "Rust");
      await capture("technology-chosen");
      await search.fill(" ");
      await count.waitFor({state:"detached"});
      await search.fill("");
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
    await review(browser, process.argv[2], process.argv[3]);
    console.log("WebKit passed: board, inspector, composer and settings at 1440 and 375 px.");
  } finally {
    await browser.close();
  }
})().catch(e => { console.error(e.message); process.exitCode = failures[screen]; });
