import React, { useCallback, useEffect, useId, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import './styles.css'

const tokenKey = 'aichat-admin-token'
const statuses = { DRAFT: '草稿', PENDING_REVIEW: '待发布', PUBLISHED: '已发布', ARCHIVED: '已归档', PENDING: '待审核', VISIBLE: '已通过', HIDDEN: '已隐藏', DELETED: '已删除' }
const labels = { stories: '故事线', characters: '角色卡', comments: '评论', accountAuth: '账号注册与登录', adminPublish: '内容发布', sync: '加密同步', llmRelay: '模型中继' }
const date = v => v ? new Date(v).toLocaleString('zh-CN') : '—'
const id = () => globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`
const rid = encodeURIComponent
function createApi(token) {
  return async (path, options = {}) => {
    const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 15000)
    try {
      const response = await fetch(path, { ...options, signal: controller.signal, headers: { Accept: 'application/json', ...(token ? { 'X-Admin-Token': token } : {}), ...(typeof options.body === 'string' ? { 'Content-Type': 'application/json' } : {}), ...options.headers } })
      let payload
      try { payload = JSON.parse(await response.text()) } catch { throw new Error(`接口返回非 JSON（HTTP ${response.status}），请检查服务地址与反向代理`) }
      if (!response.ok) {
        const details = payload.error?.details?.map(item => `${item.field}: ${item.reason || item.message}`).join('；')
        const error = new Error([payload.error?.message || `请求失败（HTTP ${response.status}）`, details, payload.error?.requestId ? `请求编号：${payload.error.requestId}` : ''].filter(Boolean).join(' · '))
        error.code = payload.error?.code; throw error
      }
      return payload?.data ?? payload
    } catch (error) {
      if (error.name === 'AbortError') throw new Error('请求超时，请检查服务器是否运行')
      if (error instanceof TypeError) throw new Error('无法连接服务器，请检查网络和服务地址')
      throw error
    } finally { clearTimeout(timer) }
  }
}
function Button({ children, busy, variant = '', ...props }) { return <button className={`button ${variant}`} {...props} disabled={props.disabled || busy}>{busy ? '处理中…' : children}</button> }
function Field({ label, textarea, children, ...props }) {
  const fieldId = useId()
  return <div className="field"><label htmlFor={fieldId}>{label}</label>{children ? React.cloneElement(children, { id: fieldId }) : textarea ? <textarea id={fieldId} {...props} /> : <input id={fieldId} {...props} />}</div>
}
function Notice({ children, error }) { return children ? <div role={error ? 'alert' : 'status'} className={`notice ${error ? 'error' : ''}`}>{children}</div> : null }
function Badge({ status }) { return <span className={`badge ${status}`}>{statuses[status] || status}</span> }
function Card({ title, hint, actions, children }) { return <section className="card"><header className="section-heading"><div><h2>{title}</h2>{hint && <p className="muted">{hint}</p>}</div>{actions}</header>{children}</section> }
function usePage(api, path, enabled = true) {
  const [page, setPage] = useState({ items: [], hasMore: false }), [busy, setBusy] = useState(false), [error, setError] = useState('')
  const generation = useRef(0)
  const load = useCallback(async (cursor = null) => {
    const current = ++generation.current; setBusy(true); setError('')
    try {
      const data = await api(`${path}${path.includes('?') ? '&' : '?'}limit=20${cursor ? `&cursor=${rid(cursor)}` : ''}`)
      if (current === generation.current) setPage(previous => ({ ...data, items: cursor ? [...previous.items, ...(data.items || [])] : data.items || [] }))
    } catch (e) { if (current === generation.current) setError(e.message) }
    finally { if (current === generation.current) setBusy(false) }
  }, [api, path])
  useEffect(() => { setPage({ items: [], hasMore: false }); setError(''); if (enabled) load(); return () => { generation.current++ } }, [load, enabled])
  return { ...page, busy, error, load }
}
function PageEnd({ page }) { return <><Notice error>{page.error}</Notice>{page.hasMore && <Button busy={page.busy} onClick={() => page.load(page.nextCursor)}>加载更多</Button>}</> }
function Login({ onLogin }) {
  const [value, setValue] = useState(''), [busy, setBusy] = useState(false), [error, setError] = useState('')
  async function submit(e) { e.preventDefault(); setBusy(true); setError(''); try { await createApi(value.trim())('/api/admin/session'); onLogin(value.trim()) } catch (e) { setError(e.message) } finally { setBusy(false) } }
  return <main className="login-page"><form className="card login-card" onSubmit={submit}><div className="brand-mark">Ai</div><p className="eyebrow">AICHAT CONTENT COMMUNITY</p><h1>内容管理台</h1><p className="muted">发布角色与故事，让读者参与讨论。</p><Field label="管理员令牌" type="password" autoComplete="off" value={value} onChange={e => setValue(e.target.value)} required /><Notice error>{error}</Notice><Button type="submit" variant="primary" busy={busy} disabled={!value.trim()}>验证并登录</Button><p className="muted">令牌只保存在当前浏览器会话中。</p></form></main>
}
const newStory = () => ({ schemaVersion: 1, storyId: '', version: 1, title: '', author: '', summary: '', tags: [], chapters: [{ id: id(), title: '第一章', order: 1, memories: [{ id: id(), order: 1, content: '' }] }] })
function StoryEditor({ api, selected, enabled, onSaved }) {
  const [document, setDocument] = useState(newStory), [draft, setDraft] = useState(null), [raw, setRaw] = useState(null), [dirty, setDirty] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState(''), [message, setMessage] = useState('')
  const publishKey = useRef(null)
  useEffect(() => { const guard = e => { if (dirty) { e.preventDefault(); e.returnValue = '' } }; window.addEventListener('beforeunload', guard); return () => window.removeEventListener('beforeunload', guard) }, [dirty])
  async function open(storyId) {
    if (dirty && !window.confirm('有未保存的修改，确认放弃并加载？')) return
    setBusy(true); setError(''); setMessage('')
    try {
      let next
      try { next = await api(`/api/admin/stories/${rid(storyId)}/draft`) }
      catch (e) { if (e.code !== 'NOT_FOUND') throw e; const live = await api(`/api/stories/${rid(storyId)}`); next = await api('/api/admin/stories', { method: 'POST', body: JSON.stringify({ document: { ...live, version: live.version + 1 }, baseVersion: live.version }) }) }
      setDraft(next); setDocument(next.status === 'PUBLISHED' ? { ...next.document, version: next.document.version + 1 } : next.document); setRaw(null); setDirty(next.status === 'PUBLISHED'); publishKey.current = null
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }
  useEffect(() => { if (selected?.storyId) open(selected.storyId) }, [selected])
  function change(next) { setDocument(next); setDirty(true); setMessage(''); publishKey.current = null }
  const patch = (key, value) => change({ ...document, [key]: value })
  const chapter = (index, next) => change({ ...document, chapters: document.chapters.map((c, n) => n === index ? next : c) })
  function reset() { if (dirty && !window.confirm('确认放弃未保存的修改并新建？')) return; setDocument(newStory()); setDraft(null); setRaw(null); setDirty(false); setError(''); setMessage(''); publishKey.current = null }
  async function save(action) {
    setBusy(true); setError(''); setMessage('')
    try {
      const content = raw === null ? { ...document, tags: (document.tags || []).filter(Boolean) } : JSON.parse(raw)
      let current = draft
      if (!current || dirty) {
        current = await api(current ? `/api/admin/stories/${rid(current.storyId)}/draft` : '/api/admin/stories', { method: current ? 'PUT' : 'POST', body: JSON.stringify(current ? { document: content, revision: current.revision } : { document: content, baseVersion: 0 }) })
        setDraft(current); setDocument(current.document); setRaw(null); setDirty(false)
      }
      if (action === 'publish') {
        if (current.status !== 'PENDING_REVIEW') { current = await api(`/api/admin/stories/${rid(current.storyId)}/submit`, { method: 'POST', body: JSON.stringify({ revision: current.revision }) }); setDraft(current) }
        publishKey.current ||= id()
        await api(`/api/admin/stories/${rid(current.storyId)}/publish`, { method: 'POST', headers: { 'Idempotency-Key': publishKey.current }, body: JSON.stringify({ revision: current.revision, baseVersion: current.baseVersion }) })
        setDraft(await api(`/api/admin/stories/${rid(current.storyId)}/draft`)); publishKey.current = null
      } else if (action === 'validate') setDraft(await api(`/api/admin/stories/${rid(current.storyId)}/validate`, { method: 'POST', body: JSON.stringify({ revision: current.revision }) }))
      setMessage(action === 'publish' ? '故事已发布，读者可以下载。' : action === 'validate' ? '校验通过。' : '草稿已保存。'); onSaved()
    } catch (e) { setError(e.message) } finally { setBusy(false) }
  }
  async function importFile(file) {
    if (!file || (dirty && !window.confirm('确认用文件替换未保存的内容？'))) return
    try { if (file.size > 1048576) throw new Error('故事文件不能超过 1MB'); const value = JSON.parse(await file.text()); if (!value || !Array.isArray(value.chapters) || !value.storyId) throw new Error('需要包含 storyId 和 chapters 的故事包'); if (draft && value.storyId !== draft.storyId) throw new Error('已有草稿不能改变故事 ID，请先新建'); change(value); setRaw(null); setError('') } catch (e) { setError(e.message) }
  }
  function toggleRaw() { if (raw === null) setRaw(JSON.stringify(document, null, 2)); else { try { const value = JSON.parse(raw); if (!Array.isArray(value.chapters)) throw new Error('chapters 必须是数组'); setDocument(value); setRaw(null); setError('') } catch (e) { setError(e.message) } } }
  const locked = !enabled || busy || draft?.status === 'ARCHIVED'
  return <Card title={draft ? `编辑故事 · ${draft.storyId}` : '新建故事线'} hint="保存草稿后校验与发布，章节和记忆点可以直接编辑。" actions={<Button onClick={reset} disabled={busy}>新建</Button>}>
    {draft && <p><Badge status={draft.status} /> <span className="muted">修订 {draft.revision} · 基础版本 {draft.baseVersion}{dirty ? ' · 未保存' : ''}</span></p>}
    {!enabled && <Notice>内容发布未启用，请设置 AICHAT_FEATURE_ADMIN_PUBLISH=true。</Notice>}
    <fieldset disabled={locked}><div className="toolbar"><Field label="导入故事 JSON" type="file" accept=".json,application/json" onChange={e => { importFile(e.target.files[0]); e.target.value = '' }} /><Button onClick={toggleRaw}>{raw === null ? '编辑 JSON' : '返回表单'}</Button></div>
      {raw !== null ? <Field label="完整故事 JSON" textarea className="code-input" rows={20} value={raw} onChange={e => { setRaw(e.target.value); setDirty(true); publishKey.current = null }} /> : <>
        <div className="form-grid"><Field label="故事 ID" placeholder="如 moon-city" value={document.storyId || ''} disabled={Boolean(draft)} onChange={e => patch('storyId', e.target.value)} /><Field label="版本" type="number" min="1" value={document.version || 1} onChange={e => patch('version', Number(e.target.value))} /><Field label="标题" value={document.title || ''} onChange={e => patch('title', e.target.value)} /><Field label="作者" value={document.author || ''} onChange={e => patch('author', e.target.value)} /></div>
        <Field label="简介" textarea rows={3} value={document.summary || ''} onChange={e => patch('summary', e.target.value)} /><Field label="标签（逗号分隔）" value={(document.tags || []).join(',')} onChange={e => patch('tags', e.target.value.split(/[,，]/).map(s => s.trim()))} />
        {(document.chapters || []).map((c, index) => <section className="chapter" key={index}><header className="section-heading"><h3>章节 {index + 1}</h3><Button disabled={document.chapters.length === 1} onClick={() => change({ ...document, chapters: document.chapters.filter((_, n) => n !== index).map((c, n) => ({ ...c, order: n + 1 })) })}>删除章节</Button></header><div className="form-grid"><Field label="章节标题" value={c.title || ''} onChange={e => chapter(index, { ...c, title: e.target.value })} /><Field label="章节 ID" value={c.id || ''} onChange={e => chapter(index, { ...c, id: e.target.value })} /></div>
          {(c.memories || []).map((m, n) => <div className="memory" key={n}><Field label={`记忆点 ${n + 1}`} textarea rows={3} value={m.content || ''} onChange={e => chapter(index, { ...c, memories: c.memories.map((m, j) => j === n ? { ...m, content: e.target.value } : m) })} /><Button disabled={c.memories.length === 1} onClick={() => chapter(index, { ...c, memories: c.memories.filter((_, j) => j !== n).map((m, j) => ({ ...m, order: j + 1 })) })}>移除</Button></div>)}<Button onClick={() => chapter(index, { ...c, memories: [...(c.memories || []), { id: id(), order: (c.memories || []).length + 1, content: '' }] })}>添加记忆点</Button></section>)}
        <Button onClick={() => change({ ...document, chapters: [...document.chapters, { id: id(), title: '', order: document.chapters.length + 1, memories: [{ id: id(), order: 1, content: '' }] }] })}>添加章节</Button>
      </>}
    </fieldset><Notice error>{error}</Notice><Notice>{message}</Notice><div className="toolbar"><Button disabled={locked} busy={busy} onClick={() => save('save')}>保存草稿</Button><Button disabled={locked} onClick={() => save('validate')}>校验</Button><Button variant="primary" disabled={locked || (!dirty && draft?.status === 'PUBLISHED')} onClick={() => { if (window.confirm('确认发布？发布后读者即可下载。')) save('publish') }}>发布故事</Button></div>
  </Card>
}
function Stories({ api, features }) {
  const live = usePage(api, '/api/stories', features.stories), drafts = usePage(api, '/api/admin/stories', features.stories && features.adminPublish), [selected, setSelected] = useState(null)
  const refresh = () => { live.load(); if (features.adminPublish) drafts.load() }
  async function archive(item) { if (!window.confirm(`确认归档 ${item.story_id}？线上故事将停止下载。`)) return; try { await api(`/api/admin/stories/${rid(item.story_id)}/archive`, { method: 'POST', body: JSON.stringify({ revision: item.revision }) }); refresh() } catch (e) { window.alert(e.message) } }
  return <div className="stack"><div className="two-columns"><Card title="已发布故事" actions={<Button busy={live.busy} onClick={() => live.load()}>刷新</Button>}>{live.items.map(item => <div className="list-row" key={item.storyId}><div><strong>{item.title}</strong><p className="muted">{item.storyId} · v{item.version} · 下载 {item.downloadCount}</p></div><Button disabled={!features.adminPublish} onClick={() => setSelected({ storyId: item.storyId })}>编辑</Button></div>)}{!live.busy && !live.items.length && <p className="empty">还没有发布故事</p>}<PageEnd page={live} /></Card>
    <Card title="故事草稿" actions={<Button busy={drafts.busy} disabled={!features.adminPublish} onClick={() => drafts.load()}>刷新</Button>}>{drafts.items.map(item => <div className="list-row" key={item.story_id}><div><strong>{item.story_id}</strong><p className="muted"><Badge status={item.status} /> · 修订 {item.revision}</p></div><div className="toolbar"><Button onClick={() => setSelected({ storyId: item.story_id })}>打开</Button><Button disabled={item.status === 'ARCHIVED'} onClick={() => archive(item)}>归档</Button></div></div>)}{!drafts.busy && !drafts.items.length && <p className="empty">从下方开始创作第一条故事</p>}<PageEnd page={drafts} /></Card></div><StoryEditor api={api} selected={selected} enabled={features.stories && features.adminPublish} onSaved={refresh} /></div>
}
function Invites({ api }) {
  const [role, setRole] = useState('USER'), [uses, setUses] = useState('1'), [hours, setHours] = useState('24'), [busy, setBusy] = useState(false), [result, setResult] = useState(null), [error, setError] = useState('')
  async function create(e) { e.preventDefault(); setBusy(true); setError(''); setResult(null); try { setResult(await api('/api/admin/invites', { method: 'POST', body: JSON.stringify({ role, maxUses: Number(uses), expiresInHours: Number(hours) }) })) } catch (e) { setError(e.message) } finally { setBusy(false) } }
  return <Card title="邀请用户" hint="用户在 APP 中填写服务器地址并兑换邀请码，认证后可参与评论。"><form onSubmit={create}><div className="form-grid three"><Field label="权限"><select value={role} onChange={e => setRole(e.target.value)}><option value="USER">普通用户</option><option value="ADMIN">管理员</option></select></Field><Field label="可用次数" type="number" min="1" max="1000" required value={uses} onChange={e => setUses(e.target.value)} /><Field label="有效小时" type="number" min="1" max="8760" required value={hours} onChange={e => setHours(e.target.value)} /></div><Button type="submit" variant="primary" busy={busy}>生成邀请码</Button></form><Notice error>{error}</Notice>{result && <div className="result-box"><span className="muted">请妥善保存，此邀请码仅显示一次</span><code>{result.code}</code><p>到期时间：{date(result.expiresAt)}</p><Button onClick={async () => { try { await navigator.clipboard.writeText(result.code) } catch { setError('复制不可用，请选中邀请码手动复制') } }}>复制邀请码</Button></div>}</Card>
}
function Comments({ api, enabled }) {
  const [status, setStatus] = useState('PENDING'), [pending, setPending] = useState(null), [error, setError] = useState(''), page = usePage(api, `/api/admin/comments?status=${status}`, enabled)
  async function moderate(item, next) { if (next === 'DELETED' && !window.confirm('确认删除此评论？')) return; setPending(item.id); setError(''); try { await api(`/api/admin/comments/${rid(item.id)}/moderate`, { method: 'POST', body: JSON.stringify({ status: next }) }); await page.load() } catch (e) { setError(e.message) } finally { setPending(null) } }
  return <Card title="评论管理" hint="仅已认证用户可以发表评论，新评论审核通过后公开。" actions={<Button busy={page.busy} disabled={!enabled} onClick={() => page.load()}>刷新</Button>}>{!enabled ? <Notice>评论服务未开启。设置 AICHAT_FEATURE_COMMENTS=true 并重启服务后即可使用。</Notice> : <><Field label="审核状态"><select value={status} onChange={e => setStatus(e.target.value)}>{['PENDING', 'VISIBLE', 'HIDDEN', 'DELETED'].map(key => <option key={key} value={key}>{statuses[key]}</option>)}</select></Field><Notice error>{error}</Notice>{page.items.map(item => <article className="comment-row" key={item.id}><div><p className="comment-body">{item.body}</p><p className="muted">{item.characterId ? `角色 ${item.characterId}` : `故事 ${item.storyId}`} · {date(item.createdAt)}{item.parentId ? ' · 回复' : ''}</p><Badge status={item.status} /></div><div className="toolbar">{['VISIBLE', 'HIDDEN', 'DELETED'].map(next => <Button key={next} variant={next === 'DELETED' ? 'danger' : ''} disabled={pending !== null || item.status === next} onClick={() => moderate(item, next)}>{next === 'VISIBLE' ? '通过' : next === 'HIDDEN' ? '隐藏' : '删除'}</Button>)}</div></article>)}{!page.busy && !page.items.length && <p className="empty">当前没有{statuses[status]}评论</p>}<PageEnd page={page} /></>}</Card>
}
function Characters({ api, enabled, publishEnabled }) {
  const page = usePage(api, '/api/characters', enabled), [form, setForm] = useState({ characterId: '', title: '', author: '', summary: '', version: 1 }), [file, setFile] = useState(null), [busy, setBusy] = useState(false), [error, setError] = useState(''), [message, setMessage] = useState(''), fileInput = useRef(null)
  async function publish(e) { e.preventDefault(); setBusy(true); setError(''); setMessage(''); try { if (!file || file.size > 4 * 1024 * 1024) throw new Error('请选择不超过 4MB 的 ZIP 角色包'); await api(`/api/admin/characters?${new URLSearchParams({ ...form, version: String(form.version) })}`, { method: 'POST', headers: { 'Content-Type': 'application/zip' }, body: file }); setMessage('角色包已发布。'); setFile(null); fileInput.current.value = ''; await page.load() } catch (e) { setError(e.message) } finally { setBusy(false) } }
  return <div className="stack"><Card title="角色卡目录" hint="服务器提供角色包下载与评论，沿用 APP 的 ZIP 格式。" actions={<Button busy={page.busy} disabled={!enabled} onClick={() => page.load()}>刷新</Button>}>{page.items.map(item => <div className="list-row" key={item.characterId}><div><strong>{item.title}</strong><p className="muted">{item.characterId} · v{item.version} · {item.author || '未署名'}</p><p>{item.summary}</p></div><div className="toolbar"><Button onClick={() => { setForm({ characterId: item.characterId, title: item.title, author: item.author, summary: item.summary, version: item.version + 1 }); setMessage('选择新角色包后发布下一版本。') }}>更新</Button><a className="button" href={`/api/characters/${rid(item.characterId)}/download`}>下载 ZIP</a></div></div>)}{!page.busy && !page.items.length && <p className="empty">暂无角色卡</p>}<PageEnd page={page} /></Card>
    <Card title="发布角色包" hint="ZIP 中应包含角色目录与 Profile.json，单个包最大 4MB。"><form onSubmit={publish}><fieldset disabled={!enabled || !publishEnabled || busy}><div className="form-grid"><Field label="角色卡 ID" pattern="[A-Za-z0-9][A-Za-z0-9._-]{1,127}" required value={form.characterId} onChange={e => setForm({ ...form, characterId: e.target.value })} /><Field label="版本" type="number" min="1" required value={form.version} onChange={e => setForm({ ...form, version: Number(e.target.value) })} /><Field label="标题" required maxLength={200} value={form.title} onChange={e => setForm({ ...form, title: e.target.value })} /><Field label="作者" maxLength={200} value={form.author} onChange={e => setForm({ ...form, author: e.target.value })} /></div><Field label="简介" textarea maxLength={2000} value={form.summary} onChange={e => setForm({ ...form, summary: e.target.value })} /><Field label="角色包 ZIP"><input ref={fileInput} type="file" accept=".zip,application/zip" onChange={e => setFile(e.target.files[0])} required /></Field><Button type="submit" variant="primary" busy={busy}>发布角色卡</Button></fieldset></form><Notice error>{error}</Notice><Notice>{message}</Notice></Card></div>
}
function Dashboard({ token, onLogout }) {
  const api = useCallback(createApi(token), [token]), [active, setActive] = useState('overview'), [health, setHealth] = useState(null), [version, setVersion] = useState(null), [connection, setConnection] = useState(null), [busy, setBusy] = useState(false), [errors, setErrors] = useState([]), audit = usePage(api, '/api/admin/audit-logs')
  async function refresh() { setBusy(true); setErrors([]); const results = await Promise.allSettled([api('/api/health'), api('/api/version'), api('/api/admin/connection')]); const setters = [setHealth, setVersion, setConnection]; results.forEach((r, n) => { if (r.status === 'fulfilled') setters[n](r.value); else if (n === 0) setHealth(null) }); setErrors(results.filter(r => r.status === 'rejected').map(r => r.reason.message)); setBusy(false) }
  useEffect(() => { refresh() }, [api])
  const features = version?.features || {}, sections = [['overview', '服务概览'], ['characters', '角色卡'], ['stories', '故事线'], ['comments', '评论审核'], ['invites', '用户邀请'], ['connection', '连接与配置']], heading = sections.find(([key]) => key === active)[1]
  return <div className="app-shell"><aside className="sidebar"><div className="brand"><div className="brand-mark">Ai</div><div><strong>AiChat</strong><span>内容管理台</span></div></div><nav aria-label="管理导航">{sections.map(([key, label]) => <button key={key} aria-current={active === key ? 'page' : undefined} className={active === key ? 'active' : ''} onClick={() => setActive(key)}>{label}</button>)}</nav><div className="sidebar-note">角色与故事由服务器发布<br />已认证用户参与评论</div><Button onClick={() => { if (window.confirm('确认退出管理台？请先保存未完成的内容。')) onLogout() }}>退出登录</Button></aside>
    <div className="workspace"><header className="topbar"><span>{heading}</span><div className="toolbar"><span className={`service-state ${health?.status === 'UP' ? 'up' : ''}`}>{health?.status === 'UP' ? '服务正常' : busy ? '检查中' : '连接异常'}</span><Button busy={busy} onClick={refresh}>刷新状态</Button></div></header><main className="content"><header className="hero"><p className="eyebrow">AICHAT CONTENT COMMUNITY</p><h1>{heading}</h1><p className="muted">管理内容发布、用户邀请与社区评论。</p></header>{errors.map((e, n) => <Notice error key={n}>{e}</Notice>)}
      <div hidden={active !== 'overview'} className="stack"><div className="metrics">{[['服务状态', health?.status], ['API 版本', version?.apiVersion], ['评论服务', features.comments ? '已开启' : '未开启']].map(([label, value]) => <div className="card" key={label}><span>{label}</span><strong>{value || '—'}</strong></div>)}</div><Card title="管理操作记录" actions={<Button busy={audit.busy} onClick={() => audit.load()}>刷新</Button>}>{audit.items.map(item => <div className="list-row" key={item.id}><div><strong>{item.action}</strong><p className="muted">{item.resource_type} · {item.resource_id || '—'}</p></div><span className="muted">{date(item.created_at)}</span></div>)}{!audit.items.length && !audit.busy && <p className="empty">尚无管理操作</p>}<PageEnd page={audit} /></Card></div>
      {version && <><div hidden={active !== 'stories'}><Stories api={api} features={features} /></div><div hidden={active !== 'characters'}><Characters api={api} enabled={features.characters} publishEnabled={features.adminPublish} /></div><div hidden={active !== 'comments'}><Comments api={api} enabled={features.comments} /></div></>}
      <div hidden={active !== 'invites'}><Invites api={api} /></div><div hidden={active !== 'connection'} className="stack"><Card title="APP 连接" hint="服务可达与用户认证分别验证。"><Field label="服务地址" readOnly value={connection?.publicBaseUrl || window.location.origin} /><p className="muted">手机上的 localhost / 127.0.0.1 指向手机本身。本地服务器应填写电脑的局域网 IP，并确保手机与电脑处于同一网络。</p><div className="toolbar"><a className="button" href="/api/health" target="_blank" rel="noreferrer">打开健康检查</a><a className="button" href="/api/version" target="_blank" rel="noreferrer">查看服务能力</a><Button onClick={() => setActive('invites')}>生成邀请码</Button></div><p>邀请码认证：{connection ? (connection.inviteRequired ? '需要邀请码' : '开放注册') : '—'}</p></Card><Card title="服务能力" hint="通过服务器环境变量调整，重启服务后生效。">{Object.entries(features).map(([key, enabled]) => <div className="list-row" key={key}><span>{labels[key] || key}</span><span className={`badge ${enabled ? 'VISIBLE' : 'HIDDEN'}`}>{enabled ? '已开启' : '已关闭'}</span></div>)}<p className="muted">评论：AICHAT_FEATURE_COMMENTS · 监听地址：AICHAT_BIND_ADDRESS · 公网地址：AICHAT_PUBLIC_BASE_URL</p></Card></div>
    </main></div></div>
}
function App() {
  const [token, setToken] = useState(''), [checking, setChecking] = useState(true)
  useEffect(() => { const saved = sessionStorage.getItem(tokenKey); if (!saved) { setChecking(false); return }; createApi(saved)('/api/admin/session').then(() => setToken(saved)).catch(() => sessionStorage.removeItem(tokenKey)).finally(() => setChecking(false)) }, [])
  const login = value => { sessionStorage.setItem(tokenKey, value); setToken(value) }, logout = () => { sessionStorage.removeItem(tokenKey); setToken('') }
  if (checking) return <main className="login-page"><p role="status">正在验证管理会话…</p></main>
  return token ? <Dashboard token={token} onLogout={logout} /> : <Login onLogin={login} />
}
createRoot(document.getElementById('root')).render(<App />)
