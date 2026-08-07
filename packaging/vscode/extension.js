const vscode = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');
const path = require('path');

let client = null;

/**
 * @param {vscode.ExtensionContext} context
 */
function activate(context) {
  const config = vscode.workspace.getConfiguration('rune');
  const lspEnabled = config.get('lspEnabled', true);

  // ─── LSP Language Server ──────────────────────────────────────
  if (lspEnabled) {
    const serverPath = config.get('schemaPath', 'rune');

    const serverOptions = {
      command: serverPath,
      args: ['lsp'],
      transport: TransportKind.stdio,
    };

    const clientOptions = {
      documentSelector: [{ scheme: 'file', language: 'rune' }],
      synchronize: {
        fileEvents: vscode.workspace.createFileSystemWatcher('**/*.ss'),
      },
    };

    client = new LanguageClient(
      'runeSchema',
      'Rune Schema Language Server',
      serverOptions,
      clientOptions,
    );

    client.start().catch((err) => {
      console.warn('Rune language server failed to start:', err.message);
      vscode.window.showWarningMessage(
        `Rune language server failed to start: ${err.message}. ` +
        `Ensure 'rune' is in your PATH or set rune.schemaPath.`,
      );
    });
  }

  // ─── Commands ─────────────────────────────────────────────────

  // Validate command
  const validateCmd = vscode.commands.registerCommand('rune.validate', async () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      vscode.window.showWarningMessage('No active editor');
      return;
    }
    const document = editor.document;
    if (document.languageId !== 'rune') {
      vscode.window.showWarningMessage('Active file is not a Rune schema');
      return;
    }
    const filePath = document.uri.fsPath;
    try {
      const { execSync } = require('child_process');
      execSync(`rune validate "${filePath}"`, { encoding: 'utf-8' });
      vscode.window.showInformationMessage('Schema is valid');
    } catch (err) {
      vscode.window.showErrorMessage(`Validation failed: ${err.message}`);
    }
  });

  // Generate command
  const generateCmd = vscode.commands.registerCommand('rune.generate', async () => {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      vscode.window.showWarningMessage('No active editor');
      return;
    }
    const document = editor.document;
    if (document.languageId !== 'rune') {
      vscode.window.showWarningMessage('Active file is not a Rune schema');
      return;
    }
    const filePath = document.uri.fsPath;
    try {
      const { execSync } = require('child_process');
      const output = execSync(`rune "${filePath}"`, { encoding: 'utf-8' });
      const outputDoc = await vscode.workspace.openTextDocument({
        content: output,
        language: 'sql',
      });
      await vscode.window.showTextDocument(outputDoc, { viewColumn: vscode.ViewColumn.Beside });
    } catch (err) {
      vscode.window.showErrorMessage(`Generate failed: ${err.message}`);
    }
  });

  // Init command
  const initCmd = vscode.commands.registerCommand('rune.init', async () => {
    const folder = await vscode.window.showOpenDialog({
      canSelectFiles: false,
      canSelectFolders: true,
      openLabel: 'Initialize Rune Schema',
    });
    if (!folder || folder.length === 0) return;
    const dirPath = folder[0].fsPath;
    try {
      const { execSync } = require('child_process');
      execSync('rune init', { cwd: dirPath, encoding: 'utf-8' });
      vscode.window.showInformationMessage('Rune schema initialized');
      const schemaFile = `${dirPath}/schema.ss`;
      const doc = await vscode.workspace.openTextDocument(schemaFile);
      await vscode.window.showTextDocument(doc);
    } catch (err) {
      vscode.window.showErrorMessage(`Init failed: ${err.message}`);
    }
  });

  context.subscriptions.push(validateCmd, generateCmd, initCmd);
}

function deactivate() {
  if (client) {
    return client.stop();
  }
  return undefined;
}

module.exports = { activate, deactivate };
