#!/usr/bin/env node

/**
 * Universal SAP ABAP Program Deployer via MCP Server (ADT)
 * 
 * Usage:
 *   node scripts/deploy.js [path/to/program.prog.abap] [PROGRAM_NAME]
 * 
 * Example:
 *   node scripts/deploy.js src/z_auth_test.prog.abap Z_AUTH_TEST
 */

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const rootDir = path.resolve(__dirname, '..');
const envPath = path.join(rootDir, '.sap.env');

if (!fs.existsSync(envPath)) {
  console.error(`❌ Error: Environment file not found at: ${envPath}`);
  console.error(`👉 Please copy .sap.env.example to .sap.env and configure your SAP credentials first.`);
  process.exit(1);
}

// Target file
const defaultFile = path.join(rootDir, 'src', 'z_auth_test.prog.abap');
const targetFile = process.argv[2] ? path.resolve(process.argv[2]) : defaultFile;

if (!fs.existsSync(targetFile)) {
  console.error(`❌ Error: Source file not found: ${targetFile}`);
  process.exit(1);
}

// Program name
const fileName = path.basename(targetFile);
const defaultProgName = fileName.replace(/\.prog\.abap$/i, '').replace(/\.abap$/i, '').toUpperCase();
const programName = (process.argv[3] || defaultProgName).toUpperCase();

const sourceCode = fs.readFileSync(targetFile, 'utf8');
console.log(`📦 Deploying ${programName} (${sourceCode.length} characters) from ${targetFile}...`);

// Determine command based on platform
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
      
      // Step 1: Initialized handshake
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
          // Try CreateProgram if update failed (program might not exist yet)
          send({
            jsonrpc: '2.0',
            id: 20,
            method: 'tools/call',
            params: {
              name: 'CreateProgram',
              arguments: {
                program_name: programName,
                title: 'SU53 Authorization Trace and Simulator',
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
