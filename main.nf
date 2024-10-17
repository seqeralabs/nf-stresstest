process GENERATE_FAKE_FASTQ {
    container 'community.wave.seqera.io/library/numpy:2.1.1--3063fc3d721f2cdf'

    cpus 2
    memory { 4.GB * task.attempt }

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

    cpus 4
    memory { 12.GB * task.attempt }

    input:
    path fastq_files

    output:
    path 'concatenated_samples.fastq'

    script:
    """
    cat ${fastq_files} > concatenated_samples.fastq
    """
}

process CHECKSUM_FASTQ {

    cpus 4
    memory { 6.GB * task.attempt }

    input:
    path fastq_file

    output:
    path 'checksum.md5'

    script:
    """
    md5sum ${fastq_file} > checksum.md5
    """
}

process COMPRESS_FASTQ {
    container 'community.wave.seqera.io/library/pigz:2.8--cc287835d69f818b'

    cpus 16
    memory { 48.GB * task.attempt }

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

    cpus 2
    memory { 6.GB * task.attempt }

    input:
    val num_files

    output:
    path 'generated_files', emit: files
    path 'checksum.txt', emit: checksum

    script:
    """
    mkdir generated_files
    for i in \$(seq 1 ${num_files}); do
        hex_name=\$(printf "%x" \$i)
        dd if=/dev/zero of=generated_files/\${hex_name}.bin bs=1M count=10
    done

    # Generate MD5 checksums
    cd generated_files
    find . -name '*.bin' -exec md5sum {} + > ../checksum.txt
    """
}

process COUNT_FILES {

    cpus 2
    memory { 6.GB * task.attempt }

    input:
    path files_folder

    output:
    stdout

    script:
    """
    cd ${files_folder}
    find . -name '*.bin' -type f | wc -l
    """
}

process RENAME_AND_COMPRESS_FILES {
    container 'community.wave.seqera.io/library/parallel:20240322--aeca7ef865f0e18b'

    cpus 16
    memory { 48.GB * task.attempt }

    input:
    path files_folder

    output:
    path 'renamed_files'

    script:
    """
    # First, create a copy of the original folder
    cp -LR ${files_folder} copy_folder

    # Now create the renamed_files directory and move files there
    mkdir renamed_files
    for file in copy_folder/*.bin; do
        mv \$file renamed_files/\$(basename \$file)
    done

    # Compress all the files
    cd renamed_files
    find . -name '*.bin' -type f | parallel -j ${task.cpus} gzip

    """
}

process UNCOMPRESS_AND_VERIFY_FILES {
    container 'community.wave.seqera.io/library/parallel:20240322--aeca7ef865f0e18b'

    cpus 16
    memory { 48.GB * task.attempt }

    input:
    path files_folder
    path original_checksum

    output:
    path 'verification.txt'

    script:
    """
     # First, create a copy of the original folder
    cp -LR ${files_folder} uncompressed_files

    # Uncompress files
    cd uncompressed_files
    find . -name '*.gz' -type f | parallel -j ${task.cpus} gzip -d

    # Verify checksums
    md5sum -c ../${original_checksum} > ../verification.txt
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
    fake_fastq_files = GENERATE_FAKE_FASTQ(generate_params)

    // Collect all generated FASTQ files
    collected_fastq_files = fake_fastq_files.collect()

    // Concatenate all FASTQ files
    CONCATENATE_FASTQ(collected_fastq_files)

    // Compress the concatenated FASTQ file
    COMPRESS_FASTQ(CONCATENATE_FASTQ.out)

    // Checksum a big file (big read with small write)
    CHECKSUM_FASTQ(CONCATENATE_FASTQ.out)

    // Generate many small files in a single process
    small_files = MANY_SMALL_FILES(params.small_files)

    // Count how many files are generated
    COUNT_FILES(small_files.files) | view { "Number of small files: $it" }

    // Rename and compress all these files
    RENAME_AND_COMPRESS_FILES(small_files.files)

    // Extract and verify checksum of all the files
    UNCOMPRESS_AND_VERIFY_FILES(RENAME_AND_COMPRESS_FILES.out, small_files.checksum)

}