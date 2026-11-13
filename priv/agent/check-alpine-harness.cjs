// Run in a disposable Node process: a native SIGABRT cannot be caught in JS.
// Resolve relative to the actual Harness install, not a project's node_modules.
const fs = require("node:fs");
const { createRequire } = require("node:module");
const dsh = createRequire(fs.realpathSync(process.argv[2]));
let subprocess;
try {
  subprocess = dsh.resolve("@deepseek-ai/dsh-subprocess-local");
} catch (error) {
  // Some launchers are not npm entry points. Let the Harness check itself.
  if (error.code !== "MODULE_NOT_FOUND") throw error;
}
if (subprocess) createRequire(subprocess)("koffi");
if (process.platform === "linux" && !["node", "dsh"].includes(fs.readFileSync("/proc/self/comm", "utf8").trim())) {
  process.exitCode = 42; // The upstream manager cannot identify this process.
}
