# VPS Foundation - Ansible Collection

## CRITICAL - File Editing Rules

**NEVER edit files in `~/.ansible/collections/` - these are installed Galaxy modules!**

Always edit source files in this repository:
- Roles: `vps_foundation/roles/`
- Playbooks: `vps_foundation/playbooks/`

After any change to Ansible files, reinstall the collection:
```bash
ansible-galaxy collection install . --force
```

## Project Structure

```
vps_foundation/
├── galaxy.yml                    # Collection metadata (namespace: softure)
├── meta/runtime.yml              # Ansible >=2.14 requirement
├── playbooks/
│   ├── vps_bootstrap.yml         # System setup (hardening + Docker)
│   └── vps_deploy_infrastructure.yml  # Service deployment
└── roles/
    ├── system_hardening/         # SSH, UFW, fail2ban, users
    ├── docker_engine/            # Docker + Compose installation
    ├── postgres/                 # PostgreSQL + PgAdmin
    ├── mssql/                    # Microsoft SQL Server
    ├── rabbitmq/                 # RabbitMQ messaging
    ├── caddy/                    # Reverse proxy
    ├── seq/                      # Centralized logging
    ├── portainer/                # Docker management UI
    ├── supertokens/              # Authentication
    ├── typesense/                # Search engine
    └── sqlpad/                   # SQL query tool
```

## Role Conventions

### Standard Role Structure
```
role/
├── tasks/main.yml          # Entry point with assertions + includes
├── defaults/main.yml       # Default variables (prefixed with role name)
├── handlers/main.yml       # Service restart handlers
├── templates/*.j2          # Jinja2 config templates
├── meta/main.yml           # Role metadata
└── files/                  # Static files
```

### Variable Naming
- All defaults prefixed with role name: `postgres_enabled`, `rabbitmq_port`
- Boolean flags always filtered: `when: postgres_enabled | bool`
- Secrets passed via playbook, never hardcoded
- Extra env support: `postgres_extra_env: {}`

### Task Patterns

1. **Always start with variable validation:**
```yaml
- name: Validate required variables
  ansible.builtin.assert:
    that:
      - postgres_db is defined
      - postgres_user is defined
      - postgres_password is defined
    fail_msg: "Required variables: postgres_db, postgres_user, postgres_password"
  when: postgres_enabled | bool
```

2. **Use FQCN (Fully Qualified Collection Names):**
```yaml
- name: Create directory
  ansible.builtin.file:        # NOT: file:
    path: /opt/services/postgres
    state: directory
```

3. **Always add tags to tasks:**
```yaml
- name: Start container
  community.docker.docker_container:
    name: postgres
  tags: postgres
```

4. **Modular task organization:**
```yaml
- name: Include SSH tasks
  ansible.builtin.include_tasks: ssh.yml
  tags: [ssh, security]
```

### Docker Container Standards

```yaml
- name: Start service container
  community.docker.docker_container:
    name: "{{ service_container_name }}"
    image: "{{ service_image }}"
    state: started
    restart_policy: always
    env:
      KEY: "{{ value }}"
    volumes:
      - "{{ service_data_dir }}:/data"
    networks:
      - name: "{{ service_network }}"
    healthcheck:
      test: ["CMD", "healthcheck-command"]
      interval: 10s
      timeout: 5s
      retries: 5
  when: service_enabled | bool
  tags: service
```

**Required elements:**
- Named container
- Explicit restart_policy: always
- Health checks with retries
- Network attachment to shared network
- Conditional execution with `when: enabled | bool`
- Tags for granular execution

### Data Persistence
- Data directories: `/opt/services/{role}/data`
- Config directories: `/opt/services/{role}/config`
- Named Docker volumes for stateful data

## Playbook Conventions

### Variable Prefixes
- Bootstrap playbook: `vps_*` (vps_app_user, vps_timezone)
- Infrastructure playbook: `services_*` (services_postgres_enabled)

### Pre-tasks Pattern
```yaml
pre_tasks:
  - name: Ensure Docker network exists
    community.docker.docker_network:
      name: "{{ services_network }}"
      driver: bridge
    tags: always
```

## Dependencies

Collection dependencies (galaxy.yml):
- `community.docker: >=3.0.0`
- `community.general: >=7.0.0`
- `ansible.posix: >=1.5.0`

System requirements:
- Ansible >= 2.14
- Ubuntu 22.04+ (jammy, noble)

## Common Commands

```bash
# Install collection locally
ansible-galaxy collection install . --force

# Run bootstrap playbook
ansible-playbook softure.vps_foundation.vps_bootstrap \
  -i inventory.yml \
  -e "vps_app_user=deploy vps_timezone=Europe/Warsaw"

# Deploy specific service
ansible-playbook softure.vps_foundation.vps_deploy_infrastructure \
  -i inventory.yml \
  -e "services_postgres_enabled=true" \
  --tags postgres

# Syntax check
ansible-playbook playbook.yml --syntax-check

# Dry run
ansible-playbook playbook.yml --check --diff
```

## Security Notes

- SSH hardening disables password auth - ensure SSH keys are configured first
- Never commit secrets to repository
- Use ansible-vault for sensitive variables
- Fail2ban configured with 20 max retries, 2h ban time
- UFW allows only 22/80/443 by default
