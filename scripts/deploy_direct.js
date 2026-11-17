const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const programName = process.argv[2] || 'Z_ROLE_01_CREATE_MASTER';
const filePath = process.argv[3] || path.join(__dirname, '..', 'src', `${programName.toLowerCase()}.prog.abap`);
const envPath = path.join(__dirname, '..', '.sap.env');

if (!fs.existsSync(filePath)) {
  console.error(`File not found: ${filePath}`);
  process.exit(1);
}

const sourceCode = fs.readFileSync(filePath, 'utf-8');
const mcpBin = path.join(process.env.APPDATA, 'npm', 'node_modules', '@mcp-abap-adt', 'core', 'bin', 'mcp-abap-adt.js');

function parseEnv(p) {
  const env = {};
  for (const line of fs.readFileSync(p, 'utf-8').split(/\r?\n/)) {
    const l = line.trim();
    if (!l || l.startsWith('#')) continue;
    const eq = l.indexOf('=');
    if (eq > 0) env[l.slice(0, eq).trim()] = l.slice(eq + 1).trim();
  }
  return env;
}
const envConfig = parseEnv(envPath);
const transportRequest = envConfig.SAP_TRANSPORT_REQUEST || '';

console.log(`📦 Deploying ${programName} (${sourceCode.length} bytes, TR: ${transportRequest})...`);

const child = spawn(process.execPath, [
  '--dns-result-order=ipv4first',
  mcpBin,
  '--transport=stdio',
  `--env-path=${envPath}`
], {
  stdio: ['pipe', 'pipe', 'pipe']
});

let buffer = '';

function send(obj) {
  child.stdin.write(JSON.stringify(obj) + '\n');
}

child.stderr.on('data', data => {
  const s = data.toString().trim();
  if (s) console.log(`[STDERR] ${s}`);
});

child.stdout.on('data', data => {
  buffer += data.toString();
  const lines = buffer.split('\n');
  buffer = lines.pop();

  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line.trim());
      handleMessage(msg);
    } catch (e) {
      console.error('JSON parse error:', e, line);
    }
  }
});

function handleMessage(msg) {
  if (msg.id === 1) {
    console.log('✅ Server initialized.');
    send({ jsonrpc: '2.0', method: 'notifications/initialized' });

    console.log(`⏳ Step 1: Updating source code for ${programName}...`);
    const updateArgs = {
      program_name: programName,
      source_code: sourceCode,
      activate: false
    };
    if (transportRequest) updateArgs.transport_request = transportRequest;

    send({
      jsonrpc: '2.0',
      id: 2,
      method: 'tools/call',
      params: {
        name: 'UpdateProgram',
        arguments: updateArgs
      }
    });
  } else if (msg.id === 2) {
    console.log(`[Update Result]:`, JSON.stringify(msg.result || msg.error, null, 2));
    if (msg.error || (msg.result && msg.result.isError)) {
      console.error(`❌ Update failed.`);
      child.kill();
      process.exit(1);
    }

    console.log(`⏳ Step 2: Activating ${programName}...`);
    const actArgs = { program_name: programName };
    if (transportRequest) actArgs.transport_request = transportRequest;

    send({
      jsonrpc: '2.0',
      id: 3,
      method: 'tools/call',
      params: {
        name: 'ActivateProgram',
        arguments: actArgs
      }
    });
  } else if (msg.id === 3) {
    console.log(`[Activate Result]:`, JSON.stringify(msg.result || msg.error, null, 2));
    if (msg.error || (msg.result && msg.result.isError)) {
      console.error(`❌ Activation failed.`);
      child.kill();
      process.exit(1);
    }
    console.log(`🎉 SUCCESS: ${programName} deployed and activated successfully!`);
    child.kill();
    process.exit(0);
  }
}

send({
  jsonrpc: '2.0',
  id: 1,
  method: 'initialize',
  params: {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'deployer-v2', version: '2.0.0' }
  }
});

setTimeout(() => {
  console.error('⏳ Timeout after 90s');
  child.kill();
  process.exit(1);
}, 90000);
