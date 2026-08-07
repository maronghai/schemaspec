#!/usr/bin/env node

const https = require('https');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const version = require('../package.json').version;
const platform = process.platform;
const arch = process.arch;

// Map Node.js platform/arch to release assets
const platformMap = {
  linux: 'linux',
  darwin: 'macos',
  win32: 'windows'
};

const archMap = {
  x64: 'x86_64',
  arm64: 'aarch64'
};

const os = platformMap[platform];
const cpu = archMap[arch];

if (!os || !cpu) {
  console.error(`Unsupported platform: ${platform}/${arch}`);
  process.exit(1);
}

const ext = platform === 'win32' ? '.zip' : '.tar.gz';
const binary = platform === 'win32' ? 'rune.exe' : 'rune';
const assetName = `rune-${os}-${cpu}${ext}`;
const url = `https://github.com/rune-lang/rune/releases/download/v${version}/${assetName}`;

const binDir = path.join(__dirname, '..', 'bin');
const binaryPath = path.join(binDir, binary);

// Create bin directory
if (!fs.existsSync(binDir)) {
  fs.mkdirSync(binDir, { recursive: true });
}

console.log(`Downloading rune v${version} for ${os}/${cpu}...`);

const download = (url, dest) => {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, (response) => {
      if (response.statusCode === 302 || response.statusCode === 301) {
        download(response.headers.location, dest).then(resolve).catch(reject);
        return;
      }
      response.pipe(file);
      file.on('finish', () => {
        file.close();
        resolve();
      });
    }).on('error', (err) => {
      fs.unlink(dest, () => {});
      reject(err);
    });
  });
};

const extract = async (archive) => {
  if (platform === 'win32') {
    execSync(`7z x "${archive}" -o"${binDir}" -y`, { stdio: 'inherit' });
  } else {
    execSync(`tar xzf "${archive}" -C "${binDir}"`, { stdio: 'inherit' });
  }
  fs.unlinkSync(archive);
};

const main = async () => {
  const archive = path.join(binDir, assetName);
  await download(url, archive);
  await extract(archive);
  fs.chmodSync(binaryPath, 0o755);
  console.log(`Installed rune v${version} to ${binaryPath}`);
};

main().catch((err) => {
  console.error('Installation failed:', err.message);
  process.exit(1);
});
