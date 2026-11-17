# Supabase 接入说明

项目 ref：`josalpkewgzritmwbocs`  
Project URL：`https://josalpkewgzritmwbocs.supabase.co`  
状态：**已接通**。三张表、RLS、RPC、Godot 客户端读写均已验证。

## 1. 需要的凭证

只需要 **publishable / anon public** key（客户端公开使用），不要使用 `service_role` key。

当前 publishable key 已写入 `cloud/supabase_config.json`，并在 `CloudService` 中保留一份打包兜底值。
如需换项目，修改这个 JSON 即可。

在 Supabase Dashboard：
- 左下角 **Project Settings**
- **API** 页面复制 **Project URL**
- **API Keys** 页面复制 **Publishable key**（`sb_publishable_...`）  
  如果只有 Legacy keys，也可以使用 **anon public**（`eyJ...`）

## 2. 建表

在左侧 **SQL Editor** → New query，整段执行：

`cloud/supabase_schema.sql`

包含：
- `metro_daily_scores`（`date + player_id` 唯一，服务器保证每日一次）
- `metro_best_scores`（`mode + city_id + player_id` 唯一，只保留最高分）
- `metro_maps`（地图大厅）
- 只读 RLS + 4 个 security definer RPC：提交每日、提交最高分、上传地图、下载计数

执行成功后到 **Table Editor** 应能看到：
- `metro_daily_scores`
- `metro_best_scores`
- `metro_maps`

## 3. 最小连通性测试

用 publishable key 请求：

```bash
curl "https://josalpkewgzritmwbocs.supabase.co/rest/v1/metro_daily_scores?select=date,display_name,score&limit=1" \
  -H "apikey: sb_publishable_xxx"
```

预期返回 `[]`（新版 publishable key 只需 apikey 头；Legacy anon JWT 才需要额外 Authorization）。

## 4. 客户端配置

已内置在 `cloud/supabase_config.json`（桌面可直接读取；移动端由 `CloudService` 的兜底常量保证可用）。

```json
{
  "url": "https://josalpkewgzritmwbocs.supabase.co",
  "key": "sb_publishable_xxx 或 eyJ...anon..."
}
```

Godot 侧请求头：

```
apikey: <key>
Content-Type: application/json
```

如果用的是 **Legacy anon public JWT**（`eyJ...`），再额外加：

```
Authorization: Bearer <key>
```

新版 `sb_publishable_...` 只需要 `apikey` 头；不要把它硬塞进 `Authorization`。

## 5. 接口映射

| 游戏功能 | Supabase |
|---|---|
| 最近 7 天每日榜 | `GET /rest/v1/metro_daily_scores?select=date,display_name,score&date=gte.<7天前>&order=date.desc,score.desc` |
| 提交每日成绩 | `POST /rest/v1/rpc/submit_daily_score` |
| 分地图最高分榜 | `GET /rest/v1/metro_best_scores?mode=eq.<mode>&city_id=eq.<city>&select=display_name,score&order=score.desc&limit=8` |
| 提交最高分 | `POST /rest/v1/rpc/submit_best_score` |
| 地图大厅列表 | `GET /rest/v1/metro_maps?select=*&order=created_at.desc&limit=20` |
| 上传地图 | `POST /rest/v1/rpc/upload_metro_map` |
| 下载地图 | `GET /rest/v1/metro_maps?id=eq.<id>`，再 `POST /rest/v1/rpc/increment_map_downloads` |

## 6. 客户端身份

本机生成一个 UUID 存进玩家档案，作为 `player_id`：
- 每日榜用 `(date, player_id)` 唯一键避免同一天重复提交
- 最高分榜用 `(mode, city_id, player_id)` 唯一键只保留最高分

这是原型级匿名身份：客户端仍可伪造新的 UUID。正式运营建议：
- 开启 Supabase Anonymous Sign-in，用 `auth.uid()` 作为玩家身份
- 用 Edge Function 校验每日一次、分数上限、地图大小
- 地图上传加人工审核/举报

## 7. 已验证内容

- REST 读取三张表正常
- `submit_daily_score`：同一天同一 player_id 第二次提交不会覆盖第一次（7 → 99 仍为 7）
- `submit_best_score`：同一地图同一玩家保留最高分
- `upload_metro_map` + `increment_map_downloads`：上传、读取、下载计数正常
- Godot 客户端启动日志：
  ```text
  CLOUD_CONFIG enabled=true live=true ...
  CLOUD_REMOTE daily days=...
  CLOUD_REMOTE best boards=...
  CLOUD_REMOTE maps=...
  ```

联调测试写入了少量 `集成测试` 数据；需要清理时在 SQL Editor 执行：

```sql
delete from public.metro_daily_scores where display_name = '集成测试';
delete from public.metro_best_scores where display_name = '集成测试';
delete from public.metro_maps where author = '集成测试';
```

## 8. 现有代码的改造点

`cloud/cloud_service.gd` 现在是**缓存 + 后台 Supabase 同步**模式：

- `daily_leaderboard` / `recent_daily_lines`
- `best_leaderboard`
- `submit_daily` / `submit_best`
- `maps` / `upload_map` / `download_map`

UI 调用同步接口立即返回缓存；HTTPRequest 在后台拉取/提交，完成后发 `updated` 信号，
主界面刷新已打开的排行榜/大厅。网络失败时保留本地示例数据继续可玩。
