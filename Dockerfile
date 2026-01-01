#===============================================================================
# CopenhagenWorkflow - Docker Container
#===============================================================================
# Complete environment for 4D cell tracking and fate analysis
#
# Includes:
# - Python 3.10 with GPU-accelerated deep learning (TensorFlow + PyTorch)
# - Cellpose, StarDist, VollSeg, Oneat for segmentation & detection
# - Fiji with TrackMate and TrackMate-Oneat plugin
# - All dependencies for the CopenhagenWorkflow pipeline
#
# Build:
#   docker build -t copenhagenworkflow:latest .
#
# Run with GPU:
#   docker run --gpus all -v /your/data:/data copenhagenworkflow:latest python script.py
#
# Convert to Singularity:
#   singularity pull copenhagen_workflow.sif docker://ghcr.io/YOUR_USER/copenhagenworkflow:latest
#
#===============================================================================

FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04

LABEL org.opencontainers.image.title="CopenhagenWorkflow"
LABEL org.opencontainers.image.description="4D cell tracking and fate analysis pipeline"
LABEL org.opencontainers.image.version="2.0"
LABEL org.opencontainers.image.authors="CopenhagenWorkflow Team"
LABEL org.opencontainers.image.source="https://github.com/YOUR_USER/CopenhagenWorkflow"

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

#===============================================================================
# System Dependencies
#===============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    wget \
    curl \
    git \
    build-essential \
    cmake \
    pkg-config \
    software-properties-common \
    ca-certificates \
    unzip \
    bzip2 \
    # OpenGL and display libraries (for napari, cellpose GUI)
    libgl1-mesa-glx \
    libgl1-mesa-dev \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libfontconfig1 \
    libxkbcommon-x11-0 \
    libdbus-1-3 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-randr0 \
    libxcb-render-util0 \
    libxcb-xinerama0 \
    libxcb-xfixes0 \
    libxcb-shape0 \
    libxcb-cursor0 \
    libegl1 \
    libpci3 \
    # Video/image codecs
    ffmpeg \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    # HDF5 and compression
    libhdf5-dev \
    libblosc-dev \
    # Java for Fiji
    openjdk-11-jdk \
    openjdk-11-jre \
    # Python
    python3.10 \
    python3.10-venv \
    python3.10-dev \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.10 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

#===============================================================================
# Environment Variables
#===============================================================================
ENV PATH="/usr/local/cuda-11.8/bin:/opt/Fiji.app:$PATH"
ENV LD_LIBRARY_PATH="/usr/local/cuda-11.8/lib64:/usr/local/cuda-11.8/extras/CUPTI/lib64:$LD_LIBRARY_PATH"
ENV CUDA_HOME="/usr/local/cuda-11.8"
ENV JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
ENV FIJI_HOME="/opt/Fiji.app"

# TensorFlow and Python settings
ENV TF_CPP_MIN_LOG_LEVEL=2
ENV TF_FORCE_GPU_ALLOW_GROWTH=true
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV OMP_NUM_THREADS=1

#===============================================================================
# Python Packages - ORDER MATTERS FOR COMPATIBILITY!
#===============================================================================

# Upgrade pip
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Core scientific stack (version locked for stability)
RUN pip install --no-cache-dir \
    numpy==1.26.4 \
    scipy==1.11.4 \
    scikit-image==0.22.0 \
    scikit-learn==1.3.2 \
    pandas==2.1.4 \
    matplotlib==3.8.2 \
    seaborn==0.13.0 \
    plotly==5.18.0

# TensorFlow with GPU support
RUN pip install --no-cache-dir tensorflow==2.13.1

# PyTorch with CUDA 11.8
RUN pip install --no-cache-dir \
    torch==2.1.1 \
    torchvision==0.16.1 \
    torchaudio==2.1.1 \
    --index-url https://download.pytorch.org/whl/cu118

#===============================================================================
# Main Analysis Packages
#===============================================================================

# Cellpose for cell/membrane segmentation
RUN pip install --no-cache-dir cellpose==3.0.1

# StarDist for nuclei segmentation
RUN pip install --no-cache-dir stardist==0.8.5

# CARE for denoising
RUN pip install --no-cache-dir csbdeep==0.7.4

# VollSeg - comprehensive segmentation pipeline
RUN pip install --no-cache-dir vollseg==2.4.3

# Oneat - mitosis detection
RUN pip install --no-cache-dir oneat==1.0.4

# NapaTrackMater - tracking analysis
RUN pip install --no-cache-dir napatrackmater==1.4.5

# caped-ai meta package
RUN pip install --no-cache-dir caped-ai

#===============================================================================
# Additional Tools
#===============================================================================

# Napari for visualization
RUN pip install --no-cache-dir "napari[all]==0.4.19" napari-animation

# Drift correction
RUN pip install --no-cache-dir napari-fast4dreg

# Configuration management (Hydra)
RUN pip install --no-cache-dir hydra-core==1.3.2 omegaconf==2.3.0

# Image I/O
RUN pip install --no-cache-dir \
    tifffile==2023.12.9 \
    imageio==2.33.1 \
    aicsimageio==4.14.0 \
    nd2==0.7.1 \
    czifile

# Utilities
RUN pip install --no-cache-dir \
    natsort==8.4.0 \
    tqdm==4.66.1 \
    joblib==1.3.2 \
    h5py==3.10.0 \
    zarr==2.16.1 \
    numba==0.58.1 \
    lxml==5.0.0

# Machine learning extras
RUN pip install --no-cache-dir xgboost==2.0.3 lightgbm==4.2.0

# Jupyter support
RUN pip install --no-cache-dir jupyter ipykernel ipywidgets

#===============================================================================
# Install Fiji with TrackMate
#===============================================================================
WORKDIR /opt

# Download and extract Fiji
RUN wget -q https://downloads.imagej.net/fiji/latest/fiji-linux64.tar.gz && \
    tar -xzf fiji-linux64.tar.gz && \
    rm fiji-linux64.tar.gz && \
    chmod +x /opt/Fiji.app/ImageJ-linux64

# Update Fiji and add TrackMate-Oneat update site
RUN /opt/Fiji.app/ImageJ-linux64 --headless --update update || true

# Try to add TrackMate-Oneat (may fail if site unavailable, that's OK)
RUN /opt/Fiji.app/ImageJ-linux64 --headless --update add-update-site "TrackMate-Oneat" \
    "https://sites.imagej.net/TrackMate-Oneat/" 2>/dev/null || true && \
    /opt/Fiji.app/ImageJ-linux64 --headless --update update 2>/dev/null || true

# Create symlinks for easier access
RUN ln -sf /opt/Fiji.app/ImageJ-linux64 /usr/local/bin/fiji && \
    ln -sf /opt/Fiji.app/ImageJ-linux64 /usr/local/bin/imagej

#===============================================================================
# Create working directory and set permissions
#===============================================================================
WORKDIR /workspace

# Create directories for data mounting
RUN mkdir -p /data /models /output

#===============================================================================
# Healthcheck and default command
#===============================================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import tensorflow; import torch; import cellpose" || exit 1

# Default command shows version info
CMD ["python", "-c", "import tensorflow as tf; import torch; import cellpose; print(f'TensorFlow: {tf.__version__}'); print(f'PyTorch: {torch.__version__}'); print(f'Cellpose: {cellpose.__version__}'); print(f'CUDA available (TF): {len(tf.config.list_physical_devices(\"GPU\"))} GPUs'); print(f'CUDA available (PyTorch): {torch.cuda.is_available()}')"]
