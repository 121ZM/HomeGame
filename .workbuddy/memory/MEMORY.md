# HomeGame 项目长期记忆

## 项目定位
**家庭版体感游戏集合** —— 不是一款游戏，是一个平台，小游戏慢慢往里加。
形态：**手机当体感手柄，大屏（PC/电视）跑游戏**，局域网 UDP 直连，无公网/无服务端/无账号。
手机端必须**原生 App**：Android Chrome / iOS Safari 只在 HTTPS 安全上下文开放网页传感器权限。

## 目录约定
- `screen/` 大屏端 Godot 项目（主）｜`controller/` 手机端 Flutter App｜`docs/` `tools/` 共享
- 两者必须**平级** —— Godot 项目不能嵌套，父项目会把子目录当资源扫描。
- `tools/`（仓库根）放**跨端共用**的脚本（如 `proto_check.py`）；
  `controller/tools/` 放手机端自己的（如 SDK 安装脚本）。

## 手机端（controller/）：Flutter 双端
- **技术选型：Flutter**，一套 Dart 代码出**安卓 + 鸿蒙 NEXT**两端。
- **必须用鸿蒙适配版 Flutter**：纯血鸿蒙 NEXT（5.0+）**不兼容 APK**，只能装 `.hap`；
  官方 Flutter 产不出 `.hap`。SDK 在 `~/DEV/flutter-ohos`（`oh-3.35.7-release`，Dart 3.9.2）。
  官方已 3.47.x，适配线在 3.35.x（落后约 4 个月）——双端必须接受。
  安装脚本 `controller/tools/setup_flutter_ohos.sh`（**幂等可重跑**）。
- 包名 `cn.zm.homegame.controller`，pubspec name `homegame_controller`。
- **平台差异全部收敛在原生侧**：Dart 业务层只有一份，两个平台走同名通道。
  - MethodChannel `cn.zm.homegame/udp` —— `open({port})` / `send({host,port,bytes})` / `close()`
  - EventChannel `cn.zm.homegame/sensor` —— 每帧推 `{gx,gy,gz,ax,ay,az,ts}`
- **验证方式：`flutter test`，不需要真机、不需要大屏、不需要鸿蒙 SDK。**
  `flutter analyze` 必须干净；测试 15 组（10 协议字节 + 5 界面），改代码后必跑。
- 分工边界：`lib/` 是 Dart 业务（我写），`android/` `ohos/` 是原生（各一个 worker 写）。

### 三个必须记住的环境坑
1. **归档下载地址全是 HTML** —— atomgit/gitcode 的 `archive/*.tar.gz` / `releases/download/*`
   / `api/v5/*/tarball` 都返回网页或 401/404。**唯一可靠路径是 `git clone --branch <分支>`**。
2. **浅克隆 → 版本号变 `0.0.0-unknown` → `pub get` 报假依赖冲突**
   （看着像 `flutter_test requires Flutter >=3.18.0`，其实是版本没解析）。
   修：`git tag <版本>` + 删 `bin/cache/flutter_tools.stamp` 重算。
3. **`flutter test` 会静默不跑** —— 只打一行 `[!] No Hmos SDK found.` 就退，
   **没有任何测试输出**，极易误判成「通过」。根因在
   `flutter_tools/lib/src/project.dart` 的 `ensureReadyForPlatformSpecificTooling()`：
   `hvigor.updateLocalProperties()` 的 `requireHarmonySdk` 默认 true，没鸿蒙 SDK 就 `throwToolExit`。
   **已给 SDK 源码打补丁**改成 `false`（编 hap 的路径另有检查，不受影响）。
   ⚠️ **升级 SDK 会覆盖补丁，重装必须重跑 setup 脚本。**
- 环境变量（每次开 shell 都要，建议写进 shell 配置）：
  `PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、
  `FLUTTER_GIT_URL=https://gitcode.com/openharmony-tpc/flutter_flutter.git`（不设会一直唠叨非标准 remote）。
- 华为的 OHOS 引擎包走**专用源** `flutter-ohos.obs.cn-south-1.myhuaweicloud.com`，不是官方 storage。
- `flutter doctor` 里 HarmonyOS / Android toolchain **必然是 ✗**（没装 DevEco / Android SDK），
  **不影响纯 Dart 单测**。
- ⚠️ **`flutter create` 会覆盖 `lib/main.dart`** —— 已有代码先备份再 create。

### 鸿蒙侧要点（待 DevEco 才能编）
- 传感器 `@ohos.sensor`（`ACCELEROMETER`/`GYROSCOPE`，`{interval: 20000}` 纳秒 ≈ 50Hz）；
  UDP `@ohos.net.socket` 的 `constructUDPSocketInstance()`
- 权限 `ohos.permission.INTERNET` / `ACCELEROMETER` / `GYROSCOPE`
  （后两个 `system_grant`，**安装即授权不弹窗**）
- **隐私合规**：不能在用户同意隐私政策前读传感器（上架华为市场会查）
- ArkTS 比 TS 严：不能用 `any`

### 安卓侧要点
- 传感器 `SensorManager` + `TYPE_ACCELEROMETER`/`TYPE_GYROSCOPE`，`SENSOR_DELAY_GAME`
- UDP `java.net.DatagramSocket`；权限 `INTERNET` / `VIBRATE` / `HIGH_SAMPLING_RATE_SENSORS`

## 架构：三层 + 框架层
1. **网络层** `screen/scripts/net/` —— 只管收包/会话/链路质量，不解释语义
2. **输入抽象层** `screen/scripts/input/` —— 原始读数 → 归一化量 + 离散事件（滤波/死区/动作识别/零点校准）
3. **玩法层** `screen/scripts/minigames/<id>/` —— 只认 `sessions` / `tilt()` / `events`，不碰网络层

**玩法层永远不直接读原始传感器值。** 换输入源（手机→摄像头→专用硬件）只动第 1、2 层，玩法层零改动。

`screen/scripts/core/` 是**框架层**：`minigame.gd` 契约、`game_registry.gd` 注册表、`game_flow.gd` 状态机、
`player_palette.gd` 8 色槽位表、`player_names.gd` 名字池、`lobby.gd` 大厅逻辑、`ui_kit.gd` 视觉底座、
`reward_service.gd` + `gateways/`。**玩法删除不影响框架**（用户明确要求）。

## 显示与坐标（做 UI 必须知道）
- **逻辑视口恒 1920×1080**（`project.godot`），`window_width/height_override = 1280/720`，
  stretch `canvas_items` + `aspect=expand`。**逻辑坐标空间永远是 1920×1080**，720 只是显示像素，
  缩放比 = 1280/1920 = 0.667（实测 `get_stretch_transform().get_scale()`）。
- **设计稿→项目基准换算 k = 1808/1180 = 1.532**：设计稿内容宽 `max-width:1180px`
  ↔ 项目内容宽 `VIEW_W − MARGIN×2 = 1920 − 112 = 1808`。CSS px × 1.532 = 逻辑 px。
- Godot 默认字体 `font.get_height()` ≈ 字号 × 1.38，**行高远大于字号**，算布局要按 height 算。

## 视觉规范：桌游盒 / 玩具感（第 3 版，按用户 HTML 设计稿重做）
**唯一视觉底座 = `scripts/core/ui_kit.gd`（`class_name UiKit`，全 static）。改视觉只改它。**
设计稿：`/home/zm/WorkBuddy/2026-09-22-20-46-44/game-lobby-ui/index.html`（权威规格）。

⚠️ **项目原有的「平涂」四原则本次全部作废**（用户拍板「完全照设计稿」）：
平涂→用硬阴影；不用渐变→用径向微光；选中不许位移→贴纸式位移；细描边→2~3px 墨色粗描边。

- **色**：`INK #221f1a` 暖褐黑 / `INK_SOFT #5c564a` / `INK_MUTE #b3a98f` /
  `PAPER #fffdf6` / `PAPER_ALT #efe8d8` / `BACKDROP #f7f2e7` 奶油纸（+`BACKDROP_BOTTOM #efe8d8`）/
  `LINE #d9d0bc`；强调 `ACCENT #e8543f` 番茄红 + `ACCENT_DEEP #c93f2c`；
  状态 `OK #2f9e6e` / `WAITING #e2a400` / `WAITING_INK #a97c00`（亮黄对比度不够，文字要压深）；
  席位 `SEAT_JOINED #2ba39a` / `SEAT_EMPTY_A #eee9dc` / `SEAT_HATCH #c9bda1`
- **尺寸**：`STROKE 3` / `STROKE_STRONG 4` / `STROKE_THIN 2` / `RADIUS 28` / `TILE_RADIUS = RADIUS` /
  `PAD 36` / `GAP 24` / `TILE_GAP 34` / `PILL_RADIUS 999`（全圆角）/ `THUMB_H 230` 封面定高 /
  `LOBBY_COLUMNS 3`（一页 3 张）/ `POP_SHIFT 5` / `SHADOW_CARD 3` / `SHADOW_POP 6`
- **字号按「隔客厅看 55 寸电视」定**（照显示器惯例会明显偏小，踩过）：
  BODY 26 / SMALL 21 / BIG 36 / TITLE 56 / HUGE 128
- **构件**：`flat_box` / `card_box` / `card` / `label` / `wrap_label` / `pill` / `badge` / `vbox` / `hbox` /
  `spacer` / `dot` / `rule` / `keycap_frame` / `tile` / `seat_dot` / `dashed_panel` / `make_theme` / `readable_fg`
- 全部节点 `mouse_filter = IGNORE` —— 大屏操作走键盘/遥控器，UI 不该抢焦点。

### StyleBoxFlat 的能力边界（踩过才知道）
只有**一组** `shadow_color/shadow_size/shadow_offset`（无第二层、无 spread）；
`border_width_bottom` 可单独设（做立体下沿）；**没有 dashed/dotted、没有斜纹填充**
→ 虚线框（`DashBox`）和席位斜纹圆点（`SeatDot`）必须 `_draw()` 手绘。

### 选中态「贴纸位移」的正确做法
**不能改 `Control.position`**（容器每帧覆写）。做法：外层包一个**普通 `Control`**，
内层磁贴 `PRESET_FULL_RECT` 锚上去再设 `offset_*`。容器只看外层 `custom_minimum_size`，
所以位移**不进布局**、不挤动旁边的卡。见 `hud.gd:_tile_wrap()`。
⚠️ **包装节点命名不能以被查前缀开头** —— `_find_named` 用 `begins_with`，
叫 `game_tile_0_wrap` 会被当成第二张磁贴。现在叫 `wrap_of_<原名>`。

### 背景微光
`GradientTexture2D`（`fill = FILL_RADIAL`）+ `TextureRect` + `modulate.a`。
`FILL_RADIAL` 只支持正圆（CSS 是椭圆，接受近似）。见 `hud.gd:_glow()`。

## 玩家容量（两层，别混）
- **架构硬上限** = `UdpServer.max_players` = 8（由颜色可辨识度、HUD 布局决定，**不由玩法决定**）
- **玩法人数区间** = 各自 `min_players`/`max_players` + 自定义规则（拔河 2–4 但只认 2 或 4，必须均分两队）

**槽位是玩法层概念**：网络层只管 `PlayerSession`（`player_id` 手机自报）；槽位（0..N-1，对应颜色与 HUD 角标）
在**开局那一刻**由 `GameFlow` 分配（`session.slot = 数组下标`）。
→ **掉线时槽位置空、绝不删除**：抽掉中间一个会让后面所有人槽位号前移，颜色身份全乱。

## 通信协议 v2
`screen/scripts/net/net_protocol.gd`（`class_name NetProtocol`）。改协议必须 +1 `VERSION`，两端同步改。
- 10B 公共头（小端）：`magic 0xA7 / version / type / pad / player_id(u16) / seq(u32)`
- 上行：`TYPE_DATA 0`（+gyro3f+accel3f+buttons u16+ts u32 = 40B）、`TYPE_HELLO 1`（+name_len u8 + name utf8≤24B）、`TYPE_BYE 2`
- 下行：**唯一**一个 `TYPE_FULL 128`（仅头）—— 房间已满，别傻等
- 名字截断必须**按字符**回退，不能按字节切（汉字 3 字节，切中间变乱码）
- v1（`motion_packet.gd`，38B 定长）已删除

## 玩家名字：默认分配一个，玩家也能自己改
`core/player_names.gd`（`class_name PlayerNames`）是**唯一一份**名字池 —— `UdpServer` 兜底、大屏 `--simulate`、
单跑 `simulator.tscn` 三处共用。**加名字只改这里。**
- 池子：孙悟空、猪八戒、沙悟净、唐僧、白龙马、哪吒、二郎神、红孩儿、牛魔王（2–4 字）
- 三行为：**没报名 → `pick()` 挑未占用的**；**报了就用自己的**；**改名 = 重发一次 HELLO**（不加新报文）
- `at(i)` 对任何整数都给得出名字（`((i % n) + n) % n`）
- `pick(taken)` 池子占满时**重用一个默认名**，绝不退化成「玩家 N」
- `_default_name_for(pid)` **排除自己已有的名字** ⇒ 重发空名 HELLO 幂等（改名靠它）
- 调试开关 `simulator.tscn -- --anon` 故意不报名，否则「默认分配」这条分支永远跑不到

## MiniGame 契约（加新玩法照抄）
```gdscript
class_name XxxGame extends MiniGame
func meta() -> Dictionary          # id / name / desc / min_players / max_players / inputs
func accepts_count(n: int) -> bool # 默认只看区间；有额外规则就覆盖
func setup() / countdown(t) / tick(delta) / is_over() -> bool
func result() -> Dictionary        # 至少含 "text"（注意：拔河返回 winner_team 不是 winner，别踩）
func status_text() -> String       # 一行状态，HUD 和无头日志都用它
func status_badges() -> Array      # 对局顶栏右端的徽标：[{"icon":"revive"|"item","n":次数}]；默认 []
func status_meta() -> String       # 旧的整句形态，留作 status_badges() 为空时的兜底
func why_not(n: int) -> String     # 「为什么开不了」由玩法自己回答，框架猜不到组队规则
# 奖励钩子（不要奖励就全留默认空实现）
func reward_catalog() / pending_reward_request() / begin_reward(req) / apply_reward(req, granted, data)
```
框架负责：槽位分配 / 玩家颜色 / HUD / 倒计时 / 结算展示 / 音效 / 手机振动。**小游戏不重复实现这些。**
名不副实的三处（坑后来人）：`meta()["inputs"]` 与 `reward_catalog()` 无运行时消费者；`result()` 注释说 winner。

**HUD 不许 `is XxxGame`** —— 顶栏要从 `status_text()` **宽松抠**「剩 N 秒」「左队 N · 右队 N」
（抠不到就整行摆进时间格兜底）。写死类型就破坏了「玩法可插拔」这条铁律。

## 奖励接口（看广告/答题得道具、复活）
目标「**边玩边学**」。核心是**可替换的奖励网关** —— 大屏不关心奖励来自哪里，只认「给/不给」。

链路：玩法 `pending_reward_request()` → `GameFlow` 挂起对局（`REWARD` 状态，不 tick 不判胜负）
→ `RewardService.request()` → 网关 → `apply_reward(...)` → 回 `PLAYING` 或 `RESULT`。

- 基类 `gateways/reward_gateway.gd`：`begin(id, req)` / `cancel(id)` / `answered(id, granted, data)`
- 三种接法：`--reward=mock`（`--ad-delay=` 秒后放行）、`--reward=http`（用户自己的答题程序）、`--reward=off`
- **HTTP 契约**（`docs/reward-api.md`）：`POST {base}/reward/open` → `{"ticket"}` 或 `{"granted","detail"}`；
  `GET {base}/reward/poll?ticket=` → `pending|granted|denied`；`POST {base}/reward/cancel?request_id=`。
  超时兜底 `RewardService.timeout_sec`（默认 45s）
- **参考实现** `tools/reward_server.py`（仓库根，与 screen/controller 平级，**不要放进 Godot 项目**）
- **顺序铁律**：`_tick_playing` 里**先问奖励再判胜负**；`_begin_reward()` **先置 REWARD 再发请求**（网关可能同步回答）
- 额度由玩法自己管（拔河：复活 1 次 + 道具 1 次）

## 输入事件消费规矩（踩过坑）
`PlayerSession.events` 是**队列**，必须用 **`drain_events()` 取走即清空**，不能直接读 `events`。
原因：无头帧率远高于手机 60Hz，一次挥动的事件会在好几帧里躺着，直接读就重复计数。
队列 `MAX_PENDING_EVENTS = 8` 封顶；玩法 `setup()` 里再 drain 一次。
**通用教训：任何「每帧读一次、由别处覆写」的状态，都要么取走即清空，要么用帧号去重。**

## 大厅与开局
- `core/lobby.gd`（`class_name Lobby`）纯逻辑无展示：`refresh(n)` / `move(±1)` / `select_id(id)` /
  `index_of(id)` / `selected_entry()` / `ready_count()` / `blocked_hint()`。
  数据全来自注册表，**加玩法不用改这里**。重建时光标尽量停在原玩法上。
- `GameRegistry.evaluate(n)` → `{id,name,desc,min/max_players,players,ready,reason}`；
  `available_for(n)` = 其中 `ready` 的。两者必须一致，自检组 [17] 守着
- 操作：`↑↓` 移光标、回车/空格开局、数字 1-9 直选。用内置 `ui_*` 动作 + 读 `unicode` 取数字
  ⇒ **兼容手柄十字键和电视遥控器**
- 人数不满足时 `_start_selected()` 只提示不硬开（`_hint` 显示在大厅）

### 大厅 UI 结构（`scripts/ui/hud.gd`）
`setup()` 末尾调 **`_build_all()`**（页面容器 + rows + content + 三次 `_build_*`）。
**加东西一律加在 `_build_all()` 最后那三行之前** —— 曾经把 `_glow()` 插进 `setup()` 中间，
把后面的页面构建变成死代码，`_result_layer` 全是 null（120 次/帧的 Nil 赋值报错）。
- 背景：奶油纸 + 两团径向微光（删除 top_band/bottom_band）
- 状态条：全圆角药丸 + **8 个席位圆点**（`_fill_seats` 建、`_carve_seats` 按在线数改 state）
  + 右端网络状态。**`_fill_seats(rec)` 漏调的症状：自检数到 0 个圆点、全组断言连锁失败**
- HUD 有**两份状态条**（大厅 + 对局各一份），各画一圈席位 → 自检统计要用 `is_visible_in_tree()` 筛
- 磁贴 = 通栏封面（定高 `THUMB_H`）+ 序列方块 + 内边距文字区 + 名字 + 人数 + 状态徽章
- 空位卡 = 虚线框（`dashed_panel`）+ ＋方块 + 一行说明。⚠️ **只占一格**：
  曾让 ghost `stretch_ratio` 吃满剩余宽度，实拍否掉（1183 宽占屏幕 2/3，主次反了）。
  剩余位置用**透明 spacer** 撑宽（不给的话本行磁贴被拉宽，翻页时整屏横着抽一下）
- 详情条 = 墨底面板 + 左文字（名字/描述/hint）+ 右红色「开始」按钮（是**指示器**，`mouse_filter = IGNORE`）
- `--lobby-only`… 没有；大厅菜单无头看不见 → `_refresh_lobby()` 重建时打进日志
  （`[main] 大厅清单（N 人）：…`），这是无头验证菜单内容的唯一窗口

## 当前玩法
**拔河**（`minigames/tug/`）首个玩法，存在意义是**验证框架接口够不够用**。
偶数槽位左队 / 奇数右队；**对着手机往上蹦，蹦得越密拉力越大**；拉到 ±1 出线，40 秒到点看谁占优。
倒计时 **5 秒**。对局屏**只有顶部一条细药丸**（`剩 N 秒 | 左 · 右 ❤n ★n`）+ 全宽 3D 场地，
没有左信息栏、没有底部玩家名单（用户明确要求「整个游戏画面都被文字挡住了」）。
奖励：**压线不立刻判负**（等落后方答题救回）；落后 ≥0.55 且 ≥8 秒可答题换「猛力一拽」（+0.35）。各限 1 次。

**「蹦」的强度模型**（`input/motion_filter.gd`，会漏到真机的坑）：
- 只认**向上**：`accel.y` 高出「自身慢速均值」才算一次冲高；`jump` 冲高取 max、不蹦按时间衰减
  → 越密越强。玩法侧 `rope += dir * JUMP_PULL_PER_SEC(0.30) * s.jump() * delta`。
- **密度反转 bug**：慢速均值被密集冲量的尾巴抬高 → 冲量反而变小 → **越密越弱**（小孩蹦越快越推不动）。
  修法：**冲高期冻结基线；非冲高时基线向下跟快、向上跟极慢**（`JUMP_EMA_RISE := 0.0005`）。
  自检判据「同冲量越密平均 jump 越大」就是守这条的。
- **倾斜通道**：拔河已不消费（常量删除），但输入层 `MotionFilter.tilt` / `PlayerSession.tilt()` 保留。
  别轻易加回 —— 倾斜一旦有收益，「歪着拿住不动」就是最优解，蹦就废了。

## 环境与操作
- **版本管理**：`https://github.com/121ZM/HomeGame.git`（**私有**，整个 HomeGame 一个仓库，
  `screen/` + `controller/` + `docs/` + `tools/` 全在内）。分支 `main`。
  **走 SSH 不用 HTTPS**（HTTPS 要 PAT，他没配凭据助手）：
  - 密钥用 **`~/.ssh/zm.pem`**（RSA 2048，早已注册在 GitHub，测试返回
    `Hi 121ZM! You've successfully authenticated`）。**别用别的新生成 ed25519** ——
    他 keyring 里那把（`SSH_AUTH_SOCK=/run/user/1000/gcr/ssh`，GNOME Keyring 代管）
    **没在 GitHub 注册**，会 `Permission denied (publickey)`。
  - `~/.ssh/config` 有 `Host github.com` → `IdentityFile ~/.ssh/zm.pem` + `IdentitiesOnly yes`。
  - `.gitignore` 忽略 `screen/.godot/`（2.6MB 引擎缓存，clone 后 `--import` 重建）；
    **`.uid` 文件保留入库**（Godot 4.4+ 靠它稳定引用脚本）。
  - `screen/addons/godot_ai/`（第三方插件）**入库**了，293 文件占入库文件一半多。
- Godot 4.7.2 标准版 `~/DEV/godot-4.7.2-stable/`，启动器 `~/.local/bin/godot`
- **新建/克隆项目第一件事**：`godot --headless --path <项目> --import`。
  只跑 `--quit` 不生成 `.godot/`，全局 `class_name` 会全部解析失败
- 无头验证首选：`--headless --path <项目> <场景> -- <参数>`，`print()` 仍到 stdout
- **`--quit-after N` 是帧数不是秒数**；无头 main.tscn 全链路约 **80fps**（22000 帧 ≈ 4.5 分钟），轻场景 ~200fps
- 自检：`godot --headless --path screen res://tools/selfcheck.tscn`，全过返回 0（可接 CI）。
  **改 core/ 或加玩法后跑一遍。**当前 18 组 / 269 项（框架 197 + 玩法 72）；末尾哨兵 `EXPECTED_MIN`（195）**加测试要同步调大**
  —— 防静默：GDScript 运行时错误不抛异常只中断当前函数，一组崩掉后总量不达标会「0 失败 + 退出码 0」地绿着
  ⚠️ **不存在 `-- --selftest` 这个 flag**（误用会进正常游戏、卡在「等待手机连接」直到超时退出码 124）。
  ⚠️ 实测踩过：`selfcheck.gd` 里一个键名写错（`rd["strip"]`，真实键是 `seats`）**静默吃掉约 18 条断言**，
  每跑必抛 SCRIPT ERROR 却哨兵没抓到。**键名写错 + 异常被吞 + 哨兵太松 = 静默盲区。**
- **`--autostart=<id>` 走大厅同一条路**（`select_id` → `_start_selected()`），不自己判人数。
  它等人数稳定 1.5s（`AUTOSTART_SETTLE_SEC`）再放弃 —— 模拟器逐个上线，刚连上第一个就判死刑会误杀 `--sim-players=4`
- **`_process` 里 `_refresh_lobby()` 必须排在 `_maybe_autostart()` 前**：
  反了的话玩家刚连上那帧菜单还是旧的（0 人）—— 症状「5 人也说还差 2 人」
- 模拟器 `res://tools/simulator.tscn` 独立可跑场景，改 `target_host` 就能当真实手机端用。
  支持 `--name= --pid= --host= --period= --anon`
- 主场景参数：`--simulate --sim-players=N --max-players=N --autostart=<id> --sim-step=0.6`
- 奖励参数：`--reward=mock|http|off`、`--reward-url=`、`--ad-policy=grant|deny|alternate|timeout`、
  `--ad-delay=`、`--reward-timeout=`
- **`pkill -f` 会杀掉自己**（`bash -c` 命令行含同样字符串）。用 `ps -eo cmd | grep -E "[s]imu[l]ator"` 这种不自匹配写法；
  杀自己起的服务用 `ss -lptnH "sport = :PORT" | grep -oP 'pid=\K[0-9]+'` 拿 PID 再 kill
- Python 后台跑（`nohup ... > log &`）日志攒缓冲，脚本里要 `sys.stdout.reconfigure(line_buffering=True)`

## 编辑器插件：Godot AI（MCP）
2026-09-22 装。`screen/addons/godot_ai/`（v4.1.0，293 文件全部与官方 manifest 哈希一致）。
链路：`WorkBuddy/Codex` ←stdio `godot-ai attach` ← HTTP 8000 ← Godot 插件 ← WS 9500。
- **能力记录必须放在私有目录**：`~/.config/godot-ai/capabilities`。
  服务端要求**祖先目录组/其他都不可写**（`mode & 0o022 == 0`）。
  `~/.config` 若是 0775 会以 `PermissionError: capability path has an unsafe ancestor` 阻塞启动 →
  `chmod g-w ~/.config`。失败详情在 `app_userdata/<项目>/godot_ai_server_startup.json`
- 插件**不会无限重试**；失败后改权限也需手动 `项目设置→插件` 关掉再打开
- 排查顺序：`godot_ai_server_startup.json` → 端口 8000/9500 → `ps` 有无 python 服务端
- 客户端配置由 dock 生成（WorkBuddy 不在支持列表，走「Run this manually」）；
  命令形态 = `uvx <一长串 uv 解析策略参数> --link-mode copy --from godot-ai==<ver> godot-ai attach --port 8000 --ws-port 9500`
- **用 MCP 做视觉验证（本项目唯一能「看见画面」的手段）**：
  `session_activate("HomeGame")` → `project_run(mode="main")` →
  `editor_manage(op="game_eval", params={code: "..."})` 在游戏进程里
  `get_viewport().get_texture().get_image().save_png(...)`。
  **`editor_screenshot` 不落盘**（只能看，不能存）。收尾 `project_manage(op="stop")`
  （游戏在跑时写操作会被 `EDITOR_PLAYING` 拒掉，先 stop 再改再 run）
- **MCP 传不了运行参数**：`project_run` schema 无 args 字段，`editor/run/main_run_args`
  在 settings 黑名单 → `--simulate --sim-players=4` 在 MCP 下无效。要看「有人在线」的观感
  只能靠 `Lobby.refresh(n)`（状态条数字不受它控制）
- **游戏窗口一切到后台，`game_eval` 立刻 `EVAL_GAME_NOT_READY`（main loop is not advancing）**。
  绕过：把「模拟 + 等待 + 截图 + 返回」合并进**同一次** eval，一次调用内完成
- `game_eval` **不支持嵌套函数声明、不支持 try/except**（报 `EVAL_COMPILE_ERROR`）
- 内部类判定可用：`is UiKit.SeatDot` 生效
- **编辑器全局类缓存不会因脚本新增 `class_name` 而更新** → Debugger 刷屏
  `Parse Error: Identifier "X" not declared`（游戏本身没事）。修：`filesystem_manage(op="scan")`；
  无头侧对应 `godot --headless --import`
- **沙箱与宿主机是不同的网络命名空间**：沙箱内 `ss` 看不到宿主机的监听，沙箱里起的模拟器
  **连不上编辑器里跑着的那局游戏**（两个 127.0.0.1 不是同一个）⇒「编辑器跑真画面 + 假手机喂数据 + MCP 截图」
  在沙箱内走不通。走 MCP / 文件系统不受影响
- 想给编辑器 F5 加参数（改 `project.godot` 的 `editor/run/main_run_args`）**不生效**：
  编辑器用的是启动时载入的 ProjectSettings 副本，且该键被 `settings_set` 明确拒绝

## 已知坑（跨主题）
- 图片 Read 会**按内容哈希去重**：截图没变时返回「内容未变」。要 `cp` 成带时间戳的新文件名再读
- `Font.has_char()` **只查根字体、不查回退链** —— 只看它会把结论下反。Godot 内嵌字体无中文，
  靠 `allow_system_fallback` + fontconfig 兜住（本机 Noto Sans CJK）。判断能否显示要看
  `get_string_size()` 宽度（CJK 应 1em/字）
- 拿「忙/不忙」这种二值判断分派 UI，状态机一多出第三阶段就会静默漏掉一个（结算文案 bug 的根因）
- GDScript lambda 捕获**按值**，给捕获的局部变量重新赋值外面看不到；可变状态要塞 Dictionary

## 待定 / 未做
- **真机手感未验证**（所有验证都是模拟器正弦波）—— 唯一剩下的瓶颈，需用户出手机。
  建议顺序：先验手感，再写第二个玩法（`MotionFilter` 的阈值全是拍出来的）
- 更多玩法：大鱼吃小鱼、体感竞速、挥击类、猜演类
- 手势映射未定型；手机屏幕的角色（纯手柄 vs 私有信息展示）未定
- 字体：打包 Android 有豆腐块风险（需子集化嵌字）
- 音效、手机振动反馈未实现
- 3D 场绳子和绳结在取景框里几乎看不见（被大厅卡挡住），取景该调
- `UdpServer.TIMEOUT_MS = 3000` 偏紧（手机放下两秒就判离线）→ 建议 5–8 秒或「掉线保留槽位 N 秒」
- `game_flow.gd` 两处待修：`drop_player` 该用 `not current.accepts_count(n)` 而非 `< min_players()`；
  `reward_settled.emit()` 该移到 `apply_reward()` 之后
- 产品判断：拔河道具「落后才解锁」可能被策略化成「故意先落后换猛推」。
  第二个玩法里该定下原则：奖励是补偿（快输才给）还是诱惑（随时可换）
- 明确**现在不要做**：第三个玩法（手感没验）、商店/成就/等级、服务端/账号、`--reward=http` 的鉴权
- 第二阶段：Android SDK 命令行工具（免 sudo，装到 `~/.local`）+ `controller/` 手机端 App
