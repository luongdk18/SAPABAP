#!/usr/bin/env node

/**
 * SAP ABAP Program Deployer via MCP Server (ADT)
 * 
 * Allows deploying a selected ABAP program to SAP.
 * 
 * Usage:
 *   node scripts/deploy.js [PROGRAM_NAME_OR_FILE] [CUSTOM_SAP_NAME]
 * 
 * Examples:
 *   npm run deploy -- Z_AUTH_TEST
 *   node scripts/deploy.js Z_AUTH_TEST
 *   node scripts/deploy.js src/z_auth_test.prog.abap
 *   npm run deploy  (Interactive selection menu)
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { spawn } = require('child_process');

const rootDir = path.resolve(__dirname, '..');
const srcDir = path.join(rootDir, 'src');
const envPath = path.join(rootDir, '.sap.env');

if (!fs.existsSync(envPath)) {
  console.error(`❌ Error: Environment file not found at: ${envPath}`);
  console.error(`👉 Please copy .sap.env.example to .sap.env and configure your SAP credentials first.`);
  process.exit(1);
}

// Discover available programs in src/
const availableFiles = fs.existsSync(srcDir)
  ? fs.readdirSync(srcDir).filter(f => f.endsWith('.abap'))
  : [];

if (availableFiles.length === 0) {
  console.error(`❌ Error: No .abap files found in: ${srcDir}`);
  process.exit(1);
}

function resolveTargetFile(input) {
  if (!input) return null;

  // Direct path
  const directPath = path.resolve(input);
  if (fs.existsSync(directPath)) return directPath;

  // Relative to srcDir
  const inSrc = path.join(srcDir, input);
  if (fs.existsSync(inSrc)) return inSrc;

  // Try with .prog.abap or .abap extensions
  const candidates = [
    input + '.prog.abap',
    input.toLowerCase() + '.prog.abap',
    input + '.abap',
    input.toLowerCase() + '.abap'
  ];

  for (const cand of candidates) {
    const candPath = path.join(srcDir, cand);
    if (fs.existsSync(candPath)) return candPath;
  }

  return null;
}

function executeDeployment(targetFile, customProgName) {
  const fileName = path.basename(targetFile);
  const defaultProgName = fileName
    .replace(/\.prog\.abap$/i, '')
    .replace(/\.abap$/i, '')
    .toUpperCase();
  const programName = (customProgName || defaultProgName).toUpperCase();

  const sourceCode = fs.readFileSync(targetFile, 'utf8');
  console.log(`\n📦 Deploying ${programName} (${sourceCode.length} characters) from ${targetFile}...`);

  const isWin = process.platform === 'win32';
  const cmd = isWin ? 'cmd.exe' : 'mcp-abap-adt';
  const args = isWin 
    ? ['/c', 'mcp-abap-adt', '--transport=stdio', `--env-path=${envPath}`]
    : ['--transport=stdio', `--env-path=${envPath}`];

  console.log(`🔌 Starting SAP ADT MCP Server with environment: ${envPath}`);
  const child = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'pipe'] });

  let buffer = '';

  function send(msgObj) {
    child.stdin.write(JSON.stringify(msgObj) + '\n');
  }

  child.stdout.on('data', data => {
    buffer += data.toString();
    const lines = buffer.split('\n');
    buffer = lines.pop();

    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line.trim());
        
        // Step 1: Handshake
        if (msg.id === 1) {
          send({ jsonrpc: '2.0', method: 'notifications/initialized' });
          
          console.log(`🚀 Checking and deploying program ${programName} on SAP...`);
          // Try UpdateProgram first
          send({
            jsonrpc: '2.0',
            id: 10,
            method: 'tools/call',
            params: {
              name: 'UpdateProgram',
              arguments: {
                program_name: programName,
                source_code: sourceCode,
                activate: true
              }
            }
          });
        }

        // Step 2: Handle Update response
        if (msg.id === 10) {
          if (msg.error || (msg.result && msg.result.isError)) {
            console.log(`⚠️ UpdateProgram returned notice. Attempting CreateProgram instead...`);
            send({
              jsonrpc: '2.0',
              id: 20,
              method: 'tools/call',
              params: {
                name: 'CreateProgram',
                arguments: {
                  program_name: programName,
                  title: `${programName} - ABAP Utility`,
                  package_name: '$TMP',
                  source_code: sourceCode,
                  activate: true
                }
              }
            });
          } else {
            console.log(`✅ Success! Program ${programName} updated and activated successfully.`);
            if (msg.result && msg.result.content) {
              console.log(msg.result.content[0].text);
            }
            child.kill();
            process.exit(0);
          }
        }

        // Step 3: Handle Create response
        if (msg.id === 20) {
          if (msg.error || (msg.result && msg.result.isError)) {
            console.error(`❌ Failed to deploy program ${programName}:`, JSON.stringify(msg, null, 2));
            child.kill();
            process.exit(1);
          } else {
            console.log(`✅ Success! Program ${programName} created and activated successfully.`);
            if (msg.result && msg.result.content) {
              console.log(msg.result.content[0].text);
            }
            child.kill();
            process.exit(0);
          }
        }
      } catch (e) {
        // Ignore non-json logs
      }
    }
  });

  child.stderr.on('data', d => {
    const str = d.toString().trim();
    if (str) console.log(`[SAP MCP] ${str}`);
  });

  child.on('error', err => {
    console.error(`❌ Failed to start MCP process:`, err);
    process.exit(1);
  });

  // Start initialization
  send({
    jsonrpc: '2.0',
    id: 1,
    method: 'initialize',
    params: {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: { name: 'sap-abap-deployer', version: '1.0' }
    }
  });

  // Safety timeout
  setTimeout(() => {
    console.error(`⏳ Deployment timed out after 60s.`);
    child.kill();
    process.exit(1);
  }, 60000);
}

// Main entry
const requestedArg = process.argv[2];

if (requestedArg) {
  const targetFile = resolveTargetFile(requestedArg);
  if (!targetFile) {
    console.error(`❌ Error: Program '${requestedArg}' not found.`);
    console.log(`\nAvailable programs in src/:`);
    availableFiles.forEach(f => console.log(`  - ${f}`));
    process.exit(1);
  }
  executeDeployment(targetFile, process.argv[3]);
} else {
  // If only 1 program exists and not in TTY, or interactive selection
  if (process.stdin.isTTY) {
    console.log(`\n📋 Select an ABAP program to deploy to SAP:`);
    availableFiles.forEach((f, idx) => {
      const progName = f.replace(/\.prog\.abap$/i, '').replace(/\.abap$/i, '').toUpperCase();
      console.log(`  [${idx + 1}] ${progName} (${f})`);
    });

    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    rl.question(`\nEnter number (1-${availableFiles.length}) or 'q' to cancel: `, answer => {
      rl.close();
      const choice = answer.trim();
      if (choice.toLowerCase() === 'q') {
        console.log(`Deployment cancelled.`);
        process.exit(0);
      }

      const num = parseInt(choice, 10);
      if (isNaN(num) || num < 1 || num > availableFiles.length) {
        console.error(`❌ Invalid selection.`);
        process.exit(1);
      }

      const selectedFile = path.join(srcDir, availableFiles[num - 1]);
      executeDeployment(selectedFile);
    });
  } else {
    // Non-interactive fallback
    console.log(`ℹ️ Usage: node scripts/deploy.js <PROGRAM_NAME>`);
    console.log(`Example: npm run deploy -- Z_AUTH_TEST`);
    console.log(`\nAvailable programs:`);
    availableFiles.forEach(f => console.log(`  - ${f.replace(/\.prog\.abap$/i, '').toUpperCase()}`));
    process.exit(1);
  }
}
