[![Nextflow](https://img.shields.io/badge/nextflow%20DSL2-%E2%89%A523.10.0-23aa62.svg)](https://www.nextflow.io/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![Launch on Seqera Platform](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Seqera%20Platform-%234256e7)](https://cloud.seqera.io/launch?pipeline=https://github.com/seqeralabs/nf-stresstest)

## Introduction

**seqeralabs/nf-stresstest** is a Nextflow pipeline designed to simulate different scenarios of dealing with varying input data sizes (large files, many small files).

The pipeline performs the following stress tests on big files:

1. Generate fake FASTQ files
2. Concatenate generated FASTQ files
3. Compress the FASTQ files
4. Perform a md5checksum on the resulting archive

In parallel the pipeline can also performs the following stress tests on small files:

1. Generate many small files and generate corresponding md5checksum
2. Count the number of many small files
3. Rename and compress the files
4. Decompress and verify the checksum

## Prerequisites

- [Nextflow](https://www.nextflow.io/docs/latest/getstarted.html#installation) >=23.10.0

## Usage

This pipeline can be executed with the following command:

```
nextflow run seqeralabs/nf-stresstest
```

### Parameters

You can modify the following parameters to adjust the file size and file number being created for stress testing, as well as which processes to selectively run or skip:

| Parameter      | Description                                                      | Default |
|----------------|------------------------------------------------------------------|---------|
| `--total_reads`| Total number of reads per file (10k reads generates a ~1GB file) | 10000   |
| `--num_files`  | Number of FASTQ files to generate in parallel and concatenate    | 10      |
| `--run`        | Tools to selectively run                                         |         |
| `--skip`       | Tools to selectively skip                                        |         |

## Credits

nf-aggregate was written by the Scientific Development and Engineering at [Seqera Labs](https://seqera.io/).