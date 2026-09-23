class_name UiKit
extends RefCounted

## 大屏 UI 的样式底座 —— 「长什么样」的唯一来源。
##
## **基准分辨率 1920x1080**（见 project.godot）。所有像素值都是这个基准下的尺寸，
## 靠 `stretch/mode=canvas_items` 缩放到实际窗口/电视上。
## 换基准分辨率时**这里所有数值要等比例改** —— 否则在客厅距离上不是太小就是挤爆。
##
## 风格：**桌游盒 / 玩具感**（第 3 版 —— 按用户给的设计稿 `game-lobby-ui/index.html` 重做）
##
## 第 2 版是「现代、平涂、收敛」：不用渐变/投影、细描边、靠灰阶分层。
## 那一版做出的东西用户连续打回四次（「太粗糙了」「就几个字」），最后直接甩了一份
## HTML 设计稿过来，并明确拍板「**完全照设计稿**」—— 所以下面这些曾经的硬约束
## **本次全部作废**，不要再拿它们否决实现：
##   · ~~平涂，不用投影~~ → **用硬阴影**（`shadow_size`/`shadow_offset`），卡片要「浮起来」
##   · ~~不用渐变~~ → **用径向微光**做背景（见 hud.gd 的 `_lobby_backdrop`）
##   · ~~选中不许位移~~ → **选中态「贴纸式」位移**（外层 Control 用 offset 位移，不进布局）
##   · ~~细描边~~ → **统一 2~3px 墨色粗描边**（描边是这一版风格的主要来源，不能省）
##
## 第 3 版的风格骨架：
##   · **奶油纸底 + 墨色粗描边 + 硬阴影** —— 物理感来自「纸 + 墨 + 厚度」
##   · 圆角统一取设计稿的 `--radius`（磁贴和卡片**同档**，不再分大小）
##   · 层级仍靠「字号档位 + 三级墨阶（INK/INK_SOFT/INK_MUTE）」，不靠字重
##     —— Godot 默认字体只有一个字重，没有 font-weight 可用
##   · 玩家身份一律用彩色药丸/圆点，颜色取自 PlayerPalette（不在别处另定色）
##   · **状态色归系统、身份色归玩家，两边不许串**（见 `OK` 的说明）
##
## 这里只放**令牌和构件**，不放「显示什么」—— 后者全在 main.gd 的视图函数里。
## 全是 static，不持状态：一次调用造一个节点，谁用谁负责挂上去。

# ------------------------------------------------------------------ 令牌
#
# **色板整体换了暖调。** 设计稿是「奶油纸 + 墨」的桌游盒配色，全套色相从冷蓝灰
# 转到暖褐：底色偏黄、墨色偏褐、灰阶也带暖。改动是一整组的，不能只换底色 ——
# 换了底色不换墨色，暖底压冷墨，画面会显脏（这是上一版「去黄」之后又改回来的原因：
# 当时只去掉了底色的黄，墨色还是冷的，所以两层不咬合）。

## 描边与正文色。**暖褐黑**（设计稿 `--ink:#221f1a`），不是冷蓝灰、更不是纯黑。
## 纯黑压在奶油纸上会显得像印刷网点，偏褐的墨才像「墨」。
const INK := Color("221f1a")
## 次要文字（说明、范围、提示）。比 INK 浅一档、暖两档
const INK_SOFT := Color("5c564a")
## 三级文字（kicker、角标、占位提示）—— 比 INK_SOFT 再退一档。
## 取设计稿给空位卡文字的 `#b3a98f`：它是这套色板里唯一一个「暖灰退色」，
## 正好就是我们要的语感（比 INK_SOFT 更淡，但仍带纸味，不发青）
const INK_MUTE := Color("b3a98f")
## 卡片底：**奶油白**（设计稿 `--card:#fffdf6`）。不是纯白 —— 纯白在奶油纸底上会发蓝
const PAPER := Color("fffdf6")
## 嵌套层 / 浅底块（设计稿 `--paper-deep:#efe8d8`）
const PAPER_ALT := Color("efe8d8")
## 未选中项的暗底（旧令牌，保留兼容）
const PAPER_DIM := Color("e5dcc6")
## 结算遮罩：把 3D 场面压暗，让结算卡跳出来。
## **色相要跟着 INK 走** —— 原来是 `14141a`（冷调），墨色转暖后它会在画面上发蓝
const SCRIM := Color("221f1a99")
## 药丸的灰底（无身份的标签，比如「槽位 3 空」）
const PILL_MUTE := Color("e8e0cd")
## 分隔线（卡片内部把区块切开用，比描边淡）。
## 设计稿的 `--line:#d9d0bc` 比上一版深不少 —— 它是**虚线空位卡的描边色**，
## 要用在 2px 的描边上，太浅就看不见了
const LINE := Color("d9d0bc")
## `DIVIDER` 保留为 `LINE` 的别名（老调用点仍在用）
const DIVIDER := Color("d9d0bc")
## 普通描边色：设计稿只有一种描边色（就是墨色），这里跟着统一
const STROKE_COLOR := Color("221f1a")
## 警示色（「这个现在开不了」这类需要当场看见的话）
const WARN := Color("c2551f")

## **主强调色：番茄红**（设计稿 `--accent:#e8543f`）。
##
## 这一个颜色承担了整屏唯一的「动作」信号：标题那个「？」、底部的「开始」按钮。
## 设计稿的原则是「**开始路径唯一**」—— 红色只出现在这两个地方，多一处就失效了。
## 不要在装饰、分区、图标上用它。
const ACCENT := Color("e8543f")
## 番茄红的暗档，只用于「开始」按钮的下沿立体阴影（设计稿 `--accent-deep:#c93f2c`）
const ACCENT_DEEP := Color("c93f2c")

## 「可以开始」用的**系统**状态色（设计稿 `--ready:#2f9e6e`）。
##
## 上一版这里借的是 `PlayerPalette.color_for_slot(3)` 的那个绿 —— 等于把某个玩家的
## **身份色**拿去当系统状态用。屏幕上同时出现两种绿时，人会以为「这是我」。
## 身份色归玩家、状态色归系统，两边不许串。
##
## 现在的 `2f9e6e` 和 slot 3 的身份绿 `2fbf71` 色相差 30°，仍能区分开。
const OK := Color("2f9e6e")
## 「人还没齐」用的系统状态色（设计稿 `--waiting:#e2a400`）。
## 和 `OK` 成对使用：**绿 = 人齐可开局、黄 = 还差 N 人**，颜色即含义，不用读字。
const WAITING := Color("e2a400")
## 「等待」徽章上的**文字**色（设计稿 `.badge.waiting{color:#a97c00}`）。
##
## 为什么不能直接用 `WAITING` 当文字色：`e2a400` 那个黄压在奶油纸上对比度只有
## ~2.1:1，远低于 WCAG AA 的 4.5:1，会变成「一团黄看不出写的什么」。
## 设计稿自己也为此单独定了一个压深的 `#a97c00`（约 4.6:1）。
const WAITING_INK := Color("a97c00")

## 席位圆点用到的两个身份色中的「非玩家」档：
## · `SEAT_JOINED` —— 已加入但**不是房主**的席位（设计稿 `--teal:#2ba39a`）
## · 已加入且是房主 → 用 `ACCENT` 红（设计稿 `.pdot.host{background:var(--accent)}`）
## · 还没加入 → 45° 斜纹暖灰（见 `seat_dot()`）
const SEAT_JOINED := Color("2ba39a")
## 席位圆点的底纹（未加入态）：浅暖灰的圆底 + 一档更深的 45° 斜线
const SEAT_EMPTY_A := Color("eee9dc")
## 斜纹本身的颜色。**刻意比 `SEAT_EMPTY_A` 深两档** ——
## 实拍第一版用了只深一档的 `e3dcc9`，在屏幕上那 27px 的小圆里完全看不出斜纹，
## 8 个圆点读成一排空心圈。斜纹是「这是个空位」的唯一线索，必须看得见。
const SEAT_HATCH := Color("c9bda1")

## 描边分三档。**第 3 版整体加粗了一档** —— 设计稿的卡片是 `border:2px solid ink`，
## 换算到 1920×1080 基准（比例 1808/1180 = 1.532）约等于 3px。
##
## 「粗墨线」是这一版风格的主要来源之一（桌游盒的印刷感），**不能当装饰省掉**：
## 描边一细，整个界面立刻退回上一版那种「扁平后台」的观感。分档：
##   · `STROKE`        —— 卡片/磁贴的常规描边
##   · `STROKE_STRONG` —— **只在选中态**用，和常规档拉开一档才读得出「我现在在哪」
##   · `STROKE_THIN`   —— 药丸、keycap、分隔这类小构件的描边
##
## 注意设计稿里选中态**不只是加粗描边**，还叠了 `--shadow-pop` 的深阴影 + 贴纸位移。
## 三样一起说「我在这」，所以描边这一档不用拉得太开（4 vs 3 够）。
const STROKE := 3
const STROKE_STRONG := 4  # 强调态描边（选中的玩法磁贴）
const STROKE_THIN := 2    # 细描边（嵌套元素、药丸、keycap）

## 圆角。设计稿 `--radius:18px` × 1.532 ≈ **28**。
##
## **卡片和磁贴同档** —— 设计稿里 `.gcard` 直接引用 `var(--radius)`，
## 不存在上一版「磁贴圆角比卡片小一档」的分档。这里跟着统一，`TILE_RADIUS` 只是别名。
const RADIUS := 28
## 小圆角：keycap（设计稿 10px → 15）、药丸内嵌元素、`.num` 序号方块（8px → 12）。
## 取 14 —— 换算后落在设计稿这几种小构件之间，凑一个数就够
const RADIUS_SM := 14
const TILE_RADIUS := RADIUS  # 磁贴圆角 = 卡片圆角（见上）
const PAD := 36              # 卡片内边距
const GAP := 24              # 元素间距
const PILL_RADIUS := 999     # 药丸圆角（传 999，靠 Godot 夹到半高 = 全圆角）
const PILL_PAD := Vector2(27.0, 12.0)

## 卡片**硬阴影**的厚度与偏移（设计稿 `--shadow-card:0 2px 0 <墨 8%>`）。
##
## 设计稿用了两层阴影，但 `StyleBoxFlat` **只支持一层**（没有 spread 概念，
## 也没有第二个 shadow 槽），所以这里**只取硬阴影那层**：
## 它就是「纸片有厚度」的来源，也是设计说明里「贴纸感」的核心；柔投影（`0 10px 24px -14px`）
## 那层负 spread 本来在 Godot 里也做不出来，硬做只会得到一圈糊边。
##
## 2px × 1.532 ≈ 3 —— **3 在 1280×720 窗口里只有 2 个屏幕像素，是可见性临界值**。
## 实拍后若「看不出浮起」，把这个数加到 4，不要靠加深颜色来补
## （加深会在奶油纸上显脏，加厚才是「纸片变厚」）。
const SHADOW_CARD := 3
## 卡片阴影色：墨色 8% 透明（设计稿 `rgba(34,31,26,.08)`）
const SHADOW_CARD_COLOR := Color("221f1a14")
## 选中态「弹起」的阴影（设计稿 `--shadow-pop:0 4px 0 <墨 85%>`）。
## 4 × 1.532 ≈ 6。这一层**很实**（85% 不透明），是「贴纸被掀起来后投下的硬影」，
## 和常规卡片的淡阴影是完全两种东西 —— 谁被选中，隔着客厅也看得出来
const SHADOW_POP := 6
const SHADOW_POP_COLOR := Color("221f1ad9")

## 选中态「贴纸位移」的量（设计稿 `transform:translate(-3px,-3px)`，× 1.532 ≈ 5）。
##
## 实现上**不能直接改 `Control.position`** —— 磁贴由 `HBoxContainer` 摆位，
## 容器每帧都会把 `position` 覆写回去。做法见 `hud.gd` 的 `_tile_wrap()`：
## 外面包一层**普通 Control**（不是容器），让它给内层设 `offset_left/top`。
## 关键好处是**位移不进布局** —— 容器算的还是外层那个不动的尺寸，
## 所以再怎么位移也不会把旁边的卡挤动（这一点上一版担心得对，只是解法不是「禁止位移」）
const POP_SHIFT := 5

# ------------------------------------------------- 布局：左信息栏 + 右舞台
#
# 16:9 的大屏不像手机是一列到底。这里定成「左边一条信息栏，右边一整片给 3D 场地」：
#   · 信息栏宽度固定，内容永远不越界 ⇒ 卡片**结构上**不可能压住场地，
#     不用再靠调宽度/调相机去躲（早先那种「卡片压住绳子」的坑就是这么来的）
#   · 右边那片场地是主角，四周不留 HUD，绳子想拉多远都看得见
const MARGIN := 56            # 离屏幕边缘
const PANEL_W := 780.0        # 左信息栏宽度

# ------------------------------------------------- 布局：大厅网格
#
# 大厅是**一整屏的网格**，不再是「套在白色大卡里的一张清单」——
# 真实电视主屏不会把整个界面框在一个白框里。
#
# **大厅必须有自己的底**：HUD 是透明的一层，底下就是 3D 世界。对局屏要的就是让场地透出来，
# 但大厅里没有场地，直接透出来的是 3D 世界的清屏色（一圈青灰）—— 看着像界面没搭完。
# 所以大厅单独铺一块 `BACKDROP`，它只在大厅状态可见（见 hud.gd 的 `_lobby_backdrop`）。

## 大厅自己的底色：**奶油纸**（设计稿 `--paper:#f7f2e7`）。
##
## 上一版一度把它「去黄」成中性暖灰 `f2f1ee`，理由是「黄味重显旧」。
## 第 3 版改回来了 —— 用户拍板完全照设计稿。而且现在整套墨色都转成暖褐，
## 奶油纸配暖墨是咬合的；当初显旧的真正原因是**暖底压冷墨**，只去底色不换墨色才会脏。
const BACKDROP := Color("f7f2e7")
## 底部收边的色带（比底色再深一档 = 设计稿 `--paper-deep`）。
##
## 设计稿的背景是「奶油纸 + 两层径向微光」，没有色带这个概念；微光由 `hud.gd` 的
## `_lobby_backdrop` 负责铺。这里保留一个深一档的纸色，给需要「压住画面下沿」的地方用。
const BACKDROP_BOTTOM := Color("efe8d8")

## 大厅网格列数。**唯一一份** —— 布列（hud.gd）和四向导航（main.gd）都读它。
##
## 为什么是 3 而不是能铺更多：1080p 基准下留给网格的高度只有 ~460px，
## 而「带真封面的大卡」需要封面至少 250px 才看得清画的是什么。
## 一行 3 张时封面 546x334（约 1.63:1）；换两行每张只剩 218px，封面被压到 30px 高 ——
## 等于没有封面，又退回「几个字」。所以**只排一行**，玩法多于这个数就翻页
## （光标移出当前页，页面跟着走，不需要额外的翻页逻辑）。
## 将来要一页放更多，只改这一个数即可。
const LOBBY_COLUMNS := 3

## 磁贴文字区的内边距（设计稿 `.body{padding:16px 18px 18px}`）。
##
## ⚠️ **必须 ×k 换算，不能照抄 CSS 的数**（k = 1808/1180 = 1.532）。
## 这里曾经写死 18/14/18 —— 是**直接抄了设计稿的 CSS 值**，漏了换算。
## 症状：磁贴圆角（28）和网格间距（34）都是换算过的，只有内边距按原值来，
## 于是**卡片之间的空隙比卡片内部留白大得多**，文字顶着卡片边缘，
## 整体读起来「内边距太挤」——比例关系反了。
##   · 左右 18 → 27.6 → **28**
##   · 上   16 → 24.5 → **25**
##   · 下   18 → 27.6 → **28**
##
## 注意**这个内边距只包住文字区**，封面是「通栏」的（顶到描边、
## 左右不留白、底下压一条墨线）—— 见 `hud.gd` 的 `_game_tile()`。
const TILE_PAD := 28
## 文字区上边距。设计稿上边距比左右小一档（16 vs 18），换算后 25 vs 28。
## 因为封面墨线已经在视觉上给了「顶边」，文字再按 28 退会让名字行看着悬空。
const TILE_PAD_TOP := 25
## 磁贴间距（设计稿 `gap:22px` → 33.7 → 34）。34 比更早那版的 22 宽不少，
## 因为这一版卡片有硬阴影和位移，贴太紧会互相蹭到。
##
## **它和 `TILE_PAD` 的比例是有讲究的**：间距 34 ≈ 内边距 28 的 1.2 倍。
## 这个「卡外比卡内略大」的关系是设计稿的本意，破坏它（比如内外一样、或内大于外）
## 整屏就会读成「挤」或者「散」。
const TILE_GAP := 34
## 磁贴内部元素之间的间距（封面墨线与名字行之间、名字行与药丸行之间）。
## 设计稿 `.body` 内是 `margin-top:8px` 说明、`margin-top:12px` 徽章 —— 取中间值
const TILE_INNER_GAP := 14
## 磁贴封面区的高度。设计稿 `.thumb{height:150px}` × 1.532 ≈ **230**。
##
## 这是**固定高**，不是 `EXPAND_FILL` —— 设计稿的封面就是定高的通栏色块，
## 卡片剩下的高度由文字区自然决定。这样封面比例恒定，「像一条缝」的问题不会复发
## （上一版封面是可伸缩的，一遇到详情行多出几行就被压扁）。
const THUMB_H := 230.0
## 未选中磁贴的封面不透明度：焦点态靠**对比**退开，不靠挪位置。
## 挪位置会重排整屏（一重排视线就跳），改透明度只动像素。
const TILE_DIM_ALPHA := 0.72

## 基准视口宽度（= project.godot 的 `window/size/viewport_width`，改基准要同步改这里）。
## **实际视口宽度只会 ≥ 它** —— stretch/aspect 是 `expand`：「宽高比不符时多给空间」，
## 不是把内容裁掉。所以按它算出来的换行宽度是**安全下限**：
## 给窄了顶多多折一行，给宽了会直接撑破布局。需要给 `wrap_label` 定宽又拿不到
## 实时尺寸时（比如建节点那一刻），就用它算。
const VIEW_W := 1920.0
const VIEW_H := 1080.0

## 字号：按「隔着客厅看 55 寸电视」定，比显示器上的惯例大一档。
## 第一版照显示器尺寸定（BODY 20）又在 720p 窗口里看了一遍，偏小；现在按 1080p 基准定死。
const FONT_HUGE := 192   # 倒计时数字
const FONT_TITLE := 84   # 菜单主标题 / 结算标题
const FONT_BIG := 54     # 玩法名 / 小标题
const FONT_BODY := 39    # 正文
const FONT_SMALL := 32   # 说明、范围、脚注
const FONT_MICRO := 27   # 链路统计这类「只有调试才看」的角标

# ------------------------------------------------------------------ 构件


## 一块平涂圆角矩形。所有卡片/药丸的底座。
static func flat_box(
	bg: Color, border: Color = INK, width: int = STROKE, radius: int = RADIUS
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb


## 带内边距的卡片底（内容不会被描边贴脸）
static func card_box(
	bg: Color = PAPER, border: Color = INK, width: int = STROKE, radius: int = RADIUS
) -> StyleBoxFlat:
	var sb := flat_box(bg, border, width, radius)
	sb.set_content_margin_all(PAD)
	return sb


## 浅底「软条」：没有深描边的浅色块，用在状态条这类不该抢注意力的横条上。
## 内边距比 `PAD` 小 —— 它是配角，不该像卡片那样端着。
##
## 内边距 24 → 16：状态条现在**兼着装玩家药丸**（大厅那屏），它的高度直接决定
## 网格能拿到多少 —— 每省 8 个基准的内边距就是上下各 8、共 16 个基准还给封面。
## 16 仍比药丸自己的内边距大，视觉上还是「条里有东西」，不会挤。
static func soft_box(
	bg: Color = PAPER_ALT, border: Color = LINE, width: int = 0, radius: int = RADIUS_SM
) -> StyleBoxFlat:
	var sb := flat_box(bg, border, width, radius)
	sb.set_content_margin_all(16)
	return sb


## 卡片容器。鼠标事件一律穿透 —— 大屏操作走键盘/遥控器，UI 不该抢焦点。
static func card(bg: Color = PAPER, border: Color = INK, width: int = STROKE) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", card_box(bg, border, width))
	return p


## 大厅的玩法磁贴。和 `card()` 只有三处不同：内边距更小（磁贴是密排的）、圆角更小、
## 描边按选中与否分两档。
##
## **底色一律 `PAPER`，选中不换底**：换底会让未选的那几张看着像「不可用」，
## 而它们只是「还没被选中」。选中态由「重一档的墨色描边 + 封面不压暗 + ▶ 角牌」三样一起说。
##
## 名字 = `TILE_NAME` + **序号**（`game_tile_0`、`game_tile_1`…）。
##
## 为什么要序号：同一行里的磁贴本该同名，而 Godot 的 `add_child` 会把后来的那个
## **自动改名**成 `@PanelContainer@305`。按名字取样（自检就是这么干的）时，
## 被改名的那几张会整个漏掉 —— 症状是「注册了 2 个玩法，只数到 1 张磁贴」。
## 自带序号就不重名，也就不触发改名。
const TILE_NAME := "game_tile"
static func tile(selected: bool, index: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "%s_%d" % [TILE_NAME, index]
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# **描边一律墨色**（设计稿 `border:2px solid ink`，选中不选中都是墨线 —— 这套风格里
	# 「每张卡都有墨线」正是玩具感的一部分，未选中的卡用浅灰描边会立刻退回「后台感」）。
	# 选中态靠**加粗一档 + 弹起阴影 + 贴纸位移**三样一起说 ——
	# 但**光靠阴影在无头自检里验不出来**，所以描边差这一档（4 vs 3）必须保留，
	# 自检正是靠它来断言「选中和未选中读得出差别」的（selfcheck 的 `ws.size() == 2`）。
	var sb := flat_box(PAPER, INK, STROKE_STRONG if selected else STROKE, TILE_RADIUS)
	# 阴影：选中 = 深而实的「弹起影」，未选中 = 极淡的「纸片厚」
	if selected:
		sb.shadow_color = SHADOW_POP_COLOR
		sb.shadow_size = SHADOW_POP
	else:
		sb.shadow_color = SHADOW_CARD_COLOR
		sb.shadow_size = SHADOW_CARD
	# **内边距只给下、左、右** —— 封面上沿要顶到描边内壁上（设计稿 `.thumb` 是通栏色块，
	# 只在下沿有 `border-bottom:2px solid ink`，上方和左右都不留白）。
	# `StyleBoxFlat` 的 content_margin 是「内容盒相对描边内壁的缩进」，
	# 上边给 0 就是贴住 —— 这也顺手把「封面槽被压扁」的老问题从结构上消掉了。
	sb.content_margin_top = 0
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_bottom = TILE_PAD
	p.add_theme_stylebox_override("panel", sb)
	# ⚠️ **这里不能靠 `clip_children` 修封面圆角** —— 子节点永远画在父节点的
	# 描边**之上**，裁剪只能切掉「出界」的部分，挡不住封面把描边整个盖住
	# （盖住后描边只剩抗锯齿毛边，圆角看着像糊掉的灰线，实拍揪出来的）。
	# 真正的修法在 `hud.gd:_cover_slot()`：封面收进描边内壁、自己带同心圆角，
	# 裁剪也下放到封面那一层。
	return p


## 封面槽：磁贴里那块给玩法画封面的区域。
##
## **必须是普通 Control，不能是容器** —— 玩法的封面靠 `PRESET_FULL_RECT` 锚点铺满它，
## 而容器的子节点是由容器摆位的，锚点会被无视（尺寸算成 0，画出来一片空白，且不报错）。
## 名字 = `COVER_SLOT_NAME` + **序号**，理由同 `tile()`：一页里多个封面槽必然重名，
## 重名就会被 Godot 改名，按名字取样就漏。自检靠它验「每张磁贴都有封面槽」。
## **两个方向都要 `EXPAND_FILL`**，垂直那个尤其容易漏：
##   横向不给 → 宽度算成 0。槽里的 `plate` 锚 `PRESET_FULL_RECT`，于是也宽 0 ——
##   画出来是**一片空白**（`slot` 本身没有 `_draw`，不是容器也就不报错）。
##   症状：磁贴竖直方向被封面槽撑到 413px 高（`COVER_MIN_H` 只是下限，
##   槽最小高度 = 下限，而它在 VBox 里又 EXPAND，把整块都吃掉了），
##   封面却是一条**看不见的竖线**，名字和药丸被挤到底边。实拍才看得出来。
##   竖向不给 → 封面永远只有 `COVER_MIN_H` 高，磁贴上方留一大块空。
const COVER_SLOT_NAME := "cover_slot"
static func cover_slot(index: int) -> Control:
	var c := Control.new()
	c.name = "%s_%d" % [COVER_SLOT_NAME, index]
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.clip_contents = false
	return c


static func label(text: String, size: int = FONT_BODY, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## 会换行的说明文字。必须给一个最大宽度，否则 Label 会一路撑出屏幕。
static func wrap_label(
	text: String, max_width: float, size: int = FONT_SMALL, color: Color = INK_SOFT
) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(max_width, 0.0)
	return l


## 底色亮就用墨色字，底色暗就用白字 —— 免得黄底白字看不清。
static func readable_fg(bg: Color) -> Color:
	return INK if bg.get_luminance() > 0.55 else Color.WHITE


## 彩色药丸标签，玩家身份的统一画法。
## fg 传透明（默认）= 自动挑对比色。
static func pill(
	text: String, bg: Color, fg: Color = Color(0.0, 0.0, 0.0, 0.0), size: int = FONT_SMALL
) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := flat_box(bg, INK, STROKE_THIN, PILL_RADIUS)
	sb.content_margin_left = PILL_PAD.x
	sb.content_margin_right = PILL_PAD.x
	sb.content_margin_top = PILL_PAD.y
	sb.content_margin_bottom = PILL_PAD.y
	p.add_theme_stylebox_override("panel", sb)

	p.add_child(label(text, size, fg if fg.a > 0.0 else readable_fg(bg)))
	return p


## 现代版玩家药丸：浅底 + 同色细描边 + 左侧一个实心圆点。
## 颜色必须来自 PlayerPalette（`m["roster"]` 的 color 字段），不要就地另定色。
##
## 尺寸比 `pill()` 更紧（横向 18/20 → 14/16、纵向 9 → 5）：它现在装在大厅的**状态条里**，
## 那条本身不许长高（它一高网格就矮）。紧一档之后 8 个人也塞得进一行。
static func player_pill(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := flat_box(tint(color, 0.86), color, 2, RADIUS_SM)
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)

	var row := hbox(8)
	var dot := UiKit.dot(color, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	row.add_child(label(text, FONT_SMALL, INK))
	p.add_child(row)
	return p


## 一个键帽小方块：`PAPER_ALT` 底 + `LINE` 细描边，代表键盘 / 遥控上的一颗键。
##
## 两个入口：
##   · `keycap_icon(code)` —— 用**真键位图标**（Kenney Input Prompts 的图标字形）
##   · `keycap(text)`      —— 用文字。图标拿不到时的兜底，也给「1-9」这种没有对应图标
##                            的提示用（键盘上九个数字各是独立键，画哪个都别扭）
static func keycap_icon(code: int) -> PanelContainer:
	var p := keycap_frame()
	var ic := icon(code, FONT_SMALL, INK_SOFT)
	if ic == null:
		# 字体丢了就退成文字，界面照样能用（宁可难看，不可空白）
		p.add_child(label(keycap_fallback_text(code), FONT_MICRO, INK_SOFT))
	else:
		p.add_child(ic)
	return p


## 图标字体缺失时，这个码位该显示成什么文字。只覆盖我们真的会用到的几个。
static func keycap_fallback_text(code: int) -> String:
	match code:
		ICON_LEFT: return "←"
		ICON_RIGHT: return "→"
		ICON_UP: return "↑"
		ICON_DOWN: return "↓"
		ICON_ARROWS_H: return "← →"
		ICON_ARROWS_V: return "↑ ↓"
		ICON_ARROWS_ALL: return "↑ ↓ ← →"
	return "?"


## 键帽的**空壳**（底 + 描边 + 内边距），内容自己往里放。
##
## **底边比其余三边粗一档**（设计稿 `kbd{border-bottom-width:3px}`）—— 这是「立体键帽」的
## 全部秘密：看着像一颗键凸在面板上，而不是一个写了字的方框。
## `StyleBoxFlat` 的 `border_width_bottom` 可以单独设，正好做这个。
##
## 底色用**纯白**（设计稿 `kbd{background:#fff}`）而**不是** `PAPER_ALT`：
## 键帽要比它所在的 `.keychip`（`PAPER` 底）更亮才像凸起 —— 和上一版「底色一律退一档」
## 的层级逻辑正好相反。层级在这套风格里是靠**厚度的亮暗**表达的，不是靠深浅。
static func keycap_frame() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := flat_box(Color.WHITE, INK, STROKE_THIN, RADIUS_SM)
	# 底边加粗 = 键帽的「厚度」（设计稿 1.5px 侧边 / 3px 底边，比例 2:1）
	sb.border_width_bottom = STROKE_THIN + 3
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	# 下边多留 2 —— 底边加粗之后不多留这点，文字会被那条粗底边顶得偏上
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	return p


## 纯文字的键帽（见 `keycap_icon` 的说明：给没有对应图标的提示用）。
static func keycap(text: String) -> PanelContainer:
	var p := keycap_frame()
	p.add_child(label(text, FONT_MICRO, INK_SOFT))
	return p


## 一组「键帽 + 说明」横排。
## `pairs` 形如 [[UiKit.ICON_ARROWS_H, "选择"], ["1-9", "直选"]]——
## 元素是 int 就当**图标码位**、是 String 就当**文字**，两种混着排。
static func key_hint(pairs: Array) -> HBoxContainer:
	var row := hbox(GAP)
	for pr in pairs:
		var pair: Array = pr
		var group := hbox(9)
		# `Variant` 显式标注：从无类型 Array 取出来推断不出类型，
		# 下面还要 `is int` 分支，不标就是 Parse Error。
		var cap: Variant = pair[0]
		group.add_child(keycap_icon(int(cap)) if cap is int else keycap(str(cap)))
		group.add_child(label(str(pair[1]), FONT_MICRO, INK_MUTE))
		row.add_child(group)
	return row


## 一个实心小牌，装一个字符（选中玩法的三角、未选玩法的序号）。
## radius 传默认值就是正圆（d/2）；传 `RADIUS_SM` 就是圆角方块。
static func badge(text: String, bg: Color, fg: Color, d: int = 44, radius: int = -1) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(d, d)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(d / 2 if radius < 0 else radius)
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	var l := label(text, FONT_MICRO, fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## 注意 `SIZE_FILL` 是 **Container 的默认 `size_flags`（只横向填充）**，
## 这里只是写出来让人看见 —— 真正容易踩的是**子节点**：`SIZE_FILL` 意味着
## 「至少给到我的最小宽度」。普通 `Control`（比如封面槽）的最小宽度是 **0**，
## 于是它会被算成 0 宽，里面的 `PRESET_FULL_RECT` 子节点也跟着 0 宽，
## 画面一片空白且不报错。磁贴里那个封面槽就栽在这上面。
static func vbox(sep: int = GAP) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = GAP) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", sep)
	return h


## 横向占位（把同一行里的东西顶到两端用），宽度传 0 就得自己设 EXPAND_FILL。
static func spacer(w: float) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(w, 0.0)
	return c


## 把颜色往纸白里插值，得到一块「冲淡但不透明」的浅色。
## 场地上的左右地界就靠它：保持平涂（不用半透明），又能一眼分出两边。
static func tint(base: Color, amount: float = 0.78) -> Color:
	return base.lerp(PAPER, amount)


## 席位圆点：顶部状态条里那 8 个「谁占了位」的圆圈（设计稿 `.pdot`）。
##
## **这是这一版设计里最有价值的一处结构改动** —— 上一版状态条只写「在线 2 / 8」，
## 那是个**数字**；这一版把 8 个位置画出来，谁加入了、谁是房主、还剩几个空位，
## 一眼就看得见，不用读字也不用数。客厅距离上这一点尤其重要。
##
## 三种状态（设计稿 `.pdot` / `.pdot.joined` / `.pdot.host`）：
##   · **未加入** —— 45° 斜纹暖灰、无字。斜纹在 Godot 里 `StyleBoxFlat` **做不出来**，
##     得手绘（见 `SeatDot._draw()`），所以这里返回的是自定义控件而不是 `dot()`
##   · **已加入** —— `SEAT_JOINED` 青实心 + 白字（写席位序号）
##   · **房主**   —— `ACCENT` 番茄红实心 + 白字
##
## `size` 传设计稿的 26（× 1.532 ≈ 40）。**别调小** —— 隔客厅看，比 40 再小就只剩
## 一团颜色，看不出「这是个位置」。
static func seat_dot(index: int, state: String, size: int = 40) -> Control:
	var d := SeatDot.new()
	d.custom_minimum_size = Vector2(size, size)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.slot_index = index
	d.state = state
	d.dot_size = size
	return d


## 席位圆点的绘制实现。做成独立类是为了能用 `_draw()` 画斜纹 ——
## `StyleBoxFlat` 只有纯色填充，没有「斜线剖面」这种填充模式，
## 而「未加入」那个斜纹灰恰恰是让空格子看起来像「空位」而不是「坏掉」的关键。
##
## 为什么不用纹理：`StyleBoxTexture` 要运行时 `Image.create` + 逐像素画斜纹，
## 代码更长，且 40px 的小纹理在 0.667 缩放下会糊。`_draw()` 是矢量的，不糊。
class SeatDot extends Control:
	## 席位序号（1 起数，显示在已加入的圆点里）
	var slot_index := 1
	## `"empty"` / `"joined"` / `"host"`
	var state := "empty"
	var dot_size := 40
	## 斜纹的线距与线宽（逻辑 px）
	const HATCH_STEP := 7.0
	const BORDER_W := 3.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		queue_redraw()

	func _draw() -> void:
		var r := float(dot_size)
		var c := Vector2(r, r) * 0.5
		# ① 底色
		match state:
			"joined":
				draw_circle(c, r * 0.5, UiKit.SEAT_JOINED)
			"host":
				draw_circle(c, r * 0.5, UiKit.ACCENT)
			_:
				# 未加入：先铺一层浅灰圆，再用**裁剪后**的斜线盖上去。
				# 不裁剪的话斜线会画到圆外面，变成方块。
				draw_circle(c, r * 0.5, UiKit.SEAT_EMPTY_A)
				_draw_hatch(c, r * 0.5)
		# ② 墨色描边（三种状态都有 —— 设计稿 `.pdot{border:2px solid var(--ink)}`）
		draw_arc(c, r * 0.5, 0.0, TAU, 48, UiKit.INK, BORDER_W, true)
		# ③ 已加入的席位写序号（未加入态不写 —— 空格子摆个数字会让人以为「已经有人了」）
		if state != "empty":
			var txt := str(slot_index)
			var f := ThemeDB.fallback_font
			var fs := int(r * 0.42)
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			# 垂直居中：`get_ascent - get_descent` 的中点，不是 `get_ascent/2`
			#（那样会整体偏上，因为字形高度 = ascent + descent，不是 ascent）。
			var pos := c + Vector2(-w.x * 0.5, (f.get_ascent(fs) - f.get_descent(fs)) * 0.5)
			draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.PAPER)

	## 45° 斜纹：在圆内按固定间距扫一组斜线。
	## 每段都用「求与圆的交点」来截断 —— 这是最简单的不糊做法，
	## 比 `draw_set_transform` + 矩形裁剪少一层状态管理（Godot 的 2D 裁剪要子 Viewport，太重）。
	##
	## **线要够粗、色要够深**：实拍第一版用的 `SEAT_EMPTY_B`(#e3dcc9) + 2px，
	## 在 40 逻辑 px（屏幕上 27px）的圆里几乎看不见，8 个圆点看起来就是一排**空心圈** ——
	## 「空位」和「坏掉的圈」就分不出来了。现在加粗到 3px 并压深一档色。
	func _draw_hatch(c: Vector2, radius: float) -> void:
		var col := UiKit.SEAT_HATCH
		# 沿 45° 方向扫：把线段绕圆心旋转扫过 [-r, r]
		var d := Vector2(1, -1).normalized()
		# 和 `d` 垂直的法向 —— 斜纹沿 `d` 铺开，一组组的偏移沿 `n` 推进
		var n := Vector2(1, 1).normalized()
		var k := 0.0
		while k <= radius:
			# `sign` 是 `for` 循环变量，从无类型数组里取出来的，**必须显式标 `float`** ——
			# 不标的话下面 `n * (k * sign)` 的类型推不出来，报
			# 「Cannot infer the type of "off" variable」（整组连锁三行）。
			for signf in [1.0, -1.0]:
				var sign: float = signf
				var off: Vector2 = n * (k * sign)
				# 线段方向 d、过圆心偏移 off；与圆求交的两点
				# （半弦长 = sqrt(r² − k²)，k 是这条线到圆心的垂距）
				var half: float = sqrt(maxf(0.0, radius * radius - k * k))
				if half <= 0.5:
					continue
				var a: Vector2 = c + off - d * half
				var b: Vector2 = c + off + d * half
				draw_line(a, b, col, 3.0, true)
			k += HATCH_STEP


## 小圆点。在线状态指示灯用 —— 绿点/灰点比写「已连接/未连接」更快看清。
static func dot(color: Color, d: int = 22) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(d, d)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(d / 2)
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	return p


## **虚线圆角框**（设计稿 `.gcard.ghost{border:2.5px dashed}` 和 `.plus{border:2px dashed}`）。
##
## `StyleBoxFlat` 的 `border_width` 只能画**实线** —— 没有 dashed / dotted 模式，
## 也没有「画刷」的概念。所以虚线只能自己 `_draw()`。
##
## 这是本次改版唯一一处需要手绘的地方，但**值得**：
## 「虚线」在视觉语义上是明确的 —— 实线是「一个存在的东西」，虚线是「一个等着被填的位置」。
## 空位卡用实线时（上一版就是）它和真磁贴的分量差别只剩颜色深浅，
## 实拍里那两张卡看起来就像「一张能玩、一张坏了」，而不是「一张能玩、一张还能加」。
##
## 返回的是一个 `Control`（不是 `StyleBox`）—— 用法是**锚满**目标区域（`PRESET_FULL_RECT`），
## 而不是塞进 `add_theme_stylebox_override`。
static func dashed_panel(color: Color, width: int, radius: int) -> Control:
	var d := DashBox.new()
	d.line_color = color
	d.line_width = float(width)
	d.corner_radius = float(radius)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## 虚线的绘制实现。**不用 `StyleBoxFlat`**（它画不出虚线），也不用 `Line2D`
## （那是 2D 世界节点，不是 UI）—— 就一个 `Control` 子类，在 `_draw()` 里
## 沿圆角矩形的四条边按固定节拍画短线，四个角用 `draw_arc` 补上。
class DashBox extends Control:
	var line_color := Color.BLACK
	var line_width := 3.0
	var corner_radius := 14.0
	## 一段实线 + 一段间隔的长度（逻辑 px）。**别调太小** ——
	## 8 以下在 0.667 缩放下会糊成一条灰实线，等于白做。
	const DASH := 12.0
	const GAP := 8.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		# 尺寸不是自己的事（由容器/锚点定），但尺寸一变就得重画。
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		var r := minf(corner_radius, minf(w, h) * 0.5)
		var half := line_width * 0.5
		# 四条直边（各让出圆角那一段）
		_dash_line(Vector2(r, half), Vector2(w - r, half))                    # 上
		_dash_line(Vector2(w - r, h - half), Vector2(r, h - half))            # 下
		_dash_line(Vector2(half, h - r), Vector2(half, r))                    # 左
		_dash_line(Vector2(w - half, r), Vector2(w - half, h - r))            # 右
		# 四个角：`draw_arc` 本身支持虚线（`dash` 参数），直接交给它
		var seg := maxi(int(r), 4)
		draw_arc(Vector2(w - r, r), r, -PI * 0.5, 0.0, seg, line_color, line_width, true)
		draw_arc(Vector2(w - r, h - r), r, 0.0, PI * 0.5, seg, line_color, line_width, true)
		draw_arc(Vector2(r, h - r), r, PI * 0.5, PI, seg, line_color, line_width, true)
		draw_arc(Vector2(r, r), r, PI, PI * 1.5, seg, line_color, line_width, true)

	## 沿着一条直线按 `DASH`/`GAP` 的节拍铺短线。
	## 最后一段**不足一个 DASH 就丢掉**（不拉长补满）—— 补满会让某一段明显比别的长，
	## 在四条边凑一圈时那一段会跳出来。
	func _dash_line(a: Vector2, b: Vector2) -> void:
		var total := a.distance_to(b)
		if total <= 0.0:
			return
		var dir := (b - a) / total
		var t := 0.0
		while t < total:
			var e := minf(t + DASH, total)
			draw_line(a + dir * t, a + dir * e, line_color, line_width, true)
			t = e + GAP


## 键位图标字体（Kenney Input Prompts，CC0）。
##
## 为什么用**字体**而不是 PNG 图标：图标要跟着字号缩放、要跟着墨色走，
## 位图做不到「和旁边的文字一样深、一样大」。字体是单色的，`font_color` 一改就跟着变 ——
## 大厅那行「← → 选择」里的箭头就能和「选择」两个字**同色同高**，不会一深一浅。
## 详见 `assets/fonts/LICENSE.md`。
const INPUT_FONT := "res://assets/fonts/kenney_input.ttf"
## 图标字形的码位（PUA 区，见 `assets/fonts/kenney_input_map.txt`）。
## 只列出真的用到的几个，不把 1500 个全抄进来。
const ICON_LEFT := 0xE01F
const ICON_RIGHT := 0xE021
const ICON_UP := 0xE023
const ICON_DOWN := 0xE01D
## 「← →」合在一枚图标里的版本（`keyboard_arrows_horizontal`）。
## 用它比并排摆两个单箭头更紧凑 —— 大厅那行键位提示就这么宽。
const ICON_ARROWS_H := 0xE029
## 「↑ ↓」合在一枚里（`keyboard_arrows_vertical`）
const ICON_ARROWS_V := 0xE032
## 四向完整的十字（`keyboard_arrows_all`），给「翻行」那种要四个方向的话用
const ICON_ARROWS_ALL := 0xE026

static var _icon_font: FontFile = null

## 懒加载键位图标字体。**加载失败只是没有图标，不能崩** ——
## 资源被误删时界面还得能用，退回用文字（见 `keycap()`）。
static func icon_font() -> FontFile:
	if _icon_font == null and ResourceLoader.exists(INPUT_FONT):
		_icon_font = load(INPUT_FONT) as FontFile
	return _icon_font


## 一个键位图标 Label。`code` 传 `ICON_*` 常量。
## 拿不到字体就返回 null，调用方负责退回文字。
static func icon(code: int, size: int, color: Color) -> Label:
	var f := icon_font()
	if f == null:
		return null
	var l := Label.new()
	l.text = String.chr(code)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## 一条细分隔线（顺手把左右留点空）
static func rule(w: float = 0.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = DIVIDER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size = Vector2(w, 2.0)
	return r


## 把一组节点排成定列的网格。
## Godot 没有流式布局容器，玩家药丸要「一行两个」只能自己切行 ——
## 左右栏里既不想一个占满一行（太散），也不想排成一长条（超出屏幕）。
static func grid(items: Array, per_row: int, sep: int = GAP) -> VBoxContainer:
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", sep)
	var r: HBoxContainer = null
	for i in items.size():
		if i % per_row == 0:
			r = hbox(sep)
			rows.add_child(r)
		r.add_child(items[i])
	return rows


## 全局默认值。逐节点 override 仍然优先 —— 主题只是省掉重复的样板。
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_BODY
	t.set_color("font_color", "Label", INK)
	return t
