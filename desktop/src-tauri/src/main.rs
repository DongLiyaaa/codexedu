#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{fs, path::PathBuf, time::Duration};
use tauri::{Manager, State};
use tokio::sync::Mutex;

const CLIENT: &str = "app_EMoamEEZ73f0CkXaXp7hrann";
#[derive(Clone, Serialize, Deserialize)]
struct Session { access_token: String, refresh_token: Option<String>, account_id: String }
struct Pending { id: String, code: String, interval: u64, expires: std::time::Instant }
struct Inner { session: Option<Session>, pending: Option<Pending> }
struct Store { path: PathBuf, inner: Mutex<Inner>, http: reqwest::Client }
fn save(path: &PathBuf, session: &Session) -> Result<(), String> {
    let parent = path.parent().ok_or("无效存储路径")?;
    fs::create_dir_all(parent).map_err(|_| "创建登录目录失败")?;
    #[cfg(unix)] { use std::os::unix::fs::PermissionsExt; fs::set_permissions(parent, fs::Permissions::from_mode(0o700)).map_err(|_| "目录权限设置失败")?; }
    let temp = path.with_extension("tmp");
    let _ = fs::remove_file(&temp);
    let mut options = fs::OpenOptions::new(); options.write(true).create_new(true);
    #[cfg(unix)] { use std::os::unix::fs::OpenOptionsExt; options.mode(0o600); }
    use std::io::Write;
    let mut file = options.open(&temp).map_err(|_| "保存登录失败")?;
    file.write_all(&serde_json::to_vec(session).map_err(|_| "编码失败")?).map_err(|_| "保存登录失败")?;
    file.sync_all().map_err(|_| "保存登录失败")?;
    drop(file);
    // Windows rename cannot replace an existing file. Keep a backup until replacement succeeds.
    let backup = path.with_extension("bak");
    if path.exists() { let _ = fs::remove_file(&backup); fs::rename(path, &backup).map_err(|_| "备份登录失败")?; }
    if fs::rename(&temp, path).is_err() { let _ = fs::rename(&backup, path); return Err("更新登录失败".into()); }
    let _ = fs::remove_file(backup);
    Ok(())
}
fn parse_tokens(v: &Value, old: Option<&Session>) -> Result<Session, String> {
    let access = v["access_token"].as_str().ok_or("缺少令牌")?;
    let jwt = v["id_token"].as_str().unwrap_or(access);
    let claims = jwt.split('.').nth(1).and_then(|s| base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(s).ok())
        .and_then(|d| serde_json::from_slice::<Value>(&d).ok()).unwrap_or(Value::Null);
    let account = claims["https://api.openai.com/auth"]["chatgpt_account_id"].as_str()
        .or_else(|| old.map(|s| s.account_id.as_str())).ok_or("缺少账号标识")?;
    Ok(Session { access_token: access.into(), account_id: account.into(), refresh_token: v["refresh_token"].as_str().map(str::to_owned).or_else(|| old.and_then(|s| s.refresh_token.clone())) })
}
async fn post(store: &Store, path: &str, body: Value) -> Result<(u16, Value), String> {
    let response = store.http.post(format!("https://auth.openai.com{path}")).json(&body).send().await.map_err(|_| "授权网络连接失败")?;
    let status = response.status().as_u16();
    Ok((status, response.json().await.unwrap_or(Value::Null)))
}
#[tauri::command]
async fn login_start(store: State<'_, Store>) -> Result<String, String> {
    let mut inner = store.inner.lock().await;
    let (status, v) = post(&store, "/api/accounts/deviceauth/usercode", json!({"client_id": CLIENT})).await?;
    if status != 200 { return Err(format!("设备授权不可用（HTTP {status}）")); }
    let code = v["user_code"].as_str().or(v["usercode"].as_str()).ok_or("无效授权码")?.to_string();
    inner.pending = Some(Pending { id: v["device_auth_id"].as_str().ok_or("无效授权响应")?.into(), code: code.clone(), interval: v["interval"].as_u64().or_else(|| v["interval"].as_str().and_then(|s| s.parse().ok())).unwrap_or(5).clamp(5, 60), expires: std::time::Instant::now() + Duration::from_secs(900) });
    open::that("https://auth.openai.com/codex/device").map_err(|_| "无法打开浏览器，请访问官方设备授权页面")?;
    Ok(code)
}
#[tauri::command]
async fn login_poll(store: State<'_, Store>) -> Result<bool, String> {
    let mut inner = store.inner.lock().await;
    let pending = inner.pending.as_ref().ok_or("没有待完成的授权")?;
    if std::time::Instant::now() >= pending.expires { inner.pending = None; return Err("授权超时，请重试".into()); }
    tokio::time::sleep(Duration::from_secs(pending.interval)).await;
    let (status, v) = post(&store, "/api/accounts/deviceauth/token", json!({"device_auth_id":pending.id,"user_code":pending.code})).await?;
    if status == 403 || status == 404 { return Ok(false); }
    if status != 200 { inner.pending = None; return Err(format!("授权失败（HTTP {status}）")); }
    let (status, tokens) = post(&store, "/oauth/token", json!({"grant_type":"authorization_code","client_id":CLIENT,"code":v["authorization_code"],"code_verifier":v["code_verifier"],"redirect_uri":"https://auth.openai.com/deviceauth/callback"})).await?;
    inner.pending = None;
    if status != 200 { return Err("令牌交换失败，请重新授权".into()); }
    let session = parse_tokens(&tokens, None)?;
    save(&store.path, &session)?;
    inner.session = Some(session);
    Ok(true)
}
#[tauri::command]
async fn logout(store: State<'_, Store>) -> Result<(), String> {
    let mut inner = store.inner.lock().await;
    if store.path.exists() { fs::remove_file(&store.path).map_err(|_| "删除登录文件失败")?; }
    inner.session = None; inner.pending = None; Ok(())
}
#[tauri::command]
async fn usage(store: State<'_, Store>) -> Result<Value, String> {
    let mut inner = store.inner.lock().await;
    let mut session = inner.session.clone().ok_or("请先登录")?;
    for attempt in 0..2 {
        let response = store.http.get("https://chatgpt.com/backend-api/wham/usage")
            .bearer_auth(&session.access_token).header("ChatGPT-Account-Id", &session.account_id)
            .send().await.map_err(|_| "额度查询网络失败")?;
        if response.status().as_u16() == 401 && attempt == 0 {
            let refresh = session.refresh_token.as_ref().ok_or("请重新登录")?;
            let (status, v) = post(&store, "/oauth/token", json!({"grant_type":"refresh_token","client_id":CLIENT,"refresh_token":refresh})).await?;
            if status != 200 { return Err("登录过期，请重新授权".into()); }
            session = parse_tokens(&v, Some(&session))?;
            inner.session = Some(session.clone()); save(&store.path, &session)?;
            continue;
        }
        if !response.status().is_success() { return Err(format!("额度查询失败（HTTP {}）", response.status().as_u16())); }
        let value: Value = response.json().await.map_err(|_| "额度响应异常")?;
        if let Some(id) = value["account_id"].as_str() { if id != session.account_id { return Err("账号不匹配".into()); } }
        // Only return display data, never identity fields or tokens to the webview.
        return Ok(json!({"plan_type":value["plan_type"],"rate_limit":value["rate_limit"]}));
    }
    Err("请重新登录".into())
}
#[tauri::command]
fn menu_size(window: tauri::WebviewWindow, expanded: bool) -> Result<(), String> {
    window.set_size(tauri::LogicalSize::new(360.0, if expanded { 175.0 } else { 36.0 })).map_err(|_| "窗口调整失败".into())
}
fn main() {
    tauri::Builder::default().setup(|app| {
        let path = app.path().app_local_data_dir()?.join("session.json");
        let backup = path.with_extension("bak");
        if !path.exists() && backup.exists() { let _ = fs::rename(&backup, &path); }
        let session = fs::read(&path).ok().and_then(|d| serde_json::from_slice(&d).ok());
        app.manage(Store { path, inner: Mutex::new(Inner { session, pending: None }), http: reqwest::Client::builder().redirect(reqwest::redirect::Policy::none()).timeout(Duration::from_secs(25)).build()? });
        let window = app.get_webview_window("main").ok_or("missing window")?;
        if let Some(monitor) = window.current_monitor()? {
            let position = monitor.position(); let size = monitor.size();
            window.set_position(tauri::PhysicalPosition::new(position.x + (size.width as i32 - (360.0 * monitor.scale_factor()) as i32) / 2, position.y + 40))?;
        }
        Ok(())
    }).invoke_handler(tauri::generate_handler![login_start, login_poll, logout, usage, menu_size])
      .run(tauri::generate_context!()).expect("Application startup failed");
}
