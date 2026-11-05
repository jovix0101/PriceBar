# PriceBar

一个 macOS 菜单栏加密货币价格工具。显示实时价格，并在价格或 24h 涨跌幅越过阈值时发系统通知。

需要 **macOS 14 以上**，Xcode 或 Command Line Tools。没有第三方依赖。

**[产品页 →](https://jovix0101.github.io/pricebar/)**

![菜单栏与面板](docs/panel.png)

## 跑起来

从[产品页](https://jovix0101.github.io/pricebar/)或 [Releases](https://github.com/jovix0101/pricebar/releases/latest)
下载 `PriceBar.zip`，解压后把 `PriceBar.app` 拖进「应用程序」。没有公证，首次打开
若被拦，右键点「打开」一次即可。

自己编：

```bash
./build.sh            # 编译并打包成 build/PriceBar.app
open build/PriceBar.app
```

测试用 `swift test`。要连真实行情跑网络测试：`NETWORK_TESTS=1 swift test`。

## 用 Xcode

Xcode 打开的是 Swift Package，不是 .xcodeproj：

```bash
xed .                          # 或者 File > Open 选这个目录
```

**预览**：打开 `Sources/PriceBar/PanelView.swift`，右侧 Canvas（`⌥⌘↩` 开关）有三个预览——
面板、人民币、拿不到行情。改代码会实时刷新。

预览只能预览面板。菜单栏图标是 `NSStatusItem` 画的，Canvas 里渲染不出来。

**运行**：左上角 scheme 选 `PriceBar`，按 `⌘R`。菜单栏会出现价格。

一个限制：Xcode 跑的是裸二进制，没有 `.app` 包，所以**开发时不会真的弹通知**
（`UNUserNotificationCenter` 在无 bundle 时会崩，`Notifier.available` 会挡住）。
提醒规则的触发逻辑照常跑，`armed` 也会正常翻转，只是屏幕上不出现横幅。
要验证通知，用 `./build.sh` 出 `.app` 再跑。

**首次装 Xcode 后**需要切一下工具链，否则 `#Preview` 宏编译不过：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

`build.sh` 已经自动优先用 Xcode 工具链，不切也能打包。

> `.build` 目录在 release 与 debug 混编后会失效（报 `plugin for module 'TestingMacros' not found`）。
> 遇到就 `rm -rf .build` 重来。

## 结构

```
Sources/PriceBarCore/       纯逻辑，不依赖 SwiftUI，可测试
  Quote.swift               数据模型与规则
  PriceAPI.swift            行情与汇率
  AppSettings.swift         配置读写、提醒引擎
  CoinValidation.swift      添加币种时的校验
  MarketSource.swift        四个交易所的差异（交易对写法、主机、批量与否）
  ProxySettings.swift       代理三档与请求会话
  CoinOrder.swift           币种的顺序：勾选、拖动、删币之后怎么排
  ErrorText.swift           把网络错误翻成人话
Sources/PriceBar/           外壳
  main.swift               入口，建 NSApplication 与 delegate
  PriceBarApp.swift        AppDelegate：store、主菜单、启动
  StatusItem.swift         菜单栏项、面板 popover、右键菜单
  PanelView.swift           面板与价格行
  AddCoinView.swift         添加币种的 popover
  RulesView.swift           提醒规则的 popover
  SettingsView.swift        设置窗口
  SettingsWindow.swift      设置窗口的承载
  Sparkline.swift           24 小时行情线
  ChangeColor.swift         涨跌颜色的取色
  MenuBarPrice.swift        菜单栏那一行字：币种、价格、涨跌幅，各是什么颜色
  Store.swift               状态、轮询、写入设置
  Notifier.swift            系统通知与权限
  LoginItem.swift           开机自启
Tests/PriceBarCoreTests/    48 个测试（Swift Testing）
.github/workflows/          GitHub Actions：编译并发布 .app
docs/                       产品页与截图（GitHub Pages）
build.sh                    打包脚本：编译、写 Info.plist、签名
```

## 界面

- **菜单栏**：`BTC $ 76,584 ▲2.02%` 这样的形式——币种、价格、24 小时涨跌幅。
  勾选多个币种时并排显示：`BTC $ 76,584 ▲2.02%   ETH $ 2,301 ▼0.87%`
- **左键图标**：面板，每个币种一行（价格 + 24h 行情线 + 涨跌），行尾铃铛设提醒
- **右键图标**：设置… / 退出
- **`+`**：添加币种，会先向交易所校验交易对是否存在
- **右键行**：打开提醒、加/移菜单栏显示、移除
- **面板底栏**：刷新、加币、「菜单栏」复选菜单、齿轮（设置与退出）
- **⌘,**：设置；**⌘Q**：退出

## 关于涨跌颜色

设置里可切「绿涨红跌」和「红涨绿跌」。国际习惯是绿涨，国内习惯是红涨，
app 不知道你从哪儿来，就让你自己选。默认绿涨红跌。

数字前面的 ▲▼ 与颜色无关，所以颜色反过来之后仍然读得懂。

## 关于提醒

阈值**永远按美元填写**，与面板显示哪种货币无关。这样切到人民币再切回来，
规则的含义不会变。通知标题也按美元写，正文里的现价才跟随面板货币。

## 关于菜单栏的涨跌幅

价格后面跟着 24 小时涨跌幅，`▲2.02%` / `▼0.31%`。三个取舍：

- **箭头不依赖颜色**：色觉障碍的人读得到方向，涨跌幅归零时也没有颜色可依。
  写法与面板里的 `▲ +2.02%` 一致。
- **小一号**：价格是这一项的正事，涨跌幅是它的注记。和价格同大就成了两个数字在争。
- **归零时写 `0%`**：涨跌幅四舍五入到 `0.00%` 时不画箭头——一个指向虚无的箭头比没有更糟——
  但数字留着。早先这里留的是空白，宽度照占，看着像数值没取到。

**涨跌幅永远是红绿，不受文字颜色那四档影响。** 四档只管币种编码和价格两部分。

这不是靠判断拼出来的，是画法决定的：整行是**一个** `attributedTitle`，每一段自带颜色。
币种和价格那几段按选项上色（「自动」时干脆不带颜色，交给菜单栏自己着），涨跌幅那段
无论选哪一档都按涨跌给绿或红。于是「价格听选项的、涨跌幅听涨跌的」自然成立，四种组合都不用特判。

涨跌幅的块宽按 `▲00.00%` 这类样本定死，短了就补**字距**（`.kern`）而不是空格：
`0%` 和 `▲12.34%` 占的宽度一样，后面的币种不会因为前面某个币归零而往前挪。
补位只能用字距——标题会**测量**空格却不**画**它，空格补出来的宽度是假的。
实测一行三个币种，价格怎么跳、某个币怎么归零，图标项都是 428 pt 不动。

## 关于菜单栏的文字颜色

菜单栏现在是透明的，背后就是壁纸。自动着色时，系统按壁纸的明暗决定这一项用深色还是浅色
文字——这个判断有时并不准：一张亮天空的壁纸，它会给出白字，读起来就吃力。

设置里给了四档：

- **自动**（默认）：那几段文字**不带颜色**，由菜单栏按自己的规则着色，换壁纸、切深浅色都跟着变。
- **深色 / 浅色**：自己指定黑色或白色，代价是不再随系统明暗自动反转。
- **随涨跌**：每个币种按自己的 24 小时涨跌方向着色，跟随「涨跌颜色」这一项，与面板里的百分比同色。
  涨跌幅正好为 0 时没有方向，退回自动。

四档都**只作用于币种编码和价格**。价格后面的涨跌幅无论选哪一档，都按涨跌显示红绿。

深色是黑色的同义词，浅色是白色——它们说的是文字本身，不是背景。

设置页的预览会按选择换底色：选了浅色，预览就放在深色块上，否则白字在白卡片上是看不见的。

## 关于菜单栏的字体

`$` 和数字总是一样大，看起来像多了一位数字：`$77601` 一眼读成 `877601`。

问题不在菜单栏，在 `MenuBarExtra`——它只收一行纯文本，字号由菜单栏决定。
自己拿 `NSStatusItem` 之后就有了 `attributedTitle`，**带属性的标题保留字号**：
`$` 用 10pt、数字用 13pt 等宽，两者落在同一条基线上，和印刷价目表一个道理。
颜色也是同一份属性，所以字号和红绿是一次设好的，不用分开画。

符号与数字之间用的是**细空格**（U+2009，1.75pt），不是普通空格。普通空格在 13pt 的等宽数字
字号下宽 3.58pt，加上 `$` 自己的右边距，读起来不像「一个金额」，像两个东西挨在一起。

整行是**一个** `attributedTitle`，图标项左右各留约 10 pt 由 `NSStatusBarButton` 自己给。
几个币种之间只隔一段字距，不再有「图片和标题之间那 22 pt」——那是分成两块才有的问题。

## 关于面板的间距

面板宽度 280 pt，每行从左到右是：币种（42 pt 定宽）、24 小时线（44 pt）、价格、涨跌幅、铃铛。
价格和涨跌幅靠着右边，中间的空隙由 `Spacer` 吃掉——所以币种和线在哪一行都从同一个 x 开始，
价格和涨跌幅也从同一个 x 结束，扫一眼就能上下比。

涨跌幅那一格定宽 54 pt，刚好装下 `▼ -12.34%` 这种少见的两位数跌幅；再宽就是白白撑开价格和
涨跌幅之间的距离。箭头和数字之间同样用细空格——箭头是方向，不是数字的一部分，但普通空格
会把 `▲ +2.02%` 拆成两截。

## 关于行情线

**它是 24 小时的图**，取自 1 小时 K 线的收盘价，24 个点。

每行价格后面是一条 24 小时的小线，取自 Binance 的 1 小时 K 线收盘价，
只画线不画填充——它是一个走势，不是一个数值，数值就在它右边。

线的颜色跟着**右边那个涨跌幅**走，不按自己的首尾差算。两者本来就是同一个 24 小时的两种数法，
偶尔差一点，就会出现红线配绿字，看着像 bug。

这条线**不在每次刷新时重取**，只在面板打开时取，并且超过 5 分钟才算旧。
价格每 10 秒刷新一次，线画得再勤也看不出变化，却会让请求量涨十倍。

## 关于千分位

菜单栏和面板的价格都带千分位（`$76,584`）。逗号是手写的，不用 `NumberFormatter`：
后者的分隔符跟随系统区域，同一个价格在不同电脑上会显示成不同样子，而币价应该处处一致。

## 数据来源

四个交易所可选，在设置里切换：

| | 交易对写法 | 24h 涨跌 | 一次请求多个币 | 通常要代理 |
|---|---|---|---|---|
| Binance | `BTCUSDT` | `priceChangePercent` | 是 | 否 |
| Gate | `BTC_USDT` | `change_percentage` | 否 | 否 |
| OKX | `BTC-USDT` | 需用 `open24h` 自算 | 否 | 是 |
| Bybit | `BTCUSDT` | `price24hPcnt`，是小数 | 否 | 是 |

**不做跨交易所自动兜底**：同一刻四家的 BTC 报价差几十美元，自动换源会让数字莫名跳动。
Binance 内部的两个域名互为备份（同一份报价），这是唯一的兜底。

- 行情线：`/api/v3/klines` 等各自端点，1 小时 × 24 根（即 24 小时），每币一次请求
- 汇率：Frankfurter，欧洲央行参考价，每天更新一次

## 关于代理

设置里三档：直连、跟随系统、自定义（`http://主机:端口` 或 `socks5://主机:端口`）。
代理**只作用于当前选中的源**，因为直连能用的源（Binance、Gate）走代理会慢 2–6 倍，
只有直连不通的源（OKX、Bybit）才值得走代理。

直连是**显式关掉代理**（`HTTPEnable: 0` 等三个键），不是「不设代理」——
后者等于去查系统设置，和「直连」正好相反。

拿不到价格时，面板会给出对应这一档的提示，而不是一句「失败了」。
网络错误也会翻成中文（`请求超时，网络可能不通` / `连不上服务器，可能被拦住了`）。

设置里的「测试」按钮会真的请求一次，报出耗时和当时的报价。

## 关于菜单栏的多个币种

勾选几个就并排显示几个，从左到右就是设置里那个列表的顺序。几处刻意的取舍：

- **不做轮播**。轮播要人一秒内读出「这是哪个币、多少钱」，滚动本身又抢注意力；
  并排显示一次看全，也不用等。
- **顺序只有一份**：设置里拖动的顺序既是菜单栏的顺序，也是面板的顺序。
  勾选按这份顺序排，不是按点击顺序——点击顺序是操作顺序，不是你想要的结果。
- **一个都不勾就回落到面板第一个币种**，并给一句说明，不锁死控件。
- **每个币的涨跌幅块宽度固定**，某个币归零时不会把后面的币种拉过来。
- 设置里那行预览就是**真的那一行字**：只看一个币，看不出三个挤不挤。

### 为什么不用 MenuBarExtra

起初用的是 SwiftUI 的 `MenuBarExtra`，三个问题凑在一起，只能换掉：

1. **面板关掉后视图不销毁**，`onAppear` / `onDisappear` 只各跑一次。用它判断
   「面板开着没有」，结果就是行情线永远不刷新。想绕过去得靠轮询窗口的
   `occlusionState`，而 `isVisible` 在面板正显示时也返回 `false`，三个窗口通知在关面板时
   一个都不来。
2. **不支持右键菜单**，设置和退出只能塞在面板的齿轮里。
3. **标签是一行纯文本**，字号由菜单栏决定，`$` 和数字永远同大；也拿不到按钮本身。

现在菜单栏图标是 `NSStatusItem` + `NSPopover`（`StatusItem.swift`）：
左键开合面板，右键弹「设置… / 退出」，`NSPopoverDelegate` 直接告诉 `Store`
面板开了还是关了，不用轮询。面板内容是同一个 `PanelView`。

`main.swift` 建 `NSApplication` 和 delegate，不用 SwiftUI 的 `App`：
一个菜单栏 app 没有窗口可开，而任何 scene 都会开一个不想要的窗口——
`Settings { EmptyView() }` 在启动那一刻就开了一个 900×450 的空窗口。

## 设置

存在 `~/Library/Application Support/PriceBar/settings.json`：

```json
{
  "coins": ["BTC", "ETH"],
  "menuBarCoins": ["BTC", "ETH"],
  "currency": "USD",
  "interval": 10,
  "source": "binance",
  "proxyMode": "direct",
  "proxyAddress": "",
  "changeColors": "greenUp",
  "menuBarTint": "automatic",
  "rules": [
    {
      "coin": "BTC",
      "metric": "price",
      "above": true,
      "threshold": 70000,
      "armed": true
    }
  ]
}
```

`metric` 是 `price`（绝对价格）或 `change`（24h 涨跌幅，`-5` 表示跌 5%）。
`armed` 为 `false` 表示这条规则已经通知过，价格回到阈值另一侧后会自动变回 `true`。

字段读不懂时只退回该字段的默认值，不会丢掉整份配置。
旧版本只有一个 `primary` 字段，读到时自动变成 `menuBarCoins: ["BTC"]`，之后不再写回。

## 发布

`.github/workflows/release.yml` 在 GitHub 自己的 Mac 上编译，所以下载不需要工具链。

- 推 tag：`git tag v0.2.0 && git push origin v0.2.0` → 建一个正式 Release，附件是
  `PriceBar-<版本>.zip` 与固定名的 `PriceBar.zip`
- 推 `main` → 重写 `nightly` 预发布，每次构建替换附件
- `build.sh` 读 `VERSION` 与 `BUILD_NUMBER` 环境变量写进 `Info.plist`，本地默认 `0.1.0` / `1`
- 发布版用 `UNIVERSAL=1` 编成通用二进制（arm64 + x86_64），Intel 的 Mac 也能跑；
  本地不加这个变量，只编本机架构，省一半时间

`PriceBar.zip` 这个固定名是给产品页的「下载 .app」用的——链接不能跟着版本号变。

## 已知缺口

- 每次 `./build.sh` 重新做 ad-hoc 签名，签名变了 macOS 可能把通知权限重置，需要重新允许一次
- 未做 App Sandbox。若以后要上架，需加 `com.apple.security.network.client` 权限
- 没有公证（notarize）。首次打开若被拦，右键「打开」一次即可
