
#!/bin/bash

# goal:
# this script run speedtest-cli (ubuntu version) against multiple servers to get more comprehensive results.
# server list can be obtained by: speedtest-cli --list (has to parse id)
# run against a server id: speedtest-cli --server id

# Configuration
DEFAULT_SERVER_COUNT=5
HOSTNAME=$(hostname)
RESULTS_DIR="speedtest_results/commu/$HOSTNAME"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if speedtest-cli is installed
check_speedtest() {
    if ! command -v speedtest-cli &> /dev/null; then
        print_status $RED "Error: speedtest-cli is not installed"
        echo "Install it with: sudo apt-get install speedtest-cli"
        exit 1
    fi
}

# Function to create results directory
create_results_dir() {
    mkdir -p "$RESULTS_DIR"
}

# Function to get server list and extract IDs
get_server_list() {
    print_status $BLUE "Fetching server list..."
    speedtest-cli --list | grep -E '^\s*[0-9]+\)' | head -50 | sed 's/^[[:space:]]*//g' > "$RESULTS_DIR/servers_${TIMESTAMP}.txt"
    
    if [ ! -s "$RESULTS_DIR/servers_${TIMESTAMP}.txt" ]; then
        print_status $RED "Error: Could not fetch server list"
        exit 1
    fi
    
    print_status $GREEN "Found $(wc -l < "$RESULTS_DIR/servers_${TIMESTAMP}.txt") servers"
}

# Function to select random servers
select_servers() {
    local count=${1:-0}
    
    if [ "$count" -eq 0 ]; then
        # Select all servers if no count specified
        cut -d')' -f1 "$RESULTS_DIR/servers_${TIMESTAMP}.txt" > "$RESULTS_DIR/selected_servers_${TIMESTAMP}.txt"
        local total_servers=$(wc -l < "$RESULTS_DIR/selected_servers_${TIMESTAMP}.txt")
        print_status $BLUE "Selected all $total_servers servers for testing"
    else
        # Select specified number of random servers
        cut -d')' -f1 "$RESULTS_DIR/servers_${TIMESTAMP}.txt" | shuf | head -$count > "$RESULTS_DIR/selected_servers_${TIMESTAMP}.txt"
        print_status $BLUE "Selected $count random servers for testing"
    fi
}

# Function to run speedtest against a server
run_speedtest() {
    local server_id=$1
    local server_info=$(grep "^${server_id})" "$RESULTS_DIR/servers_${TIMESTAMP}.txt")
    
    print_status $YELLOW "Testing server: $server_info"
    
    local output_file="$RESULTS_DIR/speedtest_${server_id}_${TIMESTAMP}.txt"
    
    # Run speedtest and capture output
    if speedtest-cli --server $server_id --simple > "$output_file" 2>&1; then
        print_status $GREEN "✓ Server $server_id test completed"
        return 0
    else
        print_status $RED "✗ Server $server_id test failed"
        return 1
    fi
}

# Function to analyze results
analyze_results() {
    print_status $BLUE "\nAnalyzing results..."
    
    local total_download=0
    local total_upload=0
    local successful_tests=0
    local failed_tests=0
    
    # Create summary file
    local summary_file="$RESULTS_DIR/summary_${TIMESTAMP}.txt"
    echo "Speedtest Summary - $(date)" > "$summary_file"
    echo "=======================================" >> "$summary_file"
    
    # Process each result file
    for result_file in "$RESULTS_DIR"/speedtest_*_${TIMESTAMP}.txt; do
        if [ -f "$result_file" ]; then
            if grep -q "Download\|Upload" "$result_file"; then
                # Extract speeds
                local download=$(grep "Download" "$result_file" | awk '{print $2}')
                local upload=$(grep "Upload" "$result_file" | awk '{print $2}')
                local server_id=$(basename "$result_file" | sed "s/speedtest_//g" | sed "s/_${TIMESTAMP}.txt//g")
                local server_info=$(grep "^${server_id})" "$RESULTS_DIR/servers_${TIMESTAMP}.txt" 2>/dev/null || echo "Server $server_id")
                
                if [ -n "$download" ] && [ -n "$upload" ]; then
                    echo "Server $server_info: Download ${download} Mbit/s, Upload ${upload} Mbit/s" >> "$summary_file"
                    total_download=$(echo "$total_download + $download" | bc -l 2>/dev/null || echo "$total_download")
                    total_upload=$(echo "$total_upload + $upload" | bc -l 2>/dev/null || echo "$total_upload")
                    ((successful_tests++))
                fi
            else
                ((failed_tests++))
            fi
        fi
    done
    
    # Calculate averages
    if [ $successful_tests -gt 0 ]; then
        local avg_download=$(echo "scale=2; $total_download / $successful_tests" | bc -l 2>/dev/null || echo "N/A")
        local avg_upload=$(echo "scale=2; $total_upload / $successful_tests" | bc -l 2>/dev/null || echo "N/A")
        
        echo "" >> "$summary_file"
        echo "Summary Statistics:" >> "$summary_file"
        echo "Successful tests: $successful_tests" >> "$summary_file"
        echo "Failed tests: $failed_tests" >> "$summary_file"
        echo "Average Download: ${avg_download} Mbit/s" >> "$summary_file"
        echo "Average Upload: ${avg_upload} Mbit/s" >> "$summary_file"
        
        print_status $GREEN "\nResults Summary:"
        print_status $GREEN "Average Download: ${avg_download} Mbit/s"
        print_status $GREEN "Average Upload: ${avg_upload} Mbit/s"
        print_status $GREEN "Successful tests: $successful_tests, Failed: $failed_tests"
    else
        print_status $RED "No successful tests completed"
    fi
    
    print_status $BLUE "Detailed results saved to: $summary_file"
}

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n COUNT    Number of servers to test (default: all servers)"
    echo "  -s FILE     Use specific server IDs from file (one ID per line)"
    echo "  -h          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Test all available servers"
    echo "  $0 -n 10              # Test 10 random servers"
    echo "  $0 -s my_servers.txt  # Test servers from file"
}

# Main function
main() {
    local server_count=0  # Default to 0 (test all servers)
    local server_file=""
    
    # Parse command line arguments
    while getopts "n:s:h" opt; do
        case $opt in
            n) server_count=$OPTARG ;;
            s) server_file=$OPTARG ;;
            h) show_help; exit 0 ;;
            \?) echo "Invalid option: -$OPTARG" >&2; show_help; exit 1 ;;
        esac
    done
    
    print_status $BLUE "Starting multi-server speedtest..."
    
    # Check prerequisites
    check_speedtest
    create_results_dir
    
    # Get server list if not using custom file
    if [ -z "$server_file" ]; then
        get_server_list
        select_servers $server_count
    else
        if [ ! -f "$server_file" ]; then
            print_status $RED "Error: Server file '$server_file' not found"
            exit 1
        fi
        cp "$server_file" "$RESULTS_DIR/selected_servers_${TIMESTAMP}.txt"
    fi
    
    # Run tests
    print_status $BLUE "\nStarting speedtests..."
    while IFS= read -r server_id; do
        if [ -n "$server_id" ]; then
            run_speedtest "$server_id"
            sleep 2  # Brief pause between tests
        fi
    done < "$RESULTS_DIR/selected_servers_${TIMESTAMP}.txt"
    
    # Analyze and display results
    analyze_results
    
    print_status $GREEN "\nMulti-server speedtest completed!"
    print_status $BLUE "All results saved to: $RESULTS_DIR"
}

# Run main function
main "$@"
