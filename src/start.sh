#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

# Optional: map persistent network volume input into ComfyUI input.
# This enables static assets in /runpod-volume/input to be visible to Load Image/Video nodes.
NETWORK_VOLUME_INPUT_DIR="/runpod-volume/input"
COMFY_INPUT_DIR="/comfyui/input"
if [ -d "${NETWORK_VOLUME_INPUT_DIR}" ]; then
    if [ -L "${COMFY_INPUT_DIR}" ]; then
        CURRENT_TARGET="$(readlink "${COMFY_INPUT_DIR}" || true)"
        if [ "${CURRENT_TARGET}" = "${NETWORK_VOLUME_INPUT_DIR}" ]; then
            echo "worker-comfyui: Using network volume input (${NETWORK_VOLUME_INPUT_DIR})"
        else
            echo "worker-comfyui: /comfyui/input already points to ${CURRENT_TARGET}, skipping relink"
        fi
    elif [ -d "${COMFY_INPUT_DIR}" ]; then
        if [ -z "$(ls -A "${COMFY_INPUT_DIR}" 2>/dev/null)" ]; then
            rmdir "${COMFY_INPUT_DIR}" && ln -s "${NETWORK_VOLUME_INPUT_DIR}" "${COMFY_INPUT_DIR}"
            echo "worker-comfyui: Linked /comfyui/input -> ${NETWORK_VOLUME_INPUT_DIR}"
        else
            echo "worker-comfyui: /comfyui/input is not empty, keeping existing directory"
            echo "worker-comfyui: (network volume input available at ${NETWORK_VOLUME_INPUT_DIR})"
        fi
    else
        ln -s "${NETWORK_VOLUME_INPUT_DIR}" "${COMFY_INPUT_DIR}"
        echo "worker-comfyui: Linked /comfyui/input -> ${NETWORK_VOLUME_INPUT_DIR}"
    fi
fi

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"
COMFY_LOG_FILE="/tmp/comfyui.log"
echo "worker-comfyui: ComfyUI log file -> ${COMFY_LOG_FILE}"
touch "${COMFY_LOG_FILE}"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout 2>&1 | tee -a "${COMFY_LOG_FILE}" &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout 2>&1 | tee -a "${COMFY_LOG_FILE}" &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py
fi