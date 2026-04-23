# CS4296 Project Artifact — WordPress on EC2 Benchmark (Docker)

This repository contains the **software artifact** for a CS4296 (Cloud Computing) technical project:
benchmarking **WordPress deployment performance across different AWS EC2 instance types** using Docker.

## 你需要做什么（完全不登录 AWS，按顺序照做即可）

### Step 0 — 我已经替你选好的默认方案（不要改）
由于你无法登录 AWS，本项目采用**本机模拟 EC2 实例类型**的方式完成：通过 Docker Desktop 对容器施加 CPU/内存限制来模拟三类“实例”。

- **平台**：Windows + Docker Desktop
- **模拟三类实例（profiles）**
  - `general`：通用（2 vCPU / 4GB RAM 量级）
  - `compute`：计算优化（更多 CPU）
  - `memory`：内存优化（更多 RAM）
- **压测工具**：ApacheBench（`ab.exe`）
- **负载场景**：见 `experiments/matrix.yaml`（S1/S2/S3，每个场景重复 3 次）

### Step 1 — 你需要准备的东西（必做）
- **Docker Desktop**：确保能在本机运行 `docker compose`。
- **Python 3**：用于解析实验矩阵与汇总结果。
- （可选）**GitHub 公共仓库**：课程 artifact 要求仓库 public；如果你暂时来不及，至少本地先跑通。

### Step 2 — 启动 WordPress（选择一个 profile）
在 PowerShell（以管理员或普通都可以）进入仓库根目录：

```powershell
cd "c:\Users\21258\Desktop\4486 project\cs4296-wordpress-benchmark"
.\scripts\up_profile.ps1 -Profile general
```

浏览器打开：
- `http://localhost/`

完成 WordPress 初始安装（一次性）。完成后再跑一次 `seed`：

```powershell
docker compose ps
.\scripts\seed_wp.sh
```

### Step 3 — 安装 ApacheBench（ab.exe）
先尝试一键安装（需要 Chocolatey）：

```powershell
.\scripts\install_ab_windows.ps1
```

如果你没有 Chocolatey，这个脚本会提示你改为手动安装（把 `ab.exe` 加到 PATH 即可）。

### Step 4 — 跑压测（对每个 profile + 每个场景 S1/S2/S3，重复 3 次）
对某个 profile（例如 general）：

```powershell
.\scripts\up_profile.ps1 -Profile general
.\scripts\run_bench_windows.ps1 -Profile general -Scenario S1 -Repeat 3
.\scripts\run_bench_windows.ps1 -Profile general -Scenario S2 -Repeat 3
.\scripts\run_bench_windows.ps1 -Profile general -Scenario S3 -Repeat 3
```

然后对 compute / memory 各跑一遍（只改 Profile 参数即可）：

```powershell
.\scripts\up_profile.ps1 -Profile compute
.\scripts\run_bench_windows.ps1 -Profile compute -Scenario S1 -Repeat 3
.\scripts\run_bench_windows.ps1 -Profile compute -Scenario S2 -Repeat 3
.\scripts\run_bench_windows.ps1 -Profile compute -Scenario S3 -Repeat 3

.\scripts\up_profile.ps1 -Profile memory
.\scripts\run_bench_windows.ps1 -Profile memory -Scenario S1 -Repeat 3
.\scripts\run_bench_windows.ps1 -Profile memory -Scenario S2 -Repeat 3
.\scripts\run_bench_windows.ps1 -Profile memory -Scenario S3 -Repeat 3
```

每次都会把原始输出保存到 `experiments/results/<RUN_ID>/`。

### Step 5 — 同步采集容器资源（推荐，每个场景都采一次）
在你跑某个场景前，在另一个 PowerShell 窗口执行（以 300 秒为例）：

```powershell
docker compose ps
bash .\scripts\collect_docker_stats.sh --out .\experiments\results\docker_stats_general_S2.csv --seconds 300
```

> 注：`collect_docker_stats.sh` 是 bash 脚本，Windows 推荐用 Git Bash 或 WSL 跑；如果你没有，我后续会补一个纯 PowerShell 的采样脚本。

### Step 6 — 汇总分析与出图（本机执行）

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

python scripts\analyze_results.py --results_dir experiments/results --out_dir experiments/summary
```

生成的汇总文件/图在 `experiments/summary/`。

## Repo layout
- `docker-compose.yml`: WordPress + MySQL + Nginx
- `nginx/`: nginx config used in tests
- `scripts/`: install, deploy, benchmark, metrics, analysis
- `experiments/matrix.yaml`: experiment plan (instance types, scenarios)
- `experiments/results/`: raw run outputs (generated)
- `experiments/summary/`: aggregated CSV + plots (generated)

## Notes (course requirements)
- 课程要求：GitHub 仓库必须 **public**，并且要有一段时间跨度的 commit 历史（不要只最后一次提交）。
- 最终报告必须包含 **Artifact Appendix**：依赖、复现命令、期望输出、仓库链接。

