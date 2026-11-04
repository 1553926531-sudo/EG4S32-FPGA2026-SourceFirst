# 媒体格式规范与转换指南 / Media Format Specification and Conversion Guide

文档版本 / Document version: **1.0, 2026-11-04**  
适用程序 / Target: **EG4S20 TF Media Player, TFM3 version 3, 1280×800**  
转换工具 / Converter: [tools/media_convert.py](../tools/media_convert.py)  
最小格式样例生成器 / Minimal conformance example: [tools/make_format_example.py](../tools/make_format_example.py)

已校验的最小二进制文件 / Validated minimal binary fixture: [minimal_format_example.tfv](../examples/minimal_format_example.tfv)

阅读顺序 / Reading order: 第 1～7 节说明格式选择和实际转换；第 8～14 节逐字节定义容器；第 15～18 节说明时间、容量和独立实现；第 19～22 节说明存储、验证、兼容和解封装。 / Sections 1–7 cover format choices and conversion; 8–14 specify the binary container; 15–18 cover timing, size and independent implementations; 19–22 cover storage, validation, compatibility and extraction.

## 1. 这是什么格式 / What these formats are

图片、独立音频和独立歌词分别采用 Windows BMP、RIFF WAVE 和 LRC 的明确受限子集。**TFV 是本工程定义的单视频文件扩展名，内部为 TFM3 第 3 版容器**。TFM3 容器把原始视频帧、PCM 音轨和索引组织成适合 FPGA 顺序读取与定位的 512 字节块。它是项目专用格式，不属于 MP4、AVI 或 MJPEG 的行业变种。

Images, standalone audio and standalone lyrics use constrained subsets of Windows BMP, RIFF WAVE and LRC. **TFV is this project's extension for a single video stored in a version-3 TFM3 container.** TFM3 arranges raw video frames, PCM sound and indexes into 512-byte blocks for FPGA reads and seeking. It is a project format rather than an industry format such as MP4, AVI or MJPEG.

容器不使用 JPEG、H.264、H.265、MP3、AAC 或任何帧间压缩。视频帧是完整的 BGRX8888 原始图像，音频是 48 kHz/16 位/双声道有符号 PCM。电脑端 FFmpeg 负责将常见压缩格式解码、缩放、降帧并重采样；FPGA 只处理转换后的表示。把 `.mp4` 改成 `.tfv`、把 `.mp3` 改成 `.wav`，均无效。

The container uses no JPEG, H.264, H.265, MP3, AAC or inter-frame compression. Every video frame is a complete raw BGRX8888 image; audio is signed 48 kHz, 16-bit, stereo PCM. FFmpeg on the computer decodes common codecs, resizes and resamples them before packaging. Renaming an MP4 to TFV or an MP3 to WAV does not convert it.

| 文件 / File | 用途 / Purpose | 实际格式 / Actual representation |
|---|---|---|
| `.BMP` | 独立图片 / Standalone picture | 未压缩 BI_RGB，24/32 位；工具输出 24 位 / Uncompressed BI_RGB, 24/32 bits; converter writes 24 bits |
| `.WAV` | 独立歌曲 / Standalone song | RIFF WAVE，PCM tag 1，48,000 Hz，16-bit stereo |
| `.LRC` | 同名歌曲的定时歌词 / Timed lyrics for the matching song | 本文规定的可打印 ASCII 子集 / Printable-ASCII subset specified here |
| `.TFV` | 独立视频及其音轨 / Standalone video and soundtrack | TFM3 version 3，1 段视频、1 条电影音轨、无图片库/歌曲库 / One video, one soundtrack, no slideshow or song library |
| `.PAK` | 兼容早期组合素材包 / Compatibility with existing combined packages | 同一 TFM3 二进制结构，可额外带图片和歌曲 / Same TFM3 structure, optionally with pictures and songs |

新素材生成独立 BMP/WAV/LRC/TFV 文件。板卡启动时会枚举这些文件，PAK 用于兼容已经在卡上的旧素材。本文描述本工程当前实现和转换器规则；TFV 仅由本项目播放器识别。

New media should be independent BMP/WAV/LRC/TFV files. The board enumerates them at startup, while PAK support preserves existing cards. This document specifies the current project implementation and converter; TFV support is specific to this player.

## 2. 术语、规范级别与数值约定 / Terminology and numeric conventions

- **必须 / MUST**：本转换器生成的规范文件应满足的要求。**建议 / SHOULD**：有助于兼容和实际播放的参数。
- **扇区 / sector**：容器内部固定的 512 字节逻辑块，不是卡的物理擦除块。
- **LBA**：相对**本文件开头**的扇区编号；字节位置为 `LBA × 512`，不对应 TF 卡物理扇区号。
- **word**：32 位无符号整数，占 4 字节；`word[k]` 的字节偏移为 `4k`。
- **样本帧 / sample frame**：同一时刻的左、右两个音频样本，共 4 字节。
- **画面帧 / video frame**：完整的一张源图像；其尺寸可以小于 HDMI 输出的 1280×800。
- 除 PCM 样本为 16 位有符号补码外，本文二进制字段均为 **little-endian unsigned 32-bit**。没有 C 结构体隐式 padding。
- 未定义的保留字段必须由本转换器写零。读取器忽略保留字段不构成扩展机制。

**MUST** describes conforming converter output; **SHOULD** identifies recommended compatibility choices. All sector addresses are file-relative, all numeric words are unsigned little-endian 32-bit values, and PCM samples alone are signed 16-bit two's-complement values. One stereo sample frame occupies four bytes. Source-frame dimensions differ from the fixed HDMI output dimensions. Writers zero reserved fields; a reader ignoring some reserved fields does not define an extension mechanism.

TFM3 的“第 3 版”由文件头 `word[1] = 3` 表示。由于历史兼容，第 3 版仍以 **`TFM1` 四个字节**开头；有效文件的开头不是字符串 `TFM3` 或 `TFV`。

Version 3 is encoded as `word[1] = 3`. For historical compatibility, the four magic bytes remain **`TFM1`**; valid files therefore begin with `TFM1`, not the text `TFM3` or `TFV`.

## 3. 安装和最短转换步骤 / Installation and quick conversion

在源码根目录打开 PowerShell。Python 3.13 已验证；安装依赖后，`imageio-ffmpeg` 提供转换所用 FFmpeg，或自行指定 FFmpeg 路径。仅转换图片不需要 FFmpeg。工具不连接 FPGA、不烧录、不写任何卡盘符。下列 `C:\Assets`、`C:\TF_OUT` 均为用户自行准备的电脑目录。

Open PowerShell in the source root. Python 3.13 is the validated version. The media requirements include an FFmpeg binary through `imageio-ffmpeg`; an existing FFmpeg can also be selected explicitly. Images only need Pillow. These tools do not connect to the board, program it, or access a card drive. The following paths are example computer directories.

```powershell
py -3.13 -m pip install -r tools/requirements-media.txt
py -3.13 tools/media_convert.py --help
py -3.13 tools/media_convert.py video --help

py -3.13 tools/media_convert.py image 'C:\Assets\photo.jpg' 'C:\TF_OUT\01_PHOTO.bmp'
py -3.13 tools/media_convert.py audio 'C:\Assets\song.mp3' 'C:\TF_OUT\01_SONG.wav'
py -3.13 tools/media_convert.py lyrics 'C:\Assets\song.lrc' 'C:\TF_OUT\01_SONG.lrc' --wav 'C:\TF_OUT\01_SONG.wav'
py -3.13 tools/media_convert.py video 'C:\Assets\movie.mp4' 'C:\TF_OUT\00_MOVIE.tfv' --report 'C:\TF_OUT\movie_conversion.json'
```

每条命令均处理完整输入，不默认截取片段。输出文件和 `--report` 均拒绝覆盖已有文件，请使用新路径或先处理旧文件。转换成功后输出 `passed: true`、字节长度及 SHA-256。临时文件在目标目录旁创建，失败后清理，校验完成后才生成最终输出。JSON 报告留在电脑端，卡上只需媒体。

Each command processes the full input and does not select a clip by default. Output files and `--report` refuse existing paths, so use a new destination or handle the old file first. Success reports `passed: true`, byte length and SHA-256. Temporary files are created beside the destination and cleaned up on failure; final output is written after validation. Keep JSON reports on the computer; the card needs only media.

如果系统没有 `py`，用 Python 3.13 可执行文件的完整路径替代 `py -3.13`。FFmpeg 选择顺序是 `--ffmpeg` → 系统 PATH → `imageio-ffmpeg`：

Replace `py -3.13` with the full Python executable path if the launcher is unavailable. FFmpeg resolution is explicit `--ffmpeg`, then system PATH, then `imageio-ffmpeg`:

```powershell
py -3.13 tools/media_convert.py audio 'C:\Assets\song.aac' 'C:\TF_OUT\02_SONG.wav' --ffmpeg 'C:\Tools\ffmpeg\bin\ffmpeg.exe'
```

## 4. 图片：标准 BMP 子集 / Pictures: the BMP subset

常见 JPEG、PNG、WebP、TIFF、GIF、BMP 可通过 Pillow 解码，实际可用格式取决于其解码插件。动画 GIF 只取第一帧。工具应用 EXIF 方向，将透明部分合成到背景色，再转成 RGB，按比例缩小至限制框内，不放大小图、不裁剪，写 24-bit BI_RGB。源图中的 ICC 色彩配置不做额外颜色管理变换；保存后的 RGB 数值作为显示比较基准。

Pillow decodes common JPEG, PNG, WebP, TIFF, GIF and BMP inputs, subject to installed decoders. Animated GIF uses its first frame. The converter applies EXIF orientation, composites transparency, converts to RGB, reduces the image to fit the limits while preserving aspect ratio, never enlarges a small image, and writes 24-bit BI_RGB. No extra ICC color-management transform is applied; the resulting RGB values define the playback reference.

| 项目 / Item | 规定 / Requirement |
|---|---|
| Signature | `BM`, bytes `42 4D` |
| DIB | 读取器接受 40～124 字节；工具输出 BITMAPINFOHEADER 40 / Reader accepts 40–124 bytes; writer uses 40 |
| Width, abs(height) | 各 1～2048 像素 / Each 1–2048 pixels |
| Planes | 1 |
| Bit count | 读取器 24/32；工具 24 / Reader 24/32; writer 24 |
| Compression | 0 = BI_RGB；不接受 RLE 或 BI_BITFIELDS / No RLE or BI_BITFIELDS |
| Pixel bytes | 24 位为 `B G R`；32 位为 `B G R X`，X 不作 alpha 混合 / 24-bit BGR; 32-bit BGRX, no alpha blending |
| Row bytes | `((width × bytes_per_pixel + 3) // 4) × 4` |
| Row order | 正 height 为自底向上；负 height 为自顶向下 / Positive height: bottom-up; negative: top-down |
| Pixel offset | 不小于 `14 + DIB_size`，且所有行必须在文件范围内 / At least `14 + DIB_size`, with all rows in bounds |

```powershell
py -3.13 tools/media_convert.py image 'C:\Assets\large.png' 'C:\TF_OUT\02_IMAGE.bmp' --max-width 2048 --max-height 2048 --background 000000
py -3.13 tools/media_convert.py inspect 'C:\TF_OUT\02_IMAGE.bmp'
```

`--background` 为六位 RGB 十六进制，例如 `FFFFFF` 白色。最大宽高默认均为 2048，可降低但不能超过板上上限。图片尺寸不必为 1280×800；板上 Z0～Z3 模式负责等比适配、中心放大/两侧压缩、拉伸和原尺寸裁剪。图片文件不包含音轨，播放图片时系统输出静音。

`--background` is six RGB hexadecimal digits, for example white `FFFFFF`. Both default limits are 2048 and may be reduced. Pictures need not be 1280×800: board zoom modes handle aspect fitting, nonlinear center expansion/edge compression, stretching and original-size cropping. Picture files contain no soundtrack; picture playback is silent.

## 5. 独立歌曲：RIFF WAVE / Standalone songs: RIFF WAVE

常见 MP3、AAC/M4A、FLAC、OGG、WAV 以及含音轨的视频，均可交给当前 FFmpeg 解码；支持的具体编码由 FFmpeg 构建决定。转换器选择**第一条音轨**，不混音多条音轨，删除封面和元数据，输出标准 RIFF PCM。单声道会变双声道；多声道会经 FFmpeg 下混；采样率重采样为 48 kHz。输出是标准 PCM，不保留压缩输入的每一位。

Common MP3, AAC/M4A, FLAC, OGG, WAV and audio-bearing video inputs can be decoded by FFmpeg, depending on its build. The first audio stream is selected; multiple streams are not mixed. Artwork and metadata are removed. Mono is converted to stereo, multichannel sound is downmixed by FFmpeg, and the result is resampled to 48 kHz. This conversion does not preserve every bit of a compressed input.

| RIFF/WAVE 字段 / Field | 值 / Value |
|---|---|
| Container | `RIFF` + 32-bit size + `WAVE`；不接受 RF64 / RF64 unsupported |
| `fmt ` format tag | 1，线性 PCM / Linear PCM |
| Channels | 2，左后右 / Left then right |
| Sample rate | 48,000 Hz |
| Byte rate | 192,000 bytes/s |
| Block align | 4 bytes |
| Bits per sample | 16 |
| `data` length | 正数且为 4 的倍数 / Positive multiple of four |
| Samples | `data_bytes / 4`，最多 172,800,000 / At most 172,800,000 |
| Duration | 大于 0，最长 3600 秒 / Positive, at most 3600 seconds |

板上读取器会按 RIFF chunk 长度和偶数字节 padding 跳过其他 chunk，最多扫描 4096 个 chunk，找到有效 `fmt ` 和 `data` 后开始使用数据。规范文件的 `fmt `、`data` 各有且只有一个，所有 chunk 均在 RIFF 和实际文件边界内；本转换工具还会检查整个 RIFF 区域，拒绝尾部重复 chunk 或缺失 padding。规范输出不使用 24-bit、float PCM、WAVE_FORMAT_EXTENSIBLE、ADPCM 或仅改扩展名的文件。

The board follows RIFF chunk sizes and even-byte padding, scanning at most 4096 chunks until valid `fmt ` and `data` chunks are found. A conforming file has exactly one of each and every chunk stays within RIFF/file bounds. This conversion tool additionally checks the complete RIFF region, rejecting trailing duplicate chunks and missing padding. Use converter output rather than 24-bit, float, extensible WAVE, ADPCM or renamed compressed files.

PCM 的每 4 字节是 `L_low L_high R_low R_high`。例如左声道 `+1234`、右声道 `-2345` 编码为 `D2 04 D7 F6`。独立 WAV 的 PCM 区域**没有** TFM3 的每扇区 CRC；两种音频存储布局分别处理。

Each PCM sample frame is `L_low L_high R_low R_high`. Left `+1234` and right `-2345` encode as `D2 04 D7 F6`. A standalone WAV data chunk has **no** TFM3 per-sector CRC; the two layouts are handled separately.

## 6. 歌词：LRC 子集和转换策略 / Lyrics: LRC subset and conversion policy

歌曲与歌词必须放在同一目录、主文件名相同，例如 `01_SONG.wav` 和 `01_SONG.lrc`；歌词不是独立播放条目。ASCII 文件名最可靠。当前字库不包含中文歌词；**工具对非 ASCII 文本报错，不会删除、翻译或生成乱码**。遇到非 ASCII 歌词时，先提供准确的英文翻译/转写版本再转换。UTF-8 能保存中文不代表板上字库能显示中文。

The WAV and LRC must have the same stem and directory, such as `01_SONG.wav` and `01_SONG.lrc`. Lyrics are not separate playlist entries. Use ASCII filenames. The current font does not contain Chinese lyric glyphs. **The tool rejects non-ASCII text and does not remove or translate it.** Supply an accurate English translation or transliteration first. UTF-8 storage alone does not make a glyph available on the board.

规范输出每行是 `[mm:ss.mmm]TEXT`，ASCII 编码，LF 换行，无 BOM：

Canonical output uses one `[mm:ss.mmm]TEXT` per line, ASCII encoding, LF line endings and no BOM:

```text
[00:00.000]TRACK TITLE
[00:12.340]FIRST LYRIC LINE
[00:18.700]NEXT LYRIC LINE
```

| 项目 / Item | 限制 / Limit |
|---|---|
| File size | 非空，最多 1 MiB / Nonempty, at most 1 MiB |
| Cue count | 工具 1～4096；歌曲可不提供 LRC / Converter 1–4096; songs may omit LRC |
| Minute / second | 各 0～59 / Each 0–59 |
| Fraction | 工具输出毫秒三位 / Writer uses three millisecond digits |
| Timeline | 严格递增且不重复，`timestamp_ms × 48 < WAV_sample_frames` / Strictly increasing, unique, inside track |
| Text bytes | 0x20～0x7E，每句最多 78 字符 / Printable ASCII, at most 78 characters per cue |
| Display | 两行各 39 字符；无自动中文排版 / Two rows of 39 characters |

转换输入允许 1～3 位小数、多个时间标签、常用 `ar/ti/al/by/re/ve/length` 元数据和一个 `[offset:整数毫秒]`。offset 按加法应用到每个时间。工具把多个时间标签展开、排序，内容相同的重复时间合并；同一时间有不同文字则拒绝。超出歌曲长度、负时间、未知语法及超过显示容量的文字均拒绝。

Input conversion accepts one to three fractional digits, repeated timestamps on one line, common `ar/ti/al/by/re/ve/length` metadata and one integer-millisecond `offset` tag. The offset is added to each time. The tool expands and sorts cues, deduplicates identical text at an identical time, and rejects conflicting text at one time. Negative/out-of-track times, unknown syntax and text beyond display capacity are rejected.

默认 `--layout two39` 按英文单词整理成两行，第一行补空格至 39 字符再接第二行；长单词无法放入一行时报错。`--layout keep` 保留 78 字符内的原有排布，但显示仍在第 39 字符后换行。`--encoding` 默认 `utf-8-sig`；旧文本可显式指定 `gb18030`，但解码后文字仍须是可打印 ASCII。

Default `--layout two39` wraps at word boundaries into two rows, padding row one to 39 characters. An oversized unbreakable word is rejected. `--layout keep` preserves the supplied arrangement up to 78 characters; the display still breaks after cell 39. Input encoding defaults to `utf-8-sig`; `--encoding gb18030` can decode a legacy file, but its lyric text must still be printable ASCII.

```powershell
py -3.13 tools/media_convert.py lyrics 'C:\Assets\english.lrc' 'C:\TF_OUT\01_SONG.lrc' --wav 'C:\TF_OUT\01_SONG.wav' --layout two39
py -3.13 tools/media_convert.py inspect 'C:\TF_OUT\01_SONG.lrc' --wav 'C:\TF_OUT\01_SONG.wav'
```

## 7. 视频转换参数与实际配置 / Video conversion parameters and operating profile

```powershell
py -3.13 tools/media_convert.py video 'C:\Assets\movie.mp4' 'C:\TF_OUT\00_MOVIE.tfv' --width 384 --height 208 --frame-ms 125
py -3.13 tools/media_convert.py video 'C:\Assets\silent.mov' 'C:\TF_OUT\01_SILENT.tfv' --silent
py -3.13 tools/media_convert.py inspect 'C:\TF_OUT\00_MOVIE.tfv' --report 'C:\TF_OUT\movie_readback.json'
```

| 参数 / Parameter | 默认 / Default | 作用 / Effect |
|---|---|---|
| `--width` | 384 | 源帧画布宽，1～2048 / Stored source canvas width, 1–2048 |
| `--height` | 208 | 源帧画布高，1～2048 / Stored source canvas height, 1–2048 |
| `--frame-ms` | 125 | 恒定帧间隔，80～60000 ms；帧率为 `1000/frame_ms` / Constant frame interval; fps is `1000/frame_ms` |
| `--silent` | 关闭 / Off | 忽略源音轨并生成等时长全零 PCM / Ignore source sound and generate equal-duration zero PCM |
| `--ffmpeg` | 自动寻找 / Auto | 明确选择解码器路径 / Explicit decoder executable |
| `--report` | 不写文件 / None | 额外新建 JSON 参数和哈希报告 / Create an additional JSON parameter/hash report |

转换过程：第一条视频流 → 按指定 fps 采样 → 保持比例缩放 → 黑边补足画布 → BGR24 临时帧 → BGRX8888 分行补零并封装。源字幕、章节、封面和其他音轨不打包；需要烧录进画面的字幕应先在电脑制作到视频画面内。本工具不执行字幕翻译。

Pipeline: first video stream → constant-rate frame selection → aspect-preserving scaling → black canvas padding → temporary BGR24 frames → padded BGRX8888 TFM3 payload. Source subtitle streams, chapters, artwork and other soundtracks are not packaged. Burn subtitles into the input pictures beforehand if required; this tool does not translate subtitles.

默认使用第一条音轨，并转换为 PCM。若输入没有音轨，默认命令报错；加 `--silent` 明确生成静音音轨。实际视频帧数为 N 时，音频规范长度设为 **`N × frame_ms × 48` 个双声道样本帧**：短音轨尾部补静音，长音轨截到画面时间线，使生成文件的两个时间线一致。原始末帧的取舍由 FFmpeg fps 滤镜决定，误差量级为一个源转换帧间隔；命令默认处理完整视频。

The first audio stream is converted to PCM. An input without audio fails unless `--silent` is specified. For N converted frames, the canonical soundtrack has **`N × frame_ms × 48` stereo sample frames**. Short soundtracks are padded with silence; longer soundtracks end at the video timeline. FFmpeg's fps filter determines terminal-frame sampling, with quantization on the order of one converted frame interval. The command processes the complete video by default.

**当前实板配置实测为 384×208、8 fps（125 ms）、48 kHz 双声道，HDMI 输出保持 1280×800。** 文件语法允许更大源帧，但当前 SD/CPU/SDRAM 链路尚未在更大尺寸或帧率下验证实时播放。提高参数时重新进行吞吐量、时序、音画和整片播放验证；日常演示使用默认配置。

**The validated board profile is 384×208 at 8 fps (125 ms), with 48 kHz stereo sound and fixed 1280×800 HDMI output.** The current SD/CPU/SDRAM chain has not been validated for real-time playback at larger dimensions or frame rates allowed by the syntax. Higher settings require fresh throughput, timing, A/V and full-playback checks. Use defaults for the demonstrated operating profile.

容器可表示最长 12 小时的音轨；**本版通用转换器主动将单次视频转换限制为 6 小时**，使完整临时 RIFF WAV 在 4 GiB 边界以内。6 小时的 PCM 为 4,147,200,000 字节，外加 WAV 头；更长输入会明确报错，不截取成 6 小时，也不生成伪 RF64 文件。此转换器限制与独立歌曲的 1 小时限制、TFM3 容器的 12 小时语法上限分别适用。

The container can represent a 12-hour soundtrack; **this general converter limits one video conversion to six hours** to keep its temporary ordinary RIFF WAV below 4 GiB. Six hours uses 4,147,200,000 PCM bytes plus the WAV header. Longer input fails explicitly; it is neither clipped to six hours nor disguised as RF64. This converter limit, the one-hour standalone-song limit and the 12-hour container syntax bound are separate constraints.

视频转换会暂存完整 BGR24 和 WAV，再调用已经验证的 TFM3 打包器，并完整回读 CRC。默认参数下，源帧临时文件约 1.917 MB/s、WAV 约 0.192 MB/s、最终 TFV 约 2.754 MB/s；转换期间需要同时容纳这些文件，约 **4.87 MB × 视频秒数**的空闲空间，另计原始输入及文件系统余量。长视频的临时输出应放在空间充足的本机磁盘，不放在容量不足的 TF 卡上。

Video conversion temporarily stores complete BGR24 and WAV files, packages them using the verified TFM3 packer, then performs full CRC readback. At defaults, temporary BGR24 is about 1.917 MB/s, WAV 0.192 MB/s and final TFV 2.754 MB/s. Their peak combined space is about **4.87 MB × video seconds**, excluding the original input and filesystem overhead. Put temporary output on a local disk with enough free space for long videos.

## 8. TFM3 总体布局 / Overall TFM3 layout

容器长度必须恰好等于 `header.total_sectors × 512`。所有元数据记录均为一个独立的 512 字节带 CRC 扇区。规范写入顺序如下；地址均为文件相对值：

File length must equal `header.total_sectors × 512` exactly. Each metadata record occupies one CRC-protected 512-byte sector. Canonical order is:

```text
LBA 0                  Header (512 bytes)
LBA 1 ... N            N video-frame descriptors (IMG2)
LBA 1+N ...            M slideshow-image descriptors (IMG2), if M > 0
LBA 1+N+M ...          K audio descriptors (AUD3), K = music_count + 1
next sectors           All CUE3 records, grouped by audio track
payload_lba ...        All video frames, then slideshow images
audio_lba ...          Movie PCM, then each standalone-music PCM region
EOF                    Exactly total_sectors * 512 bytes
```

**独立 TFV 的规范布局**为 `M=0, music_count=0, K=1`。本转换器不在电影中写歌词，因此没有 CUE3 区域：

**The canonical single-video TFV profile** has `M=0`, `music_count=0`, `K=1`; the converter writes no movie lyric cues:

```text
0             Header
1 ... N       N IMG2 descriptors
N+1           One AUD3 descriptor
N+2 ...       N raw frame payloads
audio_lba ... Movie PCM sectors
```

头中的 `image_lba` 与 `audio_index_lba` 在独立 TFV 中都为 `N+1`，因为图片描述符数量为零。所有位置都从文件起点计算，正常复制、文件碎片化或卡内物理位置变化都不需要重新封装。

For standalone TFV, `image_lba` and `audio_index_lba` both equal `N+1` because there are zero image descriptors. File-relative addresses survive ordinary copying and fragmented allocation, so physical card positions do not require repackaging.

## 9. 文件头全部字段 / Complete header fields

每行字段类型均为 `u32le`。`N=video_frames`、`M=image_count`、`K=audio_count`。

Every listed field is `u32le`. `N` is the video-frame count, `M` the slideshow-image count, and `K` the audio-track count.

| word | 字节偏移 / Byte offset | 名称 / Name | 规定及含义 / Requirement and meaning |
|---:|---:|---|---|
| 0 | 0 | magic | `0x314D4654`，字节 `54 46 4D 31` = `TFM1` |
| 1 | 4 | version | **3** |
| 2 | 8 | output_width | **1280**，目标输出宽 / Target width |
| 3 | 12 | output_height | **800**，目标输出高 / Target height |
| 4 | 16 | pixel_format | **1** = 本文 BGRX8888 / BGRX8888 defined below |
| 5 | 20 | output_pixels | **1,024,000** = 1280×800 |
| 6 | 24 | video_frames | N，1～1,000,000 |
| 7 | 28 | frame_ms | 恒定帧间隔 80～60,000 ms / Constant frame interval |
| 8 | 32 | video_lba | **1**，首视频描述符 / First video descriptor |
| 9 | 36 | descriptor_stride | **1** 个描述符扇区；帧数据另行存储 / One descriptor sector; pixel payload is stored separately |
| 10 | 40 | image_lba | **1+N**，首图片描述符位置；M=0 时为空区 / First image descriptor, empty when M=0 |
| 11 | 44 | audio_lba | 第一条电影 PCM 的起始扇区 / First movie PCM sector |
| 12 | 48 | audio_samples | 第一条电影音轨样本帧数，1～2,073,600,000 / Movie stereo sample frames, at most 12 hours |
| 13 | 52 | sample_rate | **48,000** |
| 14 | 56 | sample_bits | **16** |
| 15 | 60 | channels | **2** |
| 16 | 64 | image_ms | 图片停留时间 1,000～60,000 ms；TFV 写 5,000 / Slideshow dwell; TFV writes 5,000 |
| 17 | 68 | total_sectors | 文件总扇区数，最多 200,000,000 / Total sectors, at most 200,000,000 |
| 18 | 72 | image_count | M，0～600；独立 TFV 必须为 0 / Standalone TFV must use zero |
| 19 | 76 | loop_flags | **1**，当前版本固定值 / Fixed value in this version |
| 20 | 80 | music_count | 额外歌曲数 0～600，不含电影音轨；TFV 为 0 / Extra songs excluding movie track; zero in TFV |
| 21 | 84 | audio_index_lba | **1+N+M** |
| 22 | 88 | audio_count | **music_count+1**，包含电影音轨 / Includes movie soundtrack |
| 23 | 92 | payload_lba | 首视频像素扇区，位于所有音频描述符和歌词之后 / First pixel sector after all descriptors and cues |
| 24～126 | 96～504 | reserved | 写零 / Write zero |
| 127 | 508 | header_crc32 | 对字节 0～507 的 CRC-32 / CRC-32 of bytes 0–507 |

规范边界关系 / Canonical bounds:

```text
metadata_end = 1 + N + M + K
metadata_end <= payload_lba < audio_lba < total_sectors <= 200000000
file_bytes = total_sectors * 512
```

无歌词时 `payload_lba = metadata_end`。本打包器逐区紧密存储，不留未定义空洞。12 小时音频上限和总扇区限制分别适用，二者都必须满足。文件理论上限为 102,400,000,000 字节，约 95.37 GiB；这是语法上限，不代表现有卡容量或已验证的播放配置。

Without lyrics, `payload_lba = metadata_end`. The packer stores regions contiguously with no undefined gaps. The 12-hour audio bound and total-sector bound both apply. Maximum syntax-level file size is 102,400,000,000 bytes, about 95.37 GiB; this is a format limit, not the installed card capacity or validated playback performance.

## 10. IMG2 图像描述符 / IMG2 image descriptor

一帧或一张图对应一个 512 字节描述符。所有视频描述符先写，随后为图片描述符。

Each frame or slideshow picture has one 512-byte descriptor. All video descriptors precede slideshow descriptors.

| word | 偏移 / Offset | 名称 / Name | 规定 / Requirement |
|---:|---:|---|---|
| 0 | 0 | magic | `0x32474D49`，字节 `49 4D 47 32` = `IMG2` |
| 1 | 4 | identity | 视频：0 起算帧号 i；图片：`0x80000000 | image_index` / Video i; slideshow high-bit-tagged index |
| 2 | 8 | source_width | 1～2048 |
| 3 | 12 | source_height | 1～2048 |
| 4 | 16 | pixel_lba | 本图像像素起点 / File-relative start of this image |
| 5 | 20 | row_sectors | `ceil(source_width / 128)` |
| 6 | 24 | pixel_sectors | `row_sectors × source_height` |
| 7 | 28 | pixel_crc32 | 整个补齐后的像素区 CRC-32 / CRC-32 of the entire padded pixel payload |
| 8～126 | 32～504 | reserved | 写零 / Write zero |
| 127 | 508 | descriptor_crc32 | 对本描述符前 508 字节的 CRC-32 / CRC-32 of this descriptor's first 508 bytes |

规范打包器令第一个 `pixel_lba = payload_lba`，每个后续像素区紧接上一个，最后一个像素区恰好结束于 `audio_lba`。读取器还有越界检查；CRC 校验器会核对规范连续布局、X 字节和行尾补零。源帧尺寸取自描述符，文件头的 1280×800 是输出尺寸。

The canonical first `pixel_lba` equals `payload_lba`. Each later region immediately follows the previous one, and the last image ends at `audio_lba`. The verifier checks contiguous bounds, X bytes, row padding and CRC. Source dimensions come from each descriptor; the 1280×800 header fields are output dimensions.

## 11. 视频帧的像素编码 / Pixel payload encoding

像素按**自顶向下、每行自左向右**写入。每像素 4 字节 `B G R 00`；这也常叫 XRGB8888 的小端内存布局，word 数值为 `0x00RRGGBB`。第四字节恒为零，表示 X 字节而非透明度。红、绿、蓝、白分别如下：

Pixels are **top-down, left-to-right**, four bytes each: `B G R 00`. This is the little-endian memory representation of an XRGB8888 word `0x00RRGGBB`. The fourth byte is zero, not alpha:

| 颜色 / Color | 连续字节 / Bytes | u32le word |
|---|---|---|
| Red | `00 00 FF 00` | `0x00FF0000` |
| Green | `00 FF 00 00` | `0x0000FF00` |
| Blue | `FF 00 00 00` | `0x000000FF` |
| White | `FF FF FF 00` | `0x00FFFFFF` |

每行占 `row_sectors × 512` 字节，等价于把宽度向上补到 128 像素倍数。有效像素之后至行末必须为零；每行独立补齐。帧像素区里没有扇区尾 CRC；其整体 CRC 放在 IMG2 的 word 7 中，覆盖所有有效像素、X 字节和行尾补零。

Each row occupies `row_sectors × 512` bytes, padding the width to a multiple of 128 pixels. Padding is applied separately to every row and must be zero. Pixel sectors have no CRC trailer: the whole payload, including X bytes and row padding, is covered by IMG2 word 7.

定位某像素 / Addressing a pixel:

```text
pixel_byte_offset(x,y) = pixel_lba*512 + y*row_sectors*512 + x*4
0 <= x < source_width; 0 <= y < source_height
```

默认 384×208 恰好每行 3 扇区，每帧 624 扇区，即 319,488 字节。帧与帧相互独立，**没有 GOP、I/P/B 帧、运动矢量、JPEG 头或变长压缩码流**。因此定位到任意帧不需要解码前面的帧。

Default 384×208 uses three sectors per row and 624 sectors, or 319,488 bytes, per frame. Frames are independent: **there is no GOP, I/P/B coding, motion vector, JPEG header or variable-length compressed stream**. Seeking does not require decoding earlier frames.

## 12. AUD3 音轨描述符与 PCM 扇区 / AUD3 descriptors and PCM sectors

音轨 0 始终为电影音轨；旧 PAK 中的音轨 1…K−1 为额外歌曲。独立 TFV 仅有音轨 0。

Track zero is the movie soundtrack. Additional tracks in a legacy PAK are songs. Standalone TFV has only track zero.

| word | 偏移 / Offset | 名称 / Name | 规定 / Requirement |
|---:|---:|---|---|
| 0 | 0 | magic | `0x33445541`，字节 `41 55 44 33` = `AUD3` |
| 1 | 4 | track_index | 从 0 起算 / Zero-based |
| 2 | 8 | pcm_lba | 本音轨 PCM 起始扇区 / PCM start sector |
| 3 | 12 | samples | 1～2,073,600,000 个双声道样本帧 / Stereo sample-frame count |
| 4 | 16 | pcm_sectors | `ceil(samples / 127)`，最多 16,327,560 / At most 16,327,560 |
| 5 | 20 | background_index | 历史图片背景索引；独立 TFV 写 0 / Legacy picture index; zero in TFV |
| 6 | 24 | lyric_lba | 首 CUE3 地址，无歌词为 0 / First CUE3 sector, zero without cues |
| 7 | 28 | cue_count | 0～4096；本 TFV 转换器写 0 / This TFV converter writes zero |
| 8～126 | 32～504 | reserved | 写零 / Write zero |
| 127 | 508 | descriptor_crc32 | 本记录前 508 字节 CRC-32 / CRC-32 of first 508 bytes |

音轨 0 的 `pcm_lba`、`samples` 必须与文件头 `audio_lba`、`audio_samples` 一致。其后音轨按顺序连续存储。background 字段为兼容结构保留；当前音乐界面使用纯色背景，不会据此显示其他图片。

Track zero must agree with header `audio_lba` and `audio_samples`. Subsequent PCM regions follow contiguously. The background field preserves the legacy structure; the current music UI uses a plain background rather than displaying other pictures.

**每个 PCM 扇区恰好装 127 个双声道样本帧和一个 CRC：**

**Each PCM sector stores exactly 127 stereo sample-frame slots and a CRC:**

```text
bytes   0..3    L0(int16le), R0(int16le)
bytes   4..7    L1, R1
...
bytes 504..507  L126, R126
bytes 508..511  CRC32(bytes[0:508]), uint32le
```

最后一个扇区只使用 `min(127, remaining_samples)` 个槽，其余槽全零。CRC 覆盖完整的前 508 字节，包括末尾补零；这些补零不是额外播放样本。音量和静音由播放器实时执行，文件存原 PCM，不预先乘上用户音量。

The final sector uses only `min(127, remaining_samples)` slots; remaining slots are zero. CRC covers all 508 payload bytes including padding, which is not played as extra audio. Volume/mute are runtime operations and do not alter stored PCM.

样本帧 s 的文件位置 / Location of stereo sample frame s:

```text
sector = pcm_lba + s // 127
within = (s % 127) * 4
byte_offset = sector * 512 + within
time_seconds = s / 48000
```

## 13. CUE3 歌词记录 / CUE3 lyric records

独立 WAV/LRC 路径不需要用户创建 CUE3：存储固件把文本即时适配成同一播放接口。CUE3 是旧 TFM3 素材包内的二进制定时歌词记录，为完整解释容器仍在此规定。当前转换器生成的单视频 TFV 不带 CUE3。

Standalone WAV/LRC does not require user-created CUE3: storage firmware adapts text to the playback interface. CUE3 is specified here to fully describe the timed-lyric structure inside legacy TFM3 packages. The current single-video converter writes no CUE3 records.

| 字节偏移 / Byte offset | 类型 / Type | 名称与规定 / Name and requirement |
|---:|---|---|
| 0 | u32le | magic = `0x33455543`，bytes `43 55 45 33` = `CUE3` |
| 4 | u32le | 开始样本帧号 / Start stereo sample-frame index |
| 8 | u32le | 本音轨 0 起算 cue 编号 / Zero-based cue index in this track |
| 12 | u32le | 有效文字字节数 0～78 / Text length 0–78 |
| 16～95 | 80 bytes | ASCII 文本，剩余部分用空格 0x20 填充 / Text padded with spaces |
| 96～507 | 412 bytes | 保留，写零 / Reserved, zero |
| 508 | u32le | 本记录前 508 字节 CRC-32 / CRC-32 of bytes 0–507 |

80 字节缓冲区中最多 78 字节为有效文字；包括末尾两个字节在内的全部剩余字节必须为空格。句时间严格递增，且小于该音轨的 samples。cue k 从它的时间开始生效，下一句到来时替换；空文字可清除歌词。这里用的是 48 kHz 样本时钟，不是毫秒整数；LRC 毫秒可精确映射为 `sample = milliseconds × 48`。

At most 78 of the 80 text-buffer bytes are active; all remaining bytes, including the final two, must be spaces. Cue times are strictly increasing and below the track's sample count. A cue takes effect at its start time until replaced; empty text clears it. Times use the 48 kHz sample clock, with exact LRC mapping `sample = milliseconds × 48`.

## 14. CRC-32 精确定义 / Exact CRC-32 definition

使用 **CRC-32/ISO-HDLC**，也称 IEEE CRC-32，与 Python `zlib.crc32(data)` 的结果一致：

Use **CRC-32/ISO-HDLC**, also called IEEE CRC-32, matching Python `zlib.crc32(data)`:

| 参数 / Parameter | 值 / Value |
|---|---|
| Width | 32 |
| Polynomial | 正向 / Normal `0x04C11DB7`；反射实现 / Reflected `0xEDB88320` |
| Init | `0xFFFFFFFF` |
| RefIn / RefOut | true / true |
| XorOut | `0xFFFFFFFF` |
| Check(`123456789`) | `0xCBF43926` |
| CRC 字段存储 / Stored CRC byte order | little-endian |

独立实现 / Independent implementation:

```python
def crc32_ieee(data):
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte
        for bit in range(8):
            crc = (crc >> 1) ^ (0xEDB88320 if crc & 1 else 0)
    return crc ^ 0xFFFFFFFF

assert crc32_ieee(b'123456789') == 0xCBF43926
assert crc32_ieee(bytes(508)) == 0x0FBB6D54
```

| 区域 / Region | CRC 覆盖 / Coverage | 保存位置 / Stored at |
|---|---|---|
| Header / IMG2 / AUD3 / CUE3 | 该记录 bytes 0..507 / First 508 bytes of record | 该记录 bytes 508..511 |
| Frame/image pixels | 完整补齐后 `pixel_sectors × 512` 字节 / Entire padded pixel payload | 对应 IMG2 word 7 |
| PCM sector | 前 508 字节 / First 508 bytes | 同扇区最后 4 字节 |

CRC 计算不包含自身 CRC 字段。帧 CRC 可分块计算，但必须保持跨块累计状态；各扇区 CRC 不能简单异或。容器 CRC 与 SD 总线原生 CRC7/CRC16 属于不同层级，分别处理。CRC 用于检测偶发损坏，不提供认证或数字签名；SHA-256 用于交付文件身份核对，也不属于容器字段。

Exclude the CRC field itself. Frame CRC may be computed incrementally while maintaining state across chunks; individual sector CRCs cannot be XORed. Container CRC and native SD CRC7/CRC16 operate at different layers. CRC detects accidental corruption but does not authenticate content; delivery SHA-256 is an external identity check rather than a container field.

## 15. 时间、播放和定位规则 / Timing, playback and seeking

视频为恒定 `frame_ms` 帧间隔，无逐帧 PTS、DTS 或可变帧率表。规范转换文件的第 i 帧对应 `i × frame_ms` 毫秒；音轨样本 s 对应 `s/48000` 秒。源帧经过 FPGA 缩放到 1280×800 帧缓冲；显示屏会在两次媒体帧更新间重复显示同一帧，显示刷新率与 8 fps 素材帧率不同。

Video has a constant `frame_ms` interval, with no per-frame PTS/DTS or variable-frame-rate table. Frame i belongs to `i × frame_ms` milliseconds; audio sample frame s belongs to `s/48000` seconds. The FPGA scales source frames into a 1280×800 framebuffer. The display repeats a frame between media updates, so display refresh and media frame rate differ.

按键定位使用整秒目标。查找音频位置用 `seconds × 48000`，再按每扇区 127 个样本帧计算地址；视频帧由同一时间线取对应帧索引。CRC 校验后的数据才提交。暂停、UI 隐藏、歌词/波形开关和音量都属于播放器状态，不编码成媒体文件字段。

Button seeking uses whole-second targets. Audio seeking maps `seconds × 48000` through 127 sample-frame slots per sector; video uses the corresponding frame index on that timeline. Data is committed after CRC validation. Pause, UI visibility, lyric/waveform visibility and volume are player state rather than media-file fields.

旧 TFM3 素材包的电影音轨长度可能与最后视频帧边界略有差别；新转换器的精确等时长策略只适用于新输出。本转换器始终使 `audio_samples = N × frame_ms × 48`。格式允许的样本帧数上限与界面按秒显示的精度分别计算。

Legacy package audio may differ slightly from the terminal video-frame boundary. The new converter's exact-duration policy applies to new output, which satisfies `audio_samples = N × frame_ms × 48`. Stored sample precision differs from whole-second UI presentation.

## 16. 容量与吞吐量公式 / Capacity and throughput formulas

独立、无歌词、统一源帧尺寸的 TFV：

For a standalone, cue-free TFV with uniform source dimensions:

```text
R = ceil(width / 128)
P = R * height                         sectors per frame
A = N * frame_ms * 48                  stereo sample frames, canonical writer
S = ceil(A / 127)                      PCM sectors
payload_lba = N + 2
audio_lba = N + 2 + N * P
total_sectors = N + 2 + N * P + S
file_bytes = total_sectors * 512
```

近似持续读取带宽 / Approximate sustained payload bandwidth:

```text
video_bytes_per_second = R * height * 512 * (1000 / frame_ms)
audio_bytes_per_second = (48000 / 127) * 512
descriptor_bytes_per_second = 512 * (1000 / frame_ms)
```

默认参数总计约 2.754 MB/s，不含卡命令、文件系统映射、CPU 和 SDRAM 仲裁的开销。HDMI 输出 1280×800，容器中的源帧可以更小，以适应读取带宽。这里 MB 为 1,000,000 字节，GiB 为 1,073,741,824 字节。

Default media bandwidth is about 2.754 MB/s before card commands, filesystem mapping, CPU and SDRAM arbitration overhead. The HDMI output is fixed at 1280×800, while stored source frames can be smaller to fit the available read budget. MB is decimal; GiB is binary.

## 17. 可复现的最小二进制样例 / Reproducible minimal binary example

附带生成器只使用 Python 标准库，不调用 FFmpeg 或本工程打包库，按本文字段生成文件供独立实现核对。该样例用于格式测试，正式演示仍使用正式素材。

The bundled generator uses only the Python standard library, without FFmpeg or the project packer, to create the fields specified here for independent checks. It is a format-conformance fixture; demonstration media remains separate.

```powershell
py -3.13 tools/make_format_example.py 'C:\TF_FORMAT_TEST\MINIMAL.tfv'
py -3.13 tools/media_convert.py inspect 'C:\TF_FORMAT_TEST\MINIMAL.tfv'
```

样例内容 / Example contents:

| 项目 / Item | 值 / Value |
|---|---|
| Video | 1 帧，2×1 像素，先红后蓝 / One 2×1 frame, red then blue |
| Frame period | 80 ms |
| Source row | `00 00 FF 00 FF 00 00 00` + 504 zero bytes |
| PCM | 3840 个双声道零样本帧 / 3840 silent stereo sample frames |
| Header / IMG2 / AUD3 | LBAs 0 / 1 / 2 |
| Pixel payload / PCM | LBAs 3 / 4 |
| PCM sectors / total sectors | 31 / 35 |
| File size | **17,920 bytes** |
| Header CRC-32 | **`0xCE1FF54E`** |
| Pixel CRC-32 | **`0x52CC087C`** |
| File SHA-256 | **`ead56aac2fdf082a6dbf3186a13db32163d16371cff6fc57195bf67a755659d9`** |

文件前 32 字节应为 / Expected first 32 bytes:

```text
54 46 4D 31 03 00 00 00 00 05 00 00 20 03 00 00
01 00 00 00 00 A0 0F 00 01 00 00 00 50 00 00 00
```

## 18. 独立解析器实现步骤 / Implementing an independent parser

1. 检查文件长度是 512 的整数倍且至少包含头。读取头并核对 CRC、魔数、版本、固定输出参数、范围和总长度。
2. 用足够宽的整数核对所有地址加法、乘法和大小关系，先检查范围再 seek/分配内存。扩展名和未经校验的尺寸不作为依据。
3. 读取 IMG2、AUD3，逐个核对记录 CRC、索引、源尺寸、行跨度、样本数、连续地址及区域不重叠。
4. 读取每个补齐后的像素区，核对 X=0、行尾全零与整体 CRC；像素区与带 CRC 尾的 PCM 扇区按不同布局处理。
5. 遍历 CUE3，核对文本、空格补齐、cue 编号、时间递增及音轨范围。
6. 遍历所有 PCM 扇区，核对 CRC 和最后扇区未用槽为零，只输出声明的样本帧数。
7. 核对所有定义区域恰好到文件尾。先完成结构和 CRC 检查，再把数据视作有效媒体。

1. Require sector-aligned length and a header; verify its CRC, magic, version, fixed fields, bounds and exact file size.
2. Use wide checked arithmetic for offsets/products. Validate ranges before seeking or allocating. Do not trust extensions or unchecked dimensions.
3. Verify each IMG2/AUD3 record CRC, identity, dimensions/stride, sample count, contiguous extents and non-overlap.
4. Verify complete padded pixel payloads, zero X/row padding and whole-frame CRC. Pixel sectors are not PCM sectors with CRC trailers.
5. Validate CUE3 text, space padding, indexes and strictly increasing in-track times.
6. Verify each PCM sector CRC and zero unused final slots; emit only the declared sample frames.
7. Require all defined regions to end at EOF. Treat media as valid only after structural and integrity checks.

Python 参考读取核心 / Core Python reading pattern:

```python
import struct
import zlib

def checked_record(file, lba):
    file.seek(lba * 512)
    raw = file.read(512)
    if len(raw) != 512:
        raise ValueError('Truncated record')
    if zlib.crc32(raw[:508]) != struct.unpack_from('<I', raw, 508)[0]:
        raise ValueError('Record CRC mismatch')
    return struct.unpack('<128I', raw)
```

完整参考实现为 [tfm_format.py](../tools/tfm_format.py)、[tfm3.py](../tools/tfm3.py)。检查文件头不能替代完整文件检查；`media_convert.py inspect` 会回读全部图像/音频数据。图像和音频数据很大时，此操作会花时间，超时或中途退出均不计为通过。

Full reference implementations are linked above. Reading only a header does not verify the complete file: `media_convert.py inspect` reads all pixel/PCM data. Large files take time; a timeout or interrupted run is unsuccessful.

## 19. TF 卡准备、命名和文件顺序 / Card preparation, naming and order

卡文件系统可为 FAT32 或 exFAT，512 字节逻辑扇区，支持 MBR 或裸卷、子目录和碎片文件。不支持 GPT、NTFS、FAT16。**FAT32 单文件上限是 4 GiB−1；较长 TFV 应放在 exFAT 卡中。** TFV 必须完整保存；截断文件或修改头部长度都无法绕过 FAT32 的单文件上限。

The card may use FAT32 or exFAT with 512-byte logical sectors, MBR or an unpartitioned volume, subdirectories and fragmented files. GPT, NTFS and FAT16 are unsupported. **FAT32 limits one file to 4 GiB−1; use exFAT for longer TFV files.** Keep each TFV complete; truncating it or changing the header length cannot bypass the FAT32 file-size limit.

每类最多 128 个 TFV、128 个 BMP、128 个 WAV，最多 127 个 LRC、64 个枚举目录。建议短 ASCII 文件名并使用数字前缀。界面最多显示文件名的前 32 个 ASCII 字符；其他字符会显示 `?`。列表按视频 → 图片 → 音频分组，类内保留卡上枚举次序。数字前缀便于辨认，但不能单独保证目录物理枚举顺序；需要指定演示顺序时应使用空的目标目录并按所需顺序逐个复制，再检查板上列表。资源管理器的名称排序不会改变播放器的播放列表顺序。

Limits are 128 files per playable type, 127 LRC files and 64 enumerated directories. Use short ASCII filenames and numeric prefixes. The display shows the first 32 ASCII characters; unsupported characters become `?`. Entries are grouped video → picture → audio, preserving on-card enumeration order within each group. Prefixes aid identification but alone do not guarantee directory enumeration order. For a chosen demo order, copy files individually into an empty destination in that order and inspect the resulting list. Explorer name sorting does not determine the player's list order.

```text
00_MOVIE.tfv
01_PHOTO.bmp
02_PHOTO.bmp
01_SONG.wav
01_SONG.lrc
02_SONG.wav
02_SONG.lrc
```

转换完只复制媒体，不复制转换临时目录、报告或原始 MP4/MP3。WAV/LRC 成对保持同名同目录，避免重复或冲突歌词。读取器在启动枚举，有文件改动或换卡后应安全弹出电脑卡卷、给板卡断电后再装卡，不在读取时热插拔。已有受支持的独立媒体时它们优先于兼容 PAK；播放器不自动合并新独立媒体与旧包的全部条目。

Copy only converted media, keeping WAV/LRC pairs together; avoid duplicate/conflicting lyrics. Do not copy temporary files or assume original MP4/MP3 is playable. Enumeration happens at startup. Safely eject the computer volume and power the board down before card replacement. Independent supported media take priority over the legacy package; the player keeps them as the active entries instead of merging every old-package entry with them.

## 20. 校验、错误和复现 / Verification, errors and reproduction

```powershell
py -3.13 tools/media_convert.py inspect 'C:\TF_OUT\01_PHOTO.bmp'
py -3.13 tools/media_convert.py inspect 'C:\TF_OUT\01_SONG.wav'
py -3.13 tools/media_convert.py inspect 'C:\TF_OUT\01_SONG.lrc' --wav 'C:\TF_OUT\01_SONG.wav'
py -3.13 tools/media_convert.py inspect 'C:\TF_OUT\00_MOVIE.tfv'
py -3.13 tools/run_host_tests.py
```

新增 [test_media_convert.py](../tests/test_media_convert.py) 覆盖实际图像、FFmpeg 音频/视频、歌词及损坏输入。所有代码不含代码注释，格式定义集中在本文。现有 RTL、C 固件、已验收位流和正式素材不会因安装或运行转换器而改变。

The added test suite covers actual image data, FFmpeg audio/video, lyric handling and corrupt inputs. Source code contains no code comments; this document carries the format explanation. Installing/running the converter does not change the accepted RTL, storage firmware, bitstream or existing demonstration media.

| 现象 / Error | 处理 / Action |
|---|---|
| FFmpeg not found | 安装 requirements-media，或指定 `--ffmpeg` / Install media requirements or specify executable |
| Source file not found | 核对路径；有空格用引号 / Check path and quote spaces |
| 输出已存在 / Output exists | 使用新文件名；工具不会覆盖 / Choose a new destination |
| Text must be printable ASCII | 提供英文翻译/转写；仅修改扩展名或编码无法解决字符集限制 / Supply translated/transliterated text; changing only the extension or encoding cannot solve the character-set limit |
| Text does not fit two rows | 人工缩短句子或拆成更多定时句 / Shorten text or create more timed cues |
| Time outside track | 检查 offset、歌曲版本、长度与时间 / Check offset, track edition and times |
| Input has no audio stream | 视频可显式加 `--silent` / Use explicit silent-video mode |
| Zero/incomplete frames | 检查源文件是否损坏或时长不足以产生转换帧 / Check damaged or too-short input |
| Unsupported WAV | 重新转成 48 kHz/16-bit/stereo PCM tag 1 / Reconvert to the specified PCM profile |
| CRC / bounds mismatch | 保留损坏文件用于定位，从原素材重新转换；不跳过 CRC / Reconvert from source, never bypass checks |
| Insufficient disk space | 依据第 7、16 节预留临时和输出空间 / Allow temporary plus final space |
| 结构合格但播放不及时 / Valid structure, missed deadlines | 回到已验证默认尺寸/帧间隔，检查读卡性能 / Use validated profile and examine read performance |

板上 `FILE ERROR` 的存储代码包括：`52` 容器头/独立 TFV 不合规，`54` BMP，`55` RIFF 结构，`56` WAV 编码/长度，`57` 歌词配对/文件大小，`58` 歌词文本/时间。播放引擎还有独立 CRC/描述符错误，详见 [FPGA 用户操作手册](FPGA_用户操作手册.md)。记录文件名、错误代码和操作过程，有助于区分文件不合规、复制损坏与硬件读取异常。

Board storage error codes include `52` for container/single-TFV header/profile errors, `54` BMP, `55` RIFF structure, `56` WAV encoding/length, `57` lyric pairing/size and `58` lyric text/time. The playback engine also has CRC/descriptor errors; see the operation manual. Record filename, code and actions to distinguish invalid media, copy damage and hardware read faults.

## 21. 版本兼容和后续扩展 / Version compatibility and future changes

魔数 `TFM1` 的版本 1、2 是历史格式；当前独立文件路径要求版本 3。版本升级需要同步更新描述符、音轨索引和数据布局，不能只把 word 1 改为 3。`.PAK` 是本工程的 TFM3 包格式，兼容范围限于本工程生成的 TFM3 包。

Versions 1 and 2 using the same `TFM1` magic are historical. The current independent-file path requires version 3. A version upgrade must update the descriptors, track index and data layout together; changing only the version word does not update the old layout. `.PAK` denotes this project's TFM3 package format, and compatibility covers packages produced by this project.

如未来引入压缩、可变帧率、更换像素编码、其他采样率或新的字库编码，必须更新格式版本/协议和播放器实现，并补足转换及校验测试。不得占用保留字段而继续声称与当前版本兼容。本文中的上限、固定值和默认参数对应本次交付，不代表所有 EG4S20 项目均采用相同协议。

Compression, variable frame rate, a different pixel representation, other sample rates or a new text encoding require an explicitly updated format/protocol and player implementation, with conversion/validation tests. Do not repurpose reserved fields while claiming compatibility. These bounds and defaults describe this delivery, not a protocol shared by every EG4S20 design.

## 22. 解封装、复用与实现清单 / Extraction, reuse and implementation checklist

TFV 与 PAK 使用本工程定义的容器格式。转换应按格式读取，而不是改后缀、调用通用解压软件或直接拼接字节。要导出帧 i，先读取 `LBA=1+i` 的 IMG2，按第 11 节逐行去掉扇区补零，再从每个像素取 B/G/R、丢弃恒零的 X；保存为 BMP 时应使用 BMP 自己的行对齐和行方向，不能直接把容器头改为 `BM`。可按以下核心提取 RGB 字节：

TFV and PAK use the container formats defined by this project. Conversion must parse those formats; renaming, generic archive utilities and blind byte concatenation do not convert them. To extract frame i, read IMG2 at `LBA=1+i`, remove per-row sector padding, and keep B/G/R while discarding zero X. A BMP writer must apply BMP row alignment and orientation independently. The following core reconstructs top-down RGB bytes:

```python
def frame_rgb(file, descriptor):
    width, height = descriptor[2:4]
    row_bytes = descriptor[5] * 512
    result = bytearray(width * height * 3)
    file.seek(descriptor[4] * 512)
    for y in range(height):
        row = file.read(row_bytes)
        if len(row) != row_bytes:
            raise ValueError('Truncated pixel row')
        for x in range(width):
            b, g, r, unused = row[x*4:x*4+4]
            start = (y*width + x)*3
            result[start:start+3] = bytes((r, g, b))
    return bytes(result)
```

上述片段在第 18 节的结构与 CRC 检查之后使用，本身不代替校验器。导出音轨则按 AUD3 的 `samples` 循环：每次读一个 512 字节扇区，核对 CRC，仅向普通 WAV 的 data 写入前 `min(127, remaining)×4` 字节，不写 CRC 和末尾未用样本槽。WAV 的文件头由 WAV 写入库生成。CUE3 的样本时间除以 48 可精确转为毫秒的前提是样本号为 48 的倍数；否则导出毫秒 LRC 必须明确规定取整策略，不能声称无损时间转换。

Use this fragment only after the structural and CRC checks in section 18. For audio extraction, read sectors according to AUD3, validate each CRC, and write only the first `min(127, remaining)×4` bytes into a normal WAV data chunk. Exclude CRC trailers and unused final sample slots; let a WAV library generate its header. CUE3 sample times convert losslessly to millisecond LRC only when divisible by 48. Otherwise an exporter must declare a rounding policy rather than claiming exact timing.

源码中还保留了 [unpack_native_media.py](../tools/unpack_native_media.py)，用于从本工程旧 TFM3 组合包导出独立 TFV、BMP、WAV 和配对 LRC。它保留原始图像与 PCM，不重新解码压缩媒体；目标目录必须不存在。其电影默认文件名为 `00_INTOUCHABLE.TFV`，名称只是历史命名，可在导出后改为其他 ASCII 名称。该脚本不是任意压缩归档解包器；通用新素材优先使用本文的 `media_convert.py`。

The retained extractor exports a legacy project TFM3 package as standalone TFV, BMP, WAV and matching LRC. It preserves pixel/PCM values and requires a new destination directory. Its historical movie filename is `00_INTOUCHABLE.TFV`; this name may be changed to another ASCII name after extraction. It does not unpack arbitrary compressed archives. Use `media_convert.py` for new common-format inputs.

```powershell
py -3.13 tools/unpack_native_media.py 'C:\Assets\OLD_DEMO.pak' 'C:\TF_EXTRACTED_NEW' --report 'C:\TF_REPORTS\extraction.json'
```

独立实现完成后应至少核对以下三类文件：①本文 17,920 字节最小样例，连同 SHA-256、头 CRC 和像素 CRC；②多帧、非 128 整数倍宽度且音频末扇区不满 127 个样本的文件；③人为损坏头、描述符、像素、PCM 或地址范围的文件，必须拒绝。完整显示一张图片不足以覆盖 CRC、尾部、定位和歌词校验。

An independent implementation should check at least: (1) the 17,920-byte fixture with its SHA-256 and CRCs; (2) multiple frames, a width not divisible by 128, and a partial final PCM sector; (3) files with deliberately damaged headers, descriptors, pixels, PCM or extents, which must be rejected. Displaying one complete picture does not cover CRC, tail handling, seeking or lyrics validation.
