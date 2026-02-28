const path = require('path');
const fs = require('fs');
const bcrypt = require('bcryptjs');

const CONFIG_DIR = path.join(process.env.HOME || '/home/ubuntu', '.openclaw-admin');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');

function loadConfig() {
  let config = {
    port: parseInt(process.env.ADMIN_PORT || '3000', 10),
    sessionSecret: process.env.SESSION_SECRET || 'openclaw-admin-default-secret',
    credentials: {
      username: 'admin',
      passwordHash: bcrypt.hashSync('OpenClaw2026!', 10)
    },
    openclawPort: parseInt(process.env.OPENCLAW_PORT || '18789', 10),
    domain: process.env.ADMIN_DOMAIN || 'mayra-content.comuhack.com'
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

module.exports = { loadConfig, saveConfig, CONFIG_DIR, CONFIG_FILE };
