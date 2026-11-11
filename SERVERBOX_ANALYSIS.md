# ServerBox Feature Analysis & ClarityMelt Recommendations

Based on analysis of [ServerBox](https://github.com/lollipopkit/flutter_server_box) — a Flutter-based
server monitoring/management app that provides real-time server status, SSH terminal, Docker management,
process viewing, and more.

## ServerBox Feature Map

| ServerBox Feature | Description | ClarityMelt Status |
|---|---|---|
| **Server List + Status** | Real-time server list with CPU/RAM/Disk/Network charts | ✅ Machines screen (partial — shows provider status, not live metrics) |
| **SSH Terminal** | Full xterm.js SSH with key auth | ✅ Implemented (dartssh2 + xterm) |
| **SFTP File Browser** | Browse/edit remote files over SFTP | ❌ Not implemented |
| **Docker/Podman Containers** | List, start, stop, restart, logs, exec | ❌ Not implemented (uc inspect shows containers but no management) |
| **Process Viewer** | Sortable process list with CPU/MEM sorting | ❌ Not implemented |
| **Systemd Services** | List, start, stop, restart systemd units | ❌ Not implemented |
| **Disk/Storage** | Disk usage, mount points, S.M.A.R.T. health | ❌ Not implemented (OVH API has some disk info) |
| **Network Stats** | Real-time bandwidth per interface, connection stats | ❌ Not implemented |
| **Sensors/Temperature** | CPU temp, fan speed, voltage sensors | ❌ Not implemented |
| **GPU Monitoring** | NVIDIA/AMD GPU stats, processes | ❌ Not implemented (probably not needed for VPS) |
| **Port Forwarding** | SSH tunnel/port-forward management | ❌ Not implemented |
| **Private Key Management** | CRUD for SSH keys | ❌ Not implemented (reads from UC config only) |
| **Snippets** | Saved command snippets for quick execution | ❌ Not implemented |
| **Server Monitoring Agent** | [ServerBoxMonitor](https://github.com/lollipopkit/server_box_monitor) for push notifications | ❌ Not applicable (different architecture) |
| **iPerf Bandwidth Test** | Run iperf3 via SSH | ❌ Not implemented |
| **PVE (Proxmox)** | Proxmox VE management | ❌ Not applicable |
| **Custom Commands** | Run arbitrary scripts on servers | ❌ Not implemented (uc exec is close) |
| **Battery Status** | Laptop UPS battery monitoring | ❌ Not applicable (servers don't have batteries usually) |
| **Watch/Home Widgets** | iOS/macOS widgets, watchOS app | ❌ Not implemented |

## Recommended Features for ClarityMelt

### Priority 1 — High Value, Natural Fit

#### 1. Live Server Metrics (CPU, RAM, Disk, Network)
- **What**: Real-time or periodic server status charts fetched via SSH
- **Why**: ServerBox's core feature; ClarityMelt machines page only shows provider
  status (running/stopped), not actual resource utilization
- **How**: Execute `top -bn1`, `free -m`, `df -h`, `cat /proc/net/dev` via SSH
  and parse into time-series charts using `fl_chart`
- **Where**: Machine detail screen, new "METRICS" tab

#### 2. Docker Container Management
- **What**: List containers, view logs, start/stop/restart, exec into containers
- **Why**: We already have `uc inspect` showing containers; management is the natural
  next step. ServerBox has a full container management UI.
- **How**: Run `docker ps`, `docker logs`, `docker start/stop/restart` via SSH
  (or `uc exec` for Uncloud-managed containers)
- **Where**: Uncloud tab → Services section; Machine detail → new "CONTAINERS" section

#### 3. Process Viewer
- **What**: Sortable process list with PID, CPU%, MEM%, command
- **Why**: Essential for debugging; ServerBox makes this a first-class feature
- **How**: Run `ps aux --sort=-%mem` or `top -bn1 -o %CPU` via SSH
- **Where**: Machine detail → new "PROCESSES" section

### Priority 2 — Medium Value, Differentiation

#### 4. Systemd Service Management
- **What**: List systemd units, show status, start/stop/restart
- **Why**: ServerBox has this; essential for managing server services
- **How**: `systemctl list-units --type=service`, `systemctl status/start/stop/restart <unit>`
- **Where**: Machine detail → new "SERVICES" section

#### 5. Disk Usage Overview
- **What**: Mount points, filesystem type, used/avail/total, usage percentage bars
- **Why**: Quick health check; ServerBox shows this prominently
- **How**: Parse `df -h` or `lsblk --json` output via SSH
- **Where**: Machine detail → new "STORAGE" section

#### 6. SFTP File Browser
- **What**: Browse remote filesystem, view/edit files, upload/download
- **Why**: ServerBox has full SFTP; eliminates need for separate SFTP client
- **How**: Use `dartssh2` SFTP client (`SSHClient.sftp()`)
- **Where**: Machine detail → "FILES" tab; or new navigation tab

### Priority 3 — Nice-to-Have

#### 7. Network Interface Stats
- **What**: Per-interface RX/TX bytes, speeds, connection count
- **Why**: Useful for monitoring bandwidth; ServerBox shows net speed charts
- **How**: Parse `/proc/net/dev` and calculate delta between polls
- **Where**: Machine detail → "NETWORK" section (separate from DNS)

#### 8. SSH Key Management
- **What**: Add/edit/delete SSH keys, assign to machines, test connections
- **Why**: Currently only reads keys from UC config; ServerBox has a key manager
- **How**: Store keys in DB, write to `~/.ssh/` or pass to dartssh2 directly
- **Where**: Providers screen or new "KEYS" tab

#### 9. Saved Command Snippets
- **What**: Store frequently-used commands, run them on any machine via SSH
- **Why**: ServerBox has snippets; useful for repetitive operations
- **How**: DB table for snippets, execute via SSH terminal
- **Where**: New "SNIPPETS" tab or section in SSH terminal

#### 10. Port Forwarding (SSH Tunnels)
- **What**: Manage local/remote port forwards via SSH
- **Why**: ServerBox has this; useful for accessing private services
- **How**: `dartssh2` supports `SSHClient.forwardLocal()` and `forwardRemote()`
- **Where**: Machine detail → "TUNNELS" section

## Architecture Recommendations

Based on ServerBox patterns:

1. **SSH Command Execution Service**: Create a `SshCommandService` that can
   run arbitrary commands on any machine and return parsed output. This is the
   foundation for metrics, processes, disk, containers, and systemd features.
   Currently we only have SSH terminal (interactive) and `uc exec` (local command).

2. **Metrics Polling**: For live metrics, implement a polling provider that
   periodically runs `top`/`free`/`df`/`net` commands and caches time-series
   data. Use `fl_chart` for sparkline/line chart visualizations.

3. **Container Service**: Create a `DockerService` that wraps `docker` CLI
   commands via SSH. This parallels our `UncloudCliService` that wraps `uc`.

4. **SFTP Service**: Create an `SftpService` using `dartssh2`'s SFTP client
   for file operations. Could be used for log file browsing too.

5. **Command Snippet Storage**: Add a `CommandSnippets` table to Drift DB
   for storing reusable commands per-machine or globally.