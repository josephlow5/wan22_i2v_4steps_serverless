# ============================================================================
# Stage 1: Builder - Clone ComfyUI and install all Python packages (CUDA 12.8)
# ============================================================================
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install minimal dependencies needed for building
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    git \
    wget \
    curl \
    ca-certificates \
    && add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-12-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb

# Install pip for Python 3.12 and upgrade it
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.12 get-pip.py && \
    python3.12 -m pip install --upgrade pip && \
    rm get-pip.py

# Set CUDA environment for building
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Clone ComfyUI to get requirements
WORKDIR /tmp/build
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# Clone custom nodes to get their requirements
WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone https://github.com/kijai/ComfyUI-KJNodes && \
    git clone https://github.com/MoonGoblinDev/Civicomfy

# Install PyTorch (stable CUDA 12.8 build) and all ComfyUI dependencies
RUN python3.12 -m pip install --no-cache-dir \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128

WORKDIR /tmp/build/ComfyUI
RUN python3.12 -m pip install --no-cache-dir -r requirements.txt && \
    python3.12 -m pip install --no-cache-dir GitPython opencv-python

# Install custom node dependencies
WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN for node_dir in */; do \
        if [ -f "$node_dir/requirements.txt" ]; then \
            echo "Installing requirements for $node_dir"; \
            python3.12 -m pip install --no-cache-dir -r "$node_dir/requirements.txt" || true; \
        fi; \
    done

# ============================================================================
# Stage 2: Runtime - Clean image with pre-installed packages
# ============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg
ENV FILEBROWSER_CONFIG=/workspace/runpod-slim/.filebrowser.json

# Update and install runtime dependencies, CUDA 12.8, and common tools
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    gpg-agent \
    && add-apt-repository ppa:deadsnakes/ppa && \
    add-apt-repository ppa:cybermax-dexter/ffmpeg-nvenc && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    libssl-dev \
    wget \
    gnupg \
    xz-utils \
    openssh-client \
    openssh-server \
    nano \
    curl \
    htop \
    tmux \
    ca-certificates \
    less \
    net-tools \
    iputils-ping \
    procps \
    golang \
    make \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-12-8 \
    && apt-get install -y --no-install-recommends ffmpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb

# Copy Python packages and pip executables from builder stage
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/bin /usr/local/bin

# Remove uv to force ComfyUI-Manager to use pip (uv doesn't respect --system-site-packages properly)
RUN pip uninstall -y uv 2>/dev/null || true && \
    rm -f /usr/local/bin/uv /usr/local/bin/uvx

# Set CUDA environment variables
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Configure SSH for root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd && \
    rm -f /etc/ssh/ssh_host_*

# Create workspace directory
RUN mkdir -p /workspace/runpod-slim
WORKDIR /workspace/runpod-slim

# Fix runtime ComfyUI symlink
COPY --from=builder /tmp/build/ComfyUI /workspace/runpod-slim/ComfyUI

# Expose ports
EXPOSE 8188 22

# Copy start script
COPY start.sh /start.sh

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --set python3 /usr/bin/python3.12




# Here start my script

# === [START] Deprecated: Bake models in Docker Image ===
# Create model storage directories
# RUN mkdir -p /comfy-storage/models/diffusion_models && \
#    mkdir -p /comfy-storage/models/loras && \
#    mkdir -p /comfy-storage/models/text_encoders && \
#    mkdir -p /comfy-storage/models/vae

# Download LoRA and diffusion models
# RUN wget -O /comfy-storage/models/diffusion_models/wan2.2_i2v_A14b_high_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui_1030.safetensors \
#        https://huggingface.co/lightx2v/Wan2.2-Distill-Models/resolve/main/wan2.2_i2v_A14b_high_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui_1030.safetensors && \
#    wget -O /comfy-storage/models/diffusion_models/wan2.2_i2v_A14b_low_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui.safetensors  \
#        https://huggingface.co/lightx2v/Wan2.2-Distill-Models/resolve/main/wan2.2_i2v_A14b_low_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui.safetensors && \
#    wget -O /comfy-storage/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors \
#        https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors && \
#    wget -O /comfy-storage/models/vae/wan_2.1_vae.safetensors \
#        https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors
		
# Replace ComfyUI model folders with symlinks to persistent storage
# RUN rm -rf /workspace/runpod-slim/ComfyUI/models/diffusion_models && \
#    rm -rf /workspace/runpod-slim/ComfyUI/models/loras && \
#    rm -rf /workspace/runpod-slim/ComfyUI/models/text_encoders && \
#    rm -rf /workspace/runpod-slim/ComfyUI/models/vae && \
#    ln -s /comfy-storage/models/diffusion_models /workspace/runpod-slim/ComfyUI/models/diffusion_models && \
#    ln -s /comfy-storage/models/loras /workspace/runpod-slim/ComfyUI/models/loras && \
#    ln -s /comfy-storage/models/text_encoders /workspace/runpod-slim/ComfyUI/models/text_encoders && \
#    ln -s /comfy-storage/models/vae /workspace/runpod-slim/ComfyUI/models/vae
# === [END] Deprecated: Bake models in Docker Image ===


# === [START] Use Runpod Network Volume ===

# Download to your network volume if not exist (when you are on Pod it is /workspace)
# RUN wget -O /workspace/I2V_4steps/diffusion_models/wan2.2_i2v_A14b_high_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui_1030.safetensors \
#        https://huggingface.co/lightx2v/Wan2.2-Distill-Models/resolve/main/wan2.2_i2v_A14b_high_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui_1030.safetensors && \
#    wget -O /workspace/I2V_4steps/diffusion_models/wan2.2_i2v_A14b_low_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui.safetensors  \
#        https://huggingface.co/lightx2v/Wan2.2-Distill-Models/resolve/main/wan2.2_i2v_A14b_low_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui.safetensors && \
#    wget -O /workspace/I2V_4steps/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors \
#        https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors && \
#    wget -O /workspace/I2V_4steps/vae/wan_2.1_vae.safetensors \
#        https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors

# Replace ComfyUI model folders with symlinks to persistent storage
RUN rm -rf /workspace/runpod-slim/ComfyUI/models/diffusion_models && \
    rm -rf /workspace/runpod-slim/ComfyUI/models/loras && \
    rm -rf /workspace/runpod-slim/ComfyUI/models/text_encoders && \
    rm -rf /workspace/runpod-slim/ComfyUI/models/vae && \
    ln -s /runpod-volume/I2V_4steps/diffusion_models /workspace/runpod-slim/ComfyUI/models/diffusion_models && \
    ln -s /runpod-volume/I2V_4steps/loras /workspace/runpod-slim/ComfyUI/models/loras && \
    ln -s /runpod-volume/I2V_4steps/text_encoders /workspace/runpod-slim/ComfyUI/models/text_encoders && \
    ln -s /runpod-volume/I2V_4steps/vae /workspace/runpod-slim/ComfyUI/models/vae
	
    
RUN cd /workspace/runpod-slim/ComfyUI/custom_nodes && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && \
    cd ComfyUI-VideoHelperSuite && \
    pip install -r requirements.txt

RUN cd /workspace/runpod-slim/ComfyUI/custom_nodes && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git
	
RUN mkdir -p /workspace/runpod-slim/ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife && wget https://huggingface.co/hfmaster/models-moved/resolve/cab6dcee2fbb05e190dbb8f536fbdaa489031a14/rife/rife49.pth -O /workspace/runpod-slim/ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/rife49.pth

RUN cd /workspace/runpod-slim/ComfyUI/custom_nodes && \
    git clone https://github.com/princepainter/ComfyUI-PainterI2V.git

RUN pip install sageattention runpod websocket-client

RUN chmod +x /start.sh

COPY handler.py /workspace/runpod-slim/ComfyUI/handler.py

ENTRYPOINT ["/start.sh"]