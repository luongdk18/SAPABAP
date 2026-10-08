#!/usr/bin/env node
// Runs only the HARMLESS local ABAP Unit tests in Z_AUTH_TEST_N.
// No role changes or business-program execution are requested.
const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');

// Match EnvFileSessionStore parsing: a # inside a password is not an inline comment.
const sapEnv = {};
for (const raw of fs.readFileSync(path.resolve(__dirname, '..', '.sap.env'), 'utf8').split(/\r?\n/)) {
  const line = raw.trim();
  if (!line || line.startsWith('#')) continue;
  const split = line.indexOf('=');
  if (split < 0) continue;
  let value = line.slice(split + 1);
  const comment = value.match(/\s+#/);
  if (comment) value = value.slice(0, comment.index);
  sapEnv[line.slice(0, split).trim()] = value.trim().replace(/^["']+|["']+$/g, '').trim();
}
const base = new URL(sapEnv.SAP_URL);
if ((sapEnv.SAP_AUTH_TYPE || 'basic').toLowerCase() !== 'basic') {
  throw new Error('This test runner requires the existing SAP basic-auth configuration.');
}
const authorization = 'Basic ' + Buffer.from(sapEnv.SAP_USERNAME + ':' + sapEnv.SAP_PASSWORD).toString('base64');
const client = sapEnv.SAP_CLIENT || '100';
let cookies = '', csrf = '';
function request(relative, method = 'GET', data, extra = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(relative, base);
    if (!url.searchParams.has('sap-client')) url.searchParams.set('sap-client', client);
    if (url.origin !== base.origin) return reject(new Error('Unexpected cross-origin ADT test URL'));
    const transport = url.protocol === 'https:' ? https : http;
    const headers = { Authorization: authorization, Accept: 'application/xml', 'sap-language': sapEnv.SAP_LANGUAGE || 'EN', ...extra };
    if (cookies) headers.Cookie = cookies;
    if (csrf && method !== 'GET') headers['x-csrf-token'] = csrf;
    if (data) headers['Content-Length'] = Buffer.byteLength(data);
    const req = transport.request(url, {method, headers, timeout: 45000,
      rejectUnauthorized: sapEnv.NODE_TLS_REJECT_UNAUTHORIZED !== '0'}, res => {
      let text = '';
      res.setEncoding('utf8');
      res.on('data', chunk => text += chunk);
      res.on('end', () => {
        if (res.headers['set-cookie']) cookies = res.headers['set-cookie'].map(c => c.split(';')[0]).join('; ');
        if (res.headers['x-csrf-token']) csrf = res.headers['x-csrf-token'];
        resolve({status: res.statusCode, headers: res.headers, text});
      });
    });
    req.on('timeout', () => req.destroy(new Error('ADT unit-test request timed out')));
    req.on('error', reject);
    req.end(data);
  });
}
async function main() {
  const session = await request('/sap/bc/adt/discovery', 'GET', undefined, {'x-csrf-token': 'Fetch', Accept: '*/*'});
  if (session.status !== 200 || !csrf) throw new Error('Cannot initialize ADT test session (HTTP ' + session.status + ')');
  const xml = '<?xml version="1.0" encoding="UTF-8"?><aunit:runConfiguration xmlns:aunit="http://www.sap.com/adt/aunit"><external><coverage active="false"/></external><options><uriType value="classic"/><testDeterminationStrategy sameProgram="true" assignedTests="false" appendAssignedTestsPreview="false"/><testRiskLevels harmless="true" dangerous="false" critical="false"/><testDurations short="true" medium="false" long="false"/></options><adtcore:objectSets xmlns:adtcore="http://www.sap.com/adt/core"><objectSet kind="inclusive"><adtcore:objectReferences><adtcore:objectReference adtcore:uri="/sap/bc/adt/programs/programs/z_auth_test_n" adtcore:type="PROG/P" adtcore:name="Z_AUTH_TEST_N"/></adtcore:objectReferences></objectSet></adtcore:objectSets></aunit:runConfiguration>';
  let result = await request('/sap/bc/adt/abapunit/testruns', 'POST', xml, {'Content-Type': 'application/vnd.sap.adt.abapunit.testruns.config.v4+xml', Accept: '*/*'});
  if (result.status >= 400) throw new Error('Could not start ABAP Unit (HTTP ' + result.status + '): ' + result.text.slice(0,1000));
  const location = result.headers.location;
  if (location) {
    for (let attempt = 0; attempt < 20; attempt++) {
      result = await request(location, 'GET', undefined, {Accept: '*/*'});
      if (/state="(FINISHED|COMPLETED|finished|completed)"/.test(result.text)) break;
      const candidate = await request(location.replace(/\/$/, '') + '/results', 'GET', undefined, {Accept: '*/*'});
      if (candidate.status === 200 && /testMethod|testCase|testRunResult|aunit:runResult/.test(candidate.text)) {
        result = candidate; break;
      }
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    if (!/testMethod|testCase|testRunResult|aunit:runResult/.test(result.text)) result = await request(location.replace(/\/$/, '') + '/results', 'GET', undefined, {Accept: '*/*'});
  }
  const out = path.resolve(__dirname, '..', 'tests', 'z_auth_test_n.abapunit.xml');
  fs.mkdirSync(path.dirname(out), {recursive: true});
  fs.writeFileSync(out, result.text);
  console.log('ABAP Unit HTTP ' + result.status);
  const methods = [...result.text.matchAll(/<testMethod\b[^>]*adtcore:name="([^"]+)"/g)].map(match => match[1]);
  const failed = result.status >= 400 || methods.length !== 21 || /<alert\b|<exception\b|severity="(critical|fatal)"/.test(result.text);
  console.log(methods.map(name => 'Executed: ' + name).join('\n'));
  console.log((failed ? 'FAILED' : 'PASSED') + ': ' + methods.length + ' test methods; result saved to tests/z_auth_test_n.abapunit.xml');
  if (failed) { console.error(result.text); process.exitCode = 1; }
}
main().catch(err => { console.error(err.message); process.exitCode = 1; });


