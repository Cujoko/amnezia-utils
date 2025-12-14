#!/bin/bash

# Configuration
BACKUP_DIR="./amnezia-opt-backups"
CONTAINER_PREFIX="amnezia"
DATE_SUFFIX=$(date +%Y-%m-%d-%H-%M-%S)

# --- BLACKLIST: Containers to be excluded from backup and restore ---
# Only 'amnezia-dns' is blacklisted as per request.
BLACKLIST=("amnezia-dns")

# --- Helper Functions ---

# Check if a container name is in the blacklist
is_blacklisted() {
    local NAME="$1"
    for item in "${BLACKLIST[@]}"; do
        if [[ "$NAME" == "$item" ]]; then
            return 0 # True (is blacklisted)
        fi
    done
    return 1 # False (not blacklisted)
}

# Function to perform the actual /opt/ backup for a single container
backup_container_opt() {
    local CONTAINER_NAME="$1"
    local BACKUP_FILE="$BACKUP_DIR/${CONTAINER_NAME}_opt_${DATE_SUFFIX}.tar.gz"
    
    echo "--- Starting /opt/ backup for $CONTAINER_NAME ---"
    
    # 1. Create temporary directory for extraction
    local TEMP_DIR=$(mktemp -d)
    
    # 2. Copy /opt/ out of the container
    echo "  Copying /opt/ from container..."
    if ! docker cp "$CONTAINER_NAME":/opt/ "$TEMP_DIR/${CONTAINER_NAME}_opt"; then
        echo "  ERROR: Failed to copy /opt/ using docker cp. Skipping."
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # 3. Compress the copied /opt/ directory into a single tar.gz
    echo "  Compressing into $BACKUP_FILE..."
    if ! tar czf "$BACKUP_FILE" -C "$TEMP_DIR" "${CONTAINER_NAME}_opt"; then
        echo "  ERROR: Failed to create tar.gz archive. Skipping."
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # 4. Clean up
    rm -rf "$TEMP_DIR"
    echo "  SUCCESS: Backup saved to $BACKUP_FILE"
    echo "--------------------------------------------------------"
    return 0
}

# Function to restore /opt/ directory of a single container
restore_container_opt() {
    local CONTAINER_NAME="$1"
    
    local LATEST_BACKUP=$(ls -t "$BACKUP_DIR/$CONTAINER_NAME"_opt_*.tar.gz 2>/dev/null | head -n 1)

    if [[ -z "$LATEST_BACKUP" ]]; then
        echo "ERROR: No /opt/ backup found for $CONTAINER_NAME in $BACKUP_DIR. Skipping restore."
        return 1
    fi

    echo "--- Starting in-place /opt/ restore for $CONTAINER_NAME from $(basename "$LATEST_BACKUP") ---"
    
    local TEMP_DIR=$(mktemp -d)
    
    echo "  Stopping container..."
    if ! docker stop "$CONTAINER_NAME"; then
        echo "  ERROR: Failed to stop $CONTAINER_NAME. Aborting restore."
        return 1
    fi
    
    echo "  Unpacking archive..."
    if ! tar xzf "$LATEST_BACKUP" -C "$TEMP_DIR"; then
        echo "  ERROR: Failed to unpack backup. Aborting."
        rm -rf "$TEMP_DIR"
        docker start "$CONTAINER_NAME" 2>/dev/null
        return 1
    fi
    
    echo "  Copying /opt/ content back into container..."
    if docker cp "$TEMP_DIR/${CONTAINER_NAME}_opt/." "$CONTAINER_NAME:/opt/"; then
        echo "  SUCCESS: /opt/ content updated."
    else
        echo "  ERROR: docker cp failed. Manual check required."
    fi
    
    rm -rf "$TEMP_DIR"
    
    echo "  Starting container..."
    if ! docker start "$CONTAINER_NAME"; then
        echo "  WARNING: Failed to start $CONTAINER_NAME. Manual check required."
        return 1
    fi
    
    echo "SUCCESS: Container restored and restarted."
    echo "--------------------------------------------------------"
    return 0
}

# --- Main Execution Logic ---

# 1. Get ALL container names, filter by prefix, and save as a Bash array.
# The 'tr' command is used to replace spaces with newlines, ensuring each name is on a separate line.
readarray -t ALL_CONTAINER_NAMES < <(docker ps -a --format '{{.Names}}' | grep "^$CONTAINER_PREFIX")

# 2. Filter the array against the blacklist.
FILTERED_NAMES_ARRAY=()
for NAME in "${ALL_CONTAINER_NAMES[@]}"; do
    # ROBUSTNESS: Ensure the name is not empty and not blacklisted.
    if [[ -n "$NAME" ]] && ! is_blacklisted "$NAME"; then
        FILTERED_NAMES_ARRAY+=("$NAME")
    fi
done

if [[ ${#FILTERED_NAMES_ARRAY[@]} -eq 0 ]]; then
    echo "INFO: No containers starting with '$CONTAINER_PREFIX' found or all are blacklisted."
    exit 0
fi

# Determine if running in restore or backup mode
if [[ "$1" == "-r" ]]; then
    # RESTORE MODE
    echo "--- Amnezia Docker Restore Mode (Simplified /opt/ Restore) ---"
    echo "Containers to restore (excluding: ${BLACKLIST[*]}):"
    printf " - %s\n" "${FILTERED_NAMES_ARRAY[@]}"
    echo "--------------------------------------------------------"
    
    for NAME in "${FILTERED_NAMES_ARRAY[@]}"; do
        restore_container_opt "$NAME"
    done
else
    # BACKUP MODE (Default)
    echo "--- Amnezia Docker Backup Mode (Simplified /opt/ Backup) ---"
    mkdir -p "$BACKUP_DIR"
    echo "Containers to backup (excluding: ${BLACKLIST[*]}):"
    printf " - %s\n" "${FILTERED_NAMES_ARRAY[@]}"
    echo "--------------------------------------------------------"
    
    for NAME in "${FILTERED_NAMES_ARRAY[@]}"; do
        backup_container_opt "$NAME"
    done
fi

exit 0
