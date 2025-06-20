#!/bin/bash
# Utility script to ensure dashboard is always running
# Can be called from other scripts or added to cron

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure dashboard is running
"$SCRIPT_DIR/start-dashboard.sh" ensure

exit 0