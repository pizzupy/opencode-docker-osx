#!/usr/bin/env bash
#
# Wrapper for opencode that ensures terminal cleanup on exit
#

# Save terminal state
SAVED_TERM_STATE=$(stty -g 2>/dev/null || true)

# Cleanup function
cleanup() {
    local exit_code=$?
    
    # Reset terminal state
    # Disable bracketed paste mode
    printf '\e[?2004l' 2>/dev/null || true
    # Show cursor (in case it was hidden)
    printf '\e[?25h' 2>/dev/null || true
    # Reset colors and attributes
    printf '\e[0m' 2>/dev/null || true
    
    # Restore saved terminal state if available
    if [ -n "$SAVED_TERM_STATE" ]; then
        stty "$SAVED_TERM_STATE" 2>/dev/null || true
    else
        # Fallback to sane defaults
        stty sane 2>/dev/null || true
    fi
    
    exit $exit_code
}

# Register cleanup
trap cleanup EXIT INT TERM

# Run opencode with all arguments
exec opencode "$@"
