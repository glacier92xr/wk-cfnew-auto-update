#!/bin/bash

KV_NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WRANGLER_TOML="$PROJECT_DIR/wrangler.toml"
LOG_FILE="$SCRIPT_DIR/step-kv.log"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

info() {
    local msg="$1"
    echo -e "\033[36m$msg\033[0m"
    log "$msg"
}

success() {
    local msg="$1"
    echo -e "\033[32m$msg\033[0m"
    log "$msg"
}

warn() {
    local msg="WARN: $1"
    echo -e "\033[33m$msg\033[0m"
    log "$msg"
}

error() {
    local msg="ERROR: $1"
    echo -e "\033[31m$msg\033[0m"
    log "$msg"
    exit 1
}

get_existing_kv_id() {
    local name="$1"

    local output
    output=$(npx wrangler kv namespace list 2>&1) || {
        return 1
    }

    if echo "$output" | grep -q "\"title\": \"$name\""; then
        local kv_id
        kv_id=$(echo "$output" | grep -oP "\"title\": \"$name\".*?\"id\":\s*\"\K[^\"]+" | head -1)
        if [ -z "$kv_id" ]; then
            kv_id=$(echo "$output" | python3 -c "import sys, json; data=json.load(sys.stdin); print(next((item['id'] for item in data if item.get('title')=='$name'), ''))" 2>/dev/null)
        fi

        if [ -n "$kv_id" ]; then
            echo "$kv_id"
            return 0
        fi
    fi

    return 1
}

create_kv() {
    local name="$1"
    log "Creating new KV namespace: $name"

    local output
    output=$(npx wrangler kv namespace create "$name" --binding "C" --update-config 2>&1) || {
        error "KV creation failed: $output"
    }

    log "Wrangler output: $output"

    if echo "$output" | grep -qE "Error|error|ERROR"; then
        error "KV creation failed: $output"
    fi

    local kv_id
    kv_id=$(echo "$output" | grep -oP 'id = "\K[^"]+' | head -1)

    if [ -z "$kv_id" ]; then
        error "Failed to extract KV ID from output"
    fi

    success "KV created successfully with ID: $kv_id"
    echo "$kv_id"
}

update_wrangler_toml() {
    local kv_id="$1"
    log "Updating wrangler.toml with KV ID: $kv_id"

    if [ ! -f "$WRANGLER_TOML" ]; then
        error "wrangler.toml not found at: $WRANGLER_TOML"
    fi

    local tmp_file="$WRANGLER_TOML.tmp"
    local updated=false

    while IFS= read -r line || [ -n "$line" ]; do
        if echo "$line" | grep -qE '^id\s*='; then
            echo "id = \"$kv_id\""
            updated=true
        else
            echo "$line"
        fi
    done < "$WRANGLER_TOML" > "$tmp_file"

    if [ "$updated" = false ]; then
        if grep -q '\[\[kv_namespaces\]\]' "$WRANGLER_TOML"; then
            log "Adding KV ID to existing [[kv_namespaces]] section..."
            rm "$tmp_file"
            tmp_file="$WRANGLER_TOML.tmp2"
            local found_kv=false
            while IFS= read -r line || [ -n "$line" ]; do
                echo "$line"
                if echo "$line" | grep -qE '\[\[kv_namespaces\]\]'; then
                    found_kv=true
                elif [ "$found_kv" = true ] && echo "$line" | grep -qE '^binding\s*='; then
                    found_kv=false
                    echo "id = \"$kv_id\""
                fi
            done < "$WRANGLER_TOML" > "$tmp_file"
        else
            log "No existing [[kv_namespaces]] section, appending..."
            echo "" >> "$tmp_file"
            echo "[[kv_namespaces]]" >> "$tmp_file"
            echo "binding = \"C\"" >> "$tmp_file"
            echo "id = \"$kv_id\"" >> "$tmp_file"
        fi
    fi

    mv "$tmp_file" "$WRANGLER_TOML"
    rm -f "$WRANGLER_TOML.tmp2" 2>/dev/null
    success "wrangler.toml updated successfully"
}

find_documentation_files() {
    local doc_extensions=("md" "txt" "json" "yaml" "yml")
    local exclude_dirs=("node_modules" ".git" "dist" "build" "coverage")
    local find_exclude=""

    for dir in "${exclude_dirs[@]}"; do
        find_exclude="$find_exclude -not -path */$dir/*"
    done

    local docs=()
    for ext in "${doc_extensions[@]}"; do
        while IFS= read -r -d '' file; do
            docs+=("$file")
        done < <(find "$PROJECT_DIR" -maxdepth 3 -type f -name "*.$ext" $find_exclude -print0 2>/dev/null)
    done

    printf '%s\n' "${docs[@]}"
}

update_documentation_kv_id() {
    local old_kv_id="$1"
    local new_kv_id="$2"
    local kv_name="$3"

    if [ -z "$old_kv_id" ]; then
        log "No old KV ID provided, skipping documentation update"
        return
    fi

    log "Checking documentation files for KV ID updates..."

    local docs
    mapfile -t docs < <(find_documentation_files)
    local updated_count=0

    for doc in "${docs[@]}"; do
        if [ -f "$doc" ] && grep -q "$old_kv_id" "$doc" 2>/dev/null; then
            local tmp_file="$doc.tmp"
            while IFS= read -r line || [ -n "$line" ]; do
                echo "${line//$old_kv_id/$new_kv_id}"
            done < "$doc" > "$tmp_file" && mv "$tmp_file" "$doc"
            log "Updated KV ID in: $doc"
            ((updated_count++)) || true
        fi
    done

    if [ "$updated_count" -gt 0 ]; then
        success "Updated $updated_count documentation file(s)"
    else
        log "No documentation files needed updating"
    fi
}

get_current_kv_id() {
    if [ ! -f "$WRANGLER_TOML" ]; then
        return 1
    fi

    local kv_id
    kv_id=$(grep -oP 'id\s*=\s*"\K[^"]+' "$WRANGLER_TOML" | head -1)

    if [ -n "$kv_id" ]; then
        echo "$kv_id"
        return 0
    fi
    return 1
}

main() {
    if [ -z "$KV_NAME" ]; then
        echo "Usage: $0 <KVName>"
        echo "Example: $0 my-kv"
        exit 1
    fi

    echo ""
    info "========== KV Namespace Management =========="
    log "Starting KV namespace management for: $KV_NAME"

    if [ ! -f "$WRANGLER_TOML" ]; then
        error "wrangler.toml not found at: $WRANGLER_TOML"
    fi

    local current_kv_id
    current_kv_id=$(get_current_kv_id) || current_kv_id=""
    if [ -n "$current_kv_id" ]; then
        log "Current KV ID in wrangler.toml: $current_kv_id"
    fi

    cd "$PROJECT_DIR"

    log "Checking if KV namespace '$KV_NAME' already exists..."
    local existing_kv_id
    existing_kv_id=$(get_existing_kv_id "$KV_NAME") || existing_kv_id=""

    if [ -n "$existing_kv_id" ]; then
        log "Found existing KV: $KV_NAME with ID: $existing_kv_id"
    else
        log "KV namespace '$KV_NAME' does not exist"
    fi

    local kv_id_to_use=""
    local is_new_kv=false

    if [ -n "$existing_kv_id" ]; then
        info "KV namespace '$KV_NAME' already exists with ID: $existing_kv_id"
        kv_id_to_use="$existing_kv_id"

        if [ "$existing_kv_id" = "$current_kv_id" ]; then
            info "Current wrangler.toml already uses this KV ID, no update needed"
        else
            info "Updating wrangler.toml to use existing KV ID..."
            if ! update_wrangler_toml "$kv_id_to_use"; then
                error "Failed to update wrangler.toml"
            fi
            if [ -n "$current_kv_id" ]; then
                update_documentation_kv_id "$current_kv_id" "$kv_id_to_use" "$KV_NAME"
            fi
        fi
    else
        info "KV namespace '$KV_NAME' does not exist, creating new one..."
        kv_id_to_use=$(create_kv "$KV_NAME")

        if [ -z "$kv_id_to_use" ]; then
            error "Failed to create KV namespace"
        fi

        is_new_kv=true

        if ! update_wrangler_toml "$kv_id_to_use"; then
            error "Failed to update wrangler.toml"
        fi

        if [ -n "$current_kv_id" ]; then
            update_documentation_kv_id "$current_kv_id" "$kv_id_to_use" "$KV_NAME"
        fi
    fi

    echo ""
    success "========== SUCCESS =========="
    if [ "$is_new_kv" = true ]; then
        success "New KV namespace created: $KV_NAME"
    else
        success "Using existing KV namespace: $KV_NAME"
    fi
    success "KV ID: $kv_id_to_use"
    success "wrangler.toml: Updated"
    echo ""
    info "Next: npm run deploy"
    log "Done"
}

main "$@"
