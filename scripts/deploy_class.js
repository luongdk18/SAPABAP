#!/usr/bin/env node

/**
 * SAP ABAP Class Deployer via MCP Server (ADT)
 * 
 * Usage:
 *   node scripts/deploy_class.js [CLASS_NAME_OR_FILE]
 * 
 * Example:
 *   node scripts/deploy_class.js ZCL_SSPR_HTTP_HANDLER
 *   node scripts/deploy_class.js src/zcl_sspr_http_handler.clas.abap
 */

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const rootDir = path.resolve(__dirname, '..');
const srcDir = path.join(rootDir, 'src');
const envPath = path.join(rootDir, '.sap.env');

if (!fs.existsSync(envPath)) {
  console.error(`❌ Error: Environment file not found at: ${envPath}`);
  process.exit(1);
}

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const content = fs.readFileSync(filePath, 'utf8');
  const env = {};
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eqIdx = line.indexOf('=');
    if (eqIdx !== -1) {
      const key = line.slice(0, eqIdx).trim();
      let val = line.slice(eqIdx + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      env[key] = val;
    }
  }
  return env;
}

const fileEnv = parseEnvFile(envPath);
const targetPackage = process.env.SAP_PACKAGE || fileEnv.SAP_PACKAGE || '$TMP';
const transportRequest = process.env.SAP_TRANSPORT_REQUEST || fileEnv.SAP_TRANSPORT_REQUEST || '';

const inputTarget = process.argv[2] || 'ZCL_SSPR_HTTP_HANDLER';

let targetFile = null;
if (fs.existsSync(inputTarget)) {
  targetFile = path.resolve(inputTarget);
} else if (fs.existsSync(path.join(srcDir, inputTarget))) {
  targetFile = path.join(srcDir, inputTarget);
} else if (fs.existsSync(path.join(srcDir, inputTarget + '.clas.abap'))) {
  targetFile = path.join(srcDir, inputTarget + '.clas.abap');
} else if (fs.existsSync(path.join(srcDir, inputTarget.toLowerCase() + '.clas.abap'))) {
  targetFile = path.join(srcDir, inputTarget.toLowerCase() + '.clas.abap');
}

if (!targetFile || !fs.existsSync(targetFile)) {
  console.error(`❌ Error: Class source file not found for: ${inputTarget}`);
  process.exit(1);
}

const fileName = path.basename(targetFile);
const className = fileName.replace(/\.clas\.abap$/i, '').toUpperCase();
const sourceCode = fs.readFileSync(targetFile, 'utf8');

console.log(`\n📦 Deploying Class ${className} (${sourceCode.length} characters) from ${targetFile}...`);
console.log(`📦 Target Package: ${targetPackage} | Transport: ${transportRequest}`);

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

function getUpdateArgs() {
  const args = {
    class_name: className,
    source_code: sourceCode,
    activate: true
  };
  if (transportRequest && targetPackage.toUpperCase() !== '$TMP') {
    args.transport_request = transportRequest;
  }
  return args;
}

function getCreateArgs() {
  const args = {
    class_name: className,
    description: `${className} - SSPR & Unlock HTTP Handler`,
    package_name: targetPackage,
    transport_request: transportRequest
  };
  return args;
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
        
        console.log(`🚀 Checking and deploying class ${className} on SAP...`);
        // Try UpdateClass first
        send({
          jsonrpc: '2.0',
          id: 10,
          method: 'tools/call',
          params: {
            name: 'UpdateClass',
            arguments: getUpdateArgs()
          }
        });
      }

      // Step 2: Handle Update response
      if (msg.id === 10) {
        if (msg.error || (msg.result && msg.result.isError)) {
          console.error(`❌ UpdateClass failed:`, JSON.stringify(msg, null, 2));
          child.kill();
          process.exit(1);
        } else {
          console.log(`✅ Success! Class ${className} updated and activated successfully.`);
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
          console.error(`❌ CreateClass failed:`, JSON.stringify(msg, null, 2));
          child.kill();
          process.exit(1);
        } else {
          console.log(`Class created. Now setting source code and activating...`);
          send({
            jsonrpc: '2.0',
            id: 30,
            method: 'tools/call',
            params: {
              name: 'UpdateClass',
              arguments: getUpdateArgs()
            }
          });
        }
      }

      // Step 4: Handle second Update attempt after Create
      if (msg.id === 30) {
        if (msg.error || (msg.result && msg.result.isError)) {
          console.error(`❌ Final UpdateClass failed:`, JSON.stringify(msg, null, 2));
          child.kill();
          process.exit(1);
        } else {
          console.log(`✅ Success! Class ${className} created, updated, and activated successfully.`);
          if (msg.result && msg.result.content) {
            console.log(msg.result.content[0].text);
          }
          child.kill();
          process.exit(0);
        }
      }
    } catch (e) {
      // Ignore non-json lines
    }
  }
});

child.stderr.on('data', data => {
  // stderr can have debug logs
});

child.on('close', code => {
  if (code !== 0) {
    console.log(`Process exited with code ${code}`);
  }
});

// Trigger handshake
send({
  jsonrpc: '2.0',
  id: 1,
  method: 'initialize',
  params: {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'deploy_class', version: '1.0.0' }
  }
});
