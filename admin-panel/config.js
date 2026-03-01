const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const CONFIG_DIR = path.join(process.env.HOME || '/home/ubuntu', '.openclaw-admin');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');

function isSetupDone() {
  if (!fs.existsSync(CONFIG_FILE)) return false;
  try {
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    return !!(config.credentials && config.credentials.username && config.credentials.passwordHash);
  } catch (e) {
    return false;
  }
}

function loadConfig() {
  let config = {
    port: parseInt(process.env.ADMIN_PORT || '3000', 10),
    sessionSecret: process.env.SESSION_SECRET || crypto.randomBytes(32).toString('hex'),
    credentials: null,
    openclawPort: parseInt(process.env.OPENCLAW_PORT || '18789', 10),
    domain: process.env.ADMIN_DOMAIN || ''
  };

  if (fs.existsSync(CONFIG_FILE)) {
    try {
      const fileConfig = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
      config = { ...config, ...fileConfig };
    } catch (e) {
      console.error('Warning: Could not parse config file:', e.message);
    }
  }

  return config;
}

function saveConfig(config) {
  if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
  }
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), { mode: 0o600 });
}

module.exports = { loadConfig, saveConfig, isSetupDone, CONFIG_DIR, CONFIG_FILE };
