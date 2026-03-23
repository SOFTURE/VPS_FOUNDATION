# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.11.0] - 2025-03-23

### Changed
- GitHub Actions SSH key is now required by default (`vps_github_actions_ssh_required: true`)
- Improved prompts to clearly indicate required vs optional SSH keys

## [1.10.0] - 2025-03-22

### Changed
- Refactored known_hosts task to improve host key management and ensure correct formatting
- Proper `[host]:port` format for non-standard SSH ports in known_hosts entries
- Filtered out comment lines from ssh-keyscan output

## [1.9.0] - 2025-03-21

### Changed
- Simplified known_hosts update logic by removing pre-check for existing keys

## [1.8.0] - 2025-03-20

### Changed
- SSH port configuration now uses `ansible_port` variable for better flexibility (`vps_ssh_port: "{{ ansible_port | default(22) }}"`)

## [1.7.0] - 2025-03-19

### Added
- Automatic host key scanning and known_hosts management in bootstrap playbook
- Prevents SSH host key verification prompts during playbook execution

### Changed
- Refactored host key management in VPS bootstrap process

## [1.6.0] - 2025-03-18

### Added
- Task to ensure host keys are in known_hosts during VPS bootstrap

## [1.5.0] - 2025-03-17

### Added
- Complete example configuration directory with inventory, group_vars, playbooks, and sample files
- PostgreSQL, PgAdmin, MSSQL, RabbitMQ, Caddy, Seq, Typesense, Portainer, SuperTokens, SQLPad, and Backrest configurations in example

### Changed
- Removed unused connection variables from VPS configuration
- Standardized timezone and locale settings

## [1.4.0] - 2025-03-16

### Changed
- Refactored playbook names for consistency (`vps_bootstrap`, `vps_deploy_infrastructure`)
- Streamlined release workflow versioning and commit process

## [1.3.0] - 2025-03-15

### Changed
- Updated namespace and repository references from `jarmatys` to `softure`
- Refactored SuperTokens health check to use Docker exec command for improved reliability

### Added
- Separated SSH key handling: local machine key and GitHub Actions key
- Enhanced cookie protection configuration for PgAdmin
- Caddy reload handler with force copy of Caddyfile

## [1.2.0] - 2025-03-14

### Added
- Backrest role for backup management
- Initial configuration files for VPS setup (Caddyfile, init script, infrastructure variables)

### Fixed
- Backrest permissions and configuration

## [1.1.0] - 2025-02-05

### Added
- MSSQL `mssql_max_server_memory_mb` parameter for configuring SQL Server internal memory limit
- RabbitMQ plugins support for enabling custom plugins in container
- Resource configuration options (memory limits, CPU) for various services
- Recreate option to container tasks for all services
- SQLPad role for SQL query tool
- Typesense role for search engine
- Microsoft SQL Server (MSSQL) role
- PostgreSQL initialization scripts support
- RabbitMQ configuration file support

### Changed
- Increased fail2ban maxretry limit for SSH from 3 to 20
- Enhanced SSH hardening with authorized_keys verification
- Updated MSSQL healthcheck command to use CMD format for improved compatibility
- Improved Docker network creation with existing network check

### Fixed
- MSSQL container strict healthcheck comparison
- MSSQL directory ownership and group for data directory
- SSH public key input trimming for proper validation

## [1.0.2] - 2025-01-23

### Fixed
- Added missing permissions for GitHub release workflow

### Added
- LICENSE file (MIT)
- CHANGELOG.md file

## [1.0.1] - 2025-01-23

### Fixed
- Fixed directory paths in release workflow for building and packaging Ansible collection
- Updated release workflow to trigger on published releases instead of tag pushes

## [1.0.0] - 2025-01-23

### Added
- Initial release
- Docker role for container management
- Portainer role for Docker UI
- PostgreSQL role for database deployment
- RabbitMQ role for message queue
- Seq role for centralized logging
- SuperTokens role for authentication
- System hardening role for security configuration
