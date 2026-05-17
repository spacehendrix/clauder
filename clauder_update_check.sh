#!/bin/bash

# Script to check for clauder updates and handle the update process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DARK_GRAY='\033[90m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if we're in a git repository
check_git_repo() {
    local dir="$1"
    git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Function to check for updates
check_for_updates() {
    local clauder_dir="$1"
    local original_dir="$2"
    local update_needed_var="$3"  # Variable name to set
    
    if ! check_git_repo "$clauder_dir"; then
        print_status $YELLOW "⚠️  Clauder directory is not a git repository. Skipping update check."
        eval "$update_needed_var=false"
        return 0
    fi
    
    # Change to clauder directory
    cd "$clauder_dir"
    
    # Fetch latest changes
    print_status $BLUE "🔍 Checking for updates..."
    
    # Display directory information after the checking message
    print_status $DARK_GRAY "Clauder directory: $clauder_dir"
    print_status $DARK_GRAY "Project directory: $original_dir"
    
    git fetch origin main > /dev/null 2>&1 || {
        print_status $RED "❌ Failed to fetch updates from remote repository"
        cd "$original_dir"
        eval "$update_needed_var=false"
        return 0
    }
    
    # Check if local is behind remote
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse origin/main)
    
    if [[ "$local_commit" != "$remote_commit" ]]; then
        print_status $YELLOW "🔄 Update available for clauder!"
        print_status $BLUE "Local:  $(git rev-parse --short HEAD)"
        print_status $BLUE "Remote: $(git rev-parse --short origin/main)"
        cd "$original_dir"
        eval "$update_needed_var=true"
        return 0
    else
        print_status $GREEN "✅ Clauder is up to date"
        print_status $DARK_GRAY "Current commit: $(git rev-parse --short HEAD)"
        cd "$original_dir"
        eval "$update_needed_var=false"
        return 0
    fi
}

# Function to perform update
perform_update() {
    local clauder_dir="$1"
    local original_dir="$2"
    
    print_status $BLUE "🔄 Updating clauder..."
    
    # Change to clauder directory
    cd "$clauder_dir"
    
    # Pull latest changes
    git pull origin main || {
        print_status $RED "❌ Failed to pull latest changes"
        return 0
    }
    
    print_status $GREEN "✅ Successfully pulled latest changes"
    
    # Reinstall clauder
    print_status $BLUE "🔧 Reinstalling clauder..."
    bash ./clauder_install.sh || {
        print_status $RED "❌ Failed to reinstall clauder"
        return 0
    }
    
    print_status $GREEN "✅ Clauder reinstalled successfully"
    
    # Return to original directory
    cd "$original_dir"
    
    # Ask for user approval before activating
    echo
    print_status $YELLOW "🔄 UPDATE COMPLETE: Would you like to activate the latest version of clauder in the current project? (y/n)"
    print_status $DARK_GRAY "Current project: $original_dir"
    read -r activate_response
    
            case "$activate_response" in
            [yY]|[yY][eE][sS])
                print_status $BLUE "🔧 Activating clauder in current directory..."
                # Ensure we're in the original directory where the user ran the command
                cd "$original_dir"
                # Call the activate script directly instead of relying on alias
                bash "$clauder_dir/clauder_activate.sh" "$original_dir" || {
                    print_status $RED "❌ Failed to activate clauder"
                    return 0
                }
                print_status $GREEN "✅ Clauder updated and activated successfully!"
                ;;
        [nN]|[nN][oO])
            print_status $BLUE "Skipping activation."
            print_status $YELLOW "⚠️  Clauder was updated but the latest version was not applied to this project."
            print_status $BLUE "You can re-run 'clauder_activate' to apply the latest changes."
            ;;
        *)
            print_status $RED "Invalid response. Skipping activation."
            print_status $YELLOW "⚠️  Clauder was updated but the latest version was not applied to this project."
            print_status $BLUE "You can re-run 'clauder_activate' to apply the latest changes."
            ;;
    esac
    
    return 0
}

# Function to check target .claude/.clauderrc file
check_target_clauderrc() {
    local clauder_dir="$1"
    local target_dir="$2"
    local clauderrc_file="$target_dir/.claude/.clauderrc"
    
    # Check if .claude/.clauderrc exists
    if [[ ! -f "$clauderrc_file" ]]; then
        print_status $YELLOW "⚠️  No .claude/.clauderrc found in target project"
        return 1  # Needs activation
    fi
    
    # Get current clauder commit
    local current_clauder_commit=""
    if [[ -d "$clauder_dir/.git" ]]; then
        current_clauder_commit=$(cd "$clauder_dir" && git rev-parse HEAD 2>/dev/null)
    fi
    
    if [[ -z "$current_clauder_commit" ]]; then
        print_status $YELLOW "⚠️  Could not determine clauder commit ID"
        return 1  # Needs activation
    fi
    
    # Read the commit ID from .clauderrc
    local target_commit=""
    if [[ -f "$clauderrc_file" ]]; then
        target_commit=$(cat "$clauderrc_file" 2>/dev/null | tr -d '\n\r')
    fi
    
    if [[ -z "$target_commit" ]]; then
        print_status $YELLOW "⚠️  .claude/.clauderrc is empty or unreadable"
        return 1  # Needs activation
    fi
    
    # Compare commit IDs
    if [[ "$target_commit" != "$current_clauder_commit" ]]; then
        print_status $YELLOW "🔄 Target project has different clauder version"
        print_status $BLUE "Target:  $(echo "$target_commit" | cut -c1-8)"
        print_status $BLUE "Current: $(echo "$current_clauder_commit" | cut -c1-8)"
        return 1  # Needs activation
    fi
    
    print_status $GREEN "✅ Target project is up to date with current clauder version"
    return 0  # No activation needed
}

# Function to prompt for activation
prompt_for_activation() {
    local clauder_dir="$1"
    local target_dir="$2"
    
    echo
    print_status $YELLOW "Would you like to activate the current clauder version in this project? (y/n)"
    print_status $DARK_GRAY "This will backup existing .claude configuration and apply the latest clauder settings."
    read -r response
    
    case "$response" in
        [yY]|[yY][eE][sS])
            print_status $BLUE "🔧 Activating clauder in current directory..."
            # Call the activate script directly
            bash "$clauder_dir/clauder_activate.sh" "$target_dir" || {
                print_status $RED "❌ Failed to activate clauder"
                return 1
            }
            print_status $GREEN "✅ Clauder activated successfully!"
            return 0
            ;;
        [nN]|[nN][oO])
            print_status $BLUE "Skipping activation. Continuing with current configuration..."
            return 0
            ;;
        *)
            print_status $RED "Invalid response. Skipping activation."
            return 0
            ;;
    esac
}

# Function to prompt user for update
prompt_for_update() {
    local clauder_dir="$1"
    local original_dir="$2"
    
    echo
    print_status $YELLOW "Would you like to update clauder? (y/n)"
    read -r response
    
    case "$response" in
        [yY]|[yY][eE][sS])
            perform_update "$clauder_dir" "$original_dir"
            return 0
            ;;
        [nN]|[nN][oO])
            print_status $BLUE "Skipping update. Continuing with current version..."
            return 0
            ;;
        *)
            print_status $RED "Invalid response. Skipping update."
            return 0
            ;;
    esac
}

# Main function
main() {
    # Capture the original directory BEFORE any changes
    local original_dir="$(pwd)"
    local clauder_dir="${CLAUDER_DIR:-$(dirname "$(realpath "$0")")}"
    
    # Check for updates and get the result
    local update_needed=false
    check_for_updates "$clauder_dir" "$original_dir" "update_needed"
    
    # Only prompt for update if an update is actually needed
    if [ "$update_needed" = true ]; then
        prompt_for_update "$clauder_dir" "$original_dir"
    fi
    
    # Check if target project needs activation (regardless of whether update was needed)
    if ! check_target_clauderrc "$clauder_dir" "$original_dir"; then
        prompt_for_activation "$clauder_dir" "$original_dir"
    fi
}

# Run main function
main "$@" 