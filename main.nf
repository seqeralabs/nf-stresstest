process GENERATE_FAKE_FASTQ {
    container 'community.wave.seqera.io/library/numpy:2.1.1--3063fc3d721f2cdf'

    input:
    tuple val(total_reads), val(file_index)

    output:
    path "random_sample_${file_index}.fastq"

    script:
    """
    #!/usr/bin/env python3

    import numpy as np
    import sys

    def generate_random_sequence(length=53676):
        bases = np.array(['A', 'C', 'G', 'T'], dtype='|S1')
        return np.random.choice(bases, size=length).tobytes().decode('ascii')

    def generate_random_quality(length=53676):
        quality_ints = np.random.randint(0, 42, size=length) + 33
        return ''.join(chr(q) for q in quality_ints)

    def generate_fake_fastq(total_reads, file_index):
        output_file = f"random_sample_{file_index}.fastq"

        with open(output_file, 'w') as f:
            for i in range(1, total_reads + 1):
                seq_id = f"@fake_read_{file_index}_{i}"
                sequence = generate_random_sequence()
                quality = generate_random_quality()

                f.write(f"{seq_id}\\n")
                f.write(f"{sequence}\\n")
                f.write("+\\n")
                f.write(f"{quality}\\n")

        print(f"Generated {output_file} with {total_reads} reads.")

    generate_fake_fastq(${total_reads}, ${file_index})
    """
}

process CONCATENATE_FASTQ {
    input:
    path fastq_files

    output:
    path 'concatenated_samples.fastq'

    script:
    """
    cat ${fastq_files} > concatenated_samples.fastq
    """
}

process COMPRESS_FASTQ {
    container 'community.wave.seqera.io/library/pigz:2.8--cc287835d69f818b'

    input:
    path fastq_file

    output:
    path "${fastq_file}.gz", emit: compressed_fastq

    script:
    """
    pigz -p ${task.cpus} -c ${fastq_file} > ${fastq_file}.gz
    """
}

process MANY_SMALL_FILES {
    input:
    val num_files

    output:
    path "file_*.bin", emit: files
    path 'checksum.txt', emit: checksum

    script:
    """
    for i in \$(seq 1 ${num_files}); do
        dd if=/dev/zero of=file_\$i.bin bs=1M count=10
    done

    # Generate MD5 checksums
    md5sum file_* > checksum.txt
    """
}

process COUNT_FILES {
    input:
    path "files/*"

    output:
    stdout

    script:
    """
    find files/* | wc -l
    """
}

process RENAME_FILES {
    input:
    path "files/*"

    output:
    path 'renamed_files'

    script:
    """
    # First, create a copy of the original folder
    cp -LR files original_files

    # Now create the renamed_files directory and move files there
    mkdir renamed_files
    for file in original_files/*; do
        mv \$file renamed_files/renamed_\$(basename \$file)
    done
    """
}

process COMPRESS_FILES {
    input:
    path "files/*"

    output:
    path 'compressed_files.tar.gz'

    script:
    """
    tar -czvhf compressed_files.tar.gz -C \$(readlink -f files) .
    """
}


process UNCOMPRESS_FILES {
    input:
    path compressed_file
    path original_checksum

    script:
    """
    mkdir uncompressed_files
    tar -xzvf ${compressed_file}

    # Verify checksums
    md5sum -c ${original_checksum} > verification_results.txt
    if grep -q 'FAILED' verification_results.txt; then
        echo "Checksum verification FAILED for some files"
        exit 1
    else
        echo "All checksums verified successfully"
    fi
    """
}

workflow {

    // Create a channel with the parameters for each GENERATE_FAKE_FASTQ process
    generate_params = Channel.from(1..params.num_files).map { it -> tuple(params.total_reads, it) }

    // Run GENERATE_FAKE_FASTQ processes in parallel
    GENERATE_FAKE_FASTQ(generate_params)

    // Compress the FASTQ files
    fake_fastq_files = COMPRESS_FASTQ(GENERATE_FAKE_FASTQ.out)

    // Collect all generated FASTQ files
    collected_fastq_files = fake_fastq_files.collect()

    // Concatenate all FASTQ files
    CONCATENATE_FASTQ(collected_fastq_files)

    // Generate many small files in a single process
    MANY_SMALL_FILES(params.small_files)

    all_files = Channel.empty()
                .mix( MANY_SMALL_FILES.out.files.filter{ params.use_small_files } )
                .mix( fake_fastq_files.filter{ params.use_fastq_files } )
                .collect()

    // Count how many files are generated
    COUNT_FILES(all_files) | view { "Number of small files: $it" }

    // Rename all these files
    RENAME_FILES(all_files)

    compressed = COMPRESS_FILES(all_files)

    // UNCOMPRESS_FILES(compressed, small_files.checksum)

}