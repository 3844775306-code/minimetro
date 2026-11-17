# Supabase 接入说明

项目 ref：`oewvixujojsbqwxfnkfk`  
预计 Project URL：`https://oewvixujojsbqwxfnkfk.supabase.co`

> 注意：从本机 DNS 查询该域名返回 **NXDOMAIN**（`supabase.co` 本身正常），
> 说明项目可能已暂停/删除，或 dashboard 里的 ref 与真实项目不一致。
> 请先在 Supabase 确认项目状态，并从 **Settings → API** 复制 Project URL。

## 1. 需要的凭证

只需要 **anon / publishable** key（客户端公开使用），不要使用 `service_role` key。

在 Supabase Dashboard：
- Settings → API → Project URL
- Settings → API Keys → anon public / publishable key

当前链接 `.../settings/api-keys?method=github` 只是 dashboard 页面，URL 本身不包含 key，
而且 dashboard 需要登录，自动化工具无法替你读取。

## 2. 建表

在 SQL Editor 执行：

`cloud/supabase_schema.sql`

包含：
- `metro_daily_scores`（`date + player_id` 唯一，服务器保证每日一次）
- `metro_best_scores`（`mode + city_id + player_id` 唯一，只保留最高分）
- `metro_maps`（地图大厅）
- 只读 RLS + 4 个 security definer RPC：提交每日、提交最高分、上传地图、下载计数

## 3. 客户端配置

计划使用 `user://cloud_config.json`（桌面）或打包时内置（移动端）：

```json
{
  "url": "https://oewvixujojsbqwxfnkfk.supabase.co",
  "key": "sb_publishable_xxx 或 eyJ...anon..."
}
```

Godot 侧请求头：

```
apikey: <key>
Authorization: Bearer <key>
Content-Type: application/json
```

## 4. 接口映射

| 游戏功能 | Supabase |
|---|---|
| 最近 7 天每日榜 | `GET /rest/v1/metro_daily_scores?select=date,display_name,score&date=gte.<7天前>&order=date.desc,score.desc` |
| 提交每日成绩 | `POST /rest/v1/rpc/submit_daily_score` |
| 分地图最高分榜 | `GET /rest/v1/metro_best_scores?mode=eq.<mode>&city_id=eq.<city>&select=display_name,score&order=score.desc&limit=8` |
| 提交最高分 | `POST /rest/v1/rpc/submit_best_score` |
| 地图大厅列表 | `GET /rest/v1/metro_maps?select=*&order=created_at.desc&limit=20` |
| 上传地图 | `POST /rest/v1/rpc/upload_metro_map` |
| 下载地图 | `GET /rest/v1/metro_maps?id=eq.<id>`，再 `POST /rest/v1/rpc/increment_map_downloads` |

## 5. 客户端身份

本机生成一个 UUID 存进玩家档案，作为 `player_id`：
- 每日榜用 `(date, player_id)` 唯一键避免同一天重复提交
- 最高分榜用 `(mode, city_id, player_id)` 唯一键只保留最高分

这是原型级匿名身份：客户端仍可伪造新的 UUID。正式运营建议：
- 开启 Supabase Anonymous Sign-in，用 `auth.uid()` 作为玩家身份
- 用 Edge Function 校验每日一次、分数上限、地图大小
- 地图上传加人工审核/举报

## 6. 现有代码的改造点

`cloud/cloud_service.gd` 当前是可持久化的**本地模拟后端**，UI 已按以下同步接口调用：

- `daily_leaderboard` / `recent_daily_lines`
- `best_leaderboard`
- `submit_daily` / `submit_best`
- `maps` / `upload_map` / `download_map`

接 Supabase 时保持这些方法签名，内部改成：
1. 本地缓存立即返回（UI 不闪烁）
2. `HTTPRequest` 后台拉取/提交
3. 拉取完成发 `updated` 信号，主界面刷新已打开的排行榜/大厅

这样 HUD、模式菜单、地图编辑器的调用都不需要改。
