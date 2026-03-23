# Ansible Collection - softure.vps_foundation

Foundation roles for VPS setup - system hardening, Docker, and common services.

## Installation

```bash
ansible-galaxy collection install git+https://github.com/softure/VPS_FOUNDATION.git#vps_foundation
```

Or add to `requirements.yml`:

```yaml
collections:
  - name: softure.vps_foundation
    source: https://github.com/softure/VPS_FOUNDATION.git#vps_foundation
    type: git
```

## Roles

| Role | Description |
|------|-------------|
| `system_hardening` | System hardening (SSH, firewall, fail2ban, users) |
| `docker_engine` | Docker and Docker Compose installation |
| `postgres` | PostgreSQL container deployment (with optional PgAdmin and init scripts) |
| `mssql` | Microsoft SQL Server container deployment |
| `rabbitmq` | RabbitMQ container with management UI (with optional config) |
| `caddy` | Caddy reverse proxy (with optional Cloudflare) |
| `seq` | Seq logging server |
| `typesense` | Typesense search engine |
| `portainer` | Portainer CE for Docker management |
| `supertokens` | SuperTokens authentication server |
| `sqlpad` | SQL query tool with web UI |
| `backrest` | Backrest backup manager |

## Playbooks

### VPS Bootstrap

```yaml
- import_playbook: softure.vps_foundation.vps_bootstrap
  vars:
    vps_app_user: myproject
    vps_app_group: myproject
    vps_timezone: "Europe/Warsaw"
```

### VPS Deploy Infrastructure

```yaml
- import_playbook: softure.vps_foundation.vps_deploy_infrastructure
  vars:
    services_network: myproject-network
    services_postgres_enabled: true
    services_pgadmin_enabled: true
    postgres_db: myproject_db
    postgres_user: myproject
    postgres_password: "{{ lookup('env', 'POSTGRES_PASSWORD') }}"
    postgres_init_script_path: "{{ playbook_dir }}/files/init.sql"
    rabbitmq_config_path: "{{ playbook_dir }}/files/rabbitmq.conf"
    services_mssql_enabled: true
    mssql_sa_password: "{{ lookup('env', 'MSSQL_SA_PASSWORD') }}"
    services_seq_enabled: true
    services_typesense_enabled: true
    services_portainer_enabled: false
    services_supertokens_enabled: true
```

## Quick Start

```yaml
# playbooks/setup.yml
---
- name: "Phase 1: Bootstrap VPS"
  ansible.builtin.import_playbook: softure.vps_foundation.vps-bootstrap
  vars:
    vps_app_user: deploy
    vps_app_group: deploy
    vps_timezone: "Europe/Warsaw"
  tags: [bootstrap]

- name: "Phase 2: Deploy Infrastructure"
  ansible.builtin.import_playbook: softure.vps_foundation.vps-deploy-infrastructure
  vars:
    services_network: app-network
    services_postgres_enabled: true
    services_pgadmin_enabled: true
    services_caddy_enabled: true
    services_seq_enabled: true
  tags: [infrastructure]
```

Run from the root of your project (where `inventory/` and `playbooks/` directories are located):

```bash
# Install collection and dependencies
ansible-galaxy collection install -r requirements.yml

# Full setup (bootstrap + infrastructure)
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml

# Bootstrap only
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml --tags bootstrap

# Infrastructure only
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml --tags infrastructure

# Single service
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml --tags postgres
```

See the [example/](example/) directory for a complete working setup including inventory, group vars, playbooks, and sample config files.

## Requirements

- Ansible >= 2.14
- Ubuntu 22.04+ (jammy, noble)
- Collections: `community.docker`, `community.general`, `ansible.posix`

## Important

- Bootstrap playbook validates Ubuntu 22.04+ and waits for system readiness before proceeding
- After running `vps_bootstrap`, login using the `vps_app_user` account instead of the default `ubuntu` or `root` from your provider

## License

MIT
