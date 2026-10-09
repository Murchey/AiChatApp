import React, { useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import {
  Button,
  Card,
  CardBody,
  Chip,
  Divider,
  Input,
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
  ModalHeader,
  Navbar,
  NavbarBrand,
  NavbarContent,
  Select,
  SelectItem,
  Spinner,
  Tab,
  Tabs,
  Textarea,
  useDisclosure,
} from '@heroui/react'
import './styles.css'

const tokenKey = 'aichat-admin-token'

function unwrap(value) {
  return value?.data ?? value
}

function apiError(value) {
  return value?.error?.message || value?.message || '请求失败，请检查服务状态和管理令牌'
}

function useApi(token) {
  return async (path, options = {}) => {
    const headers = { Accept: 'application/json', ...(options.headers || {}) }
    if (token) headers['X-Admin-Token'] = token
    if (options.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json'
    const response = await fetch(path, { ...options, headers })
    const text = await response.text()
    let payload = {}
    try { payload = text ? JSON.parse(text) : {} } catch { payload = { message: text } }
    if (!response.ok) throw new Error(apiError(payload))
    return payload
  }
}

function Metric({ label, value, hint, tone = 'default' }) {
  return <Card className={`metric metric-${tone}`}><CardBody>
    <span className="metric-label">{label}</span>
    <strong>{value}</strong>
    <span className="metric-hint">{hint}</span>
  </CardBody></Card>
}

function Login({ onLogin }) {
  const [value, setValue] = useState('')
  return <main className="login-page"><Card className="login-card"><CardBody>
    <div className="brand-mark">AI</div>
    <h1>AiChat 管理面板</h1>
    <p className="muted">使用服务器 bootstrap 管理令牌登录。令牌只保存在当前浏览器会话。</p>
    <Input label="管理员令牌" type="password" value={value} onValueChange={setValue} onKeyDown={e => e.key === 'Enter' && onLogin(value)} />
    <Button color="primary" className="full-button" onPress={() => onLogin(value)} isDisabled={!value.trim()}>进入面板</Button>
  </CardBody></Card></main>
}

function StoryPublish({ api, onDone }) {
  const [json, setJson] = useState('')
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  async function publish() {
    let document
    try { document = JSON.parse(json) } catch { setMessage('JSON 格式无效'); return }
    setBusy(true); setMessage('')
    try { await api('/api/admin/stories/publish', { method: 'POST', body: JSON.stringify(document) }); setMessage('故事已发布'); setJson(''); onDone?.() }
    catch (error) { setMessage(error.message) } finally { setBusy(false) }
  }
  return <Card><CardBody className="stack">
    <div className="section-heading"><div><h2>快速发布故事</h2><p className="muted">服务端会再次校验版本、章节和记忆点 ID。</p></div><Chip color="warning" variant="flat">管理员操作</Chip></div>
    <Textarea minRows={12} label="故事 JSON" placeholder={'{"schemaVersion":1,"storyId":"example-world",...}'} value={json} onValueChange={setJson} />
    {message && <p className="inline-message">{message}</p>}
    <Button color="primary" onPress={publish} isLoading={busy} isDisabled={!json.trim()}>校验并发布</Button>
  </CardBody></Card>
}

function InvitePanel({ api }) {
  const [role, setRole] = useState('USER'); const [uses, setUses] = useState('1'); const [expires, setExpires] = useState('24');
  const [result, setResult] = useState(''); const [busy, setBusy] = useState(false)
  async function create() {
    setBusy(true); setResult('')
    try { const data = unwrap(await api('/api/admin/invites', { method: 'POST', body: JSON.stringify({ maxUses: Number(uses), expiresInHours: Number(expires), role }) })); setResult(data.code || '邀请码已创建') }
    catch (error) { setResult(error.message) } finally { setBusy(false) }
  }
  return <Card><CardBody className="stack"><div className="section-heading"><div><h2>生成设备邀请码</h2><p className="muted">邀请码角色由服务器决定，客户端不能自行提升权限。</p></div></div>
    <div className="form-grid"><Select label="角色" selectedKeys={[role]} onSelectionChange={keys => setRole([...keys][0])}><SelectItem key="USER">普通用户</SelectItem><SelectItem key="ADMIN">管理员</SelectItem></Select><Input label="可用次数" type="number" value={uses} onValueChange={setUses} /><Input label="有效小时" type="number" value={expires} onValueChange={setExpires} /></div>
    <Button onPress={create} color="secondary" isLoading={busy}>生成邀请码</Button>{result && <div className="result-box">{result}</div>}
  </CardBody></Card>
}

function Comments({ api }) {
  const [items, setItems] = useState([]); const [busy, setBusy] = useState(false); const [story, setStory] = useState(''); const [message, setMessage] = useState('')
  async function load() { setBusy(true); setMessage(''); try { const data = unwrap(await api('/api/admin/comments?status=PENDING&limit=50')); setItems(data.items || []) } catch (error) { setMessage(error.message) } finally { setBusy(false) } }
  async function moderate(id, status) { try { await api(`/api/admin/comments/${id}/moderate`, { method: 'POST', body: JSON.stringify({ status }) }); setItems(items.filter(item => item.id !== id)) } catch (error) { setMessage(error.message) } }
  useEffect(() => { load() }, [])
  const filtered = useMemo(() => story ? items.filter(item => item.storyId === story) : items, [items, story])
  return <Card><CardBody className="stack"><div className="section-heading"><div><h2>评论审核</h2><p className="muted">评论功能关闭时服务端会返回 FEATURE_DISABLED。</p></div><Button size="sm" variant="flat" onPress={load} isLoading={busy}>刷新</Button></div>
    <Input label="按故事 ID 筛选" value={story} onValueChange={setStory} />{message && <p className="inline-message">{message}</p>}
    {busy && !items.length ? <Spinner /> : filtered.length === 0 ? <p className="empty">暂无待审核评论</p> : filtered.map(item => <div className="comment-row" key={item.id}><div><strong>{item.body}</strong><p className="muted">{item.storyId} · {item.createdAt}</p></div><div className="row-actions"><Button size="sm" color="success" variant="flat" onPress={() => moderate(item.id, 'VISIBLE')}>通过</Button><Button size="sm" color="danger" variant="flat" onPress={() => moderate(item.id, 'HIDDEN')}>隐藏</Button></div></div>)}
  </CardBody></Card>
}

function Dashboard({ token, onLogout }) {
  const api = useApi(token); const [health, setHealth] = useState(null); const [version, setVersion] = useState(null); const [stories, setStories] = useState([]); const [audit, setAudit] = useState([]); const [error, setError] = useState(''); const [active, setActive] = useState('overview');
  const { isOpen, onOpen, onOpenChange } = useDisclosure()
  async function refresh() { setError(''); try { const [h, v, s, a] = await Promise.all([api('/api/health'), api('/api/version'), api('/api/admin/stories?limit=20'), api('/api/admin/audit-logs?limit=20')]); setHealth(unwrap(h)); setVersion(unwrap(v)); setStories(unwrap(s)?.items || []); setAudit(unwrap(a)?.items || []) } catch (e) { setError(e.message) } }
  useEffect(() => { refresh() }, [])
  if (!health && !error) return <div className="loading-page"><Spinner label="连接服务器中…" /></div>
  return <div className="app-shell"><Navbar maxWidth="full" className="topbar"><NavbarBrand><div className="mini-mark">AI</div><span className="brand-title">AiChat <span>Admin</span></span></NavbarBrand><NavbarContent justify="end"><Chip color={health?.status === 'UP' ? 'success' : 'danger'} variant="flat">{health?.status === 'UP' ? '服务正常' : '连接异常'}</Chip><Button size="sm" variant="flat" onPress={refresh}>刷新</Button><Button size="sm" variant="light" onPress={onOpen}>退出</Button></NavbarContent></Navbar>
    <main className="content"><header className="hero"><div><p className="eyebrow">SERVER CONTROL CENTER</p><h1>你好，管理员</h1><p className="muted">在一个地方查看服务状态、故事目录和审核队列。</p></div><div className="server-pill"><span>API</span><strong>{version?.apiVersion || '—'}</strong><small>{version?.serverVersion || '未连接'}</small></div></header>
      {error && <Card className="error-card"><CardBody>{error}<Button size="sm" variant="flat" onPress={refresh}>重试</Button></CardBody></Card>}
      <Tabs selectedKey={active} onSelectionChange={key => setActive(String(key))} color="primary" variant="underlined" className="tabs"><Tab key="overview" title="概览"><div className="stack tab-content"><div className="metrics"><Metric label="服务状态" value={health?.status || '—'} hint="/api/health" tone="success" /><Metric label="故事草稿" value={stories.length} hint="最近 20 条" /><Metric label="审计事件" value={audit.length} hint="最近 20 条" /><Metric label="功能模块" value={version ? Object.values(version.features || {}).filter(Boolean).length : '—'} hint="已启用" tone="primary" /></div><div className="two-columns"><Card><CardBody className="stack"><div className="section-heading"><div><h2>最近故事草稿</h2><p className="muted">管理员故事目录</p></div><Button size="sm" variant="flat" onPress={() => setActive('stories')}>查看全部</Button></div>{stories.length ? stories.map(item => <div className="list-row" key={item.story_id || item.storyId}><div><strong>{item.story_id || item.storyId}</strong><p className="muted">{item.status} · revision {item.revision}</p></div><Chip size="sm" variant="flat">{item.base_version ?? item.baseVersion ?? 0}</Chip></div>) : <p className="empty">暂无草稿</p>}</CardBody></Card><Card><CardBody className="stack"><div className="section-heading"><div><h2>最近审计</h2><p className="muted">管理员操作记录</p></div></div>{audit.length ? audit.slice(0, 6).map(item => <div className="list-row" key={item.id}><div><strong>{item.action}</strong><p className="muted">{item.resource_type || item.resourceType} · {item.created_at || item.createdAt}</p></div></div>) : <p className="empty">暂无审计记录</p>}</CardBody></Card></div></div></Tab><Tab key="stories" title="故事发布"><div className="stack tab-content"><StoryPublish api={api} onDone={refresh} /><InvitePanel api={api} /></div></Tab><Tab key="comments" title="评论审核"><div className="tab-content"><Comments api={api} /></div></Tab><Tab key="settings" title="服务配置"><Card><CardBody className="stack tab-content"><h2>功能开关</h2>{Object.entries(version?.features || {}).map(([name, enabled]) => <div className="list-row" key={name}><span>{name}</span><Chip color={enabled ? 'success' : 'default'} variant="flat">{enabled ? '已启用' : '已关闭'}</Chip></div>)}<Divider /><p className="muted">配置通过服务器环境变量管理，面板不会修改密钥或直接写入数据库。</p></CardBody></Card></Tab></Tabs>
    </main><Modal isOpen={isOpen} onOpenChange={onOpenChange}><ModalContent><ModalHeader>退出管理面板？</ModalHeader><ModalBody>退出后将清除当前浏览器会话中的管理令牌。</ModalBody><ModalFooter><Button variant="light" onPress={onOpenChange}>取消</Button><Button color="danger" onPress={onLogout}>退出</Button></ModalFooter></ModalContent></Modal></div>
}

function App() { const [token, setToken] = useState(() => sessionStorage.getItem(tokenKey) || ''); const login = value => { sessionStorage.setItem(tokenKey, value.trim()); setToken(value.trim()) }; const logout = () => { sessionStorage.removeItem(tokenKey); setToken('') }; return token ? <Dashboard token={token} onLogout={logout} /> : <Login onLogin={login} /> }

createRoot(document.getElementById('root')).render(<App />)
