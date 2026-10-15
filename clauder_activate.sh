#!/bin/bash

# Check if running in interactive terminal
if [[ -t 0 ]]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# Function to safely exit or return based on interactive mode
safe_exit() {
    local exit_code=$1
    if [[ "$INTERACTIVE" == "true" ]]; then
        return $exit_code
    else
        exit $exit_code
    fi
}

# Function to check if colors are supported
colors_supported() {
    # Check if we're in a terminal and colors are supported
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null) -ge 8 ]]; then
        return 0
    else
        return 1
    fi
}

# Function to print text in white
print_white() {
    if colors_supported; then
        echo -n "$(tput setaf 7)$1$(tput sgr0)"
    else
        echo -n "$1"
    fi
}

# Function to print text in gray
print_gray() {
    if colors_supported; then
        echo -n "$(tput setaf 8)$1$(tput sgr0)"
    else
        echo -n "$1"
    fi
}

# Function to display usage
usage() {
    echo "Usage: clauder_activate [target_project_path] [--expansions <name> <name> <name>]"
    echo "Example: clauder_activate ./my-project"
    echo "Example: clauder_activate                    # Use current directory"
    echo "Example: clauder_activate . --expansions frontend-dev backend-dev"
    echo ""
    echo "Arguments:"
    echo "  target_project_path    Directory to activate (default: current directory)"
    echo ""
    echo "Options:"
    echo "  --expansions          Apply expansion packs (space-separated list)"
    echo "  -h, --help            Show this help message"
    echo "  -v, --version         Show version information"
    safe_exit 0
}

# Function to display version
version() {
    echo "Claude Configuration Activator"
    echo "Version: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    echo "Commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
    safe_exit 0
}

# Function to check if a directory exists
check_directory() {
    if [ ! -d "$1" ]; then
        echo "Error: Project directory '$1' does not exist."
        safe_exit 1
    fi
}

# Function to check if current directory is named 'clauder'
check_current_directory() {
    local current_dir_name=$(basename "$(pwd)")
    if [ "$current_dir_name" = "clauder" ]; then
        echo "Error: Cannot run clauder_activate.sh from within a directory named 'clauder'."
        echo "Please navigate to a different directory before running this script."
        safe_exit 1
    fi
}

# Function to check if we're trying to activate in the clauder directory itself
check_clauder_directory_activation() {
    local target_project="$1"
    local clauder_dir="${CLAUDER_DIR:-$(dirname "$(realpath "$0")")}"
    
    # Get absolute paths for comparison
    local target_abs_path=$(realpath "$target_project")
    local clauder_abs_path=$(realpath "$clauder_dir")
    
    # Check if target project is the clauder directory itself
    if [ "$target_abs_path" = "$clauder_abs_path" ]; then
        echo "Error: Cannot activate clauder in the clauder directory itself."
        echo "Please run clauder_activate from a different project directory."
        echo "Target: $target_abs_path"
        echo "Clauder: $clauder_abs_path"
        safe_exit 1
    fi
    
    # Also check if we're currently in the clauder directory
    local current_dir=$(pwd)
    local current_abs_path=$(realpath "$current_dir")
    
    if [ "$current_abs_path" = "$clauder_abs_path" ]; then
        echo "Error: Cannot run clauder_activate from within the clauder directory."
        echo "Please navigate to a different project directory first."
        echo "Current: $current_abs_path"
        echo "Clauder: $clauder_abs_path"
        safe_exit 1
    fi
}

# Function to create backup of existing .claude directory
create_backup() {
    local target_claude="$1"
    local target_project="$2"
    
    if [ ! -d "$target_claude" ]; then
        return 0  # No existing .claude directory to backup
    fi
    
    # Create .claude-backup directory if it doesn't exist
    local backup_dir="$target_project/.claude-backup"
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
    fi
    
    # Generate timestamp in lowercase-dashed format (including seconds)
    local timestamp=$(date +%Y-%m-%d-%H-%M-%S | tr '[:upper:]' '[:lower:]')
    local backup_name="$backup_dir/$timestamp"
    
    echo "Creating backup of existing .claude directory..."
    echo "Backup location: $backup_name"
    
    # Copy existing .claude directory to backup
    if cp -r "$target_claude" "$backup_name" 2>/dev/null; then
        echo "✓ Backup created successfully"
        
        # Clean up old backups (keep only 10 most recent)
        cleanup_old_backups "$backup_dir"
    else
        echo "✗ Failed to create backup"
        return 1
    fi
    
    return 0
}

# Function to clean up old backups (keep only 10 most recent)
cleanup_old_backups() {
    local backup_dir="$1"
    
    # Get list of backup directories sorted by modification time (newest first)
    # Use macOS compatible find command
    local backups=($(find "$backup_dir" -maxdepth 1 -type d -name "20*" -exec stat -f "%m %N" {} \; | sort -nr | cut -d' ' -f2-))
    
    # Remove backups beyond the 10th one
    if [ ${#backups[@]} -gt 10 ]; then
        local backups_to_remove=()
        i=10
        while [ $i -lt ${#backups[@]} ]; do
            backups_to_remove+=("$(basename "${backups[$i]}")")
            i=$((i + 1))
        done
        
        echo "Found ${#backups_to_remove[@]} old backup(s) to remove (keeping 10 most recent):"
        printf '  %s\n' "${backups_to_remove[@]}"
        echo ""
        print_white "Do you want to remove these old backups? (y/N): "
        read -r reply
        echo
        
        if [[ $reply =~ ^[Yy]$ ]]; then
            echo "Removing old backups..."
            i=10
            while [ $i -lt ${#backups[@]} ]; do
                local old_backup="${backups[$i]}"
                echo "Removing: $(basename "$old_backup")"
                rm -rf "$old_backup"
                i=$((i + 1))
            done
            echo "✓ Old backups removed successfully"
        else
            echo "Skipping cleanup of old backups"
        fi
    fi
}

# Agents and skills the user created or modified in the target project are
# kept on activation and update. A file is considered customised when it exists
# in the target, differs from the version clauder ships now, and also differs
# from the version clauder shipped at the commit recorded in .claude/.clauderrc
# (an unmodified stale copy is simply updated). Kept files are flagged so the
# user can review clauder's version and decide whether to adopt it.
KEPT_CUSTOM_FILES=()

is_protected_path() {
    local relative_path="$1"
    case "$relative_path" in
        agents/*|skills/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Returns 0 when the target file must be kept (customised), 1 when it may be
# overwritten. Arguments: relative path, target file, source file, target .claude
# directory, path of the source root inside the clauder repository
# (".claude" or ".claude-expansion-packs/<name>").
is_customized_file() {
    local relative_path="$1"
    local target_file="$2"
    local source_file="$3"
    local target_claude="$4"
    local source_root_rel="$5"
    local clauder_dir="${CLAUDER_DIR:-$(dirname "$(realpath "$0")")}"

    is_protected_path "$relative_path" || return 1
    [ -f "$target_file" ] || return 1
    cmp -s "$target_file" "$source_file" && return 1

    # Compare with the version shipped at the previously activated commit
    local clauderrc_file="$target_claude/.clauderrc"
    if [ -f "$clauderrc_file" ] && [ -d "$clauder_dir/.git" ]; then
        local previous_commit
        previous_commit=$(tr -d '\n\r' < "$clauderrc_file")
        if [ -n "$previous_commit" ]; then
            local previous_content
            if previous_content=$(cd "$clauder_dir" && git show "$previous_commit:$source_root_rel/$relative_path" 2>/dev/null); then
                if [ "$previous_content" = "$(cat "$target_file")" ]; then
                    return 1  # unmodified clauder file, safe to update
                fi
            fi
        fi
    fi

    return 0
}

report_kept_custom_files() {
    local clauder_dir="${CLAUDER_DIR:-$(dirname "$(realpath "$0")")}"
    if [ ${#KEPT_CUSTOM_FILES[@]} -eq 0 ]; then
        return 0
    fi
    echo ""
    echo "⚠ Kept ${#KEPT_CUSTOM_FILES[@]} customised agent/skill file(s). Clauder ships a different version of each:"
    local entry
    for entry in "${KEPT_CUSTOM_FILES[@]}"; do
        local relative_path="${entry%%|*}"
        local source_file="${entry#*|}"
        echo "  • .claude/$relative_path"
        echo "      review: diff \"$source_file\" \".claude/$relative_path\""
    done
    echo "  Your versions were left untouched. To adopt clauder's version of a file, copy it over yours."
    echo ""
    KEPT_CUSTOM_FILES=()
}

# Function to check for existing .claude files that would be overwritten
check_existing_files() {
    local source_claude="$1"
    local target_claude="$2"
    local files_to_overwrite=()
    
    if [ ! -d "$source_claude" ]; then
        echo "Error: Source .claude directory does not exist."
        return 1
    fi
    
    local files_to_keep=()
    
    if [ -d "$target_claude" ]; then
        # Check which files from source would overwrite existing files in target
        while IFS= read -r -d '' source_file; do
            # Get relative path from source
            local relative_path="${source_file#$source_claude/}"
            local target_file="$target_claude/$relative_path"
            
            # Check if target file exists
            if [ -f "$target_file" ]; then
                if is_customized_file "$relative_path" "$target_file" "$source_file" "$target_claude" ".claude"; then
                    files_to_keep+=("$relative_path")
                else
                    files_to_overwrite+=("$relative_path")
                fi
            fi
        done < <(find "$source_claude" -type f -print0 2>/dev/null)
    fi
    
    if [ ${#files_to_keep[@]} -gt 0 ]; then
        echo "Note: The following customised agents/skills will be KEPT (clauder ships a different version):"
        printf '  %s\n' "${files_to_keep[@]}"
        echo ""
    fi
    
    if [ ${#files_to_overwrite[@]} -gt 0 ]; then
        echo "Warning: The following files will be backed up and overwritten:"
        printf '  %s\n' "${files_to_overwrite[@]}"
        echo ""
        print_white "Do you want to backup and replace these existing files? (y/N): "
        read -r reply
        echo
        if [[ ! $reply =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            return 1
        fi
        echo "Proceeding with replacement..."
    fi
    
    return 0
}

# Function to merge JSON files deeply
merge_json_files() {
    local target_file="$1"
    local source_file="$2"
    
    # Check if both files exist
    if [ ! -f "$target_file" ] || [ ! -f "$source_file" ]; then
        echo "Debug: Missing files - target: $target_file, source: $source_file" >&2
        return 1
    fi
    
    # Use jq to merge JSON files if available
    if command -v jq >/dev/null 2>&1; then
        # Create a temporary file for the merged result
        local temp_file=$(mktemp)
        
        # Check if source file is essentially empty (template)
        local source_content=$(jq -c '.' "$source_file" 2>/dev/null)
        if [ "$source_content" = "{}" ] || [ "$source_content" = "[]" ]; then
            rm -f "$temp_file"
            return 0
        fi
        
        # Use Python for deep merge
        if python3 -c "
import json
import sys

def deep_merge(base, override):
    if isinstance(base, dict) and isinstance(override, dict):
        result = base.copy()
        for key, value in override.items():
            if key in result and isinstance(result[key], (dict, list)) and isinstance(value, type(result[key])):
                result[key] = deep_merge(result[key], value)
            else:
                result[key] = value
        return result
    elif isinstance(base, list) and isinstance(override, list):
        # Always concatenate arrays, even if override is empty
        return base + override
    else:
        # If override is empty/null, keep base value
        if override is None or override == {} or override == []:
            return base
        else:
            return override

try:
    with open('$target_file', 'r') as f:
        base = json.load(f)
    with open('$source_file', 'r') as f:
        override = json.load(f)
    
    merged = deep_merge(base, override)
    
    with open('$temp_file', 'w') as f:
        json.dump(merged, f, indent=2)
    
    sys.exit(0)
except Exception as e:
    print(f'Debug: Python merge failed: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
            # Replace the target file with the merged content
            mv "$temp_file" "$target_file"
            return 0
        else
            # If Python merge fails, fall back to simple concatenation
            rm -f "$temp_file"
            echo "Warning: Python merge failed, using fallback method" >&2
            return 1
        fi
    else
        # Fallback: simple concatenation for JSON files
        # This is not ideal but works for simple cases
        echo "Debug: jq not available" >&2
        return 1
    fi
}

# Function to merge text files by preserving custom configurations
merge_text_files() {
    local target_file="$1"
    local source_file="$2"
    
    # Check if both files exist
    if [ ! -f "$target_file" ] || [ ! -f "$source_file" ]; then
        return 1
    fi
    
    # Create a temporary file for the merged result
    local temp_file=$(mktemp)
    
    # Start with target file content (preserve existing custom configurations)
    cat "$target_file" > "$temp_file"
    
    # Add a newline if the target file doesn't end with one
    if [ -s "$target_file" ] && [ "$(tail -c1 "$target_file" | wc -l)" -eq 0 ]; then
        echo "" >> "$temp_file"
    fi
    
    # Read source file line by line and add only non-duplicate lines
    while IFS= read -r line; do
        # Skip empty lines
        if [ -n "$line" ]; then
            # Check if line already exists in target file (case-sensitive)
            if ! grep -q "^$(echo "$line" | sed 's/[[\.*^$()+?{|]/\\&/g')$" "$target_file"; then
                echo "$line" >> "$temp_file"
            fi
        fi
    done < "$source_file"
    
    # Replace target file with merged content
    mv "$temp_file" "$target_file"
    return 0
}

# Function to copy expansion pack
copy_expansion_pack() {
    local expansion_name="$1"
    local target_project="$2"
    local target_claude="$target_project/.claude"
    local clauder_dir="${CLAUDER_DIR:-$(dirname "$(realpath "$0")")}"
    local expansion_dir="$clauder_dir/.claude-expansion-packs/$expansion_name"
    
    # Check if expansion pack exists
    if [ ! -d "$expansion_dir" ]; then
        echo "Warning: Expansion pack '$expansion_name' does not exist."
        return 1
    fi
    
    echo "Applying expansion pack: $expansion_name"
    
    # Files that need special merging
    local mergeable_files=(".exclude_security_checks" ".ignore" ".immutable" "preferences.json" "settings.json")
    
    # Copy all files from expansion pack
    while IFS= read -r -d '' source_file; do
        # Get relative path from source
        local relative_path="${source_file#$expansion_dir/}"
        local target_file="$target_claude/$relative_path"
        
        # Create target directory if it doesn't exist
        local target_dir=$(dirname "$target_file")
        if [ ! -d "$target_dir" ]; then
            mkdir -p "$target_dir"
        fi
        
        # Check if this is a mergeable file
        local filename=$(basename "$relative_path")
        local should_merge=false
        
        for mergeable_file in "${mergeable_files[@]}"; do
            if [ "$filename" = "$mergeable_file" ]; then
                should_merge=true
                break
            fi
        done
        
        # Handle file copying/merging
        if [ "$should_merge" = true ]; then
            # For mergeable files, create target if it doesn't exist, then merge
            if [ ! -f "$target_file" ]; then
                # Create empty target file for merging
                touch "$target_file"
            fi
            
            # Merge the file
            if [[ "$filename" == *.json ]]; then
                if merge_json_files "$target_file" "$source_file"; then
                    echo "  ✓ Merged: $relative_path"
                else
                    echo "  ⚠ Merged (fallback): $relative_path"
                fi
            else
                if merge_text_files "$target_file" "$source_file"; then
                    echo "  ✓ Merged: $relative_path"
                else
                    echo "  ⚠ Merged (fallback): $relative_path"
                fi
            fi
        elif is_customized_file "$relative_path" "$target_file" "$source_file" "$target_claude" ".claude-expansion-packs/$expansion_name"; then
            # Keep the user's customised agent or skill and flag it
            KEPT_CUSTOM_FILES+=("$relative_path|$source_file")
            echo "  ⚠ Kept (customised): $relative_path"
        else
            # Copy the file normally
            if cp -f "$source_file" "$target_file" 2>/dev/null; then
                echo "  ✓ Copied: $relative_path"
            else
                echo "  ✗ Failed to copy: $relative_path"
            fi
        fi
    done < <(find "$expansion_dir" -type f -print0 2>/dev/null)
    
    # Add expansion name to .claude.expansion_packs if not already present
    local expansion_packs_file="$target_claude/.expansion_packs"
    if [ ! -f "$expansion_packs_file" ]; then
        touch "$expansion_packs_file"
    fi
    
    # Check if expansion name is already in the file
    if ! grep -q "^$expansion_name$" "$expansion_packs_file" 2>/dev/null; then
        echo "$expansion_name" >> "$expansion_packs_file"
        echo "  ✓ Added to expansion packs list"
    else
        echo "  ℹ Already in expansion packs list"
    fi
    
    echo "✓ Expansion pack '$expansion_name' applied successfully"
}

# Function to apply expansion packs
apply_expansion_packs() {
    local target_project="$1"
    shift
    local expansions=("$@")
    
    if [ ${#expansions[@]} -eq 0 ]; then
        return 0
    fi
    
    echo ""
    echo "Applying expansion packs..."
    
    for expansion in "${expansions[@]}"; do
        copy_expansion_pack "$expansion" "$target_project"
    done
    
    echo ""
    echo "All expansion packs applied."
}

# Function to create .clauderrc file with commit ID
create_clauderrc() {
    local target_claude="$1"
    local clauder_dir="${CLAUDER_DIR:-$(dirname "$(realpath "$0")")}"
    local clauderrc_file="$target_claude/.clauderrc"
    
    # Get the commit ID from the clauder directory
    local commit_id=""
    if [ -d "$clauder_dir/.git" ]; then
        commit_id=$(cd "$clauder_dir" && git rev-parse HEAD 2>/dev/null)
    fi
    
    # If we couldn't get commit ID from git, try to get it from version function
    if [ -z "$commit_id" ]; then
        commit_id=$(cd "$clauder_dir" && git rev-parse HEAD 2>/dev/null || echo "unknown")
    fi
    
    # Create the .clauderrc file with only the commit ID
    echo "$commit_id" > "$clauderrc_file"
    
    if [ $? -eq 0 ]; then
        echo "✓ Created .clauderrc with commit ID: $commit_id"
    else
        echo "⚠ Failed to create .clauderrc file"
        return 1
    fi
}

# Function to apply previously applied expansion packs
apply_previous_expansions() {
    local target_project="$1"
    local target_claude="$target_project/.claude"
    local expansion_packs_file="$target_claude/.expansion_packs"
    
    if [ ! -f "$expansion_packs_file" ]; then
        return 0
    fi
    
    # Read expansion packs from file
    local previous_expansions=()
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            previous_expansions+=("$line")
        fi
    done < "$expansion_packs_file"
    
    if [ ${#previous_expansions[@]} -gt 0 ]; then
        echo ""
        echo "Applying previously installed expansion packs..."
        for expansion in "${previous_expansions[@]}"; do
            copy_expansion_pack "$expansion" "$target_project"
        done
        echo ""
        echo "All previous expansion packs applied."
    fi
}

    # Function to select MCP servers interactively
    select_mcp_servers() {
        local servers=("$@")
        local selected=()
        local current=0
        local total=${#servers[@]}
        local first_display=true
        local clauder_dir="${CLAUDER_DIR:-$(dirname "$(realpath "$0")")}"
        local source_mcp_file="$clauder_dir/.mcp.json"
        
        # Pagination variables
        local servers_per_page=7
        local current_page=0
        local total_pages=$(( (total + servers_per_page - 1) / servers_per_page ))
        local show_warning=false
        
        # Initialize selected array (all false initially)
        for ((i=0; i<total; i++)); do
            selected[i]=false
        done
    
    # Function to print colored text
    print_gray() {
        if colors_supported; then
            echo -n "$(tput setaf 8)$1$(tput sgr0)"
        else
            echo -n "$1"
        fi
    }
    
    print_pink() {
        if colors_supported; then
            echo -n "$(tput setaf 5)$1$(tput sgr0)"
        else
            echo -n "$1"
        fi
    }
    
    print_yellow() {
        if colors_supported; then
            echo -n "$(tput setaf 3)$1$(tput sgr0)"
        else
            echo -n "$1"
        fi
    }
    
    print_green() {
        if colors_supported; then
            echo -n "$(tput setaf 2)$1$(tput sgr0)"
        else
            echo -n "$1"
        fi
    }
    
    # Function to display the menu
    display_menu() {
        # If this is the first display, add lines and clear screen
        if [ "$first_display" = true ]; then
            # Add 400 new lines to push previous content into scrollback buffer
            for ((i=0; i<400; i++)); do
                echo ""
            done
            
            # Now clear the screen
            printf "\033[2J"  # Clear the entire screen
            printf "\033[H"   # Move cursor to top-left corner
        else
            # For subsequent redraws, just clear the screen
            printf "\033[2J"  # Clear the entire screen
            printf "\033[H"   # Move cursor to top-left corner
        fi
        
        # Mark that we've displayed the menu
        first_display=false
        
        # Display the menu
        echo ""
        print_white "Select MCP servers to add to the project:"
        echo ""
        echo ""
        print_gray "Enabling more than 5-7 MCP servers within a single project may significantly degrade performance."
        echo ""
        print_gray "If you need more than that, consider using an MCP gateway."
        echo ""
        echo ""
        print_gray "Avoid enabling servers with similar functionalities, as they may confuse Claude and degrade performance."
        echo ""
        echo ""
        print_gray "Clauder will help you set the required environment variables upon selecting servers."
        echo ""
        print_gray "Use dedicated keys with limited access when possible."
        echo ""
        echo ""
        echo "Press SPACE to select/unselect, ↑/↓ or J/K to navigate, ←/→ to change pages, ENTER to proceed, Q to cancel"
        echo ""
        echo ""
        
        # Calculate start and end indices for current page
        local start_index=$((current_page * servers_per_page))
        local end_index=$((start_index + servers_per_page - 1))
        if [ $end_index -ge $total ]; then
            end_index=$((total - 1))
        fi
        
        # Display servers for current page
        for ((i=start_index; i<=end_index; i++)); do
            local display_index=$((i - start_index))
            local marker="☐"
            local color=""
            local server_name="${servers[i]}"
            
            # Get description for this server
            local description=""
            if [ -f "$source_mcp_file" ]; then
                if command -v jq >/dev/null 2>&1; then
                    description=$(jq -r ".mcpServers.\"$server_name\"._description // empty" "$source_mcp_file" 2>/dev/null)
                else
                    # Fallback: use grep and sed to extract description
                    description=$(grep -A 10 "\"$server_name\":" "$source_mcp_file" | grep "_description" | sed 's/.*"_description": *"\([^"]*\)".*/\1/' 2>/dev/null)
                fi
            fi
            
            # Get category for this server
            local category=""
            if [ -f "$source_mcp_file" ]; then
                if command -v jq >/dev/null 2>&1; then
                    category=$(jq -r ".mcpServers.\"$server_name\"._category // empty" "$source_mcp_file" 2>/dev/null)
                else
                    # Fallback: use grep and sed to extract category
                    category=$(grep -A 10 "\"$server_name\":" "$source_mcp_file" | grep "_category" | sed 's/.*"_category": *"\([^"]*\)".*/\1/' 2>/dev/null)
                fi
            fi
            
            # Get requirements for this server
            local requirements=()
            if [ -f "$source_mcp_file" ]; then
                if command -v jq >/dev/null 2>&1; then
                    # Use jq to extract the _requires array
                    while IFS= read -r req; do
                        if [ -n "$req" ] && [ "$req" != "null" ]; then
                            requirements+=("$req")
                        fi
                    done < <(jq -r ".mcpServers.\"$server_name\"._requires[]? // empty" "$source_mcp_file" 2>/dev/null)
                else
                    # Fallback: use grep and sed to extract requirements
                    local req_line=$(grep -A 20 "\"$server_name\":" "$source_mcp_file" | grep -A 5 "_requires" | grep -E '^\s*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null)
                    if [ -n "$req_line" ]; then
                        requirements+=("$req_line")
                    fi
                fi
            fi
            
            # Format server name with description if available
            local display_name="$server_name"
            local has_description=false
            if [ -n "$description" ]; then
                has_description=true
            fi
            
            if [ $i -eq $current ]; then
                # Current item - highlight with different marker
                if [ "${selected[i]}" = true ]; then
                    marker="⏹"
                    color="pink"
                else
                    marker="☐"
                    color="gray"
                fi
                # Add cursor indicator
                printf "> "
            else
                # Other items
                if [ "${selected[i]}" = true ]; then
                    marker="⏹"
                    color="pink"
                else
                    marker="☐"
                    color="gray"
                fi
                printf "  "
            fi
            
            if [ "$color" = "pink" ]; then
                print_pink "$marker $server_name"
                if [ "$has_description" = true ]; then
                    print_gray " ("
                    print_gray "$description"
                    print_gray ")"
                fi
            else
                print_white "$marker $server_name"
                if [ "$has_description" = true ]; then
                    print_gray " ("
                    print_gray "$description"
                    print_gray ")"
                fi
            fi
            echo ""
            
            # Display category if any
            if [ -n "$category" ]; then
                local category_lower=$(echo "$category" | tr '[:upper:]' '[:lower:]')
                if [ "$category_lower" = "dangerous" ] || [ "$category_lower" = "risky" ]; then
                    printf "    ⚠ "
                    # Show dangerous/risky categories in yellow if selected, gray if not
                    if [ "${selected[i]}" = true ]; then
                        print_yellow "$category"
                    else
                        print_gray "$category"
                    fi
                elif [ "$category_lower" = "recommended" ]; then
                    printf "    ⏣ "
                    # Show recommended categories in green if selected, gray if not
                    if [ "${selected[i]}" = true ]; then
                        print_green "$category"
                    else
                        print_gray "$category"
                    fi
                else
                    printf "    ⏣ "
                    print_gray "$category"
                fi
                echo ""
            fi
            
            # Display requirements if any
            if [ ${#requirements[@]} -gt 0 ]; then
                for req in "${requirements[@]}"; do
                    printf "    ⌙ "
                    if [ "${selected[i]}" = true ]; then
                        echo -n "requires $req"
                    else
                        print_gray "requires $req"
                    fi
                    echo ""
                done
            fi
            
            # Add spacing between options
            echo ""
        done
        
        echo ""
        
        # Count selected servers properly
        local selected_count=0
        local dangerous_selected_count=0
        for ((i=0; i<total; i++)); do
            if [ "${selected[i]}" = true ]; then
                selected_count=$((selected_count+1))
                
                # Check if this server is dangerous
                local server_name="${servers[i]}"
                local category=""
                if [ -f "$source_mcp_file" ]; then
                    if command -v jq >/dev/null 2>&1; then
                        category=$(jq -r ".mcpServers.\"$server_name\"._category // empty" "$source_mcp_file" 2>/dev/null)
                    else
                        # Fallback: use grep and sed to extract category
                        category=$(grep -A 10 "\"$server_name\":" "$source_mcp_file" | grep "_category" | sed 's/.*"_category": *"\([^"]*\)".*/\1/' 2>/dev/null)
                    fi
                fi
                
                local category_lower=$(echo "$category" | tr '[:upper:]' '[:lower:]')
                if [ "$category_lower" = "dangerous" ]; then
                    dangerous_selected_count=$((dangerous_selected_count+1))
                fi
            fi
        done
        
        # Display selection count with warning if too many selected
        if [ $selected_count -gt 5 ]; then
            print_yellow "($selected_count selected - enabling too many servers may significantly degrade performance)"
        else
            print_gray "($selected_count selected)"
        fi
        
        # Display dangerous server warning if any dangerous servers are selected
        if [ $dangerous_selected_count -gt 0 ]; then
            echo ""
            print_yellow "Some of these MCP servers may cause irreversible damages."
            echo ""
            print_yellow "Restrict their accesses through server or token configurations, use isolated environments, and supervise their use."
        fi
        
        # Display pagination info
        if [ $total_pages -gt 1 ]; then
            echo ""
            print_gray "Page $((current_page + 1)) of $total_pages"
        fi
        
        # Show warning if no servers selected and Enter was pressed
        if [ "$show_warning" = true ]; then
            echo ""
            print_yellow "No MCP server selected. Use SPACE to select, or Q to cancel."
        fi
        
        echo ""
    }
    
    # Function to handle key input
    handle_key() {
        local key
        # Use IFS to prevent word splitting and read raw input
        IFS= read -rs -n1 key
        
        # Handle escape sequences (arrow keys)
        if [ "$key" = $'\e' ]; then
            IFS= read -rs -n2 key
            case "$key" in
                '[A') # Up arrow
                    if [ $current -gt 0 ]; then
                        current=$((current-1))
                        # Check if we need to move to previous page
                        local new_page=$((current / servers_per_page))
                        if [ $new_page -lt $current_page ]; then
                            current_page=$new_page
                        fi
                    fi
                    show_warning=false  # Clear warning when user navigates
                    ;;
                '[B') # Down arrow
                    if [ $current -lt $((total-1)) ]; then
                        current=$((current+1))
                        # Check if we need to move to next page
                        local new_page=$((current / servers_per_page))
                        if [ $new_page -gt $current_page ]; then
                            current_page=$new_page
                        fi
                    fi
                    show_warning=false  # Clear warning when user navigates
                    ;;
                '[C') # Right arrow - next page
                    if [ $current_page -lt $((total_pages-1)) ]; then
                        current_page=$((current_page+1))
                        # Adjust current to first item on new page
                        current=$((current_page * servers_per_page))
                    fi
                    show_warning=false  # Clear warning when user navigates
                    ;;
                '[D') # Left arrow - previous page
                    if [ $current_page -gt 0 ]; then
                        current_page=$((current_page-1))
                        # Adjust current to first item on new page
                        current=$((current_page * servers_per_page))
                    fi
                    show_warning=false  # Clear warning when user navigates
                    ;;
                '') # Single escape - cancel
                    return 1
                    ;;
            esac
            return 2  # Continue
        fi
        
        case "$key" in
            " ")  # Space - toggle selection
                if [ "${selected[current]}" = true ]; then
                    selected[current]=false
                else
                    selected[current]=true
                fi
                show_warning=false  # Clear warning when user makes a selection
                ;;
            "")   # Enter - proceed
                # Check if any servers are selected
                local selected_count=0
                for ((i=0; i<total; i++)); do
                    if [ "${selected[i]}" = true ]; then
                        selected_count=$((selected_count+1))
                    fi
                done
                
                if [ $selected_count -eq 0 ]; then
                    # No servers selected - set warning flag and continue
                    show_warning=true
                    return 2
                else
                    # Servers selected - clear warning and proceed
                    show_warning=false
                    return 0
                fi
                ;;
            "j") # j key - down
                if [ $current -lt $((total-1)) ]; then
                    current=$((current+1))
                    # Check if we need to move to next page
                    local new_page=$((current / servers_per_page))
                    if [ $new_page -gt $current_page ]; then
                        current_page=$new_page
                    fi
                fi
                show_warning=false  # Clear warning when user navigates
                ;;
            "k") # k key - up
                if [ $current -gt 0 ]; then
                    current=$((current-1))
                    # Check if we need to move to previous page
                    local new_page=$((current / servers_per_page))
                    if [ $new_page -lt $current_page ]; then
                        current_page=$new_page
                    fi
                fi
                show_warning=false  # Clear warning when user navigates
                ;;
            "q") # q key - quit
                return 1
                ;;
            *)    # Unknown key - ignore
                ;;
        esac
        return 2  # Continue
    }
    
    # Main selection loop
    while true; do
        display_menu
        handle_key
        local result=$?
        
        if [ $result -eq 0 ]; then
            # User pressed enter with selections - proceed
            break
        elif [ $result -eq 1 ]; then
            # User pressed escape - cancel
            echo "Selection cancelled."
            return 1
        elif [ $result -eq 2 ]; then
            # User pressed enter with no selections - show warning at bottom
            # Continue the loop to show menu again with warning
            :
        fi
    done
    
    # Collect selected servers
    local selected_servers=()
    for ((i=0; i<total; i++)); do
        if [ "${selected[i]}" = true ]; then
            selected_servers+=("${servers[i]}")
        fi
    done
    
    if [ ${#selected_servers[@]} -gt 0 ]; then
        # Clear screen and show selected options
        printf "\033[2J"  # Clear the entire screen
        printf "\033[H"   # Move cursor to top-left corner
        
        echo ""
        print_white "Selected MCP servers:"
        echo ""
        for server in "${selected_servers[@]}"; do
            print_pink "  ⏹ $server"
            echo ""
        done
        echo ""
        
        # Check environment variables requirements
        echo "Checking environment variables requirement.."
        echo ""
        
        # Source shell configuration files first to load any existing environment variables
        echo "Loading existing environment variables..."
        # echo ""
        
        # Define shell configuration files
        local shell_files=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc")
        
        for shell_file in "${shell_files[@]}"; do
            if [ -f "$shell_file" ]; then
                . "$shell_file" >/dev/null 2>&1
            fi
        done
        
        # echo ""
        
        # Collect all required environment variables
        local required_vars=()
        local project_name_placeholder_found=false
        
        for server in "${selected_servers[@]}"; do
            # Get requirements for this server
            local requirements=()
            if [ -f "$source_mcp_file" ]; then
                if command -v jq >/dev/null 2>&1; then
                    # Use jq to extract the _requires array
                    while IFS= read -r req; do
                        if [ -n "$req" ] && [ "$req" != "null" ]; then
                            requirements+=("$req")
                        fi
                    done < <(jq -r ".mcpServers.\"$server\"._requires[]? // empty" "$source_mcp_file" 2>/dev/null)
                else
                    # Fallback: use grep and sed to extract requirements
                    local req_line=$(grep -A 20 "\"$server\":" "$source_mcp_file" | grep -A 5 "_requires" | grep -E '^\s*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/' 2>/dev/null)
                    if [ -n "$req_line" ]; then
                        requirements+=("$req_line")
                    fi
                fi
            fi
            
            # Add to required_vars and check for project name placeholder
            for req in "${requirements[@]}"; do
                # Skip "OAuth at runtime" as it's not an environment variable
                if [ "$req" != "OAuth at runtime" ]; then
                    required_vars+=("$req")
                    if [[ "$req" == *"{{PROJECT_NAME}}"* ]]; then
                        project_name_placeholder_found=true
                    fi
                fi
            done
        done
        
        # Remove duplicates from required_vars
        local unique_vars=()
        for var in "${required_vars[@]}"; do
            local found=false
            for unique_var in "${unique_vars[@]}"; do
                if [ "$var" = "$unique_var" ]; then
                    found=true
                    break
                fi
            done
            if [ "$found" = false ]; then
                unique_vars+=("$var")
            fi
        done
        
        # Ask for project name if needed
        local project_name=""
        if [ "$project_name_placeholder_found" = true ]; then
            # echo ""
            echo "Project name required for some MCP servers."
            # echo ""
            print_white "Enter project name (uppercase letters, numbers, and underscores only): "
            read -r project_name
            
            # Validate project name
            while [[ ! "$project_name" =~ ^[A-Z0-9_]+$ ]] || [ -z "$project_name" ]; do
                echo ""
                print_white "Invalid project name. Please use only uppercase letters, numbers, and underscores: "
                read -r project_name
            done
            echo ""
        fi
        
        # Display environment variables if any
        if [ ${#unique_vars[@]} -gt 0 ]; then
            echo ""
            print_white "Required environment variables:"
            echo ""
            
            # Collect missing environment variables
            local missing_vars=()
            for var in "${unique_vars[@]}"; do
                # Replace project name placeholder if present
                local display_var="$var"
                if [ -n "$project_name" ]; then
                    display_var=$(echo "$var" | sed "s/{{PROJECT_NAME}}/$project_name/g")
                fi
                
                # Get current value (first 3 characters + ellipsis)
                # Remove $ prefix for variable access
                local var_name="${display_var/#\$/}"
                local current_value="${!var_name:-}"
                if [ -n "$current_value" ]; then
                    local masked_value="${current_value:0:3}..."
                    print_gray "  $display_var = $masked_value"
                else
                    print_gray "  $display_var = (not set)"
                    missing_vars+=("$display_var")
                fi
                echo ""
            done
            
            # Ask for values and add missing environment variables to shell configuration files
            if [ ${#missing_vars[@]} -gt 0 ]; then
                echo ""
                echo "Please provide values for the missing environment variables:"
                #echo ""
                
                # Collect values for missing environment variables
                local env_values=()
                for var in "${missing_vars[@]}"; do
                    print_white "Enter value for $var: "
                    read -r value
                    env_values+=("$var=$value")
                done
                
                echo ""
                print_white "Adding environment variables to shell configuration files..."
                echo ""
                
                # Define shell configuration files
                local shell_files=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc")
                
                for shell_file in "${shell_files[@]}"; do
                    # Create file if it doesn't exist
                    if [ ! -f "$shell_file" ]; then
                        touch "$shell_file"
                        local display_path="${shell_file/#$HOME/~}"
                        echo "  ✓ Created $display_path"
                    fi
                    
                    # Add environment variables to the file
                    echo "" >> "$shell_file"
                    echo "# MCP Environment Variables - Added by Clauder" >> "$shell_file"
                    for env_pair in "${env_values[@]}"; do
                        # Remove $ prefix from variable name for shell files
                        local clean_pair="${env_pair/#\$/}"
                        echo "export $clean_pair" >> "$shell_file"
                    done
                    echo "# End MCP Environment Variables" >> "$shell_file"
                    echo "" >> "$shell_file"
                    
                    local display_path="${shell_file/#$HOME/~}"
                    echo "  ✓ Added environment variables to $display_path"
                done
                
                echo ""
                echo "Sourcing shell configuration files..."
                echo ""
                
                # Source the shell configuration files
                for shell_file in "${shell_files[@]}"; do
                    if [ -f "$shell_file" ]; then
                        local display_path="${shell_file/#$HOME/~}"
                        if . "$shell_file" >/dev/null 2>&1; then
                            # Silently source successful files
                            :
                        else
                            echo "  ⚠ Failed to source $display_path"
                        fi
                    fi
                done
                
                echo ""
                print_gray "Environment variables have been set with the values you provided."
                echo ""
            fi
        else
            echo ""
            print_gray "No environment variables required."
            echo ""
        fi
        
        # Backup and merge .mcp.json file
        PROJECT_NAME="$project_name" backup_and_merge_mcp_file "$target_project" "${selected_servers[@]}"
    else
        echo "No servers selected."
        echo ""
    fi
}

# Function to clean up old MCP backup files (keep only 5 most recent)
cleanup_old_mcp_backups() {
    local backup_dir="$1"
    
    # Get list of backup files sorted by modification time (newest first)
    # Use macOS compatible find command
    local backups=($(find "$backup_dir" -maxdepth 1 -type f -name ".mcp.json.backup.*" -exec stat -f "%m %N" {} \; | sort -nr | cut -d' ' -f2-))
    
    # Remove backups beyond the 5th one
    if [ ${#backups[@]} -gt 5 ]; then
        local backups_to_remove=()
        i=5
        while [ $i -lt ${#backups[@]} ]; do
            backups_to_remove+=("$(basename "${backups[$i]}")")
            i=$((i + 1))
        done
        
        echo "Found ${#backups_to_remove[@]} old MCP backup(s) to remove (keeping 5 most recent):"
        printf '  %s\n' "${backups_to_remove[@]}"
        echo ""
        print_white "Do you want to remove these old MCP backups? (y/N): "
        read -r reply
        echo
        
        if [[ $reply =~ ^[Yy]$ ]]; then
            echo "Removing old MCP backups..."
            i=5
            while [ $i -lt ${#backups[@]} ]; do
                local old_backup="${backups[$i]}"
                echo "Removing: $(basename "$old_backup")"
                rm -f "$old_backup"
                i=$((i + 1))
            done
            echo "✓ Old MCP backups removed successfully"
        else
            echo "Skipping cleanup of old MCP backups"
        fi
    fi
}

# Function to backup and merge .mcp.json file
backup_and_merge_mcp_file() {
    local target_project="$1"
    shift
    local selected_servers=("$@")
    local clauder_dir="${CLAUDER_DIR:-$(dirname "$(realpath "$0")")}"
    local source_mcp_file="$clauder_dir/.mcp.json"
    local target_mcp_file="$target_project/.mcp.json"
    
    # Get project name from the calling function's scope
    local project_name=""
    # Check if project_name was set in the calling function
    if [ -n "${PROJECT_NAME:-}" ]; then
        project_name="$PROJECT_NAME"
    fi
    
    # Check if source .mcp.json exists
    if [ ! -f "$source_mcp_file" ]; then
        echo "Warning: Source .mcp.json file not found."
        return 1
    fi
    
    # Check if we have selected servers
    if [ ${#selected_servers[@]} -eq 0 ]; then
        return 0
    fi
    
    echo ""
    echo "Configuring MCP servers..."
    
    # Backup existing .mcp.json if it exists
    if [ -f "$target_mcp_file" ]; then
        # Create .claude-mcp-backup directory if it doesn't exist
        local backup_dir="$target_project/.claude-mcp-backup"
        if [ ! -d "$backup_dir" ]; then
            mkdir -p "$backup_dir"
        fi
        
        local backup_file="$backup_dir/.mcp.json.backup.$(date +%Y%m%d_%H%M%S)"
        if cp "$target_mcp_file" "$backup_file" 2>/dev/null; then
            echo "  ✓ Backed up existing .mcp.json to $(basename "$backup_file")"
            
            # Clean up old backups (keep only 5 most recent)
            cleanup_old_mcp_backups "$backup_dir"
        else
            echo "  ⚠ Failed to backup existing .mcp.json"
        fi
    fi
    
    # Create target .mcp.json if it doesn't exist
    if [ ! -f "$target_mcp_file" ]; then
        echo '{"mcpServers": {}}' > "$target_mcp_file"
        echo "  ✓ Created new .mcp.json file"
    fi
    
    # Merge selected servers from source to target
    if command -v jq >/dev/null 2>&1; then
        # Use jq for JSON manipulation
        local temp_file=$(mktemp)
        
        # Read source and target files
        local source_json=$(cat "$source_mcp_file")
        local target_json=$(cat "$target_mcp_file")
        
        # Extract selected servers from source
        local selected_servers_json="{}"
        for server in "${selected_servers[@]}"; do
            local server_config=$(echo "$source_json" | jq -r ".mcpServers.\"$server\" // empty" 2>/dev/null)
            if [ -n "$server_config" ] && [ "$server_config" != "null" ]; then
                # Remove metadata fields (_website, _category, _description, _requires) before adding to target
                local clean_config=$(echo "$server_config" | jq 'del(._website, ._category, ._description, ._requires)' 2>/dev/null)
                
                # Replace PROJECT_NAME placeholder if project_name is provided
                if [ -n "$project_name" ]; then
                    clean_config=$(echo "$clean_config" | sed "s/{{PROJECT_NAME}}/$project_name/g")
                fi
                
                selected_servers_json=$(echo "$selected_servers_json" | jq --arg server "$server" --argjson config "$clean_config" '. + {($server): $config}' 2>/dev/null)
            fi
        done
        
        # Merge selected servers into target, preserving the entire JSON structure
        local merged_json=$(echo "$target_json" | jq --argjson selected "$selected_servers_json" '.mcpServers = (.mcpServers * $selected)' 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$merged_json" ]; then
            echo "$merged_json" > "$temp_file"
            mv "$temp_file" "$target_mcp_file"
            echo "  ✓ Merged selected MCP servers into .mcp.json"
        else
            echo "  ✗ Failed to merge MCP servers using jq"
            rm -f "$temp_file"
            return 1
        fi
    else
        # Fallback: use Python for JSON manipulation
        local temp_file=$(mktemp)
        
        if python3 -c "
import json
import sys
import re

def merge_mcp_servers(target_file, source_file, selected_servers, project_name):
    try:
        # Read source and target files
        with open(source_file, 'r') as f:
            source_data = json.load(f)
        with open(target_file, 'r') as f:
            target_data = json.load(f)
        
        # Ensure mcpServers exists in target
        if 'mcpServers' not in target_data:
            target_data['mcpServers'] = {}
        
        # Add selected servers to target
        for server in selected_servers:
            if server in source_data.get('mcpServers', {}):
                server_config = source_data['mcpServers'][server].copy()
                # Remove metadata fields
                metadata_fields = ['_website', '_category', '_description', '_requires']
                for field in metadata_fields:
                    server_config.pop(field, None)
                
                # Replace PROJECT_NAME placeholder if project_name is provided
                if project_name:
                    # Convert to JSON string, replace, then parse back
                    config_str = json.dumps(server_config)
                    config_str = config_str.replace('{{PROJECT_NAME}}', project_name)
                    server_config = json.loads(config_str)
                
                target_data['mcpServers'][server] = server_config
        
        # Write merged data to temp file
        with open('$temp_file', 'w') as f:
            json.dump(target_data, f, indent=2)
        
        sys.exit(0)
    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        sys.exit(1)
" "$target_mcp_file" "$source_mcp_file" "${selected_servers[@]}" "$project_name" 2>/dev/null; then
            mv "$temp_file" "$target_mcp_file"
            echo "  ✓ Merged selected MCP servers into .mcp.json"
        else
            echo "  ✗ Failed to merge MCP servers using Python"
            rm -f "$temp_file"
            return 1
        fi
    fi
    
    # Display added servers
    echo "  Added MCP servers:"
    for server in "${selected_servers[@]}"; do
        echo "    ✓ $server"
    done
    
    echo ""
    echo "MCP configuration updated successfully."
    echo ""
    print_gray "The newly added MCP servers will be active upon starting Clauder"
}

# Function to check for missing MCP servers
check_missing_mcp_servers() {
    local target_project="$1"
    local clauder_dir="${CLAUDER_DIR:-$(dirname "$(realpath "$0")")}"
    local source_mcp_file="$clauder_dir/.mcp.json"
    local target_claude="$target_project/.claude"
    
    # Check if source .mcp.json exists
    if [ ! -f "$source_mcp_file" ]; then
        return 0
    fi
    
    # Get currently enabled MCP servers
    local enabled_servers=()
    if command -v claude >/dev/null 2>&1; then
        # Change to target project directory to run claude command in correct context
        cd "$target_project" 2>/dev/null || return 0
        
        local mcp_output=$(claude mcp list 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$mcp_output" ]; then
            # Extract server names from the output
            enabled_servers=($(echo "$mcp_output" | grep -E '^[a-zA-Z0-9_-]+:' | sed 's/:.*$//'))
        fi
    fi
    
    # Get recommended MCP servers from source .mcp.json
    local recommended_servers=()
    if command -v jq >/dev/null 2>&1; then
        # Use jq to extract server names
        recommended_servers=($(jq -r '.mcpServers | keys[]' "$source_mcp_file" 2>/dev/null))
    else
        # Fallback: use grep and sed to extract server names
        recommended_servers=($(grep -o '"[^"]*":\s*{' "$source_mcp_file" | sed 's/":\s*{//g' | sed 's/"//g' 2>/dev/null))
    fi
    
    # Find missing servers
    local missing_servers=()
    for recommended in "${recommended_servers[@]}"; do
        local found=false
        for enabled in "${enabled_servers[@]}"; do
            if [ "$recommended" = "$enabled" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            missing_servers+=("$recommended")
        fi
    done
    
    # Sort missing servers: recommended first (alphabetical), then others (alphabetical)
    local recommended_missing=()
    local other_missing=()
    
    for server in "${missing_servers[@]}"; do
        # Get category for this server
        local category=""
        if command -v jq >/dev/null 2>&1; then
            category=$(jq -r ".mcpServers.\"$server\"._category // empty" "$source_mcp_file" 2>/dev/null)
        else
            # Fallback: use grep and sed to extract category
            category=$(grep -A 10 "\"$server\":" "$source_mcp_file" | grep "_category" | sed 's/.*"_category": *"\([^"]*\)".*/\1/' 2>/dev/null)
        fi
        
        local category_lower=$(echo "$category" | tr '[:upper:]' '[:lower:]')
        if [ "$category_lower" = "recommended" ]; then
            recommended_missing+=("$server")
        else
            other_missing+=("$server")
        fi
    done
    
    # Sort each group alphabetically
    IFS=$'\n' recommended_missing=($(sort <<<"${recommended_missing[*]}"))
    IFS=$'\n' other_missing=($(sort <<<"${other_missing[*]}"))
    
    # Combine: recommended first, then others
    missing_servers=("${recommended_missing[@]}" "${other_missing[@]}")
    
    # Display missing servers if any
    if [ ${#missing_servers[@]} -gt 0 ]; then
        echo ""
        echo "Clauder may help you setup any of the following recommended MCP servers:"
        for server in "${missing_servers[@]}"; do
            # Try to get description from .mcp.json
            local description=""
            if command -v jq >/dev/null 2>&1; then
                description=$(jq -r ".mcpServers.\"$server\"._description // empty" "$source_mcp_file" 2>/dev/null)
            else
                # Fallback: use grep and sed to extract description
                description=$(grep -A 10 "\"$server\":" "$source_mcp_file" | grep "_description" | sed 's/.*"_description": *"\([^"]*\)".*/\1/' 2>/dev/null)
            fi
            
            # Try to get category from .mcp.json
            local category=""
            if command -v jq >/dev/null 2>&1; then
                category=$(jq -r ".mcpServers.\"$server\"._category // empty" "$source_mcp_file" 2>/dev/null)
            else
                # Fallback: use grep and sed to extract category
                category=$(grep -A 10 "\"$server\":" "$source_mcp_file" | grep "_category" | sed 's/.*"_category": *"\([^"]*\)".*/\1/' 2>/dev/null)
            fi
            
            # Format server name with description
            local display_name="$server"
            if [ -n "$description" ]; then
                display_name="$server ($description)"
            fi
            
            print_gray "  ☐ $display_name"
            echo ""
        done
        
        # Ask if user wants to setup MCP tools
        echo ""
        print_white "Would you like to setup any of these MCP tools for this project? (y/N): "
        read -r setup_reply
        echo
        
        if [[ $setup_reply =~ ^[Yy]$ ]]; then
            echo ""
            
            # Show interactive selection
            select_mcp_servers "${missing_servers[@]}"
        fi
    fi
}

# Function to display MCP servers
display_mcp_servers() {
    local target_project="$1"
    
    # Change to target project directory to run claude command in correct context
    cd "$target_project" 2>/dev/null || return 0
    
    echo ""
    echo "Scanning available MCP servers.."
    echo "MCP servers are standard tools allowing Claude to interact with other systems."
    echo "Learn more about MCP: https://modelcontextprotocol.io/docs/getting-started/intro"
    echo ""
    echo "MCP servers enabled for this project:"
    
    # Run 'claude mcp list' command and extract server names
    local mcp_output=$(claude mcp list 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$mcp_output" ]; then
        # Extract server names from the output (look for lines with server names followed by status)
        local server_names=$(echo "$mcp_output" | grep -E '^[a-zA-Z0-9_-]+:' | sed 's/:.*$//')
        if [ -n "$server_names" ]; then
            echo "$server_names" | while IFS= read -r server_name; do
                echo "  ☒ $server_name"
            done
        else
            print_gray "  ⌀ (none)"
        fi
    else
        print_gray "  ⌀ (none)"
    fi
}

# Function to copy .claude folder
copy_claude_folder() {
    # Check if CLAUDER_DIR environment variable is set
    if [[ -z "$CLAUDER_DIR" ]]; then
        echo "Error: CLAUDER_DIR environment variable is not set."
        echo "Please run clauder_install.sh first within the 'clauder' directory to set up the environment."
        safe_exit 1
    fi
    
    local source_claude="$CLAUDER_DIR/.claude"
    local target_project="$1"
    local target_claude="$target_project/.claude"
    
    # Check if source .claude exists
    if [ ! -d "$source_claude" ]; then
        echo "Error: Source .claude directory does not exist."
        safe_exit 1
    fi
    
    # Check if target project exists
    check_directory "$target_project"
    
    # Change to target project directory for backup operations
    cd "$target_project"
    
    # Check if target .claude directory exists
    if [ ! -d "$target_claude" ]; then
        # Create target .claude directory if it doesn't exist
        echo "Creating .claude directory in $target_project..."
        mkdir -p "$target_claude"
    else
        # Backup existing .claude directory and check for existing files
        create_backup "$target_claude" "$target_project"
        
        # Check for existing files and prompt for approval
        check_existing_files "$source_claude" "$target_claude"
        if [ $? -ne 0 ]; then
            return 0
        fi
    fi
    
    # Copy all files from source .claude to target .claude
    echo "Source directory: $source_claude"
    echo "Target directory: $target_claude"
    echo "Copying .claude files to $target_claude..."
    
    # Files that need special merging to preserve existing configurations
    local mergeable_files=(".exclude_security_checks" ".ignore" ".immutable" "preferences.json") # settings.json is not mergeable to ensure working operations upon auto-updates, for custom settings use .claude/settings.local.json instead
    
    # Track successful and failed copies
    local successful_copies=()
    local failed_copies=()
    
    # Copy each file individually to track success/failure
    while IFS= read -r -d '' source_file; do
        # Get relative path from source
        local relative_path="${source_file#$source_claude/}"
        local target_file="$target_claude/$relative_path"
        
        # Create target directory if it doesn't exist
        local target_dir=$(dirname "$target_file")
        if [ ! -d "$target_dir" ]; then
            mkdir -p "$target_dir"
        fi
        
        # Check if this is a mergeable file
        local filename=$(basename "$relative_path")
        local should_merge=false
        
        for mergeable_file in "${mergeable_files[@]}"; do
            if [ "$filename" = "$mergeable_file" ]; then
                should_merge=true
                break
            fi
        done
        
        # Handle file copying/merging
        if [ "$filename" = ".agent-runs.json" ] && [ -f "$target_file" ]; then
            # Per-project state (sub-agent last-run markers): create once, never overwrite
            successful_copies+=("$relative_path (kept, project state)")
        elif [ "$should_merge" = true ] && [ -f "$target_file" ]; then
            # Merge with existing configuration to preserve custom settings
            if [[ "$filename" == *.json ]]; then
                if merge_json_files "$target_file" "$source_file"; then
                    successful_copies+=("$relative_path (merged)")
                else
                    failed_copies+=("$relative_path (merge failed)")
                fi
            else
                if merge_text_files "$target_file" "$source_file"; then
                    successful_copies+=("$relative_path (merged)")
                else
                    failed_copies+=("$relative_path (merge failed)")
                fi
            fi
        elif is_customized_file "$relative_path" "$target_file" "$source_file" "$target_claude" ".claude"; then
            # Keep the user's customised agent or skill and flag it
            KEPT_CUSTOM_FILES+=("$relative_path|$source_file")
            successful_copies+=("$relative_path (kept, customised)")
        else
            # Copy the file normally (overwrite if it doesn't exist or isn't mergeable)
            if cp -f "$source_file" "$target_file" 2>/dev/null; then
                successful_copies+=("$relative_path")
            else
                failed_copies+=("$relative_path")
                echo "Failed to copy: $source_file -> $target_file" >&2
            fi
        fi
    done < <(find "$source_claude" -type f -print0 2>/dev/null)
    
    # Display results
    if [ ${#successful_copies[@]} -gt 0 ]; then
        echo "Successfully copied files:"
        printf '  ✓ %s\n' "${successful_copies[@]}"
    fi
    
    if [ ${#failed_copies[@]} -gt 0 ]; then
        echo "Failed to copy files:"
        printf '  ✗ %s\n' "${failed_copies[@]}"
    fi
    
    if [ ${#failed_copies[@]} -eq 0 ]; then
        echo "All files copied successfully."
    else
        echo "Some files could not be copied, but continuing with activation..."
    fi
    
    # Flag customised agents/skills that were kept instead of overwritten
    report_kept_custom_files
    
    # Create .clauderrc file to track the commit ID
    create_clauderrc "$target_claude"
    
    echo "Successfully activated Claude configuration in $target_project"
    echo "You can now use Claude in this project with your custom configuration."
    
    # Display MCP servers if available
    display_mcp_servers "$target_project"
    
    # Check for missing MCP servers
    check_missing_mcp_servers "$target_project"
}

# Main script logic
main() {
    # Check if current directory is named 'clauder'
    check_current_directory
    
    # Parse arguments
    local target_path="."
    local expansions=()
    local i=1
    
    while [ $i -le $# ]; do
        case "${!i}" in
            -h|--help)
                usage
                ;;
            -v|--version)
                version
                ;;
            --expansions)
                # Collect expansion names
                i=$((i + 1))
                while [ $i -le $# ] && [[ "${!i}" != -* ]]; do
                    expansions+=("${!i}")
                    i=$((i + 1))
                done
                continue
                ;;
            -*)
                echo "Error: Unknown option '${!i}'"
                usage
                ;;
            *)
                if [ "$target_path" = "." ]; then
                    target_path="${!i}"
                else
                    echo "Error: Multiple target paths specified"
                    usage
                fi
                ;;
        esac
        i=$((i + 1))
    done
    
    # Check if we're trying to activate in the clauder directory itself
    check_clauder_directory_activation "$target_path"
    
    # Copy the .claude folder
    copy_claude_folder "$target_path"
    
    # Apply previously applied expansion packs first
    apply_previous_expansions "$target_path"
    
    # Apply new expansion packs if specified (these will override previous ones)
    if [ ${#expansions[@]} -gt 0 ]; then
        apply_expansion_packs "$target_path" "${expansions[@]}"
    fi
    
    # Flag customised agents/skills that were kept instead of overwritten
    report_kept_custom_files
}

# Run main function with all arguments
main "$@"

# If running in interactive mode and this script was executed (not sourced),
# keep the terminal open by waiting for user input
if [[ "$INTERACTIVE" == "true" && "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo ""
    echo "Activation complete. Press Enter to continue..."
    read -r
    echo ">>"
    echo ""
    echo ""
fi
