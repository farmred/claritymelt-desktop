# Uncloud Integration Plan

## Overview

Uncloud (`uc`) is a CLI tool that connects machines into clusters and deploys container services using a Compose file. ClarityMelt integrates with Uncloud to:

1. **Discover Uncloud clusters** — Read `~/.config/uncloud/config.yaml` to find contexts and machine connections
2. **Match machines** — Correlate ClarityMelt machines with Uncloud machine IDs and SSH targets
3. **Show deployed services** — Scan compose files to show which services are deployed to which machines
4. **Update machine context** — Allow updating the Uncloud config from ClarityMelt (add connections, switch contexts)

## Uncloud Config Structure

```yaml
# ~/.config/uncloud/config.yaml
current_context: prod
contexts:
  prod:
    connections:
      - ssh: root@192.168.1.100
        machine_id: 3f60c88ac6b0f250d8aecb92a090922f
      - ssh: myserver   # SSH config alias
  dev:
    connections:
      - ssh: debian@10.0.0.5
        ssh_key_file: ~/.ssh/id_ed25519
        machine_id: 4e81d368edf48480e5a2efb0915d6e38
```

### Key Fields

| Field | Type | Description |
|-------|------|-------------|
| `current_context` | string | Active context name |
| `contexts` | map | Named contexts, each with connections |
| `connections[].ssh` | string | SSH target (user@host[:port] or host alias) |
| `connections[].ssh_go` | string | Go SSH library connection |
| `connections[].tcp` | string | Direct TCP connection |
| `connections[].unix` | string | Unix socket connection |
| `connections[].ssh_key_file` | string | SSH private key path |
| `connections[].machine_id` | string | Uncloud machine ID (hash) |

## Compose File Extensions (uncloud.yml)

```yaml
x-context: prod  # Target cluster context

services:
  web:
    image: nginx:latest
    x-machines:
      - machine-1
      - machine-2
    x-ports:
      - 80/https
      - example.com:80/https
    x-caddy: |
      example.com {
        reverse_proxy {{upstreams 80}}
      }
    x-pre_deploy:
      command: python manage.py migrate
      timeout: 10m
```

### Key Extensions

| Extension | Purpose |
|-----------|---------|
| `x-context` | Target cluster context (top-level) |
| `x-machines` | Restrict service to specific machines |
| `x-ports` | Publish HTTP/HTTPS/TCP ports |
| `x-caddy` | Caddy reverse proxy config |
| `x-pre_deploy` | Pre-deploy hook (migrations, etc.) |

## Implementation Status

### ✅ Done

- **UncloudService** (`lib/services/uncloud_service.dart`) — Parses `~/.config/uncloud/config.yaml`, reads compose files, matches machines by SSH target or machine ID
- **UncloudConfig model** — `UncloudContext`, `UncloudConnection`, `UncloudComposeFile`, `UncloudServiceDef`
- **Providers** — `uncloudConfigProvider`, `uncloudMachineMatchProvider`, `uncloudComposeProvider`
- **Machine Detail: Uncloud Section** — Shows cluster context, connection info, deployed services, setup instructions

### 🔜 Next Steps

1. **uc CLI integration** — Call `uc` commands from ClarityMelt (deploy, logs, ps)
2. **Compose file editor** — Create/edit `uncloud.yml` from ClarityMelt UI
3. **Live service status** — Show container status from `uc ps` output
4. **Machine context update** — "Add to Uncloud" button that runs `uc machine add`
5. **Service logs** — Stream logs from `uc logs <service>`
6. **One-click deploy** — Deploy a compose file to the active context

## Architecture

```
ClarityMelt Desktop
├── Machine Detail Screen
│   ├── Uncloud Section
│   │   ├── Cluster context name
│   │   ├── Connection list (SSH target, type, machine ID)
│   │   ├── Deployed services (from compose files)
│   │   └── Setup info dialog
│   └── "Add to Uncloud" button → adds SSH connection to config
├── UncloudService (lib/services/uncloud_service.dart)
│   ├── loadConfig() — reads ~/.config/uncloud/config.yaml
│   ├── parseConfig() — YAML → UncloudConfig
│   └── loadComposeFiles() — scans dirs for compose files
├── Providers (lib/providers/app_providers.dart)
│   ├── uncloudConfigProvider — async load of config
│   ├── uncloudMachineMatchProvider.family — match machine to connection
│   └── uncloudComposeProvider — async scan for compose files
└── Models
    ├── UncloudConfig (currentContext, contexts)
    ├── UncloudContext (name, connections)
    ├── UncloudConnection (ssh, sshGo, tcp, unix, sshKeyFile, machineId)
    ├── UncloudComposeFile (filePath, xContext, services)
    └── UncloudServiceDef (name, image, xMachines, xPorts, xContext)
```

## Machine Matching Logic

ClarityMelt matches machines to Uncloud connections by:

1. **Machine ID match** — If `connection.machineId` matches any part of the ClarityMelt machine ID
2. **IP match** — If `connection.sshTarget` contains any of the machine's IP addresses
3. **Hostname match** — If `connection.sshTarget` contains the machine name

When a match is found, ClarityMelt shows:
- The cluster context name
- The SSH connection details
- The machine's Uncloud ID
- Services deployed to this machine (from compose files with `x-machines` targeting it)