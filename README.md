# nf-stresstest

## Overview

This repository contains a Nextflow pipeline for stress testing. The pipeline is designed to simulate high computational loads and test the performance and stability of computational resources.

## Requirements

- Nextflow
- Java 17 or higher
- Docker

## Usage

To run the pipeline, use the following command:

```bash
nextflow run seqeralabs/nf-stresstest
```

params usage:

- `total_reads`: Total number of reads per file (10k reads generates a ~1GB file)
- `num_files`: Number of FASTQ files to generate in parallel and concatenate
- `small_files`: Number of small files to generate in a single process
- `run`: Tools to selectively run
- `skip`: Tools to selectively skip
