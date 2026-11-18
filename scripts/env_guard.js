/**
 * Guard against a silent credential corruption that locks SAP accounts.
 *
 * The MCP server reads .sap.env with dotenv, which treats an unquoted '#' as the
 * start of an inline comment. An unquoted SAP_PASSWORD containing '#' is therefore
 * truncated and every connection attempt is a wrong-password logon, which quickly
 * locks the SAP user. Abort BEFORE any connection is made if that is the case.
 */
const fs = require('fs');

function assertSafeEnvFile(envPath) {
  const lines = fs.readFileSync(envPath, 'utf8').split(/\r?\n/);
  const problems = [];
  for (const line of lines) {
    if (!line.startsWith('SAP_PASSWORD')) continue;
    const val = line.slice(line.indexOf('=') + 1).trim();
    const quoted = /^(['"]).*\1$/.test(val);
    if (!quoted && /[#\s]/.test(val)) {
      problems.push("SAP_PASSWORD contains '#' or whitespace but is not quoted");
    }
  }
  if (problems.length > 0) {
    console.error(`❌ Unsafe ${envPath}: ${problems.join('; ')}.`);
    console.error("👉 Wrap the value in single quotes, e.g. SAP_PASSWORD='your#pass', otherwise the password is truncated and the SAP user gets locked.");
    process.exit(1);
  }
}

module.exports = { assertSafeEnvFile };
