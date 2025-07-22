#!/bin/bash

# ansible-log - Ansible run logger and viewer
# Usage: ansible-log [command] [options]
# Can also be used as: ansible-playbook ... | ansible-log

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
    ansible-log run <ansible-command> [--diff]  Run ansible command with logging
    ansible-log log [run-number] [--diff]       Show log for specific run (default: 0 = latest)
    ansible-log list-runs                       List all recorded runs
    ansible-log setup-config [path]            Create optimized ansible.cfg for better logging
    ansible-log clean                           Clean old logs (keep last $MAX_RUNS)
    ansible-log help                            Show this help
    
    # Piping mode:
    ansible-playbook site.yml | ansible-log [--diff]  Pipe ansible output to logger

OPTIONS:
    --diff: Only show tasks with changes (works with 'run', 'log', and piping modes)

EXAMPLES:
    ansible-log run ansible-playbook site.yml -i inventory
    ansible-log run ansible-playbook site.yml --diff    # Show only changes during run
    ansible-log log 0                                   # Show latest run
    ansible-log log 0 --diff                           # Show latest run with only changes
    ansible-log log 5                                   # Show 6th most recent run
    ansible-log list-runs
    ansible-log setup-config                            # Create ansible.cfg in current directory
    ansible-log setup-config ~/.ansible.cfg            # Create global ansible.cfg
    
    # Piping examples:
    ansible-playbook site.yml -i inventory | ansible-log
    ansible-playbook site.yml -i inventory | ansible-log --diff
    
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

# Function to get git information
get_git_info() {
    local git_info=""
    
    # Check if we're in a git repository (including subdirectories)
    if git rev-parse --git-dir >/dev/null 2>&1; then
        local commit_hash
        local branch
        local is_dirty=""
        
        # Get current commit hash (short)
        commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        
        # Get current branch name
        branch=$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        
        # Check if working directory is dirty (has uncommitted changes)
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            is_dirty=" (dirty)"
        fi
        
        git_info="Branch: ${branch} - Commit SHA: ${commit_hash}${is_dirty}"
    fi
    
    echo "$git_info"
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

# UNIFIED function to process ansible output - handles ALL modes (pipe, run, log)
process_ansible_output() {
    local diff_only="$1"
    local strip_colors_flag="$2"
    
    # Temporarily disable set -e to avoid issues with array operations
    set +e
    
    # For non-diff mode, just pass everything through with color handling
    if [[ "$diff_only" == false ]]; then
        while IFS= read -r line; do
            if [ "$strip_colors_flag" = true ]; then
                echo "$line" | sed 's/\x1b\[[0-9;]*m//g'
            else
                echo "$line"
            fi
        done
        set -e
        return
    fi
    
    # For diff mode, collect all input first
    local all_lines=()
    while IFS= read -r line; do
        all_lines+=("$line")
    done
    
    # Process lines for diff mode - show only tasks with changes/errors
    local current_play=""
    local play_shown=false
    local i=0
    
    # First pass: handle pre-structured errors/warnings
    while [[ $i -lt ${#all_lines[@]} ]]; do
        local line="${all_lines[$i]}"
        local clean_line
        clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g')
        
        # Stop when we hit structured output
        if [[ "$clean_line" =~ ^PLAY\ \[.*\] ]] || [[ "$clean_line" =~ ^TASK\ \[.*\] ]] || [[ "$clean_line" =~ ^PLAY\ RECAP ]]; then
            break
        fi
        
        # Show error/warning lines that appear before structured output
        if [[ "$clean_line" =~ ^ERROR! ]] || [[ "$clean_line" =~ ^FATAL: ]] || [[ "$clean_line" =~ ^WARNING: ]] || [[ "$clean_line" =~ (failed|fatal|UNREACHABLE): ]]; then
            if [ "$strip_colors_flag" = true ]; then
                echo "$clean_line"
            else
                echo "$line"
            fi
        fi
        ((i++))
    done
    
    # Second pass: process structured output (PLAY/TASK/RECAP sections)
    while [[ $i -lt ${#all_lines[@]} ]]; do
        local line="${all_lines[$i]}"
        local clean_line
        clean_line=$(echo "$line" | sed 's/\x1b\[[0-9;]*m//g')
        
        if [[ "$clean_line" =~ ^PLAY\ \[.*\] ]]; then
            # New play - reset state
            current_play="$line"
            play_shown=false
            ((i++))
            
        elif [[ "$clean_line" =~ ^TASK\ \[.*\] ]]; then
            # Process a complete task
            local task_lines=("$line")  # Start with task header
            ((i++))
            
            # Collect all lines belonging to this task
            while [[ $i -lt ${#all_lines[@]} ]]; do
                local task_line="${all_lines[$i]}"
                local clean_task_line
                clean_task_line=$(echo "$task_line" | sed 's/\x1b\[[0-9;]*m//g')
                
                # Stop if we hit another TASK, PLAY, or PLAY RECAP
                if [[ "$clean_task_line" =~ ^PLAY\ \[.*\] ]] || [[ "$clean_task_line" =~ ^TASK\ \[.*\] ]] || [[ "$clean_task_line" =~ ^PLAY\ RECAP ]]; then
                    break
                fi
                
                # Add non-empty lines to task
                if [[ -n "$clean_task_line" && ! "$clean_task_line" =~ ^[[:space:]]*$ ]]; then
                    task_lines+=("$task_line")
                fi
                ((i++))
            done
            
            # Check if this task has changes or errors
            local has_changes=false
            local has_errors=false
            
            for task_line in "${task_lines[@]}"; do
                local clean_task_line
                clean_task_line=$(echo "$task_line" | sed 's/\x1b\[[0-9;]*m//g')
                
                if [[ "$clean_task_line" =~ (changed|failed|fatal|UNREACHABLE): ]]; then
                    if [[ "$clean_task_line" =~ changed: ]]; then
                        has_changes=true
                    elif [[ "$clean_task_line" =~ (failed|fatal|UNREACHABLE): ]]; then
                        has_errors=true
                    fi
                elif [[ "$clean_task_line" =~ ^---\ before ]] || [[ "$clean_task_line" =~ ^\+\+\+\ after ]] || [[ "$clean_task_line" =~ ^@@.*@@ ]]; then
                    has_changes=true
                fi
            done
            
            # Show task if it has changes or errors
            if [[ "$has_changes" == true || "$has_errors" == true ]]; then
                # Show play header if not shown yet
                if [[ "$play_shown" == false && -n "$current_play" ]]; then
                    if [ "$strip_colors_flag" = true ]; then
                        echo "$current_play" | sed 's/\x1b\[[0-9;]*m//g'
                    else
                        echo "$current_play"
                    fi
                    echo ""
                    play_shown=true
                fi
                
                # Show the task
                for task_line in "${task_lines[@]}"; do
                    if [ "$strip_colors_flag" = true ]; then
                        echo "$task_line" | sed 's/\x1b\[[0-9;]*m//g'
                    else
                        echo "$task_line"
                    fi
                done
                
                # Add spacing after task only if the last line wasn't already empty
                local last_line=""
                if [[ ${#task_lines[@]} -gt 0 ]]; then
                    last_line="${task_lines[-1]}"
                    local clean_last_line
                    clean_last_line=$(echo "$last_line" | sed 's/\x1b\[[0-9;]*m//g')
                    if [[ -n "$clean_last_line" && ! "$clean_last_line" =~ ^[[:space:]]*$ ]]; then
                        echo ""
                    fi
                fi
            fi
            
        elif [[ "$clean_line" =~ ^PLAY\ RECAP ]]; then
            # Always show PLAY RECAP section
            if [ "$strip_colors_flag" = true ]; then
                echo "$line" | sed 's/\x1b\[[0-9;]*m//g'
            else
                echo "$line"
            fi
            ((i++))
            
            # Show all recap lines until end of input
            while [[ $i -lt ${#all_lines[@]} ]]; do
                local recap_line="${all_lines[$i]}"
                local clean_recap_line
                clean_recap_line=$(echo "$recap_line" | sed 's/\x1b\[[0-9;]*m//g')
                
                # Show host summary lines and other recap content
                if [[ -n "$clean_recap_line" && ! "$clean_recap_line" =~ ^[[:space:]]*$ ]]; then
                    if [ "$strip_colors_flag" = true ]; then
                        echo "$clean_recap_line"
                    else
                        echo "$recap_line"
                    fi
                fi
                ((i++))
            done
            
        else
            # Skip any other lines
            ((i++))
        fi
    done
    
    # Re-enable set -e
    set -e
}

# Function to handle piped input
handle_piped_input() {
    local diff_only=false
    local timestamp
    local log_file
    
    # Parse arguments for --diff flag
    while [[ $# -gt 0 ]]; do
        case $1 in
            --diff)
                diff_only=true
                shift
                ;;
            *)
                echo "Unknown option for piped mode: $1"
                echo "Usage: ansible-command | ansible-log [--diff]"
                return 1
                ;;
        esac
    done
    
    timestamp=$(get_timestamp)
    log_file="$ANSIBLE_LOG_DIR/run_${timestamp}.log"
    
    echo "📝 Logging piped Ansible output..."
    echo "📁 Log file: $log_file"
    if [[ "$diff_only" == true ]]; then
        echo "🔍 Mode: Showing changes and errors only"
    fi
    echo ""
    
    # Get git information
    local git_info
    git_info=$(get_git_info)
    
    # Write header to log file
    cat << EOF > "$log_file"
=== ANSIBLE RUN LOG ===
Timestamp: $(date)
$([ -n "$git_info" ] && echo "$git_info")
Command: [Piped from stdin]
Working Directory: $(pwd)
User: $(whoami)
Host: $(hostname)

=== COMMAND OUTPUT ===
EOF
    
    # Read from stdin and process
    local temp_file
    temp_file=$(mktemp)
    local exit_code=0
    
    # Read all input and save to temp file while also displaying
    if tee "$temp_file" | process_ansible_output "$diff_only" false; then
        exit_code=0
    else
        exit_code=${PIPESTATUS[0]}
    fi
    
    # Append the buffered content to log file
    cat "$temp_file" >> "$log_file"
    rm -f "$temp_file"
    
    # Add completion status to log
    echo "" >> "$log_file"
    if [ $exit_code -eq 0 ]; then
        echo "=== RUN COMPLETED SUCCESSFULLY ===" >> "$log_file"
        echo ""
        echo -e "${GREEN}✅ Ansible run completed successfully${NC}"
    else
        echo "=== RUN FAILED (exit code: $exit_code) ===" >> "$log_file"
        echo ""
        echo -e "${RED}❌ Ansible run failed with exit code: $exit_code${NC}"
    fi
    
    # Clean old runs
    clean_old_runs
    
    echo "💾 Log saved to: $log_file"
    return $exit_code
}

# Function to clean old runs
clean_old_runs() {
    local run_files
    readarray -t run_files < <(get_run_files)
    
    if [ ${#run_files[@]} -gt "$MAX_RUNS" ]; then
        echo "🧹 Cleaning old runs (keeping last $MAX_RUNS)..."
        for ((i=MAX_RUNS; i<${#run_files[@]}; i++)); do
            rm -f "${run_files[$i]}"
            echo "🗑️ Removed: $(basename "${run_files[$i]}")"
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
    local diff_only=false
    
    # Check for --diff flag in arguments
    local filtered_args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --diff)
                diff_only=true
                shift
                ;;
            *)
                filtered_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Restore filtered arguments
    set -- "${filtered_args[@]}"
    first_arg="$1"
    
    timestamp=$(get_timestamp)
    log_file="$ANSIBLE_LOG_DIR/run_${timestamp}.log"
    cmd_line="$*"
    
    # Resolve the first command to bypass any aliases
    resolved_cmd=$(resolve_command "$first_arg")
    
    echo "🚀 Starting Ansible run at $(date)"
    echo "⚡ Command: $cmd_line"
    echo "📁 Log file: $log_file"
    if [ "$diff_only" = true ]; then
        echo "🔍 Mode: Showing changes and errors only"
    fi
    echo ""
    
    # Get git information
    local git_info
    git_info=$(get_git_info)
    
    # Write header to log file
    cat << EOF > "$log_file"
=== ANSIBLE RUN LOG ===
Timestamp: $(date)
$([ -n "$git_info" ] && echo "$git_info")
Command: $cmd_line
Working Directory: $(pwd)
User: $(whoami)
Host: $(hostname)

=== COMMAND OUTPUT ===
EOF
    
    # Run the ansible command and capture output
    local temp_file
    temp_file=$(mktemp)
    local exit_code=0
    
    if command -v script >/dev/null 2>&1; then
        # Use script to preserve TTY for colored output
        shift  # Remove first argument
        if ANSIBLE_FORCE_COLOR=1 script -qec "$resolved_cmd $*" /dev/null 2>&1 | tee "$temp_file" | process_ansible_output "$diff_only" false; then
            exit_code=0
        else
            exit_code=${PIPESTATUS[0]}
        fi
    else
        # Fallback if script command is not available
        echo "Warning: 'script' command not available, colors may not be preserved in terminal"
        shift  # Remove first argument
        if ANSIBLE_FORCE_COLOR=1 "$resolved_cmd" "$@" 2>&1 | tee "$temp_file" | process_ansible_output "$diff_only" false; then
            exit_code=0
        else
            exit_code=${PIPESTATUS[0]}
        fi
    fi
    
    # Append the captured output to log file
    cat "$temp_file" >> "$log_file"
    rm -f "$temp_file"
    
    # Add completion status
    echo "" >> "$log_file"
    if [ $exit_code -eq 0 ]; then
        echo "=== RUN COMPLETED SUCCESSFULLY ===" >> "$log_file"
        echo ""
        echo -e "${GREEN}✅ Ansible run completed successfully${NC}"
    else
        echo "=== RUN FAILED (exit code: $exit_code) ===" >> "$log_file"
        echo ""
        echo -e "${RED}❌ Ansible run failed with exit code: $exit_code${NC}"
        
        # Clean old runs even on failure
        clean_old_runs
        return $exit_code
    fi
    
    # Clean old runs after successful completion
    clean_old_runs
    
    echo "💾 Log saved to: $log_file"
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

# Function to show log for specific run (with diff support)
show_log() {
    local run_number="0"  # Default to latest run
    local diff_only=false
    local strip_colors_flag=false
    
    # Check if output is being piped or redirected
    if [[ ! -t 1 ]]; then
        strip_colors_flag=true
    fi
    
    # Parse arguments - support both run number and --diff flag
    while [[ $# -gt 0 ]]; do
        case $1 in
            [0-9]*)
                run_number="$1"
                shift
                ;;
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
    
    # Show header
    if [ "$diff_only" = true ]; then
        if [ "$strip_colors_flag" = true ]; then
            echo "=== Ansible Run Log #$run_number ($basename_file) - Changes and Errors Only ==="
        else
            echo -e "${BLUE}=== Ansible Run Log #$run_number ($basename_file) - Changes and Errors Only ===${NC}"
        fi
    else
        if [ "$strip_colors_flag" = true ]; then
            echo "=== Ansible Run Log #$run_number ($basename_file) ==="
        else
            echo -e "${BLUE}=== Ansible Run Log #$run_number ($basename_file) ===${NC}"
        fi
    fi
    echo ""
    
    # Show header info
    local in_output=false
    while IFS= read -r line; do
        if [[ "$line" == "=== COMMAND OUTPUT ===" ]]; then
            in_output=true
            break
        fi
        
        # Show header info with basic formatting
        if [[ "$line" =~ ^(Timestamp|Branch|Command|Working\ Directory|User|Host): ]]; then
            local key
            local value
            key=$(echo "$line" | cut -d':' -f1)
            value=$(echo "$line" | cut -d':' -f2-)
            if [ "$strip_colors_flag" = true ]; then
                echo "$key:$value"
            else
                echo -e "${BLUE}$key:${NC}$value"
            fi
        elif [[ -n "$line" && ! "$line" =~ ^=== ]]; then
            echo "$line"
        fi
    done < "$log_file"
    
    echo ""
    
    # Extract and process ansible output
    local temp_file
    temp_file=$(mktemp)
    local success_message=""
    local failure_message=""
    
    # Extract ansible output section to temp file
    local show_output=false
    while IFS= read -r line; do
        if [[ "$line" == "=== COMMAND OUTPUT ===" ]]; then
            show_output=true
            continue
        elif [[ "$line" == "=== RUN COMPLETED SUCCESSFULLY ===" ]]; then
            success_message="$line"
            break
        elif [[ "$line" == "=== RUN FAILED"* ]]; then
            failure_message="$line"
            break
        fi
        
        if [ "$show_output" = true ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$log_file"
    
    # Process the ansible output using the unified function
    cat "$temp_file" | process_ansible_output "$diff_only" "$strip_colors_flag"
    
    # Show success/failure message
    echo ""
    if [[ -n "$success_message" ]]; then
        if [ "$strip_colors_flag" = true ]; then
            echo "$success_message"
        else
            echo -e "${GREEN}$success_message${NC}"
        fi
    elif [[ -n "$failure_message" ]]; then
        if [ "$strip_colors_flag" = true ]; then
            echo "$failure_message"
        else
            echo -e "${RED}$failure_message${NC}"
        fi
    fi
    
    rm -f "$temp_file"
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
# Check if input is being piped - only if no arguments or only --diff
if [[ ! -t 0 ]] && ([[ $# -eq 0 ]] || [[ $# -eq 1 && "$1" == "--diff" ]]); then
    # Input is being piped, handle it
    handle_piped_input "$@"
    exit $?
fi

case "${1:-help}" in
    "run")
        if [ $# -lt 2 ]; then
            echo "Error: No ansible command provided."
            echo "Usage: ansible-log run <ansible-command> [--diff]"
            exit 1
        fi
        shift
        run_ansible "$@"
        ;;
    "log")
        shift
        show_log "$@"
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
