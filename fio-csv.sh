#!/bin/bash

# ===== CONFIGURATION =====
TEST_DIR="${1:-.}"                     # directory for test file (default: current dir)
OUTPUT_CSV="fio_randrw_results.csv"    # output CSV filename
RUNTIME=60                             # seconds per test
IODEPTH=1                              # queue depth
SIZE="1G"                              # size of test file
RW_MIXREAD=70                          # 70% reads, 30% writes
BLOCK_SIZES=("4k" "16k" "32k" "64k" "128k" "512k" "1m")
# =========================

# Check dependencies
command -v fio >/dev/null 2>&1 || { echo "Error: fio not found"; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "Error: jq not found"; exit 1; }
command -v bc  >/dev/null 2>&1 || { echo "Error: bc not found"; exit 1; }

# Create test file path (unique to avoid conflicts)
TEST_FILE="${TEST_DIR}/fio_test_file_$$"

# Cleanup on exit
cleanup() { rm -f "$TEST_FILE"; }
trap cleanup EXIT

# Write CSV header
echo "bs,rwmixread,read_iops,write_iops,read_bw_mbs,write_bw_mbs,read_lat_avg_us,write_lat_avg_us" > "$OUTPUT_CSV"

# Run a single randrw test and append one row to CSV
run_fio_randrw() {
    local bs=$1
    local output_json
    local read_iops write_iops read_bw write_bw read_lat_ns write_lat_ns
    local read_bw_mbs write_bw_mbs read_lat_us write_lat_us

    echo "Running randrw (${RW_MIXREAD}% read) with bs=${bs} ..."

    output_json=$(fio --name=test \
        --filename="$TEST_FILE" \
        --size="$SIZE" \
        --rw=randrw \
        --rwmixread="$RW_MIXREAD" \
        --bs="$bs" \
        --iodepth="$IODEPTH" \
        --direct=1 \
        --runtime="$RUNTIME" \
        --time_based \
        --ioengine=libaio \
        --group_reporting \
        --output-format=json 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$output_json" ]; then
        echo "  ERROR: fio failed for bs=${bs}"
        return 1
    fi

    # Extract read metrics
    read_iops=$(echo "$output_json" | jq '.jobs[0].read.iops')
    read_bw=$(echo "$output_json" | jq '.jobs[0].read.bw')          # bytes/sec
    read_lat_ns=$(echo "$output_json" | jq '.jobs[0].read.lat_ns.mean')
    # Extract write metrics
    write_iops=$(echo "$output_json" | jq '.jobs[0].write.iops')
    write_bw=$(echo "$output_json" | jq '.jobs[0].write.bw')
    write_lat_ns=$(echo "$output_json" | jq '.jobs[0].write.lat_ns.mean')

    # Convert bandwidth from B/s to MiB/s
    read_bw_mbs=$(echo "scale=2; $read_bw / 1048576" | bc)
    write_bw_mbs=$(echo "scale=2; $write_bw / 1048576" | bc)
    # Convert latency from ns to µs
    read_lat_us=$(echo "scale=2; $read_lat_ns / 1000" | bc)
    write_lat_us=$(echo "scale=2; $write_lat_ns / 1000" | bc)

    # Append to CSV
    echo "$bs,$RW_MIXREAD,$read_iops,$write_iops,$read_bw_mbs,$write_bw_mbs,$read_lat_us,$write_lat_us" >> "$OUTPUT_CSV"
}

# Main loop over all block sizes
for bs in "${BLOCK_SIZES[@]}"; do
    run_fio_randrw "$bs"
done

echo "All tests completed. Results saved to $OUTPUT_CSV"