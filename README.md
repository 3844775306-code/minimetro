# MiniMetro（Godot 4.7）

极简地铁调度游戏 —— *Mini Metro* 机制的致敬实现，**非官方、非 1:1 复刻**。
当前进度：**M0 工程基线 + M1 白盒手势原型**（完整方案见 [设计方案](docs/设计方案.md)）。

![M1 手势原型](.shots/m1.png)

## 现在能玩到什么

- 按住车站拖拽 → 新建线路；拖过其他站会**即时接线**（连续画线）
- 拖回上一站 → 回退一段；不足两站时抬手自动回滚并返还资源
- 按住线路端点的小圆手柄 → 从该端继续延伸
- 按住线路**中间**的车站拖动 → 调整站序（相邻交换）
- `Ctrl+Z` 撤销整次手势；右键 / `Esc` 取消当前手势
- 线路资源 3 条，HUD 实时显示占用；站点每 13 秒按约束自动出现
- `空格` 暂停，`1/2/3` 倍速，`R` 重开

> 截图姿态可以用 `--demo --pose=draft` 复现（见下）。

## 运行

本机引擎：`D:\Downloads\06_游戏与Flash资源\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`（4.7.2 stable，导出模板已装）。

```powershell
# 用编辑器打开工程
& "D:\Downloads\06_游戏与Flash资源\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path .

# 直接跑游戏（先做一次导入）
& "...\Godot_v4.7.2-stable_win64_console.exe" --headless --import --path .
& "...\Godot_v4.7.2-stable_win64.exe" --path .
```

编辑器里按 F5 即可。窗口默认 1600×900，内部按 1920×1080 设计分辨率缩放。

## 测试（headless，无需显示）

```powershell
$godot = "D:\Downloads\06_游戏与Flash资源\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path . --script res://tests/run_tests.gd
# 期望输出：TESTS PASSED (68 checks)
```

在受限沙箱里如果子进程 stdout 被管道捕获失败，用文件重定向启动：

```powershell
Start-Process -FilePath $godot -ArgumentList '--headless','--path',$PWD.Path,
  '--script','res://tests/run_tests.gd' -RedirectStandardOutput out.txt -Wait -NoNewWindow
```

## 截图 / 演示姿态（回归对比用）

```powershell
$godot = "D:\Downloads\06_游戏与Flash资源\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
Start-Process -FilePath $godot -ArgumentList '--path',$PWD.Path,'--',
  '--demo','--shot=C:/Users/18749/Documents/mini-metro/.shots/m1.png' -Wait -NoNewWindow
```

- `--demo`：确定性布局 11 站 + 3 条线路
- `--pose=draft`：额外摆出"正在画线"的中间姿态（飞线虚线 + 已接线段）
- `--seed=12345`：固定随机种子
- `--smoke=300`：无渲染跑 300 tick 后打印状态退出（冒烟测试）

## 工程结构

```
main.tscn / main.gd       入口：装配世界与 UI、驱动模拟
autoload/game.gd          单例：一局的网络/种子/倍速
model/                    纯数据（RefCounted，不依赖 Node）
  shape.gd                站点形状（枚举 + 顶点表）
  station.gd              站点
  metro_line.gd           线路
  line_geometry.gd        圆角折线 + 弧长表 + 端点手柄
  metro_network.gd        站点/线路的唯一事实来源
  draw_util.gd            绘制小工具
sim/                      固定步长模拟
  simulation.gd           1/60s tick 驱动
  station_spawner.gd      拒绝采样生成站点
view/                     表现层（Node2D，只读模型）
  map_view.gd             水色 + 纸面陆地
  station_view.gd         站点形状 + 悬停环 + 弹出动画
  station_layer.gd        站点视图容器
  line_layer.gd           每线一个 Line2D（Round 关节/端点）
input/line_editor.gd      画线手势状态机（IDLE / DRAFT / REORDER）
ui/hud.gd                 资源槽、站点数、提示、Toast
tools/demo_setup.gd       截图用的确定性布局
tests/                    headless 测试（68 checks）
art/shaders/paper_grain.gdshader  极轻纸纹
docs/设计方案.md           完整实现方案（机制拆解 / 架构 / 里程碑）
```

## 几个关键实现决定

1. **模型 / 模拟 / 视图三层分离**：`model/` 是纯 `RefCounted`，`sim/` 只推进 tick，视图每帧读模型。
   好处是单测可以完全绕开窗口和渲染（`tests/` 就是这么跑的）。
2. **列车未来用弧长驱动**（M2）：`LineGeometry` 已有 `sample(distance)` / `nearest_distance()`，
   线路被编辑后把列车按最近弧长重映射，不会跳。
3. **站点不持有 MetroLine 对象**，只存 `line_ids`：否则 `Station ↔ MetroLine` 形成引用环，
   `RefCounted` 永不释放（M1 冒烟时实测泄漏 43 个实例，已改掉）。
4. **固定步长 + 种子 RNG**：倍速是"多跑 tick"而不是放大 delta，为每日挑战可复现打基础。
5. **中文用 `SystemFont`**（微软雅黑等），不把字体文件打进工程，避免豆腐块和字体授权问题。

## 已知限制 / 下一步

- [ ] **M2**：列车往返、乘客生成/上下车/换乘、送达计分、站点溢出失败 —— 核心闭环
- [ ] M3：每周抽卡（线路/列车/车厢）
- [ ] M4：河道 + 桥隧资源、换乘站容量、特殊形状
- [ ] M5：音效与分层音乐、粒子/动效打磨
- [ ] M6：模式（无尽/每日挑战）、存档、设置、中英双语
- 触屏依赖 Godot 的 `emulate_mouse_from_touch`（默认开启），尚未做移动端 UI 适配
- Web 导出需把渲染器切到 Compatibility 并压缩音频素材
- `.shots/` 是本地截图产物，已在 `.gitignore` 忽略
