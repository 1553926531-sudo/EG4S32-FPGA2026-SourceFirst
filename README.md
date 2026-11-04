# EG4S20 TF 多媒体播放器 / EG4S20 TF Media Player

版本 / Release：2026-11-04 · EG4S20BG256 · AN9134 / SiI9134 · 1280×800

## 中文：先选择你要做的事

| 目的 | 应执行的步骤 |
|---|---|
| 使用已验收程序，断电后仍可启动 | 核对接线与位流 → 执行 **Flash 写入及校验** → 断电冷启动 |
| 临时试运行，断电后恢复 Flash 程序 | 执行 **SRAM 下载** |
| 核对 Flash 是否仍为交付程序 | 执行 **只校验 Flash** |
| 从源码重新生成位流 | 安装 TD → 执行 **源码构建** → 检查完整 setup/hold → 使用新位流路径及哈希烧录 |
| 修改存储固件 | 先用 Zig 0.13.0 重建 ROM，再构建位流 |
| 转换常见图片、音频、视频和歌词 | 使用 `tools/media_convert.py`；按独立双语格式规范生成并校验媒体 |

当前交付位流已完成 Flash 写入和独立校验；用户确认仅供电冷启动、画面声音、按键及数码管熄灭均正常。正常使用无需再次烧录。烧录命令由用户手动执行，构建和仿真不会自动打开下载器。

## 1. 文件与版本身份

```text
bitstream/media_player.bit   已在板上验收的位流
rtl/                         无代码注释的 Verilog、字库和固件 ROM
firmware/                    RV32IM 存储固件 C、启动汇编和链接脚本
tests/                       RTL 测试平台及主机测试
tools/                       构建、仿真、媒体和烧录工具
media_player.adc              全部物理引脚与电气约束
media_player.sdc              时钟及输入输出时序约束
docs/FPGA_用户操作手册.md     板载操作与英文界面释义
docs/媒体格式规范与转换指南_Media_Format_Specification.md
                             独立中英双语格式定义、全部字段及转换步骤
examples/                    可直接验证格式的最小 TFV 样例
verification/                字库、面板文字 JSON 输入，以及运行时产生的临时报告
NOTICE.txt                   器件厂商版权声明
```

`bitstream/media_player.bit` 的 SHA-256：

```text
9f46370b796f8bda3b004b857217137cf4ad5d83ad8c7f857e0859132c8632b5
```

保留 17 处综合保留属性。`tools/build.py` 在临时构建副本中恢复 TD 已验证的保留指令，构建时应通过该工具保留这些属性。重新布局布线的位流可能具有不同哈希；已验收位流保持上述身份。

## 2. 硬件、软件与接线

硬件：EG4S20BG256 开发板、AN9134/SiI9134 HDMI 扩展板、1280×800 正式屏、可播放的 TF 卡、AL-Link 下载器及原有电源。保留已验证的扩展板连接、供电和共地。显示链路是 FPGA → AN9134 HDMI OUT → 正式屏。

| 接口 | FPGA 球位 / 开发板位置 | 接收端 |
|---|---|---|
| 50 MHz 时钟 | R7 | 板载振荡器 |
| TF CLK / CMD | F15 / F14 | 板载 TF 卡座 |
| TF DAT0 / 1 / 2 / 3 | D14 / D16 / G14 / F13 | 板载 TF 卡座 |
| I2S MCLK | M12 / P2-35 | SiI9134 音频接口 pin 5 |
| I2S SDATA | N12 / P2-36 | SiI9134 音频接口 pin 9 |
| I2S LRCLK | P12 / P2-37 | SiI9134 音频接口 pin 10 |
| I2S BCLK | R16 / P2-38 | SiI9134 音频接口 pin 11 |
| UART TX，可选诊断 | D12 | 3.3 V USB 串口 RX，共地 |

音频接口使用 3.3 V 电平并共地。J1-35～40 不是上述音频排针。全部 HDMI 数据、时钟、控制、按键和拨码球位以 `media_player.adc` 为准。数码管段选固定为 0、位选固定为 1，始终熄灭。

构建平台为 Windows 10/11 x64。已验证工具：Anlogic TD **5.6.5 SP3，151.449**、Python **3.13**、Zig **0.13.0**。默认 TD 路径为 `C:\Anlogic\TD_5.6.5_SP3_151.449\bin\td_commands_prompt.exe`。下载器应在设备管理器中显示为正常启用的 **Anlogic AL-Link Mini**；使用 TD 随附的驱动。只烧录已有位流不需要 Zig、Icarus 或媒体依赖。

把整个源码目录放在较短的 ASCII 路径，例如 `C:\FPGA_TF`。以下 PowerShell 命令均在该目录执行：

```powershell
Set-Location 'C:\FPGA_TF'
py -3.13 --version
Get-FileHash '.\bitstream\media_player.bit' -Algorithm SHA256
```

如果电脑没有 `py`，用本机 Python 3.13 可执行文件的完整路径替换 `py -3.13`。TD 安装位置不同时，在相关命令末尾追加 `--td '实际路径\td_commands_prompt.exe'`。

## 3. SRAM 下载：仅临时运行

给板卡正常供电，接好 AL-Link 的下载接口与电脑 USB 数据线，保留 TF 卡和 HDMI 接线。先执行离线命令预览，再执行下载：

```powershell
py -3.13 tools/program.py --mode sram --dry-run
py -3.13 tools/program.py --mode sram
```

`--dry-run` 只生成命令计划，不访问下载器，报告 `plan_validated=true`、`hardware_accessed=false`；该结果仅表示计划有效，不表示烧录成功。实际 SRAM 下载模式为 `jtag_burst`，不更改配置 Flash；断电后本次 SRAM 内容消失。

## 4. Flash 写入及校验：断电保留程序

使用同样的供电、下载器和数据线连接，执行：

```powershell
py -3.13 tools/program.py --mode flash --dry-run
py -3.13 tools/program.py --mode flash
```

该命令按顺序执行 `program_spi` 和 `verify_spi`。全程保留供电和下载连接，等待程序退出；默认总超时为 **900 秒**，覆盖写入和校验。输出应包含 `passed: true`，并在打印的 `verification/program_时间_flash/result.json` 中确认全部 `checks` 为 true。写入返回或下载器亮灯都不能替代校验结果。

只校验当前 Flash，不重写：

```powershell
py -3.13 tools/program.py --mode verify
```

脚本先核对位流哈希和器件标识 `EAGLE_S20_BG256`，器件不符即停止。日志、Tcl 和结果保存在新的 `verification/program_*` 目录。若未得到 `passed: true`，先查看该次日志；中断结果不算成功。

Flash 校验通过后，让板卡完全断电约 10 秒，断开 AL-Link 和电脑的数据连接，保留 TF 卡、HDMI、音频线及共地，再用原有供电入口提供单独 USB 电源。应自动进入文件列表、保持静音，选择文件后才能播放；数码管保持熄灭。配置和媒体读取不依赖电脑。音量、亮度、对比度等运行设置不写入 Flash，重新上电恢复默认。

## 5. 从源码构建

源码已附生成好的字库、面板文字和三个有效固件 ROM bank，未修改固件时可以直接构建：

```powershell
py -3.13 tools/build.py --build-root 'C:\tf_hdmi_build'
```

构建目录会以 `native_日期_时间` 命名，包含源文件副本、TD 工程、完整日志和 `build_manifest.json`。不指定 `--build-root` 时，默认使用系统临时目录下的 `tf_hdmi_build`，避免旧版 TD 的深路径问题。工具不读写 TF 卡，也不下载到板卡。

成功需同时满足：进程退出码 0、构建返回标记存在、无工具错误、输入源码未改变、生成 `.bit`，以及**完整物理布局布线的 setup 和 hold 均通过**。`--synthesis-only` 只能检查综合，完整构建仍需执行物理布局布线。保持 `media_player.sdc` 的原有约束，不用放宽约束掩盖负时序。物理报告位于：

```text
构建目录/project/media_player_Runs/phy_1/media_player.bit
构建目录/project/media_player_Runs/phy_1/*_phy.timing
构建目录/project/media_player_Runs/phy_1/*_phy.tsm
构建目录/build_manifest.json
```

烧录自行重建的位流时，显式给出该文件和独立计算的完整哈希。例如：

```powershell
$rebuiltBit = 'C:\tf_hdmi_build\native_实际日期_实际时间\project\media_player_Runs\phy_1\media_player.bit'
$rebuiltSha = (Get-FileHash -LiteralPath $rebuiltBit -Algorithm SHA256).Hash
py -3.13 tools/program.py --mode flash --bit $rebuiltBit --sha256 $rebuiltSha
```

修改 `firmware/storage.c`、`start.S` 或 `storage.ld` 后，先重建 ROM：

```powershell
py -3.13 tools/build_storage_firmware.py --zig 'C:\Tools\zig-0.13.0\zig.exe'
py -3.13 tools/build.py --build-root 'C:\tf_hdmi_build'
```

脚本检查 Zig 0.13.0，并将固件限制在 12 KiB ROM。结果写入 `verification/firmware/manifest.json`，并更新 `rtl/storage_rom_0`、`_1`、`_2` 的 `.hex/.mif`。修改固件后重新运行存储回归，再交付新的 ROM。

## 6. 仿真与回归

主机测试及语义检查所需 Python 包：

```powershell
py -3.13 -m pip install -r tools/requirements.txt -r tools/requirements-media.txt
py -3.13 tools/run_host_tests.py
py -3.13 tools/lint_rtl.py
```

本项目使用 Icarus Verilog **10.1 stable**，源码包不含模拟器。将完整 Windows 发行包（含 `bin/`、`lib/` 等配套文件）解压到 `tools/_iverilog/`，其中应有 `tools/_iverilog/bin/iverilog.exe` 和同目录的 `vvp.exe`；仅复制两个可执行文件无法运行。通用 `run_sim.py` 也会搜索 PATH，或可用 `--iverilog` 指定已安装位置。快速关键检查：

```powershell
py -3.13 tools/run_sim.py ui_start ui i2s_volume top_compile --report verification/smoke.json
```

存储边界回归还需要 Windows 版 **Verilator 5.48.0** 和 **Zig 0.13.0**。在项目根目录安装到脚本默认位置：

```powershell
py -3.13 -m pip install --target tools/_verilator verilator==5.48.0
py -3.13 -m pip install --target tools/_zig ziglang==0.13.0
```

已有安装可用环境变量 `VERILATOR_ROOT` 指向含 `bin/verilator_bin.exe`、`include/` 的 Verilator 目录，`TF_ZIG` 指向 `zig.exe`。这两项工具只用于相应仿真；普通 TD 构建使用已附 ROM 即可。全量通用回归（27 项）与当前存储链路回归分别执行：

```powershell
py -3.13 tools/run_sim.py --timeout 7200
py -3.13 tools/test_media_storage.py
py -3.13 tools/test_storage_boundaries.py
py -3.13 tools/test_storage_cpu.py --program-bits 32
py -3.13 tools/test_storage_cpu.py --program-bits 14
py -3.13 tools/test_media_library.py --production --pcm-period 1042 --sd-gap 14 --timeout 7200
```

安装 Verilator 后，`run_sim.py`、`test_media_storage.py` 和 `test_media_library.py` 均可追加 `--simulator verilator` 加速；`test_storage_boundaries.py` 固定使用 Verilator。`test_storage_cpu.py` 使用上述 Icarus 安装。

整帧、时码穷举和生产参数端到端仿真可能耗时较长；超时记为未通过，长测试仍需保留。`ui_times` 覆盖全部 65,536 秒值的三个时钟输出。每次运行会把通用回归、主机回归和专项结果写入 `verification/`，该目录中的报告不作为源码输入。

不同测试应使用不同的结果目录。

完整回归包括 RTL、文件系统边界、生产参数端到端和主机测试。语义检查存在已归类警告；“通过”表示无语义错误且输入未改变，不表示无警告。物理时序和板上验收需要在目标硬件和 TD 环境中重新执行。

各功能的板上操作见 `docs/FPGA_用户操作手册.md`，媒体字段和转换步骤见 `docs/媒体格式规范与转换指南_Media_Format_Specification.md`。

## 7. TF 卡与支持格式

当前程序在上电时枚举真实 FAT32/exFAT 文件系统，支持 MBR 分区或裸卷、子目录和碎片文件，无须编译文件扇区表。卡使用 512 字节逻辑扇区；不支持 GPT、NTFS 或 FAT16。读取期间不热插拔，换卡后重新上电。

| 文件 | 当前支持的内容 |
|---|---|
| `.BMP` | 24/32 位、BI_RGB 未压缩；宽高均为 1～2048，支持正向或倒向行序 |
| `.WAV` | RIFF PCM、48,000 Hz、16 位、双声道；最多 172,800,000 个双声道样本帧 |
| `.LRC` | 同目录同主文件名匹配 WAV；可打印 ASCII、最多 1 MiB、4096 句、每句 78 字符；时间严格递增、分钟小于 60 且在歌曲内 |
| `.TFV` | 本工程 TFM3 单视频容器，含未压缩图像帧和 PCM；不是把 MP4 改扩展名 |
| `.PAK` | 兼容既有 TFM3 素材包；有受支持的独立媒体时优先使用独立媒体 |

每类视频、图片、歌曲最多 128 个，歌词最多 127 个，枚举目录最多 64 个。列表按视频 → 图片 → 音频排列，类内按卡上目录枚举次序；每行显示文件名的前 32 个 ASCII 字符，非 ASCII 字符显示 `?`。LRC 不单独出现在播放列表。同名歌词应与对应歌曲匹配，避免把不同内容放在同一目录中。

图片静音轮播，音乐使用纯色背景，视频使用容器内音轨；程序不会自动把其他歌曲混入图片。默认进入列表，不自动播放。操作请看 `docs/FPGA_用户操作手册.md`。

### 7.1 转换新素材

通用转换器为 [tools/media_convert.py](tools/media_convert.py)，独立说明为 [媒体格式规范与转换指南 / Media Format Specification](docs/媒体格式规范与转换指南_Media_Format_Specification.md)。该双语文件逐字段说明 TFM3 容器、BGRX 像素、PCM、CRC、时间与定位、容量、限制、最小样例及独立解封装。BMP/WAV/LRC 使用标准格式的受限子集；TFV 是本工程的单视频容器扩展名，不是通用压缩编码。

```powershell
py -3.13 -m pip install -r tools/requirements-media.txt
py -3.13 tools/media_convert.py image 'C:\Assets\photo.jpg' 'C:\TF_OUT\01_PHOTO.bmp'
py -3.13 tools/media_convert.py audio 'C:\Assets\song.mp3' 'C:\TF_OUT\01_SONG.wav'
py -3.13 tools/media_convert.py lyrics 'C:\Assets\song.lrc' 'C:\TF_OUT\01_SONG.lrc' --wav 'C:\TF_OUT\01_SONG.wav'
py -3.13 tools/media_convert.py video 'C:\Assets\movie.mp4' 'C:\TF_OUT\00_MOVIE.tfv'
py -3.13 tools/media_convert.py inspect 'C:\TF_OUT\00_MOVIE.tfv'
```

工具使用 Pillow 和 FFmpeg 处理完整输入并拒绝覆盖；视频默认 **384×208、8 fps**，音轨 **48 kHz/16-bit/stereo**，转换后完整回读 CRC。独立歌曲最多 1 小时，本转换器单视频最多 6 小时；长视频需要充足的电脑临时空间及 exFAT 目标卡。非 ASCII 歌词直接报错，需先提供准确英文转写或译文。转换不访问板卡，完成后按上述支持格式复制到 TF 卡。参数和文件布局以独立规范为准。

## 8. 故障处理

| 现象 | 操作 |
|---|---|
| USB device open error | 检查下载数据线、AL-Link 驱动和设备是否被禁用；关闭其他占用下载器的工具，再重试 |
| Device Manager Code 22 | 在设备管理器启用 Anlogic AL-Link Mini |
| 写入后校验超时 | 保留日志；恢复下载连接后单独执行 `--mode verify`，通过后再做冷启动 |
| 上电有列表但无声音 | 启动列表本来不播放；选择 WAV/TFV，检查 `VOL` 与 `MUTED`，再检查 HDMI 音量与 I2S 连接 |
| 没有支持文件 | 检查文件系统和真实编码；不能只改扩展名 |
| FILE ERROR | 抄下十六进制代码；KEY0 进入列表选择其他文件。格式代码见操作手册 |
| INVALID、黑屏或花屏持续 | 检查卡、HDMI、供电和位流身份；保留屏幕状态与构建/烧录日志，不把状态异常当成功 |
| 独立供电后程序不对 | 确认做过 Flash 写入与校验，且使用原有供电入口和已验证的 Flash 启动设置 |

可选只读串口诊断：D12 → 3.3 V USB-UART RX、共地，1,000,000 baud、8N1；`tools/monitor_status.py --help` 显示参数。串口状态不是 HDMI 画面或实际声音。

---

## English: build, program and operate the FPGA

### Release identity and hardware

This release targets **EG4S20BG256**, an **AN9134 / SiI9134** transmitter and the validated **1280×800** display. The supplied `bitstream/media_player.bit` has SHA-256:

```text
9f46370b796f8bda3b004b857217137cf4ad5d83ad8c7f857e0859132c8632b5
```

This bitstream passed configuration Flash programming and independent verification. The user confirmed a cold start with power only, normal picture, sound and controls, and all seven-segment digits off. A working board needs no further programming.

Keep the validated expansion-board connection, TF card, HDMI cable, power input and common ground. Use **3.3 V I2S**: M12 / P2-35 → SiI9134 pin 5 (MCLK), N12 / P2-36 → pin 9 (SDATA), P12 / P2-37 → pin 10 (LRCLK), R16 / P2-38 → pin 11 (BCLK). J1-35 through J1-40 are not these audio pins. `media_player.adc` is the authority for all remaining pins and electrical settings. The board oscillator is 50 MHz at R7. UART TX at D12 is optional, 1,000,000 baud, 8N1, read-only diagnostics.

### Required tools and working directory

Validated on Windows x64 with **Anlogic TD 5.6.5 SP3, 151.449**, **Python 3.13**, and **Zig 0.13.0** for firmware rebuilds. Install the TD AL-Link driver and enable **Anlogic AL-Link Mini** in Device Manager. Existing bitstream programming needs Python and TD; Zig and a simulator are not required.

Copy this complete folder to a short ASCII path such as `C:\FPGA_TF`, open PowerShell there, and run `py -3.13` commands. Replace that launcher with the full Python 3.13 executable path if needed. The default TD executable is `C:\Anlogic\TD_5.6.5_SP3_151.449\bin\td_commands_prompt.exe`; add `--td 'your\td_commands_prompt.exe'` if different.

### Programming commands

Connect board power, the AL-Link JTAG interface and the USB data cable. Keep the TF card and HDMI connections in place.

```powershell
Set-Location 'C:\FPGA_TF'
Get-FileHash '.\bitstream\media_player.bit' -Algorithm SHA256
py -3.13 tools/program.py --mode sram --dry-run
py -3.13 tools/program.py --mode sram
py -3.13 tools/program.py --mode flash --dry-run
py -3.13 tools/program.py --mode flash
py -3.13 tools/program.py --mode verify
```

Choose **sram** for temporary `jtag_burst` configuration, **flash** for persistent `program_spi` followed by `verify_spi`, or **verify** to check Flash without rewriting it. These modes are alternatives. `--dry-run` only writes a plan and never opens the downloader; `plan_validated` confirms the plan, not hardware programming.

The script validates the bitstream hash and device ID `EAGLE_S20_BG256`. Programming is complete only when it exits successfully and reports `passed: true` with every check true. Logs, Tcl and JSON are saved in a new `verification/program_*` directory. Keep power and the downloader connected until it finishes; the default total timeout is **900 seconds**. If verification is interrupted, restore the connection and run **verify** separately.

After successful Flash verification, turn board power off for about 10 seconds. Disconnect the downloader and computer data connection, keep the media and display wiring, then supply power through the original board power input. The file list should appear without automatic playback, and the seven-segment display must remain dark. Select a file to start playback. Runtime volume and picture settings return to defaults after power cycling; they are not saved in Flash.

### Rebuilding the design

Generated fonts, panel text and the three active firmware ROM banks are included. An ordinary full build is:

```powershell
py -3.13 tools/build.py --build-root 'C:\tf_hdmi_build'
```

Without `--build-root`, a short `tf_hdmi_build` folder under the system temporary directory is used. The script creates a timestamped project, does not access hardware or media, and checks process status, error messages, unchanged input hashes, the output bitstream and **complete routed setup and hold timing**. Synthesis alone checks only the synthesis stage; the full routed build remains required. Keep the original SDC constraints so timing failures remain visible.

Outputs are `project/media_player_Runs/phy_1/media_player.bit`, the `*_phy.timing` and `*_phy.tsm` reports, and `build_manifest.json` under the printed build directory. A rebuilt bitstream may have a different hash. To program it, pass its full path with `--bit` and independently computed SHA-256 with `--sha256`.

The comment-free RTL preserves 17 keep attributes. The build tool restores the validated TD synthesis directives in its temporary inputs. Use the build tool to preserve these attributes.

After changing `firmware/storage.c`, `start.S` or `storage.ld`, run:

```powershell
py -3.13 tools/build_storage_firmware.py --zig 'C:\Tools\zig-0.13.0\zig.exe'
py -3.13 tools/build.py --build-root 'C:\tf_hdmi_build'
```

The ROM builder checks Zig 0.13.0 and enforces a 12 KiB ROM limit. It writes `rtl/storage_rom_0`, `_1`, `_2` as HEX/MIF plus a generated `verification/firmware/manifest.json`. Run storage regression again after firmware changes.

### Reproducing checks

Install both requirements files for the complete host suite, including media conversion. Icarus Verilog **10.1 stable** is used for simulation but is not included in this source package. Extract the complete Windows distribution, including its `bin/`, `lib/` and supporting files, into `tools/_iverilog/`; both `bin/iverilog.exe` and `bin/vvp.exe` must exist. The general `run_sim.py` runner also searches PATH or accepts `--iverilog`; storage-specific regression scripts use the default location. The two executables alone are not a complete installation.

The storage boundary suite also needs Windows **Verilator 5.48.0** and **Zig 0.13.0**. Install them into the default locations from the project root:

```powershell
py -3.13 -m pip install --target tools/_verilator verilator==5.48.0
py -3.13 -m pip install --target tools/_zig ziglang==0.13.0
```

Alternatively, set `VERILATOR_ROOT` to the directory containing `bin/verilator_bin.exe` and `include/`, and `TF_ZIG` to `zig.exe`. These tools are needed for the corresponding simulations; an ordinary TD build uses the included ROMs.

```powershell
py -3.13 -m pip install -r tools/requirements.txt -r tools/requirements-media.txt
py -3.13 tools/run_host_tests.py
py -3.13 tools/lint_rtl.py
py -3.13 tools/run_sim.py ui_start ui i2s_volume top_compile --report verification/smoke.json
py -3.13 tools/run_sim.py --timeout 7200
py -3.13 tools/test_media_storage.py
py -3.13 tools/test_storage_boundaries.py
py -3.13 tools/test_storage_cpu.py --program-bits 32
py -3.13 tools/test_storage_cpu.py --program-bits 14
py -3.13 tools/test_media_library.py --production --pcm-period 1042 --sd-gap 14 --timeout 7200
```

After installing Verilator, append `--simulator verilator` to `run_sim.py`, `test_media_storage.py` or `test_media_library.py` for faster simulation. `test_storage_boundaries.py` always uses Verilator; `test_storage_cpu.py` uses the Icarus installation above.

Full-frame and exhaustive simulations can be slow. The general suite has 27 tests; `ui_times` checks all 65,536 second values and three independently formatted outputs. A timeout is an unsuccessful result. Give concurrent runs separate output directories.

Host and general simulation reports, along with storage-suite output, are generated under `verification/`. Semantic checks have categorized warnings; passing means no semantic errors and unchanged inputs, not zero warnings. Re-run physical timing and board checks on the target TD and hardware setup.

The board controls and user-visible behavior are documented in `docs/FPGA_用户操作手册.md`; the media container and conversion rules are in `docs/媒体格式规范与转换指南_Media_Format_Specification.md`.

### Supported media and operation

The firmware enumerates FAT32/exFAT volumes at startup, including MBR or unpartitioned volumes, subdirectories and fragmented files. Logical sectors are 512 bytes. GPT, NTFS and FAT16 are unsupported. No compiled physical-sector map is required. Power down before replacing the card.

Supported files are uncompressed BI_RGB 24/32-bit BMP (1–2048 pixels per axis), RIFF PCM WAV (48 kHz, 16-bit stereo, at most 172,800,000 stereo sample frames), matching ASCII LRC files, and this project's TFM3 single-video TFV container. TFV contains raw frames and PCM, and is not an MP4 renamed to another extension. Matching LRC files must share the WAV's folder and stem, be at most 1 MiB, contain at most 4096 cues of 78 characters each, and use increasing in-track timestamps with minutes below 60. Existing TFM3 PAK packages remain compatible; supported independent media take priority.

Limits are 128 videos, 128 pictures, 128 songs, 127 LRC files and 64 enumerated directories. The list is grouped video → image → audio, preserving on-card enumeration order within each group. Names show up to 32 ASCII characters; unsupported characters appear as `?`. LRC files accompany songs rather than appearing as separate playable entries.

Startup opens the file list and stays silent. KEY1/2 move, KEY3 opens, KEY0 returns to the list, KEY13 hides or recalls the UI, KEY4 enters keyboard seek, and KEY15 taps to mute or holds for about half a second to open the volume page. Pictures are silent, songs use a plain background, and video uses its own soundtrack. The complete board key layout, context-dependent actions and English on-screen labels are documented in `docs/FPGA_用户操作手册.md`.

### Converting new media

Use [tools/media_convert.py](tools/media_convert.py) and the separate bilingual [Media Format Specification and Conversion Guide](docs/媒体格式规范与转换指南_Media_Format_Specification.md). The guide defines every container field, BGRX pixels, PCM, CRC, timing, seeking, capacity, bounds, a binary conformance fixture and independent extraction. BMP/WAV/LRC are constrained standard formats; TFV is the project's single-video container extension, not a general compression codec.

```powershell
py -3.13 -m pip install -r tools/requirements-media.txt
py -3.13 tools/media_convert.py image 'C:\Assets\photo.jpg' 'C:\TF_OUT\01_PHOTO.bmp'
py -3.13 tools/media_convert.py audio 'C:\Assets\song.mp3' 'C:\TF_OUT\01_SONG.wav'
py -3.13 tools/media_convert.py lyrics 'C:\Assets\song.lrc' 'C:\TF_OUT\01_SONG.lrc' --wav 'C:\TF_OUT\01_SONG.wav'
py -3.13 tools/media_convert.py video 'C:\Assets\movie.mp4' 'C:\TF_OUT\00_MOVIE.tfv'
py -3.13 tools/media_convert.py inspect 'C:\TF_OUT\00_MOVIE.tfv'
```

The converter uses Pillow and FFmpeg, handles the full input, refuses overwrites and performs complete CRC readback for TFV. Defaults are **384×208 at 8 fps**, **48 kHz/16-bit/stereo**. Standalone songs are limited to one hour; one video conversion is limited to six hours. Long videos need adequate temporary disk space and an exFAT destination card. Non-ASCII lyrics are rejected; supply an accurate English translation/transliteration first. Conversion does not connect to the board. Copy validated media to the card using the rules above; consult the independent specification for all parameters and binary layouts.

For downloader errors, check the data cable, TD driver, disabled-device status and competing downloader applications. Code 22 means the device must be enabled. For silent playback, first select an audio/video file and check `VOL`, `MUTED`, the display volume and I2S wiring. On `FILE ERROR`, record the hexadecimal code and use KEY0 to select another file. Persistent `INVALID`, black or corrupt output is a fault to investigate using the card, wiring, bitstream identity and saved logs. UART diagnostics do not capture HDMI pixels or actual sound.
