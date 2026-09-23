#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
答题奖励服务 —— 大屏（HomeGame/screen）的「看广告得道具 / 复活」后端参考实现。

这个文件就是**你自己要写的那类程序**的一个最小可用版本：
大屏在玩法需要奖励时（要复活、要道具）来问你一句「给不给」，你出题、判分，
把结论告诉大屏。框架完全不关心奖励从哪来 —— 广告、答题、家长审批都行。

用法
    python3 reward_server.py                    # 监听 0.0.0.0:8787，网页人工答题
    python3 reward_server.py --auto             # 不人工点，N 秒后自动放行（联调用）
    python3 reward_server.py --auto --deny      # 自动拒绝
    python3 reward_server.py --port=9000

大屏那边这样接
    godot --path screen -- --reward=http --reward-url=http://127.0.0.1:8787

孩子怎么答
    浏览器打开 http://<这台机器的局域网IP>:8787   —— 会看到题目和选项，点一下即可。
    手机、平板、另一台电脑都能开（服务监听 0.0.0.0，别只绑 127.0.0.1）。

协议（三个端点，全部 JSON，UTF-8）
    POST /reward/open   大屏开一单   → {"ticket": "..."} 或 {"granted": true, ...}
    GET  /reward/poll   大屏问结果   → {"state": "pending"|"granted"|"denied", "detail": "..."}
    POST /reward/cancel 大屏撤单
详见 docs/reward-api.md。
"""

import argparse
import json
import random
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

# ----------------------------------------------------------------- 题库
# 换成你自己的题库即可（比如从课本单词表生成）。格式：题干 + 选项 + 正确项下标。
QUESTION_BANK = [
    ("“苹果”的英文是？", ["apple", "banana", "orange"], 0),
    ("7 × 8 = ?", ["54", "56", "64"], 1),
    ("“星期一”的英文是？", ["Sunday", "Monday", "Saturday"], 1),
    ("3/4 化成小数是？", ["0.34", "0.75", "0.43"], 1),
    ("“书”的英文是？", ["book", "look", "cook"], 0),
    ("12 + 39 = ?", ["41", "51", "61"], 1),
    ("“water” 是什么意思？", ["火", "水", "土"], 1),
    ("一个正方形有几条边？", ["3", "4", "6"], 1),
    ("“family” 指的是？", ["朋友", "家庭", "学校"], 1),
    ("6 × 7 = ?", ["42", "36", "48"], 0),
    ("“blue” 是什么意思？", ["蓝色", "绿色", "红色"], 0),
    ("100 − 37 = ?", ["63", "67", "73"], 0),
]


class Quiz:
    """当前等待作答的那一单。大屏在等，孩子在答。"""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.ticket = ""
        self.reward = {}        # 大屏送来的那一单（kind/player/game/reason…）
        self.question = ""
        self.options: list = []
        self.answer_index = -1
        self.state = "idle"     # idle | pending | granted | denied
        self.detail = ""
        self.started_at = 0.0

    def open(self, reward: dict, auto: str = "", auto_sec: float = 0.0) -> str:
        with self.lock:
            self.ticket = uuid.uuid4().hex[:12]
            self.reward = reward
            q, opts, idx = random.choice(QUESTION_BANK)
            self.question, self.options, self.answer_index = q, list(opts), idx
            self.state = "pending"
            self.detail = ""
            self.started_at = time.time()
            ticket = self.ticket
        if auto:
            # 注意：自动放行要选**正确项**，不能固定选 0 —— 正确项下标是随机的
            pick = self.answer_index if auto == "grant" else -1
            threading.Timer(auto_sec, lambda: self.answer(pick, auto=True)).start()
        return ticket

    def answer(self, choice: int, auto: bool = False) -> bool:
        with self.lock:
            if self.state != "pending":
                return False
            ok = choice == self.answer_index
            self.state = "granted" if ok else "denied"
            if ok:
                self.detail = ("自动放行" if auto else "答对啦") + "：" + self.question
            else:
                right = self.options[self.answer_index] if 0 <= self.answer_index < len(self.options) else "?"
                self.detail = ("自动拒绝" if auto else "答错了") + "，正确答案是 " + str(right)
            return True

    def cancel(self) -> None:
        with self.lock:
            self.state = "idle"
            self.ticket = ""
            self.reward = {}
            self.detail = ""

    def public(self) -> dict:
        """给网页看的快照（不含答案）"""
        with self.lock:
            return {
                "state": self.state,
                "question": self.question,
                "options": self.options,
                "reward": self.reward,
                "detail": self.detail,
                "left_sec": round(max(0.0, self.timeout_sec - (time.time() - self.started_at)), 1)
                if self.state == "pending" else 0.0,
            }

    timeout_sec: float = 45.0


QUIZ = Quiz()


# ----------------------------------------------------------------- 网页
PAGE = """<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>答题得道具 / 复活</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
         background:#f5f6f8; color:#1b1f24;
         font-family:system-ui,-apple-system,"Noto Sans CJK SC","PingFang SC",sans-serif; }
  .card { width:min(560px,92vw); background:#fff; border-radius:20px; padding:28px 26px 22px;
          box-shadow:0 8px 32px rgba(0,0,0,.09); }
  .tag { display:inline-block; font-size:13px; padding:4px 12px; border-radius:999px;
         background:#eef1f6; color:#4a5260; }
  .tag.on { background:#fdecec; color:#c0392b; }
  h1 { font-size:22px; margin:14px 0 6px; }
  .sub { font-size:14px; color:#6b7280; margin-bottom:22px; line-height:1.6; }
  .q { font-size:26px; font-weight:600; margin:18px 0 20px; line-height:1.45; }
  button { display:block; width:100%; font-size:19px; padding:15px 18px; margin-bottom:12px;
           border:2px solid #dfe3ea; border-radius:14px; background:#fff; color:#1b1f24;
           cursor:pointer; text-align:left; transition:.15s; }
  button:hover { border-color:#8aa4ff; background:#f7f9ff; }
  button:active { transform:scale(.99); }
  button.ok  { border-color:#3ba55d; background:#eefaf1; }
  button.bad { border-color:#d9534f; background:#fdeeee; }
  button:disabled { opacity:.5; cursor:default; }
  .msg { margin-top:6px; font-size:15px; min-height:22px; color:#4a5260; }
  .idle { font-size:15px; color:#8b93a1; text-align:center; padding:34px 0; line-height:1.8; }
</style></head><body>
<div class="card">
  <span class="tag" id="tag">等待中</span>
  <h1 id="title">游戏里还没有求助</h1>
  <div class="sub" id="sub">孩子在对局中需要「复活」或「道具」时，这里会弹出题目。<br>
       答对 → 大屏自动放行；答错 → 这局拿不到，比赛继续。</div>
  <div id="stage"></div>
  <div class="msg" id="msg"></div>
</div>
<script>
let answered = false, lastTicket = "";
async function tick() {
  try {
    const r = await fetch("panel/state", {cache:"no-store"});
    const s = await r.json();
    render(s);
  } catch (e) { /* 服务重启中，忽略 */ }
  setTimeout(tick, 700);
}
function render(s) {
  const tag = document.getElementById("tag");
  const stage = document.getElementById("stage");
  const msg = document.getElementById("msg");
  const pending = s.state === "pending";
  const reward = s.reward || {};
  const kind = reward.kind === "revive" ? "复活（绳子拉回中线）"
             : reward.kind === "item" ? "道具「" + (reward.item_id || "") + "」" : "奖励";
  tag.textContent = pending ? "有条目！剩 " + s.left_sec + " 秒" : "等待中";
  tag.className = "tag" + (pending ? " on" : "");
  document.getElementById("title").textContent = pending ? kind : "游戏里还没有求助";
  document.getElementById("sub").innerHTML = pending
    ? "玩家：<b>" + (reward.player || "?") + "</b>　玩法：" + (reward.game_name || reward.game || "?")
      + "<br>" + (reward.reason || "")
    : "孩子在对局中需要「复活」或「道具」时，这里会弹出题目。<br>答对 → 大屏自动放行；答错 → 这局拿不到，比赛继续。";

  if (!pending) {
    stage.innerHTML = '<div class="idle">' + (s.state === "idle" ? "去玩吧，有事我叫你" : "") + '</div>';
    msg.textContent = s.detail || "";
    answered = false; lastTicket = "";
    return;
  }
  if (s.question !== window._q) {
    window._q = s.question;
    stage.innerHTML = '<div class="q"></div>' +
      s.options.map((o, i) => '<button data-i="' + i + '"></button>').join("");
    stage.querySelector(".q").textContent = s.question;
    stage.querySelectorAll("button").forEach(b => b.textContent = s.options[+b.dataset.i]);
    stage.querySelectorAll("button").forEach(b => b.onclick = () => pick(+b.dataset.i, b));
    answered = false;
    msg.textContent = "选一个答案";
  }
}
async function pick(i, btn) {
  if (answered) return;
  answered = true;
  // 本地不给对错反馈，交给服务端判 —— 孩子看不到「点哪个对」的提示
  await fetch("panel/answer", {method:"POST", headers:{"Content-Type":"application/json"},
                               body: JSON.stringify({choice: i})});
}
tick();
</script></body></html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "HomeGameReward/1.0"

    # ---- 小工具
    def _json(self, obj: dict, code: int = 200) -> None:
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _html(self, text: str) -> None:
        body = text.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return {}

    def log_message(self, fmt: str, *a) -> None:  # 别把每条轮询都刷到终端
        if "/reward/poll" in (a[0] if a else ""):
            return
        print("[reward] " + (fmt % a))

    # ---- 大屏接口
    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path == "/reward/open":
            req = self._body()
            ticket = QUIZ.open(req, auto=AUTO, auto_sec=AUTO_SEC)
            kind = req.get("kind", "?")
            print("[reward] 开单 ticket=%s  %s → %s（%s）  %s" % (
                ticket, req.get("player", "?"), kind,
                req.get("item_id") or "-", req.get("reason", "")))
            print("[reward]   题目：%s  %s" % (QUIZ.question, QUIZ.options))
            if INSTANT:
                QUIZ.answer(QUIZ.answer_index)
                self._json({"granted": True, "detail": "联调模式：直接放行"})
                return
            self._json({"ticket": ticket})
        elif path == "/reward/cancel":
            q = parse_qs(urlparse(self.path).query)
            print("[reward] 大屏撤单 request_id=%s" % q.get("request_id", ["?"])[0])
            QUIZ.cancel()
            self._json({"ok": True})
        elif path == "/panel/answer":
            choice = int(self._body().get("choice", -1))
            accepted = QUIZ.answer(choice)
            print("[reward] 孩子作答 → %s（%s）" % ("受理" if accepted else "无效/已判过", QUIZ.detail))
            # accepted 只表示「这票算数」，对错看 detail 与 state
            self._json({"accepted": accepted, "detail": QUIZ.detail})
        else:
            self._json({"error": "unknown path"}, 404)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/reward/poll":
            q = parse_qs(urlparse(self.path).query)
            ticket = q.get("ticket", [""])[0]
            with QUIZ.lock:
                if ticket and ticket == QUIZ.ticket and QUIZ.state in ("granted", "denied"):
                    self._json({"state": QUIZ.state, "detail": QUIZ.detail})
                else:
                    self._json({"state": "pending"})
        elif path == "/panel/state":
            QUIZ.timeout_sec = TIMEOUT
            self._json(QUIZ.public())
        elif path in ("/", "/index.html"):
            self._html(PAGE)
        else:
            self._json({"error": "unknown path"}, 404)


def main() -> None:
    global AUTO, AUTO_SEC, INSTANT, TIMEOUT
    ap = argparse.ArgumentParser(description="HomeGame 答题奖励服务")
    ap.add_argument("--host", default="0.0.0.0", help="监听地址（默认 0.0.0.0，手机才能连）")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--auto", action="store_true", help="不用人工点，自动作答")
    ap.add_argument("--deny", action="store_true", help="配合 --auto：自动答错")
    ap.add_argument("--auto-sec", type=float, default=2.0, help="自动作答延迟（秒）")
    ap.add_argument("--instant", action="store_true", help="联调：open 直接回 granted，不出题")
    ap.add_argument("--timeout", type=float, default=45.0, help="答题时限（秒，仅用于网页倒计时显示）")
    a = ap.parse_args()

    AUTO = "deny" if a.deny else ("grant" if a.auto else "")
    AUTO_SEC = a.auto_sec
    INSTANT = a.instant
    TIMEOUT = a.timeout

    # 重定向到文件时 Python 会攒缓冲，日志要等进程退出才看得到 —— 关掉它
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass

    srv = ThreadingHTTPServer((a.host, a.port), Handler)
    print("答题奖励服务已启动：http://%s:%d" % (a.host, a.port))
    print("  · 给孩子/家长开的答题页：http://<本机局域网IP>:%d" % a.port)
    print("  · 大屏这样接：godot --path screen -- --reward=http --reward-url=http://127.0.0.1:%d" % a.port)
    if AUTO:
        print("  · 自动模式：%s（%.1f 秒后）" % ("放行" if AUTO == "grant" else "拒绝", AUTO_SEC))
    if INSTANT:
        print("  · 联调模式：open 即 granted")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")


if __name__ == "__main__":
    main()
