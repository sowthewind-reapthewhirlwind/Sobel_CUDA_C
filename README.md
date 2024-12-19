# CUDA Accelerated Sobel Edge Detection

This repository provides a C/CUDA implementation of Sobel edge detection applied to a JPEG image. It uses the **libjpeg** library to handle image input and output, and **CUDA** kernels to accelerate the computation of the Sobel operator.

## Overview

The program:
1. Loads a JPEG image from disk.
2. Applies the Sobel X and Sobel Y filters to detect edges in the image.
3. Combines the Sobel X and Y results to produce a final edge-detected image.
4. Saves the output as `out.jpg`.

The computation of the Sobel filter is offloaded to the GPU via CUDA kernels, significantly speeding up the convolution operations on large images.

## Requirements

- **CUDA Toolkit**: Ensure you have a CUDA-capable GPU and the CUDA toolkit installed.
- **libjpeg**: The program uses `libjpeg` for handling JPEG input/output.
  - On Debian/Ubuntu: `sudo apt-get install libjpeg-dev`
  - On other systems, refer to your distribution's package manager or build from source.
- **PAPI (Performance API)**: For timing measurements (optional).
  - On Debian/Ubuntu: `sudo apt-get install libpapi-dev`
  - If you don't need timing, you can remove or comment out references to PAPI.
- A C compiler with CUDA support (e.g., `nvcc`).

## Building

1. Make sure you have `nvcc` and required libraries in your `PATH`.
2. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/cuda-sobel-edge-detection.git
   cd cuda-sobel-edge-detection
