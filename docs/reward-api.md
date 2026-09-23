# 奖励接口 —— 看广告 / 答题得道具、复活

> 大屏**不关心奖励从哪来**。它只在需要的时候问一句「给不给」，拿回一个布尔值就继续。
> 所以「看广告」「答题」「家长审批」对框架而言是同一件事，换个后端就换了一种玩法激励。

---

## 1. 一句话架构

```
玩法层 (TugOfWar)          框架层 (GameFlow)              奖励后端（你的程序）
  绳子被拔过线
  pending_reward_request() ─► 挂起对局 → REWARD 状态
                              RewardService.request() ──►  POST /reward/open
                                                             出题 / 播广告
                              （对局冻结，大屏显示「答题中」）        │
                              GET /reward/poll  ◄───────────── 轮询
                              ◄── {"state":"granted"} ────────  孩子答对了
  apply_reward(绳子回中线) ◄─ REWARD → PLAYING
```

奖励后端**不负责显示题目**。题目显示在你自己的程序里（网页、手机 App、别的窗口都行），
大屏只显示一句「答题中… 答对可得复活」。

---

## 2. 大屏怎么接你的程序

```bash
godot --path screen -- --reward=http --reward-url=http://127.0.0.1:8787
```

| 参数 | 作用 |
|---|---|
| `--reward=mock` | 开发用假网关（默认），`--ad-delay=` 秒后自动放行 |
| `--reward=http` | **接你自己的程序**，配合 `--reward-url=` |
| `--reward=off` | 不开奖励：玩法要奖励一律按「拿不到」算，不会卡死对局 |
| `--reward-url=http://127.0.0.1:8787` | 你的程序地址 |
| `--reward-timeout=45` | 大屏最多等多久（秒），到点按「拿不到」算并撤单 |

---

## 3. 协议（3 个端点，JSON / UTF-8）

### 3.1 开一单

```http
POST {base}/reward/open
Content-Type: application/json

{
  "request_id": 1,                 // 大屏内部请求号，回包原样带回最好
  "kind": "revive",                // revive（复活）| item（道具）
  "item_id": "",                   // kind=item 时有值，如 "big_pull"
  "slot": 1,                       // 玩家槽位号（0..N-1）
  "player": "小红",                 // 玩家名字（大屏上显示的那个）
  "players": ["小明", "小红"],       // 本局全部玩家
  "game": "tug",                   // 玩法 id
  "game_name": "拔河",
  "reason": "绳子就要被拔过线了 —— 答对一题，把它拉回中线"
}
```

两种回法，任选：

```json
{"ticket": "abc123"}                        // 要出题 / 要播广告，慢慢来
{"granted": true, "detail": "答对第 3 题"}   // 已经能立刻判定
```

### 3.2 问结果（大屏每 0.4 秒轮询一次）

```http
GET {base}/reward/poll?ticket=abc123
```

```json
{"state": "pending"}                        // 还在答题 / 还在播
{"state": "granted", "detail": "答对啦：family 指的是？"}
{"state": "denied",  "detail": "答错了，正确答案是 家庭"}
```

### 3.3 撤单（可选实现）

大屏超时或对局被中止时会调它，收到就把它丢掉：

```http
POST {base}/reward/cancel?request_id=1
```

---

## 4. 几条必须知道的规矩

- **`detail` 是给人看的一句话**，会直接印在大屏提示里，写中文没问题。
- **答多久都行，但大屏只等 `--reward-timeout` 秒**（默认 45）。到点按「拿不到」算 ——
  也就是孩子这道题白答了，比赛继续。想宽松就把它调大。
- **单次轮询失败不算数**，下一轮重试；只有超时才判负。所以你重启服务、改代码不会误判。
- **跨设备时你的程序必须监听 `0.0.0.0`**，绑 `127.0.0.1` 的话手机连不上 ——
  局域网方案的经典坑。
- **额度是玩法定的**：拔河一局只给「复活 1 次 + 道具 1 次」，游戏自己扣，你的程序不用管。
- **一局里可能来两单**：先落后要道具、后压线要复活。别假设只有一次。

---

## 5. 参考实现：`tools/reward_server.py`

一个能直接跑的最小版本（也是大屏 HTTP 网关的联调对端），零依赖，只用标准库：

```bash
cd HomeGame/tools
python3 reward_server.py                     # 监听 0.0.0.0:8787，人工答题
python3 reward_server.py --auto              # 3 秒后自动放行（不想手动点时用）
python3 reward_server.py --auto --deny       # 自动拒绝（测「答错」分支）
```

然后浏览器打开 `http://<这台机器的局域网IP>:8787` —— 会看到题目和三个选项，
手机上也能开。孩子点一下，大屏立刻放行。

配套大屏：

```bash
godot --path screen -- --reward=http --reward-url=http://127.0.0.1:8787
# 想让一局里真的出现「压线 → 复活」，把两队实力拉开：
godot --path screen -- --simulate --sim-players=2 --sim-step=6 \
      --autostart=tug --reward=http --reward-url=http://127.0.0.1:8787
```

题库在文件开头的 `QUESTION_BANK`，格式是 `(题干, [选项…], 正确项下标)`，
换成课本单词表即可 —— 「边玩边学」的学就落在这一行上。

---

## 6. 换成真广告

你的广告 SDK 只要能回答「看完没 / 给不给」，就在 `HttpRewardGateway` 的位置
再写一个网关（继承 `scripts/core/gateways/reward_gateway.gd`，实现 `begin()` /
`cancel()`，判定完 `answered.emit(id, granted, {"detail": "..."})`），
然后在 `main.gd` 的 `_setup_reward_gateway()` 里加一个分支。
**玩法层一行都不用动** —— 这是整个框架的设计前提。

---

## 7. 相关文件

| 文件 | 职责 |
|---|---|
| `screen/scripts/core/gateways/reward_gateway.gd` | 网关基类（谁给奖励） |
| `screen/scripts/core/gateways/http_gateway.gd` | HTTP 后端实现（就是本文档的对端） |
| `screen/scripts/core/gateways/mock_gateway.gd` | 开发用假网关 |
| `screen/scripts/core/reward_service.gd` | 转发 + 超时兜底 + 撤单 |
| `screen/scripts/core/game_flow.gd` | `REWARD` 状态：挂起对局 |
| `screen/scripts/core/minigame.gd` | 玩法侧的 4 个钩子 |
| `screen/scripts/minigames/tug/tug_of_war.gd` | 拔河的复活 / 道具实现 |
