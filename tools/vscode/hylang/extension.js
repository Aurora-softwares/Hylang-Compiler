const vscode = require("vscode");
const cp = require("node:child_process");

function activate(context) {
  const output = vscode.window.createOutputChannel("Hylang");
  context.subscriptions.push(output);

  const startServer = () => {
    const config = vscode.workspace.getConfiguration("hylang");
    const hyPath = process.env.HYLANG_BIN || config.get("hyPath") || "hy";
    const server = cp.spawn(hyPath, ["lsp"], { stdio: ["pipe", "pipe", "pipe"] });
    server.stderr.on("data", data => output.append(data.toString()));
    server.on("error", error => output.appendLine(`Failed to start hy lsp: ${error.message}`));
    context.subscriptions.push({ dispose: () => server.kill() });
  };

  startServer();
}

function deactivate() {}

module.exports = { activate, deactivate };
