#!/usr/bin/env node
/**
 * PreToolUse Hook (Read|Edit|Write|Bash): blocks reading, modifying, and
 * exfiltrating secret material through the tool layer.
 *
 * Complements file-guard.cjs, which only covers Edit/Write on known file
 * names: this guard also covers the Read tool and the Bash channels
 * (cat/source/scp/curl of key material, env dumps) — the class "every path
 * from a secret into context or repo is a secret channel".
 *
 * Levels: critical (keys, .env) < high (+ secrets files, env dumps,
 * exfiltration) < strict (+ configs that may hold secrets). Default: high.
 * Ask mode per level via env: HOOK_ASK_CRITICAL / HOOK_ASK_HIGH /
 * HOOK_ASK_STRICT = "true" answers "ask" instead of "deny".
 *
 * Instance extension (optional): <project>/.claude/rules/secret-patterns.json
 *   { "files":  [{ "id": "...", "regex": "...", "reason": "...", "level": "high" }],
 *     "bash":   [{ "id": "...", "regex": "...", "reason": "...", "level": "high" }],
 *     "allowlist": ["regexString", ...] }
 * Regexes are strings (case-insensitive); a broken regex is reported to
 * stderr and skipped, it never disables the guard.
 *
 * Based on protect-secrets.js from karanb192/claude-code-hooks (MIT).
 * Adapted: os.homedir(), Windows path normalization, instance pattern file.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const SAFETY_LEVEL = (process.env.HOOK_SECRET_LEVEL || 'high').toLowerCase();

const envBool = (key, fallback) => key in process.env ? process.env[key] === 'true' : fallback;
const ASK = {
  critical: envBool('HOOK_ASK_CRITICAL', false),
  high:     envBool('HOOK_ASK_HIGH', false),
  strict:   envBool('HOOK_ASK_STRICT', false),
};

// Files explicitly safe to access (templates, examples)
const ALLOWLIST = [
  /\.env\.example$/i, /\.env\.sample$/i, /\.env\.template$/i,
  /\.env\.schema$/i, /\.env\.defaults$/i, /env\.example$/i, /example\.env$/i,
];

const SENSITIVE_FILES = [
  // CRITICAL
  { level: 'critical', id: 'env-file',           regex: /(?:^|\/)\.env(?:\.[^/]*)?$/,                    reason: '.env file contains secrets' },
  { level: 'critical', id: 'envrc',              regex: /(?:^|\/)\.envrc$/,                              reason: '.envrc (direnv) contains secrets' },
  { level: 'critical', id: 'ssh-private-key',    regex: /(?:^|\/)\.ssh\/id_[^/]+$/,                      reason: 'SSH private key' },
  { level: 'critical', id: 'ssh-private-key-2',  regex: /(?:^|\/)(id_rsa|id_ed25519|id_ecdsa|id_dsa)$/,  reason: 'SSH private key' },
  { level: 'critical', id: 'ssh-authorized',     regex: /(?:^|\/)\.ssh\/authorized_keys$/,               reason: 'SSH authorized_keys' },
  { level: 'critical', id: 'aws-credentials',    regex: /(?:^|\/)\.aws\/credentials$/,                   reason: 'AWS credentials file' },
  { level: 'critical', id: 'aws-config',         regex: /(?:^|\/)\.aws\/config$/,                        reason: 'AWS config may contain secrets' },
  { level: 'critical', id: 'kube-config',        regex: /(?:^|\/)\.kube\/config$/,                       reason: 'Kubernetes config contains credentials' },
  { level: 'critical', id: 'pem-key',            regex: /\.pem$/i,                                       reason: 'PEM key file' },
  { level: 'critical', id: 'key-file',           regex: /\.key$/i,                                       reason: 'Key file' },
  { level: 'critical', id: 'p12-key',            regex: /\.(p12|pfx)$/i,                                 reason: 'PKCS12 key file' },

  // HIGH
  { level: 'high', id: 'credentials-json',       regex: /(?:^|\/)credentials\.json$/i,                   reason: 'Credentials file' },
  { level: 'high', id: 'secrets-file',           regex: /(?:^|\/)(secrets?|credentials?)\.(json|ya?ml|toml)$/i, reason: 'Secrets configuration file' },
  { level: 'high', id: 'service-account',        regex: /service[_-]?account.*\.json$/i,                 reason: 'GCP service account key' },
  { level: 'high', id: 'gcloud-creds',           regex: /(?:^|\/)\.config\/gcloud\/.*(credentials|tokens)/i, reason: 'GCloud credentials' },
  { level: 'high', id: 'azure-creds',            regex: /(?:^|\/)\.azure\/(credentials|accessTokens)/i,  reason: 'Azure credentials' },
  { level: 'high', id: 'docker-config',          regex: /(?:^|\/)\.docker\/config\.json$/,               reason: 'Docker config may contain registry auth' },
  { level: 'high', id: 'netrc',                  regex: /(?:^|\/)\.netrc$/,                              reason: '.netrc contains credentials' },
  { level: 'high', id: 'npmrc',                  regex: /(?:^|\/)\.npmrc$/,                              reason: '.npmrc may contain auth tokens' },
  { level: 'high', id: 'pypirc',                 regex: /(?:^|\/)\.pypirc$/,                             reason: '.pypirc contains PyPI credentials' },
  { level: 'high', id: 'gem-creds',              regex: /(?:^|\/)\.gem\/credentials$/,                   reason: 'RubyGems credentials' },
  { level: 'high', id: 'vault-token',            regex: /(?:^|\/)(\.vault-token|vault-token)$/,          reason: 'Vault token file' },
  { level: 'high', id: 'keystore',               regex: /\.(keystore|jks)$/i,                            reason: 'Java keystore' },
  { level: 'high', id: 'htpasswd',               regex: /(?:^|\/)\.?htpasswd$/,                          reason: 'htpasswd contains hashed passwords' },
  { level: 'high', id: 'pgpass',                 regex: /(?:^|\/)\.pgpass$/,                             reason: 'PostgreSQL password file' },
  { level: 'high', id: 'my-cnf',                 regex: /(?:^|\/)\.my\.cnf$/,                            reason: 'MySQL config may contain password' },

  // STRICT
  { level: 'strict', id: 'database-config',      regex: /(?:^|\/)(?:config\/)?database\.(json|ya?ml)$/i, reason: 'Database config may contain passwords' },
  { level: 'strict', id: 'ssh-known-hosts',      regex: /(?:^|\/)\.ssh\/known_hosts$/,                   reason: 'SSH known_hosts reveals infrastructure' },
  { level: 'strict', id: 'gitconfig',            regex: /(?:^|\/)\.gitconfig$/,                          reason: '.gitconfig may contain credentials' },
  { level: 'strict', id: 'curlrc',               regex: /(?:^|\/)\.curlrc$/,                             reason: '.curlrc may contain auth' },
];

const BASH_PATTERNS = [
  // CRITICAL
  { level: 'critical', id: 'cat-env',            regex: /\b(cat|less|head|tail|more|bat|view)\s+[^|;]*\.env\b/i,           reason: 'Reading .env file exposes secrets' },
  { level: 'critical', id: 'cat-ssh-key',        regex: /\b(cat|less|head|tail|more|bat)\s+[^|;]*(id_rsa|id_ed25519|id_ecdsa|id_dsa|\.pem|\.key)\b/i, reason: 'Reading private key' },
  { level: 'critical', id: 'cat-aws-creds',      regex: /\b(cat|less|head|tail|more)\s+[^|;]*\.aws\/credentials/i,         reason: 'Reading AWS credentials' },

  // HIGH - Environment exposure
  { level: 'high', id: 'env-dump',               regex: /\bprintenv\b|(?:^|[;&|]\s*)env\s*(?:$|[;&|])/,                    reason: 'Environment dump may expose secrets' },
  { level: 'high', id: 'echo-secret-var',        regex: /\becho\b[^;|&]*\$\{?[A-Za-z_]*(?:SECRET|KEY|TOKEN|PASSWORD|PASSW|CREDENTIAL|API_KEY|AUTH|PRIVATE)[A-Za-z_]*\}?/i, reason: 'Echoing secret variable' },
  { level: 'high', id: 'printf-secret-var',      regex: /\bprintf\b[^;|&]*\$\{?[A-Za-z_]*(?:SECRET|KEY|TOKEN|PASSWORD|CREDENTIAL|API_KEY|AUTH|PRIVATE)[A-Za-z_]*\}?/i, reason: 'Printing secret variable' },
  { level: 'high', id: 'cat-secrets-file',       regex: /\b(cat|less|head|tail|more)\s+[^|;]*(credentials?|secrets?)\.(json|ya?ml|toml)/i, reason: 'Reading secrets file' },
  { level: 'high', id: 'cat-netrc',              regex: /\b(cat|less|head|tail|more)\s+[^|;]*\.netrc/i,                    reason: 'Reading .netrc credentials' },
  { level: 'high', id: 'source-env',             regex: /\bsource\s+[^|;]*\.env\b|(?:^|[;&|]\s*)\.\s+[^|;]*\.env\b|^\.\s+[^|;]*\.env\b/i, reason: 'Sourcing .env loads secrets' },
  { level: 'high', id: 'export-cat-env',         regex: /export\s+.*\$\(cat\s+[^)]*\.env/i,                                reason: 'Exporting secrets from .env' },

  // HIGH - Exfiltration
  { level: 'high', id: 'curl-upload-env',        regex: /\bcurl\b[^;|&]*(-d\s*@|-F\s*[^=]+=@|--data[^=]*=@)[^;|&]*(\.env|credentials|secrets|id_rsa|\.pem|\.key)/i, reason: 'Uploading secrets via curl' },
  { level: 'high', id: 'curl-post-secrets',      regex: /\bcurl\b[^;|&]*-X\s*POST[^;|&]*[^;|&]*(\.env|credentials|secrets)/i, reason: 'POSTing secrets via curl' },
  { level: 'high', id: 'wget-post-secrets',      regex: /\bwget\b[^;|&]*--post-file[^;|&]*(\.env|credentials|secrets)/i,  reason: 'POSTing secrets via wget' },
  { level: 'high', id: 'scp-secrets',            regex: /\bscp\b[^;|&]*(\.env|credentials|secrets|id_rsa|\.pem|\.key)[^;|&]+:/i, reason: 'Copying secrets via scp' },
  { level: 'high', id: 'rsync-secrets',          regex: /\brsync\b[^;|&]*(\.env|credentials|secrets|id_rsa)[^;|&]+:/i,    reason: 'Syncing secrets via rsync' },
  { level: 'high', id: 'nc-secrets',             regex: /\bnc\b[^;|&]*<[^;|&]*(\.env|credentials|secrets|id_rsa)/i,       reason: 'Exfiltrating secrets via netcat' },

  // HIGH - Copy/move/delete secrets
  { level: 'high', id: 'cp-env',                 regex: /\bcp\b[^;|&]*\.env\b/i,                                           reason: 'Copying .env file' },
  { level: 'high', id: 'cp-ssh-key',             regex: /\bcp\b[^;|&]*(id_rsa|id_ed25519|\.pem|\.key)\b/i,                 reason: 'Copying private key' },
  { level: 'high', id: 'mv-env',                 regex: /\bmv\b[^;|&]*\.env\b/i,                                           reason: 'Moving .env file' },
  { level: 'high', id: 'rm-ssh-key',             regex: /\brm\b[^;|&]*(id_rsa|id_ed25519|id_ecdsa|authorized_keys)/i,     reason: 'Deleting SSH key' },
  { level: 'high', id: 'rm-env',                 regex: /\brm\b.*\.env\b/i,                                                 reason: 'Deleting .env file' },
  { level: 'high', id: 'rm-aws-creds',           regex: /\brm\b[^;|&]*\.aws\/credentials/i,                                reason: 'Deleting AWS credentials' },
  { level: 'high', id: 'truncate-secrets',       regex: /\btruncate\b.*\.(env|pem|key)\b|(?:^|[;&|]\s*)>\s*\.env\b/i,      reason: 'Truncating secrets file' },

  // HIGH - Process environ
  { level: 'high', id: 'proc-environ',           regex: /\/proc\/[^/]*\/environ/,                                          reason: 'Reading process environment' },
  { level: 'high', id: 'find-exec-cat-env',      regex: /find\b.*\.env.*-exec|find\b.*-exec.*(cat|less)\b[^|;]*\.env/i,    reason: 'Finding and reading .env files' },

  // STRICT
  { level: 'strict', id: 'grep-password',        regex: /\bgrep\b[^|;]*(-r|--recursive)[^|;]*(password|secret|api.?key|token|credential)/i, reason: 'Grep for secrets may expose them' },
  { level: 'strict', id: 'base64-secrets',       regex: /\bbase64\b[^|;]*(\.env|credentials|secrets|id_rsa|\.pem)/i,       reason: 'Base64 encoding secrets' },
];

const LEVELS = { critical: 1, high: 2, strict: 3 };
const LOG_DIR = path.join(os.homedir(), '.claude', 'hooks-logs');

/**
 * Load instance patterns from <project>/.claude/rules/secret-patterns.json.
 * A missing file is the normal case; a broken file or regex is reported and
 * skipped — it never widens or disables the guard.
 */
function loadInstancePatterns(projectDir) {
  const out = { files: [], bash: [], allowlist: [] };
  if (!projectDir) return out;
  const fp = path.join(projectDir, '.claude', 'rules', 'secret-patterns.json');
  let raw;
  try { raw = fs.readFileSync(fp, 'utf8'); } catch { return out; }
  try {
    const data = JSON.parse(raw);
    const compile = (entry, target) => {
      try {
        target.push({
          level: LEVELS[entry.level] ? entry.level : 'high',
          id: 'instance:' + (entry.id || 'unnamed'),
          regex: new RegExp(entry.regex, 'i'),
          reason: entry.reason || 'instance secret pattern',
        });
      } catch (e) {
        console.error('secret-guard: broken instance regex "' + entry.regex + '": ' + e.message);
      }
    };
    (data.files || []).forEach(e => compile(e, out.files));
    (data.bash || []).forEach(e => compile(e, out.bash));
    (data.allowlist || []).forEach(r => {
      try { out.allowlist.push(new RegExp(r, 'i')); }
      catch (e) { console.error('secret-guard: broken allowlist regex "' + r + '": ' + e.message); }
    });
  } catch (e) {
    console.error('secret-guard: unreadable secret-patterns.json: ' + e.message);
  }
  return out;
}

function log(data) {
  try {
    if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });
    const file = path.join(LOG_DIR, new Date().toISOString().slice(0, 10) + '.jsonl');
    fs.appendFileSync(file, JSON.stringify({ ts: new Date().toISOString(), hook: 'secret-guard', ...data }) + '\n');
  } catch {}
}

function checkFilePath(filePath, safetyLevel, instance) {
  if (!filePath) return { blocked: false, pattern: null };
  const fp = filePath.replace(/\\/g, '/');
  const allow = ALLOWLIST.concat(instance ? instance.allowlist : []);
  if (allow.some(p => p.test(fp))) return { blocked: false, pattern: null };
  const threshold = LEVELS[safetyLevel] || 2;
  const patterns = SENSITIVE_FILES.concat(instance ? instance.files : []);
  for (const p of patterns) {
    if (LEVELS[p.level] <= threshold && p.regex.test(fp)) return { blocked: true, pattern: p };
  }
  return { blocked: false, pattern: null };
}

function checkBashCommand(cmd, safetyLevel, instance) {
  if (!cmd) return { blocked: false, pattern: null };
  const allow = ALLOWLIST.concat(instance ? instance.allowlist : []);
  if (allow.some(p => p.test(cmd))) return { blocked: false, pattern: null };
  const threshold = LEVELS[safetyLevel] || 2;
  const patterns = BASH_PATTERNS.concat(instance ? instance.bash : []);
  for (const p of patterns) {
    if (LEVELS[p.level] <= threshold && p.regex.test(cmd)) return { blocked: true, pattern: p };
  }
  return { blocked: false, pattern: null };
}

function check(toolName, toolInput, safetyLevel, instance) {
  const level = safetyLevel || SAFETY_LEVEL;
  if (['Read', 'Edit', 'Write'].includes(toolName)) {
    return checkFilePath(toolInput && toolInput.file_path, level, instance);
  }
  if (toolName === 'Bash') {
    return checkBashCommand(toolInput && toolInput.command, level, instance);
  }
  return { blocked: false, pattern: null };
}

async function main() {
  let input = '';
  for await (const chunk of process.stdin) input += chunk;

  try {
    const data = JSON.parse(input);
    const { tool_name, tool_input, session_id, cwd, permission_mode } = data;

    if (!['Read', 'Edit', 'Write', 'Bash'].includes(tool_name)) {
      return console.log('{}');
    }

    const instance = loadInstancePatterns(process.env.CLAUDE_PROJECT_DIR || cwd);
    const result = check(tool_name, tool_input, SAFETY_LEVEL, instance);

    if (result.blocked) {
      const p = result.pattern;
      const level = p.level in ASK ? p.level : 'high';
      const decision = ASK[level] === true ? 'ask' : 'deny';
      const target = (tool_input && tool_input.file_path) || (tool_input && tool_input.command || '').slice(0, 100);
      log({ decision, id: p.id, priority: p.level, tool: tool_name, target, session_id, cwd, permission_mode });

      const action = { Read: 'read', Edit: 'modify', Write: 'write to', Bash: 'execute' }[tool_name];
      return console.log(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: decision,
          permissionDecisionReason: 'secret-guard [' + p.id + '] Cannot ' + action + ': ' + p.reason
        }
      }));
    }
    console.log('{}');
  } catch (e) {
    log({ decision: 'error', error: e.message });
    console.log('{}');
  }
}

if (require.main === module) {
  main();
} else {
  module.exports = {
    SENSITIVE_FILES, BASH_PATTERNS, ALLOWLIST, LEVELS, SAFETY_LEVEL, ASK,
    check, checkFilePath, checkBashCommand, loadInstancePatterns,
  };
}
