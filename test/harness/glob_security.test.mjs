import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";

let directory;
let matcherPath;

before(() => {
  const lock = JSON.parse(readFileSync(new URL("../../priv/agent/harness/package-lock.json", import.meta.url)));
  const entry = lock.packages["node_modules/@deepseek-ai/dsh-hmr/node_modules/picomatch"] ??
    lock.packages["node_modules/picomatch"];
  assert.ok(entry, "the Harness glob matcher must be locked");
  assert.equal(entry.dependencies, undefined, "the isolated fixture must include every matcher dependency");

  // Install the exact artifact and integrity used by HMR, without installing
  // or starting the Harness. A renamed but vulnerable artifact still fails below.
  directory = mkdtempSync(join(tmpdir(), "board-glob-security-"));
  const manifest = { name: "board-glob-security", private: true,
    dependencies: { picomatch: `npm:${entry.name ?? "picomatch"}@${entry.version}` } };
  writeFileSync(join(directory, "package.json"), JSON.stringify(manifest));
  writeFileSync(join(directory, "package-lock.json"), JSON.stringify({
    name: manifest.name, lockfileVersion: 3, requires: true,
    packages: { "": manifest, "node_modules/picomatch": entry },
  }));
  const install = spawnSync("npm", ["ci", "--ignore-scripts", "--no-fund"], {
    cwd: directory, encoding: "utf8", timeout: 60_000,
  });
  assert.ifError(install.error);
  assert.equal(install.status, 0, install.stdout + install.stderr);
  matcherPath = createRequire(join(directory, "package.json")).resolve("picomatch");
});

after(() => { if (directory) rmSync(directory, { recursive: true, force: true }); });

test("the locked matcher rejects CVE-2026-112366 inputs within a bounded process", () => {
  const attacks = [
    ["+(*a)", "a".repeat(80) + "!"],
    ["*(*a)", "a".repeat(80) + "!"],
    ["+(a*)", "a".repeat(80) + "/"],
    ["*(a*)", "a".repeat(80) + "/"],
    ["+(*)", "a".repeat(80) + "/"],
    ["*(*)", "a".repeat(80) + "/"],
    ["+(*)b", "a".repeat(80) + "!"],
    ["*(*)b", "a".repeat(80) + "!"],
    ["+(*a)c", "a".repeat(80) + "!"],
    ["+(a*b)", "ab".repeat(40) + "!"],
    ["+(**)", "a".repeat(80) + "/."],
    ["+(**a)", "a".repeat(80) + "!"],
    ["+(@(*a))", "a".repeat(80) + "!"],
    ["+(?(*a))", "a".repeat(80) + "!"],
  ];
  const result = spawnSync(process.execPath, ["-e", `
    const assert = require("node:assert/strict");
    const match = require(${JSON.stringify(matcherPath)});
    for (const [pattern, input] of ${JSON.stringify(attacks)}) {
      assert.equal(match(pattern)(input), false, pattern);
    }
  `], { encoding: "utf8", timeout: 5_000 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
});

test("Harness watch exclusions still match directories and dotfiles", () => {
  const match = createRequire(import.meta.url)(matcherPath);
  const ignored = match(["**/node_modules", "**/.*", "cache", "data"]);
  for (const path of ["node_modules", "plugins/node_modules", ".git", "plugins/.cache", "cache", "data"]) {
    assert.equal(ignored(path), true, path);
  }
  for (const path of ["plugin.js", "plugins/index.ts", "metadata", "src/cache.js"]) {
    assert.equal(ignored(path), false, path);
  }
  assert.equal(match(["**/*.{js,ts}"])("plugins/index.ts"), true);
  assert.equal(match(["**/*.{js,ts}"])("plugins/README.md"), false);
});

test("ordinary repeated extglobs preserve positive and negative matches", () => {
  const match = createRequire(import.meta.url)(matcherPath);
  assert.equal(match("+(*a)")("ababa"), true);
  assert.equal(match("+(*a)")("abab"), false);
  assert.equal(match("+(a*b)")("axbayb"), true);
  assert.equal(match("+(a*b)")("axbay"), false);
});
