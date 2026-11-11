# OVH API Monitoring & Metrics Analysis

## Available API Endpoints for Monitoring

### VPS (`/vps/{serviceName}/`)

| Endpoint | Method | What It Returns |
|---|---|---|
| `/monitoring` | GET | Monitoring configuration (state, period, IPv4/IPv6) |
| `/statistics` | GET | Real-time stats (CPU, RAM, disk I/O, network) |
| `/disks` | GET | List of virtual disks |
| `/disks/{id}/monitoring` | GET | Per-disk monitoring data (IOPS, throughput, usage %) |
| `/disks/{id}/use` | GET | Disk usage (used/total/percentage) |
| `/ips` | GET | IP addresses with details |
| `/ips/{ipAddress}` | GET | IP details (version, type, reverse) |
| `/serviceInfos` | GET | Service info (expiration, renewal, status) |
| `/tasks` | GET | Task list (reboots, reinstalls, snapshots in progress) |
| `/tasks/{id}` | GET | Task detail (status, progress, comment) |

### Dedicated Server (`/dedicated/server/{serviceName}/`)

| Endpoint | Method | What It Returns |
|---|---|---|
| `/specifications/hardware` | GET | CPU model, cores, threads, RAM, disks, RAID |
| `/specifications/network` | GET | NICs, bandwidth, vRack, routing |
| `/specifications/ip` | GET | IP blocks, routing, failover IPs |
| `/monitoring` (via specs) | GET | Monitoring config (alerting, SMTP) |
| `/mrtg` | GET | MRTG traffic graph data (network bandwidth over time) |
| `/networkInterfaceController` | GET | NIC list (MAC, type, link speed) |
| `/networkInterfaceController/{mac}/mrtg` | GET | Per-NIC MRTG traffic data |
| `/burst` | GET | Bandwidth burst status (current/total/used) |
| `/intervention` | GET | Hardware intervention history |
| `/intervention/{id}` | GET | Intervention details (date, type, status) |
| `/ongoing` | GET | Current ongoing interventions |
| `/plannedIntervention` | GET | Planned maintenance windows |
| `/task` | GET | Server task list (reboots, installs, etc.) |
| `/task/{taskId}` | GET | Task details |
| `/boot` | GET | Boot mode (harddisk, rescue, ipmi, network) |
| `/boot/{bootId}` | GET | Boot config details (kernel, initrd, cmdline) |
| `/features/ipmi` | GET | IPMI/KVM access availability |
| `/features/ipmi/access` | GET | IPMI access URL/credentials |
| `/features/kvm` | GET | Physical KVM access availability |
| `/reboot` | POST | Reboot the server |
| `/networking` | GET | Network configuration (vRack, OLA, etc.) |
| `/vrack` | GET | vRack interfaces |

### Cloud Project (`/cloud/project/{projectId}/`)

| Endpoint | Method | What It Returns |
|---|---|---|
| `/instance/{instanceId}` | GET | Instance details (status, flavor, image, IPs) |
| `/flavor/{flavorId}` | GET | Flavor specs (vCPUs, RAM, disk) |
| `/usage/current` | GET | Current resource usage (compute hours, storage, bandwidth) |
| `/usage/forecast` | GET | Projected usage/cost for the month |
| `/usage/history` | GET | Historical usage data |
| `/quota` | GET | Quota limits (instances, CPUs, RAM, volumes) |
| `/alerting` | GET | Alert configurations |
| `/alerting/{id}/alert` | GET | Alert history/triggered alerts |
| `/database/.../metric` | GET | Managed database metrics (PostgreSQL, MySQL, etc.) |

### Standalone Monitoring Product (`/metrics/`)

| Endpoint | Method | What It Returns |
|---|---|---|
| `/{serviceName}` | GET | Metrics service config |
| `/{serviceName}/consumption` | GET | Data consumption (ingested data, storage) |
| `/{serviceName}/quota` | GET | Quota limits |

---

## What We Already Call

- `GET /vps/{serviceName}` → VPS detail (name, state, datacenter, os, model)
- `GET /vps/{serviceName}/ips` → IP list
- `GET /vps/{serviceName}/specifications` → Hardware specs (vCPU, RAM, disk)
- `GET /vps/{serviceName}/serviceInfos` → Service info
- `GET /dedicated/server/{serviceName}` → Server detail
- `GET /dedicated/server/{serviceName}/ips` → IP list
- `GET /dedicated/server/{serviceName}/specifications/hardware` → Hardware specs
- `GET /dedicated/server/{serviceName}/specifications/monitoring` → Monitoring config
- `GET /cloud/project/{projectId}/instance` → Instance list
- `GET /cloud/project/{projectId}/instance/{id}` → Instance detail
- `GET /cloud/project/{projectId}/flavor/{id}` → Flavor details

## What We Should Add

### High Value (real-time metrics & status)

1. **VPS Statistics** — `GET /vps/{serviceName}/statistics`
   - Real-time CPU, RAM, disk I/O, network traffic
   - Show as sparkline/time-series charts on machine detail

2. **VPS Disk Usage** — `GET /vps/{serviceName}/disks/{id}/use`
   - Disk space used/available/percentage
   - Show as usage bars

3. **Dedicated Server MRTG** — `GET /dedicated/server/{serviceName}/mrtg`
   - Network bandwidth graphs over time
   - Show as traffic charts

4. **Dedicated Server NIC MRTG** — `GET /dedicated/server/{serviceName}/networkInterfaceController/{mac}/mrtg`
   - Per-interface traffic data
   - Show per-NIC bandwidth

5. **Dedicated Server Bandwidth Burst** — `GET /dedicated/server/{serviceName}/burst`
   - Current burst usage vs. limit
   - Show as utilization bar

6. **Cloud Usage Current** — `GET /cloud/project/{projectId}/usage/current`
   - Current compute/storage/bandwidth consumption
   - Show as usage counters on cloud instances

### Medium Value (operational status)

7. **Server Tasks** — `GET /vps/{name}/tasks` and `GET /dedicated/server/{name}/task`
   - Active tasks (reboots, reinstalls, backups)
   - Show as status alerts on machine detail

8. **Interventions** — `GET /dedicated/server/{name}/intervention` + `/ongoing` + `/plannedIntervention`
   - Hardware interventions, ongoing maintenance, planned maintenance
   - Show as alerts/notices

9. **Boot Mode** — `GET /dedicated/server/{name}/boot` → `GET .../boot/{id}`
   - Current boot mode (harddisk, rescue, ipmi, network)
   - Show in hardware section

10. **IPMI/KVM Access** — `GET /dedicated/server/{name}/features/ipmi/access`
    - Remote console access URL
    - Show as "OPEN IPMI" button on machine detail

### Lower Value (nice-to-have)

11. **Cloud Alerting** — `GET /cloud/project/{id}/alerting`
12. **VPS Snapshots** — `GET /vps/{name}/snapshot`
13. **Server Reboot Action** — `POST /vps/{name}/reboot` / `POST /dedicated/server/{name}/reboot`
14. **Cloud Usage Forecast** — `GET /cloud/project/{id}/usage/forecast`

---

## Recommended Implementation Priority

### Phase 1: Live Monitoring Metrics (highest impact)
- Add `getVpsStatistics()`, `getVpsDiskUsage()`, `getDedicatedMrtg()`, `getDedicatedBurst()`
- Create `OvhMetricsProvider` that polls these periodically
- Display sparkline charts on machine detail screen using `fl_chart`

### Phase 2: Operational Status
- Add `getServerTasks()`, `getInterventions()`, `getOngoingInterventions()`
- Show task/intervention alerts on machine detail
- Add "REBOOT" action button

### Phase 3: Advanced
- IPMI/KVM access button
- Cloud project usage/billing
- Boot mode display