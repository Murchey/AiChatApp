// Build the JAR first, then run: node scripts/account-smoke.cjs
// Uses a temporary database and local port; never touches the configured server.
const { spawn } = require('node:child_process')
const { randomBytes } = require('node:crypto')
const fs = require('node:fs/promises')
const path = require('node:path')
const os = require('node:os')
const net = require('node:net')

async function main() {
  const root = path.resolve(__dirname, '..')
  const data = await fs.mkdtemp(path.join(os.tmpdir(), 'aichat-account-smoke-'))
  const reserve = net.createServer()
  await new Promise(resolve => reserve.listen(0, '127.0.0.1', resolve))
  const port = reserve.address().port
  await new Promise(resolve => reserve.close(resolve))
  const endpoint = `http://127.0.0.1:${port}`
  const service = spawn('java', ['-jar', path.join(root, 'build/libs/aichat-backend.jar')], {
    cwd: root, windowsHide: true,
    env: { ...process.env, AICHAT_DATA_DIR: data, AICHAT_PORT: String(port),
      AICHAT_BIND_ADDRESS: '127.0.0.1', AICHAT_REQUIRE_TOKEN_PEPPER: 'true',
      AICHAT_TOKEN_PEPPER: randomBytes(32).toString('hex'),
      AICHAT_BOOTSTRAP_ADMIN_TOKEN: randomBytes(32).toString('hex'),
      AICHAT_FEATURE_ACCOUNT_AUTH: 'true', AICHAT_INVITE_REQUIRED: 'true' },
  })
  let logs = ''
  service.stdout.on('data', chunk => { logs += chunk })
  service.stderr.on('data', chunk => { logs += chunk })
  const exited = new Promise(resolve => service.once('close', resolve))
  try {
    let ready = false
    for (let n = 0; n < 120; n++) {
      if (service.exitCode !== null) throw new Error('Test server exited before readiness')
      try {
        const response = await fetch(endpoint + '/api/health')
        if (response.ok) { ready = true; break }
      } catch {}
      await new Promise(resolve => setTimeout(resolve, 250))
    }
    if (!ready) throw new Error('Test server readiness timeout')
    const args = ['test', '--no-pub', 'test/integration/backend_account_live_test.dart']
    const isWindows = process.platform === 'win32'
    const test = spawn(isWindows ? 'cmd.exe' : 'flutter', isWindows ? ['/d', '/s', '/c', 'flutter', ...args] : args, {
      cwd: path.dirname(root), windowsHide: true, stdio: 'inherit',
      env: { ...process.env, AICHAT_TEST_BACKEND: endpoint },
    })
    const code = await new Promise((resolve, reject) => { test.once('error', reject); test.once('close', resolve) })
    if (code !== 0) throw new Error(`Flutter account integration failed (${code})`)
    console.log('PASS: Flutter registration, restored session, login, refresh and logout against local JAR')
  } catch (error) {
    console.error(logs.slice(-6000))
    throw error
  } finally {
    if (service.exitCode === null) service.kill()
    await exited
    await fs.rm(data, { recursive: true, force: true })
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1 })
