#!/bin/bash
# Script to monitor the progress of the WGS pipeline

clear
echo "====================================================="
echo "        PRECISIONGENE PIPELINE LIVE MONITOR"
echo "====================================================="

TIMELINE="log/local_runs/timeline.log"

if [[ ! -f "$TIMELINE" ]]; then
    echo "Timeline log not found! Pipeline may not have started yet."
    exit 1
fi

# Use watch to update the view every 2 seconds
watch -n 2 -c "
echo -e '\033[1;36m=====================================================\033[0m'
echo -e '\033[1;36m           PIPELINE STATUS (Press Ctrl+C to exit)\033[0m'
echo -e '\033[1;36m=====================================================\033[0m'
echo -e '\033[1;33m>>> Most Recent Pipeline Steps <<<\033[0m'
tail -n 15 $TIMELINE | awk '{
    if (\$0 ~ /START/) print \"\033[1;34m\" \$0 \"\033[0m\"
    else if (\$0 ~ /SUCCESS/) print \"\033[1;32m\" \$0 \"\033[0m\"
    else if (\$0 ~ /SKIP/) print \"\033[1;30m\" \$0 \"\033[0m\"
    else if (\$0 ~ /FAIL/) print \"\033[1;31m\" \$0 \"\033[0m\"
    else print \$0
}'
echo ''
echo -e '\033[1;33m>>> Currently Active Bakta Jobs <<<\033[0m'
ps aux | grep '[b]akta' | awk '{print \$2, \$11, \$12, \$13}' || echo 'No active Bakta process'
echo ''
echo -e '\033[1;33m>>> Latest Output Files Generated <<<\033[0m'
find results -type f -not -name '*.log' -printf '%T+ %p\n' 2>/dev/null | sort -r | head -n 8 | awk '{print \"\033[0;36m\" \$1 \"\033[0m\", \$2}'
"
