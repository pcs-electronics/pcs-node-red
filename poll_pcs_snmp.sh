#!/usr/bin/env bash

set -u

IP="${1:-192.168.1.140}"
COMMUNITY="${2:-public}"
MIB_DIR="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

MAX_OIDS_PER_GET=5
EXPECTED_COUNT=21

SYMBOLIC_OIDS=(
  "PCS-ELECTRONICS-MIB::pcsDeviceObjectId.0"
  "PCS-ELECTRONICS-MIB::txForwardPower.0"
  "PCS-ELECTRONICS-MIB::txReflectedPower.0"
  "PCS-ELECTRONICS-MIB::txPowerPercent.0"
  "PCS-ELECTRONICS-MIB::txInternalTemperature.0"
  "PCS-ELECTRONICS-MIB::txExternalTemperature.0"
  "PCS-ELECTRONICS-MIB::txAlarmBits.0"
  "PCS-ELECTRONICS-MIB::txPAConnected.0"
  "PCS-ELECTRONICS-MIB::txAlarmCodeNow.0"
  "PCS-ELECTRONICS-MIB::txAlarmCodeLatched.0"
  "PCS-ELECTRONICS-MIB::txExciterVoltage.0"
  "PCS-ELECTRONICS-MIB::txPAVoltage.0"
  "PCS-ELECTRONICS-MIB::txPA2Voltage.0"
  "PCS-ELECTRONICS-MIB::txExciterCurrent.0"
  "PCS-ELECTRONICS-MIB::txPACurrent.0"
  "PCS-ELECTRONICS-MIB::txAudioInputSource.0"
  "PCS-ELECTRONICS-MIB::txAudioGain.0"
  "PCS-ELECTRONICS-MIB::txVULeft.0"
  "PCS-ELECTRONICS-MIB::txVURight.0"
  "PCS-ELECTRONICS-MIB::txStereoChannels.0"
  "PCS-ELECTRONICS-MIB::txFrequencykHz.0"
)

NUMERIC_OIDS=(
  "1.3.6.1.4.1.65081.1.1.0"
  "1.3.6.1.4.1.65081.1.2.1.0"
  "1.3.6.1.4.1.65081.1.2.2.0"
  "1.3.6.1.4.1.65081.1.2.3.0"
  "1.3.6.1.4.1.65081.1.3.1.0"
  "1.3.6.1.4.1.65081.1.3.2.0"
  "1.3.6.1.4.1.65081.1.4.1.0"
  "1.3.6.1.4.1.65081.1.4.2.0"
  "1.3.6.1.4.1.65081.1.4.3.0"
  "1.3.6.1.4.1.65081.1.4.4.0"
  "1.3.6.1.4.1.65081.1.5.1.0"
  "1.3.6.1.4.1.65081.1.5.2.0"
  "1.3.6.1.4.1.65081.1.5.3.0"
  "1.3.6.1.4.1.65081.1.6.1.0"
  "1.3.6.1.4.1.65081.1.6.2.0"
  "1.3.6.1.4.1.65081.1.7.1.0"
  "1.3.6.1.4.1.65081.1.7.2.0"
  "1.3.6.1.4.1.65081.1.7.3.0"
  "1.3.6.1.4.1.65081.1.7.4.0"
  "1.3.6.1.4.1.65081.1.7.5.0"
  "1.3.6.1.4.1.65081.1.8.1.0"
)

RAW_LINES=()

push_lines() {
  local text="$1"
  local line
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    case "$line" in
      "Wrong Type ("*) continue ;;
    esac
    RAW_LINES+=("$line")
  done <<< "$text"
}

collect_chunked() {
  local mode="$1"
  local oids=("${@:2}")
  local args=()
  local start=0
  local count="${#oids[@]}"

  while [ "$start" -lt "$count" ]; do
    args=()
    local end=$((start + MAX_OIDS_PER_GET))
    if [ "$end" -gt "$count" ]; then
      end="$count"
    fi
    while [ "$start" -lt "$end" ]; do
      args+=("${oids[$start]}")
      start=$((start + 1))
    done

    local out
    if [ "$mode" = "symbolic" ]; then
      out="$(snmpget -v2c -c "$COMMUNITY" -M "+$MIB_DIR" -m +PCS-ELECTRONICS-MIB -Oqv "$IP" "${args[@]}" 2>/dev/null)" || return 1
    else
      out="$(snmpget -m '' -v2c -c "$COMMUNITY" -Oqv "$IP" "${args[@]}")" || return 1
    fi
    push_lines "$out"
  done
}

enum_to_num() {
  local value="$1"
  local map_type="$2"
  case "$map_type:$value" in
    alarm:noAlarm) echo "0" ;;
    alarm:extTemp) echo "1" ;;
    alarm:highSWR) echo "2" ;;
    alarm:intTemp) echo "3" ;;
    alarm:highCurrent) echo "4" ;;
    alarm:highVoltage) echo "5" ;;
    alarm:noExciter) echo "6" ;;
    source:analogInput) echo "0" ;;
    source:aesEbu) echo "1" ;;
    source:i2s1) echo "2" ;;
    source:i2s2) echo "3" ;;
    stereo:mpxLeft) echo "0" ;;
    stereo:mpxRight) echo "1" ;;
    stereo:stereo) echo "2" ;;
    stereo:monoLeftPlusRight) echo "3" ;;
    *) echo "$value" ;;
  esac
}

num_prefix() {
  local value="$1"
  if [[ "$value" =~ ^[-+]?[0-9]+ ]]; then
    echo "${BASH_REMATCH[0]}"
  else
    echo "$value"
  fi
}

normalize_line() {
  local idx="$1"
  local value="$2"
  value="${value#\"}"
  value="${value%\"}"

  case "$idx" in
    0) echo "$value" ;;                                 # pcsDeviceObjectId
    8|9) echo "$(enum_to_num "$value" "alarm")" ;;      # txAlarmCodeNow/Latched
    15) echo "$(enum_to_num "$value" "source")" ;;      # txAudioInputSource
    19) echo "$(enum_to_num "$value" "stereo")" ;;      # txStereoChannels
    *) echo "$(num_prefix "$value")" ;;
  esac
}

# Try symbolic names first (chunked, max 5 OIDs per snmpget).
# If symbolic polling fails OR returns incomplete value count (type-mismatch cases),
# retry everything in numeric mode.
RAW_LINES=()
if collect_chunked "symbolic" "${SYMBOLIC_OIDS[@]}"; then
  if [ "${#RAW_LINES[@]}" -ne "$EXPECTED_COUNT" ]; then
    RAW_LINES=()
    collect_chunked "numeric" "${NUMERIC_OIDS[@]}"
  fi
else
  RAW_LINES=()
  collect_chunked "numeric" "${NUMERIC_OIDS[@]}"
fi

if [ "${#RAW_LINES[@]}" -ne "$EXPECTED_COUNT" ]; then
  echo "Expected $EXPECTED_COUNT SNMP values, got ${#RAW_LINES[@]}" >&2
  printf '%s\n' "${RAW_LINES[@]}" >&2
  exit 1
fi

for i in "${!RAW_LINES[@]}"; do
  normalize_line "$i" "${RAW_LINES[$i]}"
done
