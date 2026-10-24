## 2026-10-24 Applications 安装与菜单闪烁修复

已运行进程确认为 `/Applications/zihusic.app`，且 Applications 和 dist 的 designated requirement 均为同一 cdhash `553eaf1592db3f19a356004ec75c07e506763f49`。TCC 日志仍以旧授权的 `880693cb186c96f2d96aa3cd92eaad7a70f51472` 拒绝 Accessibility，因此本次失效不能归因于单纯复制位置。系统未配置有效签名证书；开发构建默认 ad-hoc。构建脚本现在支持指定现有 `CODE_SIGN_IDENTITY`，未放宽 designated requirement 或修改 TCC 数据库。

菜单由 SwiftUI WindowGroup 与原生菜单恢复观察器竞争维护。改为 AppKit 持有唯一 NSWindow/NSMenu、SwiftUI 只承载内容，删除 KVO 和增删菜单后重装的循环。更新到 Applications 后，实际播放时菜单持续展开约 30 秒仍保持有效，随后原生菜单的暂停动作成功执行；全套 29 项测试与签名校验通过。已新增 `--install`，安装前完整备份原应用。

通过系统设置仅移除 zihusic 的旧辅助功能条目，再添加 `/Applications/zihusic.app`，未要求额外管理员认证。恢复后程序自动打开系统选择器并勾选 MacBook，随后自行关闭；外层显示本机播放开启、MacBook 关闭，两个音量滑块均存在。外层 MacBook 开关可切换为开启；用户随后实际调节了两台设备的音量，保留当前播放而未重启。此轮验证了安装版的自动接入与控制 UI，未新增声学同步结论，歌词声音对齐问题仍未获确认。

## 2026-10-24 歌词时钟回归与交互更新

用户报告所有歌曲的歌词时序不准。排查中复现了一个全局切歌错误：`AVSampleBufferRenderSynchronizer.setRate(_:time:)` 同步更新 rate、异步更新时间基，原本紧接着读取 currentTime 会把旧曲时钟以新 revision 发给 UI。静音回归测试稳定捕获了新曲从 0 开始时收到 `[2.5, 0, 0, 0]`。增加时钟锚点保护后，该回归及全套 29 项测试通过；音频包、接收端与共同时间线的启动方式保持原有实现。正在播放状态使用实际 timebase effective rate。

歌词与进度条改用同一份已发布播放时间，移除固定提前 0.4 秒的处理。原生视图仅在换句时做 0.32 秒短过渡，切歌/手动滚轮/点击会取消旧运动，避免旧动画回写新曲位置；滚轮结束后 3 秒回到播放行。顶部 68 pt 与底部播放器整个高度禁止歌词点击，悬停轻微变色。增加源文件校验与本地缓存、后台曲库预读；该次主应用已生成 229 首缓存。实际 UI 验证了滚轮浏览后返回播放位置，绿灯进入原生全屏。用户在此前构建报告的声音/歌词整体错位尚不能仅凭软件测试宣布已经解决，最新构建仍需实际听感确认。

## 2026-10-24 自动接入、默认静音与离散歌词验证

系统原生选择器的辅助功能自动化已在当前 release 主应用中完成实测：程序自动勾选 MacBook 并关闭系统弹窗，用户无需右键逐台选择；外层显示本机播放开启、MacBook 播放关闭，两个音量滑块均保留。同一已授权构建重启后仍能出现两台设备，并默认只有本机开启播放。随后用户验证 App 先启动、MacBook 休眠再唤醒的场景，确认：“自动出现，默认不出声”。此结果验证接入和默认播放状态，不替代声学同步测量，也没有验证多个远端接收器。

期间发现 ad-hoc 重编译改变 cdhash 后，系统设置可能仍显示旧辅助功能授权已开启，而 TCC 实际以代码要求不匹配拒绝新进程。通过系统设置仅移除并重新添加当前 zihusic 构建，用户完成正常管理员认证后恢复；没有修改 TCC 数据库或重置其他应用权限。

歌词移除 60 Hz 时间线与连续滚动，仅在当前句改变时更新行布局，翻译/长段落仍按实测高度显示。菜单改为音乐、窗口、播放；主题浅色切换和侧边栏开关已通过原生 UI 检查。22 项回归测试全部通过，包含逐句边界、翻译分组和远端静音恢复时公共时间线不中断。

## 2026-10-24 较早阶段：播放开关修复与自动发现边界

用户明确：勾选控制出声，不允许取消勾选导致断开。现已分离连接与播放偏好；MacBook 实测 `canMute=false`、`canSetVolume=true`，因此停止时写音量 0，保留原音量并持续发送共同时间线。快速反复操作使用最新合并写入；相同目标不重复推迟提交，避免密集通知让静音迟迟不执行。重同步只重建公共时间线，不移除路由。面板去掉加号，停止的设备保留音量滑块。

当时自动发现尚未完整解决：本机 AVFoundation/MediaRemote、直接 local/XPC FigRouteDiscoverer、FigEndpointManager 均未返回未选中的 MacBook；Bonjour 可见。以真实 UUID 的最小 RouteUID 描述请求加入返回 destination-change status 3。不能把扫到 Bonjour 名称等同于拿到了可用原生路由，也不能把单测的模拟发现当作实机自动接入成功。精确过滤点尚未证实，Music 的内部 entitlement 与本应用不同。当时通过图标右键中的系统菜单首次接入；已知句柄在应用运行期间可自动接回，应用重启后仍可能需要系统菜单。此手动接入流程现已由上面的辅助功能自动化替代。

release 验证发现另一处实际卡顿：进程 sample 显示主线程停在 `SmoothLyricsPane.reloadLyrics → LyricsService.readText → open`，导致启动恢复窗口和 AirPlay UI 都不响应。歌词旁挂文件读取已移到后台任务，按歌曲取消旧任务并忽略迟到结果；保持原歌词测量和字形样式。

最新 release 主应用已完成本次控制验证：取消外层 MacBook 勾选时，系统原生菜单仍显示该设备已接入、原生音量降为 0；应用偏好保留约 0.377，恢复勾选后原生音量恢复同值。用户在歌曲播放期间确认：“能停止并恢复，Mac mini 不受影响”。19 项回归测试通过，release 构建与签名验证通过。此结果没有验证完全自动首次接入，也不替代声学同步测量。

以下保留先前同步调试记录；旧方案的加号、连接勾选和 reconnect 不代表本次行为。

# AirPlay 多设备同步与交互调查

日期：2026-10-23 至 2026-10-24。环境：原生 macOS 15.6.1，Mac mini → MacBook Air。

## 2026-10-24 后续进展

- 独立共享缓冲原型改为两路使用同一批 AAC 样本。固定未来 host time 的启动仍被用户确认有明显先后；日志中可见接收端在握手完成后确认自己的播放起点。
- 改用 `AVSampleBufferRenderSynchronizer.setRate(_:time:)`，让 AirPlay 确认起点并更新公共时间线后，用户确认节拍“基本重合”。随后用户确认 60 秒《That Girl》原型“两台都响，基本同步”。
- 已将同样的播放机制接入 `GroupedAudioOutput`，替换双 AVPlayer 伴随播放；主应用 release 构建签名检查通过，用户再次确认主应用《That Girl》“两台都响，基本同步”。
- FLAC 等源文件通过苹果原生 M4A 导出准备临时 AAC 传输副本，不改写原文件。普通本机播放继续使用原文件。原型最初的 PCM 样本总字节数为 0，补齐样本大小后本机出声；PCM 远端转换仍失败，不能将补齐样本大小说成完整修复。
- 16 项回归测试通过，涵盖共享音频准备、缓存失效、暂停/跳转/恢复/结束、取消旧回调、路由勾选状态和歌词排版。未做麦克风声学测量；主应用其他交互和重连仍需逐项硬件验证。

以下保留此前失败方案的调查记录，不能将其中“当前双播放器”误认为新的实现。

## 当前结论与验证状态

双机同时出声已由用户确认，但最新构建仍被用户确认存在明显延迟、首次勾选导致本机取消、音量控件不稳定、交互迟缓。因此此功能**尚未解决**，不能用编译成功或两路软件时钟接近作为完成依据。暂不继续向用户投放双 AVPlayer 纠偏的试验版本。

本轮修正的一个明确错误是：原来的本机伴随播放器调用 `setRate(_:time:atHostTime:)`，却保留了默认的 `automaticallyWaitsToMinimizeStalling = true`。系统日志出现了苹果文档规定的 `NSInvalidArgumentException`。修正后用户确认能同时出声，但听感仍不合格。

## 苹果资料核对

1. [Supporting AirPlay in your app](https://developer.apple.com/documentation/avfoundation/supporting-airplay-in-your-app)
   - `AVAudioSession.longFormAudio` 这部分明确针对 iOS、tvOS、watchOS；不能给原生 macOS 抄上这段配置就认为获得 Music 的音频分组能力。
   - 官方播放入口是 AVPlayer/AVQueuePlayer，或 AVSampleBufferAudioRenderer + AVSampleBufferRenderSynchronizer。
2. [Tune up your AirPlay audio experience, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10238/)
   - 介绍增强缓冲、远端同步和样本缓冲播放；不提供 Music 的 macOS 设备组管理器实现。
3. [setRate(_:time:atHostTime:)](https://developer.apple.com/documentation/avfoundation/avplayer/setrate(_:time:athosttime:))
   - 同步启动要求关闭自动等待；这是本轮已经修正的确定错误。
   - 这个接口负责媒体时间与主机时间的关系，不是远端扬声器声学延迟的测量接口。
4. [sourceClock](https://developer.apple.com/documentation/avfoundation/avplayer/sourceclock)
   - 苹果警告，换成不对应实际音频设备的时钟可能导致漂移。因此不能强行把两个输出设成 host clock 来冒充同步。
5. [AVSampleBufferAudioRenderer.audioOutputDeviceUniqueID](https://developer.apple.com/documentation/avfoundation/avsamplebufferaudiorenderer/audiooutputdeviceuniqueid)
   - 苹果明确警告：同一个 synchronizer 内的多个 renderer 使用不同输出设备时，音频仍可能失去同步。
   - 因此“把双 AVPlayer 换成两个 renderer 挂一个 synchronizer”也不是已经得到官方保证的解决办法。
6. [Implementing flexible enhanced buffering](https://developer.apple.com/documentation/avfoundation/implementing-flexible-enhanced-buffering-for-your-content) 与 [Playing custom audio with your own player](https://developer.apple.com/documentation/avfaudio/playing-custom-audio-with-your-own-player)
   - 样本入队、flush、缓冲重建和播放操作放在串行队列；UI 不应同步等待音频管线或路由查询。
7. [macOS program audio output to AirPlay, with EQ and volume control](https://developer.apple.com/forums/thread/698988)
   - 2022 年已有开发者提出与本项目很接近的问题：想获得 Music 的 AirPlay 选择和音量控制；Apple Media Engineer 的回复要求提交 enhancement request。
   - 这条旧回复能说明问题并非简单漏配一个属性；它不能单独证明 2026 年所有第三方实现都不可能。
8. [Use AirPlay to stream audio](https://support.apple.com/en-us/105068)
   - Music 应用支持多个扬声器；Mac 控制中心只支持一个。

## 其他项目实际采用的办法

### Airfoil：统一延迟预算，再做设备偏移

[开发商自己的延迟与同步说明](https://rogueamoeba.com/support/knowledgebase/?showArticle=Airfoil-AudioLatency)说明，它把所有输出延后到最慢设备需要的延迟，再用独立设备偏移作微调。文档中的 AirPlay 约两秒是该产品这条链路的行为，不能直接当作所有 AirPlay 2 接收器的固定常数。

可借鉴的是“共同的实际呈现时间 + 本机缓冲”，而不是给两个独立播放器设置相同进度。Airfoil 的完整发送实现是闭源的，此次没有把其文档描述当作可直接移植的源代码。

### OwnTone：协议时钟同步 + 本机缓冲和速率控制

- [项目](https://github.com/owntone/owntone-server)本身实现 AirPlay 1/2 发送及本机输出。
- [维护者解释同步机制](https://github.com/owntone/owntone-server/issues/1635)：远端通过协议同步时钟；本机延后启动，并根据声卡真实消耗速度进行速率适配。
- [当前 AirPlay 发送源码](https://github.com/owntone/owntone-server/blob/master/src/outputs/airplay.c)管理 RTP 时间戳、输出缓冲样本数和设备偏移。当前源码的最小协议延迟常量是 250 ms，还另有总体启动缓冲；这进一步说明不能把某个固定秒数直接套到本项目。
- [macOS 接收器密码配对问题](https://github.com/owntone/owntone-server/issues/1385)是值得提前验证的兼容边界。该报告较旧，不能据此断言当前 MacBook 一定不兼容；但也不能未经配对验证就把它当作即插即用后端。

集成独立发送后端不需要网页接收器或浏览器界面；本项目的原生 UI 可以控制发送引擎。但后台进程、打包依赖、许可证及 Mac 接收端认证都需要作为真实工程工作处理。

### HomeSounds Sync：共享 PCM 延迟缓冲

- [项目说明](https://github.com/techjuicelab/homesounds-sync)和[缓冲代码](https://github.com/techjuicelab/homesounds-sync/blob/main/Sources/HomeSoundsSync/RingBuffer.swift)采用单一 PCM 历史缓冲、每个本机输出独立读取位置，远端交给 OwnTone。
- 这能作为缓冲结构的参考；仓库较新，其自述不能替代本项目两台 Mac 的兼容性和同步验证。它还需要用户手动调本机延迟，不等于已经实现自动声学校准。

## 对现有问题的具体解释

### 勾选与音量忽隐忽现

首次点击在没有已知接收器时直接呈现 AVKit 系统选择器；后续点击则呈现本项目自己的面板。系统选择器控制远端路由，本机伴随播放器由另外的 `localEnabled` 控制。系统菜单勾选 MacBook 后会取消本机，但本机伴随播放可能仍在继续，因此两套 UI 的勾选语义冲突。系统菜单也会按其自身连接状态增减音量控件。

应统一由应用面板表达本机与远端的选择、连接中、已连接、失败状态。系统认证/添加流程只作明确的设备添加入口，不能与主面板混用成同一套输出状态。音量能力、滑块显示及连接状态需分别保存，不能用一次临时属性查询决定控件是否存在。

### 反应慢

此前的播放进度回调每 100 ms 调用路由查询；本轮已移除这个调用，但当前适配器仍在主线程执行部分 KVC 查询和同步 add/remove 操作。减少调用频率不足以消除单次同步 IPC 的阻塞。源码随后已把查询、音量写入和连接操作移到串行后台队列，主线程消费快照和提交意图；设备添加完成后异步刷新，并保留拖动音量时的短期显示值。新的主按钮始终打开应用面板，设备添加使用行内 + 或右键入口，结束后返回应用面板。这些后续交互改动尚未重新打包运行或通过用户硬件验收。

### 明显延迟

当前双播放器方案主要对齐媒体时间，并没有证明本机输出样本与接收端实际呈现时间一致。最新听感验证否定了“软件时钟接近即可解决”的假设。手动校准可以辅助测量，但不能作为自动同步已经完成的依据。也没有证据表明这是左右声道被拆分；两台设备目前获得的都是完整音乐内容。

独立诊断窗口在不播放音频的情况下读取了当前 MacBook 的 `airPlayProperties` 和 `outputDeviceInfo`：可见发现、会话和格式能力等元数据，没有得到实际呈现延迟/缓冲时长字段，音频 context 的 `associatedAudioDeviceID` 也仍为 nil。因此当前适配器不能凭这些字段完成可靠的自动延迟补偿。诊断结束已释放该路由。

## 后续实现的验收门槛

先把独立的音频原型验证清楚，再接回播放器，避免用主应用反复试错：

- 同一音源、统一样本时间与缓冲预算；证明本机和 MacBook 的实际同步，不能只比较 currentTime。
- 接收端认证沿用其正常访问设置，验证当前 MacBook 的真实兼容性。
- 主线程无路由 IPC、解码、握手或等待；连接超时不冻结其他设备控件。
- 首次连接、取消连接、同时勾选、单独调音量、暂停、恢复、跳转、切歌均保持状态一致。
- 短音频、断网/重连、应用退出后不留下重复播放或残留连接。
- 记录听感或声学测量以及具体版本；本地单测与构建结果只作为软件回归证据。
