# 大文件传输性能验证

日期：2026-11-07。Windows x64 / Dart 3.12.2，同进程两个 LanService，IPv4 回环，生成的二进制文件，系统文件缓存已预热。包含 offer、上传、校验和完成确认；接收自动同意。每次传输之后用独立的 `crypto.sha256` 重新读取接收文件核验，该复核耗时不计入传输耗时。

## 实测

| 场景 | 大小 | 耗时 | 接收首字节 | 传输吞吐 |
| --- | --- | --- | --- | --- |
| 修改前，第 1 次 | 256 MiB | 7.733 s | 3552 ms | 33.10 MiB/s |
| 修改前，第 2 次 | 256 MiB | 7.206 s | 3295 ms | 35.52 MiB/s |
| 修改前，第 3 次 | 256 MiB | 6.914 s | 3150 ms | 37.02 MiB/s |
| 修改后，第 1 次 | 256 MiB | 1.403 s | 41 ms | 182.35 MiB/s |
| 修改后，第 2 次 | 256 MiB | 1.576 s | 20 ms | 162.41 MiB/s |
| 修改后，第 3 次 | 256 MiB | 1.052 s | 11 ms | 243.28 MiB/s |
| 修改后，大文件检查 | 1 GiB | 4.738 s | 34 ms | 216.10 MiB/s |

256 MiB 三次平均耗时从 7.284 s 降到 1.344 s，约为原来的 18.4%。1 GiB 时测试进程峰值 RSS 为 233.64 MiB，256 MiB 三次为 231.61–235.52 MiB。RSS 包括两个服务、Dart VM 与夹具管理，不是单连接缓冲区大小。5 ms 采样的首字节是观察到接收字节增加的时间，存在采样和事件循环误差。

这组数据不代表两台真实设备、千兆网络、Wi-Fi 或机械硬盘表现。真实网络上，主要收益是首字节更早、减少完整文件读盘和降低校验 CPU 开销；网卡与磁盘仍决定最高速度。尚未增加断点续传、压缩或多连接分片。

## 实现

- 协商 `streaming-sha256-v1`，边发送/接收边校验，摘要匹配并确认后公开文件。
- Windows 使用系统 CNG SHA-256；不可用时回退标准 Dart 实现。
- 1 MiB 文件读取、接收写入背压、去掉周期性强制 flush 与接收后复读。
- 保留旧请求头协议；旧模式预校验移到独立 isolate。
- 活跃传输不再受固定 30 分钟上传截止影响，改用 45 秒无进展检查。

## 复测

```powershell
dart run tool/transfer_benchmark.dart --size-mib=256 --runs=3 --output=outputs/performance/recheck.json
dart run tool/transfer_benchmark.dart --size-mib=1024 --runs=1 --output=outputs/performance/recheck-1gib.json
```

夹具在临时目录生成并自动清理，不发送用户文件。原始记录保存在 `outputs/performance/before.json`、`streaming-dart.json`、`after.json` 与 `after-1gib.json`。
