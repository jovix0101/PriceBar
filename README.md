# PriceBar

一个 macOS 菜单栏加密货币价格工具。显示实时价格，并在价格或 24h 涨跌幅越过阈值时发系统通知。

## 跑起来

```bash
./build.sh            # 编译并打包成 build/PriceBar.app
open build/PriceBar.app
```

测试用 `swift test`。

## 用 Xcode

Xcode 打开的是 Swift Package，不是 .xcodeproj：

```bash
xed ~/Workspaces/PriceBar     # 或者 File > Open 选这个目录
```

**预览**：打开 `Sources/PriceBar/PanelView.swift`，右侧 Canvas（`⌥⌘↩` 开关）有三个预览——
面板、人民币、拿不到行情。改代码会实时刷新。

预览只能预览面板。`MenuBarExtra` 本身没法在 Canvas 里渲染，那是窗口级的东西。

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
  MenuBarOrder.swift        菜单栏币种的勾选顺序
  ErrorText.swift           把网络错误翻成人话
Sources/PriceBar/           外壳
  PriceBarApp.swift         MenuBarExtra、主菜单
  PanelView.swift           面板与价格行
  AddCoinView.swift         添加币种的 popover
  RulesView.swift           提醒规则的 popover
  SettingsView.swift        设置窗口
  SettingsWindow.swift      设置窗口的承载
  Sparkline.swift           24 小时行情线
  ChangeColor.swift         涨跌颜色的取色
  MenuBarPrice.swift        菜单栏价格，画成图片
  Store.swift               状态、轮询、写入设置
  Notifier.swift            系统通知与权限
  LoginItem.swift           开机自启
Tests/PriceBarCoreTests/    43 个测试（Swift Testing）
reference-go/               最早用 MyGo 写的原型，已弃用，留作参考
```

## 界面

- **菜单栏**：`BTC $ 76,584` 这样的形式，多个币种时按设定间隔轮播
- **点图标**：面板，每个币种一行（价格 + 24h 行情线 + 涨跌），行尾铃铛设提醒
- **`+`**：添加币种，会先向交易所校验交易对是否存在
- **右键行**：打开提醒、加/移菜单栏轮播、移除
- **面板底栏**：刷新、加币、「菜单栏」复选菜单、齿轮（设置与退出）
- **⌘,**：设置；**⌘Q**：退出

## 关于涨跌颜色

设置里可切「绿涨红跌」和「红涨绿跌」。国际习惯是绿涨，国内习惯是红涨，
app 不知道你从哪儿来，就让你自己选。默认绿涨红跌。

数字前面的 ▲▼ 与颜色无关，所以颜色反过来之后仍然读得懂。

## 关于提醒

阈值**永远按美元填写**，与面板显示哪种货币无关。这样切到人民币再切回来，
规则的含义不会变。通知标题也按美元写，正文里的现价才跟随面板货币。

## 关于菜单栏的字体

菜单栏会把标题按自己的字体、自己的字号重新渲染，标签里指定的字体**会被忽略**。
所以 `$` 和数字总是同大，看起来像多了一位数字。

解决办法是把文字画成图片再交给菜单栏：`$` 用 10pt、数字用 13pt 等宽，
两者落在同一条基线上。图片设成 template，菜单栏会按亮/暗色自动反色，观感和系统原生一致。

## 关于行情线

**它是 24 小时的图**，取自 1 小时 K 线的收盘价，24 个点。

每行价格后面是一条 24 小时的小线，取自 Binance 的 1 小时 K 线收盘价，
只画线不画填充——它是一个走势，不是一个数值，数值就在它右边。

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

## 关于菜单栏轮播

菜单栏可以勾选多个币种，按 3/5/10 秒的间隔轮流显示。几处刻意的取舍：

- **轮播只换显示对象，不发请求**：价格本来就是按刷新间隔取的，轮播只是换显示谁
- **面板打开时暂停**：盯着面板看时菜单栏还在跳，是干扰
- **顺序按面板里的顺序**，不是勾选的顺序——勾选顺序是操作顺序，不是你想要的结果
- **一个都不勾就回落到面板第一个币种**，并给一句说明，不锁死控件
- **宽度按最宽的币种预留**，否则菜单栏图标会随价格位数左右移动
- 设置里那行预览**按真实间隔轮播**：光看几个数字判断不了快慢

### 面板开合是怎么知道的

`MenuBarExtra` 关闭面板后**不会销毁它的视图**，所以 `onAppear` / `onDisappear`
只在第一次打开时各跑一次，之后再也不会触发。用它判断「面板是不是开着」，
结果就是轮播永远暂停、行情线永远不刷新。

窗口本身知道答案，但不会主动说：`didBecomeKey`、`didResignKey`、
`didChangeOcclusionState` 三个通知实测只在开面板时到过一次，关面板时一个都没到。
`isVisible` 更没用——面板正显示着，它也返回 `false`。

能用的只有 `occlusionState.contains(.visible)`，而且得主动去问：
`PanelWindowProbe` 把面板的窗口交给 `Store`，`Store` 每 0.5 秒读一次这个属性，
状态翻转时才行动（开→取行情线，关→轮播归位）。代价是每秒两次属性读。

## 设置

存在 `~/Library/Application Support/PriceBar/settings.json`：

```json
{
  "coins": ["BTC", "ETH"],
  "menuBarCoins": ["BTC", "ETH"],
  "rotateInterval": 5,
  "currency": "USD",
  "interval": 10,
  "source": "binance",
  "proxyMode": "direct",
  "proxyAddress": "",
  "changeColors": "greenUp",
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

## 已知缺口

- 菜单栏图标不支持右键菜单（`MenuBarExtra` 没有这个能力），设置和退出放在面板的齿轮里
- 每次 `./build.sh` 重新做 ad-hoc 签名，签名变了 macOS 可能把通知权限重置，需要重新允许一次
- 未做 App Sandbox。若以后要上架，需加 `com.apple.security.network.client` 权限
