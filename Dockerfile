#===============================================================================
# CopenhagenWorkflow - Docker Container (Optimized)
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
#   singularity pull copenhagen_workflow.sif docker://ghcr.io/andresgordoortiz/copenhagenworkflow:latest
#
#===============================================================================

# Use runtime image (smaller than devel) - still has CUDA/cuDNN
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

LABEL org.opencontainers.image.title="CopenhagenWorkflow"
LABEL org.opencontainers.image.description="4D cell tracking and fate analysis pipeline"
LABEL org.opencontainers.image.version="2.0"
LABEL org.opencontainers.image.authors="CopenhagenWorkflow Team"
LABEL org.opencontainers.image.source="https://github.com/andresgordoortiz/CopenhagenWorkflow"

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

#===============================================================================
# System Dependencies - Combined into single layer
#===============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl git unzip bzip2 ca-certificates \
    build-essential cmake pkg-config \
    # OpenGL and display libraries
    libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender-dev \
    libfontconfig1 libxkbcommon-x11-0 libdbus-1-3 \
    libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 \
    libxcb-render-util0 libxcb-xinerama0 libxcb-xfixes0 libxcb-shape0 \
    libegl1 libpci3 \
    # Video/image codecs
    ffmpeg libavcodec-dev libavformat-dev libswscale-dev \
    # HDF5 and compression
    libhdf5-dev libblosc-dev \
    # Java for Fiji
    openjdk-11-jre-headless \
    # Python
    python3.10 python3.10-venv python3.10-dev python3-pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Set Python 3.10 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

#===============================================================================
# Environment Variables
#===============================================================================
ENV PATH="/usr/local/cuda-11.8/bin:/opt/Fiji.app:$PATH"
ENV LD_LIBRARY_PATH="/usr/local/cuda-11.8/lib64:$LD_LIBRARY_PATH"
ENV CUDA_HOME="/usr/local/cuda-11.8"
ENV JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
ENV FIJI_HOME="/opt/Fiji.app"
ENV TF_CPP_MIN_LOG_LEVEL=2
ENV TF_FORCE_GPU_ALLOW_GROWTH=true
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV OMP_NUM_THREADS=1
ENV PIP_NO_CACHE_DIR=1

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

#===============================================================================
# Python Packages - COMBINED to minimize layers and disk usage
#===============================================================================

# Core scientific stack + TensorFlow in ONE layer
RUN pip install \
    # Core scientific packages
    numpy==1.24.3 \
    scipy==1.11.4 \
    scikit-image==0.22.0 \
    scikit-learn==1.3.2 \
    pandas==2.1.4 \
    matplotlib==3.8.2 \
    seaborn==0.13.0 \
    plotly==5.18.0 \
    # TensorFlow (use numpy 1.24 for compatibility)
    tensorflow==2.13.1 \
    && rm -rf ~/.cache/pip /tmp/*

# PyTorch with CUDA 11.8 (separate because different index)
RUN pip install \
    torch==2.1.1 \
    torchvision==0.16.1 \
    torchaudio==2.1.1 \
    --index-url https://download.pytorch.org/whl/cu118 \
    && rm -rf ~/.cache/pip /tmp/*

#===============================================================================
# Main Analysis Packages - Combined
#===============================================================================
RUN pip install \
    # Segmentation
    cellpose==3.0.1 \
    stardist==0.8.5 \
    csbdeep==0.7.4 \
    vollseg \
    # Detection and tracking
    oneat \
    napatrackmater \
    caped-ai \
    && rm -rf ~/.cache/pip /tmp/*

#===============================================================================
# Additional Tools - Combined
#===============================================================================
RUN pip install \
    # Visualization
    "napari[all]==0.4.19" \
    napari-animation \
    napari-fast4dreg \
    # Configuration
    hydra-core==1.3.2 \
    omegaconf==2.3.0 \
    # Image I/O (tifffile must be <2023.3.15 for aicsimageio)
    "tifffile>=2021.8.30,<2023.3.15" \
    imageio==2.33.0 \
    aicsimageio==4.14.0 \
    nd2==0.7.1 \
    czifile \
    # Utilities
    natsort==8.4.0 \
    tqdm==4.66.1 \
    joblib==1.3.2 \
    h5py==3.10.0 \
    zarr==2.16.1 \
    numba==0.58.1 \
    "lxml>=4.6,<5" \
    # ML extras
    xgboost==2.0.3 \
    lightgbm==4.2.0 \
    # Jupyter
    jupyter \
    ipykernel \
    ipywidgets \
    && rm -rf ~/.cache/pip /tmp/*

#===============================================================================
# Install Fiji with TrackMate (combined and cleaned up)
#===============================================================================
WORKDIR /opt

RUN wget -q https://downloads.imagej.net/fiji/latest/fiji-linux64.tar.gz && \
    tar -xzf fiji-linux64.tar.gz && \
    rm fiji-linux64.tar.gz && \
    chmod +x /opt/Fiji.app/ImageJ-linux64 && \
    # Update and add TrackMate-Oneat
    /opt/Fiji.app/ImageJ-linux64 --headless --update update 2>/dev/null || true && \
    /opt/Fiji.app/ImageJ-linux64 --headless --update add-update-site "TrackMate-Oneat" \
        "https://sites.imagej.net/TrackMate-Oneat/" 2>/dev/null || true && \
    /opt/Fiji.app/ImageJ-linux64 --headless --update update 2>/dev/null || true && \
    # Create symlinks
    ln -sf /opt/Fiji.app/ImageJ-linux64 /usr/local/bin/fiji && \
    ln -sf /opt/Fiji.app/ImageJ-linux64 /usr/local/bin/imagej && \
    # Clean up Fiji update cache
    rm -rf /opt/Fiji.app/update /tmp/*

#===============================================================================
# Finalize
#===============================================================================
WORKDIR /workspace

RUN mkdir -p /data /models /output

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import tensorflow; import torch; import cellpose" || exit 1

# Default command
CMD ["python", "-c", "import tensorflow as tf; import torch; import cellpose; print(f'TensorFlow: {tf.__version__}'); print(f'PyTorch: {torch.__version__}'); print(f'Cellpose: {cellpose.__version__}'); print(f'CUDA (TF): {len(tf.config.list_physical_devices(\"GPU\"))} GPUs'); print(f'CUDA (PyTorch): {torch.cuda.is_available()}')"]
