// Run from server_project after scripts/build.ps1 or scripts/build.sh.
// Requires Playwright; AICHAT_PLAYWRIGHT_PATH may point to a shared installation.
const { chromium } = require(process.env.AICHAT_PLAYWRIGHT_PATH || 'playwright')
const { spawn, execFileSync } = require('node:child_process')
const { randomBytes } = require('node:crypto')
const fs = require('node:fs/promises')
const path = require('node:path')
const os = require('node:os')
const net = require('node:net')
const assert = require('node:assert/strict')

async function main() {
  const root = path.resolve(__dirname, '..')
  const data = await fs.mkdtemp(path.join(os.tmpdir(), 'aichat-admin-smoke-'))
  const reserve = net.createServer()
  await new Promise(resolve => reserve.listen(0, '127.0.0.1', resolve))
  const port = reserve.address().port
  await new Promise(resolve => reserve.close(resolve))
  const base = `http://127.0.0.1:${port}`
  const admin = randomBytes(32).toString('hex')
  const service = spawn('java', ['-jar', path.join(root, 'build/libs/aichat-backend.jar')], {
    cwd: root, windowsHide: true,
    env: { ...process.env, AICHAT_DATA_DIR: data, AICHAT_PORT: String(port), AICHAT_BIND_ADDRESS: '127.0.0.1',
      AICHAT_TOKEN_PEPPER: randomBytes(32).toString('hex'), AICHAT_REQUIRE_TOKEN_PEPPER: 'true',
      AICHAT_BOOTSTRAP_ADMIN_TOKEN: admin, AICHAT_FEATURE_COMMENTS: 'true', AICHAT_FEATURE_CHARACTERS: 'true',
      AICHAT_FEATURE_STORIES: 'true', AICHAT_FEATURE_ADMIN_PUBLISH: 'true', AICHAT_INVITE_REQUIRED: 'true' },
  })
  let logs = '', browser
  service.stdout.on('data', chunk => { logs += chunk })
  service.stderr.on('data', chunk => { logs += chunk })
  const api = async (url, options = {}) => {
    const response = await fetch(base + url, options)
    assert.equal(response.ok, true, `HTTP ${response.status} on ${url}`)
    const json = await response.json()
    return json.data ?? json
  }
  try {
    let ready = false
    for (let n = 0; n < 120; n++) {
      try { await api('/api/health'); ready = true; break } catch {}
      if (service.exitCode !== null) throw new Error('Test server exited before readiness')
      await new Promise(resolve => setTimeout(resolve, 250))
    }
    assert.ok(ready, 'Test server readiness timeout')
    browser = await chromium.launch({ headless: true, ...(process.env.AICHAT_BROWSER_PATH ? { executablePath: process.env.AICHAT_BROWSER_PATH } : {}) })
    const page = await browser.newPage({ viewport: { width: 1440, height: 1080 } })
    const errors = []
    page.on('pageerror', error => errors.push(error.message))
    page.on('dialog', dialog => dialog.accept())
    await page.goto(base)
    await page.getByLabel('管理员令牌').fill('invalid')
    await page.getByRole('button', { name: '验证并登录' }).click()
    await page.getByRole('alert').waitFor()
    assert.equal(await page.getByRole('heading', { name: '内容管理台' }).count(), 1)
    await page.getByLabel('管理员令牌').fill(admin)
    await page.getByRole('button', { name: '验证并登录' }).click()
    await page.getByRole('heading', { name: '服务概览', exact: true }).waitFor()
    await page.getByRole('button', { name: '故事线', exact: true }).click()
    await page.getByLabel('故事 ID', { exact: true }).fill('browser-story')
    await page.getByLabel('标题', { exact: true }).first().fill('星港来信')
    await page.getByLabel('作者', { exact: true }).first().fill('AiChat')
    await page.getByLabel('简介', { exact: true }).first().fill('一座星港，一封迟到的信。')
    console.log('UI: editing first story')
    await page.getByLabel('记忆点 1', { exact: true }).fill('你在星港中收到了一封来信。')
    await page.getByRole('button', { name: '保存草稿', exact: true }).click()
    await page.getByText('草稿已保存。', { exact: true }).waitFor()
    await page.getByRole('button', { name: '校验', exact: true }).click()
    await page.getByText('校验通过。', { exact: true }).waitFor()
    await page.getByRole('button', { name: '发布故事', exact: true }).click()
    await page.getByText('故事已发布，读者可以下载。', { exact: true }).waitFor()
    const first = await api('/api/stories/browser-story/download')
    assert.equal(first.title, '星港来信')
    assert.equal(first.version, 1)
    await page.getByRole('button', { name: '编辑', exact: true }).click()
    await page.getByLabel('版本', { exact: true }).first().waitFor({ state: 'visible' })
    await page.waitForFunction(() => { const inputs = [...document.querySelectorAll('input[type=number]')]; return inputs.some(input => input.value === '2' && input.offsetParent !== null && !input.closest('fieldset').disabled) })
    console.log('UI: editing next story version')
    await page.getByLabel('版本', { exact: true }).first().fill('2')
    await page.getByLabel('记忆点 1', { exact: true }).fill('你发现来信来自另一座星港。')
    await page.getByRole('button', { name: '发布故事', exact: true }).click()
    await page.getByText('故事已发布，读者可以下载。', { exact: true }).waitFor()
    assert.equal((await api('/api/stories/browser-story/download')).version, 2)

    await page.getByRole('button', { name: '角色卡', exact: true }).click()
    await page.getByLabel('角色卡 ID', { exact: true }).fill('browser-character')
    await page.getByLabel('标题', { exact: true }).last().fill('星港邮差')
    await page.getByLabel('作者', { exact: true }).last().fill('AiChat')
    const pack = execFileSync(process.env.AICHAT_PYTHON || 'python', ['-c', "import io,zipfile,sys; b=io.BytesIO(); z=zipfile.ZipFile(b,'w'); z.writestr('Courier/Profile.json','{\"name\":\"Courier\"}'); z.writestr('Courier/Prompt.txt','You are a courier.'); z.close(); sys.stdout.buffer.write(b.getvalue())"], { windowsHide: true })
    await page.getByLabel('角色包 ZIP', { exact: true }).setInputFiles({ name: 'courier.zip', mimeType: 'application/zip', buffer: pack })
    await page.getByRole('button', { name: '发布角色卡', exact: true }).click()
    await page.getByText('角色包已发布。', { exact: true }).waitFor()
    const downloaded = await fetch(`${base}/api/characters/browser-character/download`)
    assert.deepEqual(Buffer.from(await downloaded.arrayBuffer()), pack)

    await page.getByRole('button', { name: '用户邀请', exact: true }).click()
    await page.getByRole('button', { name: '生成邀请码', exact: true }).click()
    await page.locator('.result-box code').waitFor()
    const code = await page.locator('.result-box code').innerText()
    const session = await api('/api/invite/exchange', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ inviteCode: code, deviceId: 'browser-device', label: '测试读者' }) })
    const auth = { Authorization: `Bearer ${session.accessToken}`, 'Content-Type': 'application/json', 'Idempotency-Key': 'browser-comment' }
    const comment = await api('/api/characters/browser-character/comments', { method: 'POST', headers: auth, body: JSON.stringify({ body: '邮差的故事很有趣。' }) })
    assert.equal(comment.status, 'PENDING')
    await page.getByRole('button', { name: '评论审核', exact: true }).click()
    const comments = page.getByRole('heading', { name: '评论管理', exact: true }).locator('xpath=ancestor::section[1]')
    await comments.getByRole('button', { name: '刷新', exact: true }).click()
    await page.getByText('邮差的故事很有趣。', { exact: true }).waitFor()
    await comments.getByRole('button', { name: '通过', exact: true }).click()
    await page.getByText('当前没有待审核评论', { exact: true }).waitFor()
    assert.equal((await api('/api/characters/browser-character/comments')).items[0].body, '邮差的故事很有趣。')
    const refreshed = await api('/api/auth/refresh', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refreshToken: session.refreshToken }) })
    assert.ok(refreshed.accessToken)
    await page.getByRole('button', { name: '角色卡', exact: true }).click()
    await fs.mkdir(path.join(root, 'build/qa'), { recursive: true })
    await page.screenshot({ path: path.join(root, 'build/qa/admin-desktop.png'), fullPage: true })
    await page.setViewportSize({ width: 390, height: 844 })
    await page.screenshot({ path: path.join(root, 'build/qa/admin-mobile.png'), fullPage: true })
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'Mobile page overflows horizontally')
    assert.deepEqual(errors, [], 'Browser runtime errors')
    console.log('PASS: verified login, story draft/publish/update, ZIP upload/download, invite/exchange/refresh, comment moderation, desktop/mobile layout')
  } catch (error) {
    console.error(error.message)
    if (browser) {
      await fs.mkdir(path.join(root,'build/qa'),{recursive:true})
      const page=browser.contexts()[0]?.pages()[0]
      if (page) { await page.screenshot({path:path.join(root,'build/qa/admin-failure.png'),fullPage:true}); await fs.writeFile(path.join(root,'build/qa/admin-failure.html'),await page.content()) }
    }
    // Startup logs contain no generated tokens; omit logs once the UI is running.
    if (!browser) console.error(logs.slice(-3000))
    process.exitCode = 1
  } finally {
    if (browser) await browser.close()
    if (service.exitCode === null) { service.kill(); await new Promise(resolve => service.once('exit', resolve)) }
    await fs.rm(data, { recursive: true, force: true })
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1 })
