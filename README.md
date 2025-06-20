# 📋 ansible-log

> **A powerful Ansible run logger and viewer with intelligent filtering and beautiful output formatting**

[![Shell Script](https://img.shields.io/badge/shell-bash-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![POSIX Compliant](https://img.shields.io/badge/POSIX-compliant-brightgreen.svg)](https://pubs.opengroup.org/onlinepubs/9699919799/)

## ✨ Features

- 🎯 **Smart Logging** - Automatically captures and stores all Ansible runs with metadata
- 🔍 **Intelligent Filtering** - View only tasks with changes using `--diff` mode
- 🎨 **Beautiful Output** - Color-coded output with proper formatting for better readability
- 📊 **Run Management** - List, view, and clean historical runs with ease
- ⚡ **Performance Optimized** - Automatic cleanup of old logs to save disk space
- 🔧 **Easy Setup** - One-command configuration generation for optimal Ansible settings
- 🏗️ **Context Aware** - Shows PLAY structure for filtered tasks to maintain context

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd ansible-log

# Make the script executable
chmod +x ansible-log.sh

# Optional: Add to your PATH
sudo ln -s $(pwd)/ansible-log.sh /usr/local/bin/ansible-log
```

### Basic Usage

```bash
# Run an Ansible command with logging
ansible-log run ansible-playbook site.yml -i inventory

# View the latest run
ansible-log log

# View only tasks with changes
ansible-log log --diff

# List all recorded runs
ansible-log list-runs
```

## 📖 Commands

| Command | Description | Example |
|---------|-------------|---------|
| `run <command>` | Execute Ansible command with logging | `ansible-log run ansible-playbook site.yml` |
| `log [number] [--diff]` | Show log for specific run | `ansible-log log 0 --diff` |
| `list-runs` | List all recorded runs | `ansible-log list-runs` |
| `setup-config [path]` | Create optimized ansible.cfg | `ansible-log setup-config` |
| `clean` | Remove all stored logs | `ansible-log clean` |
| `help` | Show usage information | `ansible-log help` |

## 🎨 Output Examples

### Standard Log View
```
=== Ansible Run Log #0 (run_2024-01-15_14-30-25.log) ===

PLAY [Configure web servers] ************************************************

TASK [Install nginx] *********************************************************
changed: [web1]
changed: [web2]

TASK [Start nginx service] ***************************************************
ok: [web1]
ok: [web2]

PLAY RECAP *******************************************************************
web1                       : ok=2    changed=1    unreachable=0    failed=0
web2                       : ok=2    changed=1    unreachable=0    failed=0
```

### Diff Mode (Changes Only)
```
=== Ansible Run Log #0 (run_2024-01-15_14-30-25.log) - Changes Only ===

PLAY [Configure web servers] ************************************************

TASK [Install nginx] *********************************************************
changed: [web1]
changed: [web2]

PLAY RECAP *******************************************************************
web1                       : ok=2    changed=1    unreachable=0    failed=0
web2                       : ok=2    changed=1    unreachable=0    failed=0
```

## ⚙️ Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ANSIBLE_LOG_DIR` | `~/.ansible-logs` | Directory to store log files |
| `ANSIBLE_MAX_RUNS` | `50` | Maximum number of runs to keep |

### Optimized Ansible Configuration

Generate an optimized `ansible.cfg` for better logging:

```bash
# Create project-specific config
ansible-log setup-config

# Create global config
ansible-log setup-config ~/.ansible.cfg
```

## 🔧 Shell Integration

### Bash Aliases

Add these aliases to your `~/.bashrc` or `~/.bash_profile` for seamless integration:

```bash
# Ansible logging aliases
alias ansible='ansible-log run ansible'
alias ansible-playbook='ansible-log run ansible-playbook'
alias ansible-vault='ansible-log run ansible-vault'
alias ansible-galaxy='ansible-log run ansible-galaxy'

# Quick log viewing
alias alog='ansible-log log'
alias alogd='ansible-log log --diff'
alias alogs='ansible-log list-runs'

# Ansible log management
alias alog-clean='ansible-log clean'
alias alog-setup='ansible-log setup-config'
```

### Zsh Integration

For Zsh users, add to your `~/.zshrc`:

```zsh
# Ansible logging aliases
alias ansible='ansible-log run ansible'
alias ansible-playbook='ansible-log run ansible-playbook'
alias ansible-vault='ansible-log run ansible-vault'
alias ansible-galaxy='ansible-log run ansible-galaxy'

# Quick log viewing with tab completion
alias alog='ansible-log log'
alias alogd='ansible-log log --diff'
alias alogs='ansible-log list-runs'

# Management commands
alias alog-clean='ansible-log clean'
alias alog-setup='ansible-log setup-config'
```

### Fish Shell Integration

For Fish shell users, add to your `~/.config/fish/config.fish`:

```fish
# Ansible logging aliases
alias ansible='ansible-log run ansible'
alias ansible-playbook='ansible-log run ansible-playbook'
alias ansible-vault='ansible-log run ansible-vault'
alias ansible-galaxy='ansible-log run ansible-galaxy'

# Quick log viewing
alias alog='ansible-log log'
alias alogd='ansible-log log --diff'
alias alogs='ansible-log list-runs'

# Management commands
alias alog-clean='ansible-log clean'
alias alog-setup='ansible-log setup-config'
```

## 💡 Pro Tips

### 1. **Always Use Diff Mode for Quick Reviews**
```bash
# Quickly see what changed in your last run
alogd  # Using the alias from above
```

### 2. **Set Up Project-Specific Configs**
```bash
# In each Ansible project directory
ansible-log setup-config
```

### 3. **Monitor Long-Running Playbooks**
```bash
# Run in background and check logs periodically
ansible-log run ansible-playbook long-running.yml &
# Check progress
alog --diff
```

### 4. **Clean Up Regularly**
```bash
# Set a lower max runs for projects with frequent deployments
export ANSIBLE_MAX_RUNS=20
```

## 🏗️ Advanced Usage

### Custom Log Directory
```bash
# Use project-specific log directory
export ANSIBLE_LOG_DIR="./logs"
ansible-log run ansible-playbook deploy.yml
```

### Integration with CI/CD
```bash
#!/bin/bash
# In your CI/CD pipeline
export ANSIBLE_LOG_DIR="/var/log/ansible-ci"
export ANSIBLE_MAX_RUNS=100

ansible-log run ansible-playbook deploy.yml -i production

# Check for failures
if ansible-log log 0 | grep -q "FAILED"; then
    echo "Deployment failed!"
    ansible-log log 0 --diff
    exit 1
fi
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Setup

```bash
# Clone and setup
git clone <repository-url>
cd ansible-log

# Test the script
bash -n ansible-log.sh  # Syntax check
./ansible-log.sh help   # Functionality test

# Run shellcheck if available
shellcheck ansible-log.sh
```

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with ❤️ for the Ansible community
- Inspired by the need for better Ansible run visibility
- Thanks to all contributors and users providing feedback

---

<div align="center">

**[⭐ Star this repo](../../stargazers) if you find it useful!**

Made with 🔧 by developers, for developers

</div>