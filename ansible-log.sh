#!/bin/bash

# ansible-log - Ansible run logger and viewer
# Usage: ansible-log [command] [options]

set -euo pipefail

# Configuration
ANSIBLE_LOG_DIR="${ANSIBLE_LOG_DIR:-$HOME/.ansible-logs}"
MAX_RUNS="${ANSIBLE_MAX_RUNS:-50}"  # Keep last 50 runs

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Create log directory if it doesn't exist
mkdir -p "$ANSIBLE_LOG_DIR"

# Function to show usage
show_usage() {
    cat << EOF
ansible-log - Ansible run logger and viewer

USAGE:
    ansible-log run <ansible-command>     Run ansible command with logging
    ansible-log log [run-number] [--diff] Show log for specific run (default: 0 = latest)
                                      --diff: Only show tasks with changes
    ansible-log list-runs                 List all recorded runs
    ansible-log setup-config [path]      Create optimized ansible.cfg for better logging
    ansible-log clean                     Clean old logs (keep last $MAX_RUNS)
    ansible-log help                      Show this help

EXAMPLES:
    ansible-log run ansible-playbook site.yml -i inventory
    ansible-log log 0                     # Show latest run
    ansible-log log 0 --diff             # Show latest run with only changes
    ansible-log log 5                     # Show 6th most recent run
    ansible-log list-runs
    ansible-log setup-config              # Create ansible.cfg in current directory
    ansible-log setup-config ~/.ansible.cfg  # Create global ansible.cfg
    
ENVIRONMENT VARIABLES:
    ANSIBLE_LOG_DIR      Directory to store logs (default: ~/.ansible-logs)
    ANSIBLE_MAX_RUNS     Maximum number of runs to keep (default: 50)
EOF
}

# Function to strip ANSI color codes from text
strip_colors() {
    sed 's/\x1b\[[0-9;]*m//g'
}

# Function to get timestamp
get_timestamp() {
    date '+%Y-%m-%d_%H-%M-%S'
}

# Function to resolve actual command path (bypass aliases)
resolve_command() {
    local cmd="$1"
    # Use 'command -v' to get the actual executable path, bypassing aliases
    command -v "$cmd" 2>/dev/null || echo "$cmd"
}

# Function to get run files sorted by modification time (newest first)
get_run_files() {
    find "$ANSIBLE_LOG_DIR" -name "run_*.log" -type f -printf '%T@ %p\n' 2>/dev/null | \
        sort -rn | cut -d' ' -f2- || true
}

# Function to clean old runs
clean_old_runs() {
    local run_files
    readarray -t run_files < <(get_run_files)
    
    if [ ${#run_files[@]} -gt "$MAX_RUNS" ]; then
        echo "Cleaning old runs (keeping last $MAX_RUNS)..."
        for ((i=MAX_RUNS; i<${#run_files[@]}; i++)); do
            rm -f "${run_files[$i]}"
            echo "Removed: $(basename "${run_files[$i]}")"
        done
    fi
}

# Function to run ansible command with logging
run_ansible() {
    local timestamp
    local log_file
    local cmd_line
    local resolved_cmd
    local first_arg="$1"
    
    timestamp=$(get_timestamp)
    log_file="$ANSIBLE_LOG_DIR/run_${timestamp}.log"
    cmd_line="$*"
    
    # Resolve the first command to bypass any aliases
    resolved_cmd=$(resolve_command "$first_arg")
    
    echo "Starting Ansible run at $(date)"
    echo "Command: $cmd_line"
    echo "Log file: $log_file"
    echo ""
    
    # Write header to log file
    cat << EOF > "$log_file"
=== ANSIBLE RUN LOG ===
Timestamp: $(date)
Command: $cmd_line
Working Directory: $(pwd)
User: $(whoami)
Host: $(hostname)

=== COMMAND OUTPUT ===
EOF
    
    # Run the ansible command and capture output
    # Force colored output by setting ANSIBLE_FORCE_COLOR and using script to preserve TTY
    # Use the resolved command path to bypass aliases
    if command -v script >/dev/null 2>&1; then
        # Use script to preserve TTY for colored output
        # Reconstruct command with resolved path
        shift  # Remove first argument
        if ANSIBLE_FORCE_COLOR=1 script -qec "$resolved_cmd $*" /dev/null 2>&1 | tee -a "$log_file"; then
            echo "" >> "$log_file"
            echo "=== RUN COMPLETED SUCCESSFULLY ===" >> "$log_file"
            echo -e "${GREEN}Ansible run completed successfully${NC}"
        else
            local exit_code=$?
            echo "" >> "$log_file"
            echo "=== RUN FAILED (exit code: $exit_code) ===" >> "$log_file"
            echo -e "${RED}Ansible run failed with exit code: $exit_code${NC}"
            
            # Clean old runs even on failure
            clean_old_runs
            return $exit_code
        fi
    else
        # Fallback if script command is not available
        echo "Warning: 'script' command not available, colors may not be preserved in terminal"
        # Use resolved command path and shift arguments
        shift  # Remove first argument
        if ANSIBLE_FORCE_COLOR=1 "$resolved_cmd" "$@" 2>&1 | tee -a "$log_file"; then
            echo "" >> "$log_file"
            echo "=== RUN COMPLETED SUCCESSFULLY ===" >> "$log_file"
            echo -e "${GREEN}Ansible run completed successfully${NC}"
        else
            local exit_code=$?
            echo "" >> "$log_file"
            echo "=== RUN FAILED (exit code: $exit_code) ===" >> "$log_file"
            echo -e "${RED}Ansible run failed with exit code: $exit_code${NC}"
            
            # Clean old runs even on failure
            clean_old_runs
            return $exit_code
        fi
    fi
    
    # Clean old runs after successful completion
    clean_old_runs
    
    echo "Log saved to: $log_file"
}

# Function to list all runs
list_runs() {
    local run_files
    local reversed_files
    readarray -t run_files < <(get_run_files)
    
    if [ ${#run_files[@]} -eq 0 ]; then
        echo "No ansible runs recorded yet."
        return 0
    fi
    
    # Reverse the array so newest runs appear at the bottom
    for ((i=${#run_files[@]}-1; i>=0; i--)); do
        reversed_files+=("${run_files[$i]}")
    done
    
    echo -e "${BLUE}Recent Ansible Runs (oldest to newest):${NC}"
    echo "----------------------------------------"
    
    for i in "${!reversed_files[@]}"; do
        local file="${reversed_files[$i]}"
        local basename_file
        local timestamp
        local cmd
        local status
        local original_index
        
        basename_file=$(basename "$file")
        timestamp=$(echo "$basename_file" | sed 's/run_\(.*\)\.log/\1/' | tr '_' ' ' | sed 's/-/:/3' | sed 's/-/:/3')
        
        # Calculate the original index (for log command reference)
        original_index=$((${#run_files[@]} - 1 - i))
        
        # Extract command and status from log file
        cmd=$(grep "^Command:" "$file" 2>/dev/null | cut -d' ' -f2- || echo "Unknown command")
        
        if grep -q "RUN COMPLETED SUCCESSFULLY" "$file" 2>/dev/null; then
            status="${GREEN}✓ SUCCESS${NC}"
        elif grep -q "RUN FAILED" "$file" 2>/dev/null; then
            status="${RED}✗ FAILED${NC}"
        else
            status="${YELLOW}? UNKNOWN${NC}"
        fi
        
        printf "%2d: %s - %s\n" "$original_index" "$timestamp" "$status"
        printf "    Command: %s\n" "$cmd"
        echo ""
    done
}

# Function to show log for specific run
show_log() {
    local run_number="${1:-0}"
    local diff_only=false
    local strip_colors_flag=false
    
    # Check if output is being piped or redirected
    if [[ ! -t 1 ]]; then
        strip_colors_flag=true
    fi
    
    # Parse arguments - handle the case where we might not have additional args
    if [[ $# -gt 1 ]]; then
        shift
        while [[ $# -gt 0 ]]; do
            case $1 in
                --diff)
                    diff_only=true
                    shift
                    ;;
                *)
                    echo "Unknown option: $1"
                    echo "Usage: ansible-log log [run-number] [--diff]"
                    return 1
                    ;;
            esac
        done
    fi
    
    local run_files
    readarray -t run_files < <(get_run_files)
    
    if [ ${#run_files[@]} -eq 0 ]; then
        echo "No ansible runs recorded yet."
        return 1
    fi
    
    if ! [[ "$run_number" =~ ^[0-9]+$ ]] || [ "$run_number" -ge ${#run_files[@]} ]; then
        echo "Invalid run number. Use 'ansible-log list-runs' to see available runs."
        return 1
    fi
    
    local log_file="${run_files[$run_number]}"
    local basename_file
    basename_file=$(basename "$log_file")
    
    if [ "$diff_only" = true ]; then
        if [ "$strip_colors_flag" = true ]; then
            echo "=== Ansible Run Log #$run_number ($basename_file) - Changes Only ==="
        else
            echo -e "${BLUE}=== Ansible Run Log #$run_number ($basename_file) - Changes Only ===${NC}"
        fi
    else
        if [ "$strip_colors_flag" = true ]; then
            echo "=== Ansible Run Log #$run_number ($basename_file) ==="
        else
            echo -e "${BLUE}=== Ansible Run Log #$run_number ($basename_file) ===${NC}"
        fi
    fi
    echo ""
    
    if [ "$diff_only" = true ]; then
        if [ "$strip_colors_flag" = true ]; then
            show_diff_log "$log_file" | strip_colors
        else
            show_diff_log "$log_file"
        fi
    else
        if [ "$strip_colors_flag" = true ]; then
            show_full_log "$log_file" | strip_colors
        else
            show_full_log "$log_file"
        fi
    fi
}

# Function to show full log with formatting
show_full_log() {
    local log_file="$1"
    local in_output=false
    
    while IFS= read -r line; do
        if [[ "$line" == "=== COMMAND OUTPUT ===" ]]; then
            in_output=true
            continue
        elif [[ "$line" == "=== RUN COMPLETED SUCCESSFULLY ===" ]]; then
            echo -e "${GREEN}$line${NC}"
            continue
        elif [[ "$line" == "=== RUN FAILED"* ]]; then
            echo -e "${RED}$line${NC}"
            continue
        fi
        
        if [ "$in_output" = true ]; then
            # Format ansible output with colors
            if [[ "$line" =~ ^PLAY\ \[.*\] ]]; then
                echo -e "${PURPLE}$line${NC}"
            elif [[ "$line" =~ ^TASK\ \[.*\] ]]; then
                echo -e "${CYAN}$line${NC}"
            elif [[ "$line" =~ ^ok: ]]; then
                echo -e "${GREEN}$line${NC}"
            elif [[ "$line" =~ ^changed: ]]; then
                echo -e "${YELLOW}$line${NC}"
            elif [[ "$line" =~ ^skipped: ]]; then
                echo -e "${BLUE}$line${NC}"
            elif [[ "$line" =~ ^(failed|fatal): ]]; then
                echo -e "${RED}$line${NC}"
            elif [[ "$line" =~ ^PLAY\ RECAP ]]; then
                echo -e "${PURPLE}$line${NC}"
            else
                echo "$line"
            fi
        else
            # Show header information with formatting
            if [[ "$line" =~ ^(Timestamp|Command|Working\ Directory|User|Host): ]]; then
                local key
                local value
                key=$(echo "$line" | cut -d':' -f1)
                value=$(echo "$line" | cut -d':' -f2-)
                echo -e "${BLUE}$key:${NC}$value"
            else
                echo "$line"
            fi
        fi
    done < "$log_file"
}

# Function to show diff log (changes only)
# Function to show diff log (changes only)
show_diff_log() {
    local log_file="$1"
    local in_output=false
    local task_buffer=()
    local in_task=false
    local current_play=""
    local play_shown=false
    
    # First pass: show header info
    while IFS= read -r line; do
        if [[ "$line" == "=== COMMAND OUTPUT ===" ]]; then
            break
        fi
        
        if [[ "$line" =~ ^(Timestamp|Command|Working\ Directory|User|Host): ]]; then
            local key
            local value
            key=$(echo "$line" | cut -d':' -f1)
            value=$(echo "$line" | cut -d':' -f2-)
            echo -e "${BLUE}$key:${NC}$value"
        elif [[ -n "$line" && ! "$line" =~ ^=== ]]; then
            echo "$line"
        fi
    done < "$log_file"
    
    echo ""
    
    # Second pass: process ansible output for changes only
    local show_output=false
    while IFS= read -r line; do
        if [[ "$line" == "=== COMMAND OUTPUT ===" ]]; then
            show_output=true
            continue
        elif [[ "$line" == "=== RUN COMPLETED SUCCESSFULLY ===" ]]; then
            echo -e "${GREEN}$line${NC}"
            continue
        elif [[ "$line" == "=== RUN FAILED"* ]]; then
            echo -e "${RED}$line${NC}"
            continue
        fi
        
        if [ "$show_output" = true ]; then
            if [[ "$line" =~ ^PLAY\ \[.*\] ]]; then
                # Store current play but don't show it yet
                current_play="$line"
                play_shown=false
            elif [[ "$line" =~ ^TASK\ \[.*\] ]]; then
                # Start new task - reset buffer
                task_buffer=("$(echo -e "${CYAN}$line${NC}")")
                in_task=true
            elif [[ "$line" =~ ^PLAY\ RECAP ]]; then
                # Always show PLAY RECAP and following lines
                echo -e "${PURPLE}$line${NC}"
                in_task=false
                current_play=""
                play_shown=false
                # Continue reading and showing recap lines until we hit an empty line or end
                while IFS= read -r recap_line; do
                    if [[ -z "$recap_line" ]] || [[ "$recap_line" =~ ^=== ]]; then
                        # End of recap section
                        if [[ "$recap_line" =~ ^=== ]]; then
                            # Put the line back by echoing it in the appropriate color
                            if [[ "$recap_line" == "=== RUN COMPLETED SUCCESSFULLY ===" ]]; then
                                echo -e "${GREEN}$recap_line${NC}"
                            elif [[ "$recap_line" == "=== RUN FAILED"* ]]; then
                                echo -e "${RED}$recap_line${NC}"
                            fi
                        fi
                        break
                    else
                        echo "$recap_line"
                    fi
                done
            elif [[ "$line" =~ (^|.*\[0;[0-9]+m)(changed|failed|fatal): ]] && [ "$in_task" = true ]; then
                # Task had changes - show the play first if not already shown
                if [ "$play_shown" = false ] && [ -n "$current_play" ]; then
                    echo -e "${PURPLE}$current_play${NC}"
                    echo ""
                    play_shown=true
                fi
                
                # Show everything we buffered plus this status line
                printf '%s\n' "${task_buffer[@]}"
                if [[ "$line" =~ (^|.*\[0;[0-9]+m)changed: ]]; then
                    echo -e "${YELLOW}$line${NC}"
                elif [[ "$line" =~ (^|.*\[0;[0-9]+m)(failed|fatal): ]]; then
                    echo -e "${RED}$line${NC}"
                fi
                echo ""
                task_buffer=()
                in_task=false
            elif [[ "$line" =~ (^|.*\[0;[0-9]+m)(ok|skipped): ]] && [ "$in_task" = true ]; then
                # Task had no changes - discard buffer completely
                task_buffer=()
                in_task=false
            elif [[ "$line" =~ skipping:.*no\ hosts\ matched ]]; then
                # Skip these lines
                continue
            else
                # Any other line - add to buffer if we're in a task
                if [ "$in_task" = true ]; then
                    task_buffer+=("$line")
                elif [[ -n "$line" && ! "$line" =~ ^$ ]]; then
                    # Show warnings that aren't part of a task
                    if [[ "$line" =~ WARNING ]] || [[ "$line" =~ ^\[WARNING ]]; then
                        echo "$line"
                    fi
                fi
            fi
        fi
    done < "$log_file"
}
# Function to clean logs
clean_logs() {
    echo "Cleaning all ansible logs..."
    rm -f "$ANSIBLE_LOG_DIR"/run_*.log
    echo "All logs cleaned."
}

# Function to setup ansible configuration
setup_config() {
    local config_file="${1:-ansible.cfg}"
    local config_dir
    
    # Create directory if it doesn't exist (for paths like ~/.ansible.cfg)
    config_dir=$(dirname "$config_file")
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
        echo "Created directory: $config_dir"
    fi
    
    # Convert relative path to absolute for display
    local display_path
    display_path=$(realpath "$config_file" 2>/dev/null || echo "$config_file")
    
    if [ -f "$config_file" ]; then
        echo -e "${YELLOW}Warning: Configuration file already exists at $display_path${NC}"
        read -p "Overwrite existing file? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Setup cancelled."
            return 0
        fi
    fi
    
    echo "Creating optimized ansible.cfg at $display_path..."
    
    cat > "$config_file" << 'EOF'
# ansible.cfg - Ansible configuration for enhanced logging

[defaults]
# Enable stdout callback for better output formatting
stdout_callback = default
# Show task execution time
callback_enabled = timer, profile_tasks
# Display skipped tasks
display_skipped_hosts = yes
# Show task arguments (be careful with sensitive data)
display_args_to_stdout = no
# Increase verbosity for better logging (adjust as needed)
verbosity = 0

# Log all ansible runs to a file (this is in addition to our custom logging)
log_path = ~/.ansible.log

# Host key checking (adjust based on your security requirements)
host_key_checking = False

# SSH timeout settings
timeout = 30

# Retry files location
retry_files_enabled = True
retry_files_save_path = ~/.ansible-retry

[inventory]
# Cache settings for dynamic inventories
cache = True
cache_plugin = memory
cache_timeout = 3600

[ssh_connection]
# SSH multiplexing for better performance
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
EOF
    
    echo -e "${GREEN}✓ Created ansible.cfg at $display_path${NC}"
    echo ""
    echo "Configuration highlights:"
    echo "  - Enhanced output formatting with task timing"
    echo "  - Automatic logging to ~/.ansible.log"
    echo "  - SSH connection optimization"
    echo "  - Inventory caching for better performance"
    echo ""
    
    # Show scope information
    if [[ "$config_file" == *"/.ansible.cfg" ]] || [[ "$config_file" == "$HOME/.ansible.cfg" ]]; then
        echo -e "${BLUE}Note: This is a global configuration that will affect all Ansible runs${NC}"
    else
        echo -e "${BLUE}Note: This is a project-specific configuration${NC}"
    fi
    
    echo "You can customize these settings based on your needs."
}

# Main script logic
case "${1:-help}" in
    "run")
        if [ $# -lt 2 ]; then
            echo "Error: No ansible command provided."
            echo "Usage: ansible-log run <ansible-command>"
            exit 1
        fi
        shift
        run_ansible "$@"
        ;;
    "log")
        show_log "${2:-0}" "${@:3}"
        ;;
    "list-runs")
        list_runs
        ;;
    "setup-config")
        setup_config "${2:-}"
        ;;
    "clean")
        clean_logs
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        echo "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
