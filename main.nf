process GENERATE_FAKE_FASTQ {
    tag "${file_index}"

    container 'community.wave.seqera.io/library/numpy:2.1.1--3063fc3d721f2cdf'

    input:
    tuple val(total_reads), val(file_index), val(length)

    output:
    path "random_sample_${file_index}.fastq", emit: fastq
    path "checksum.txt"                    , emit: checksum

    script:
    """
    #!/usr/bin/env python3

    import hashlib
    import sys
    import numpy as np

    def generate_random_sequence(length=${length}):
        bases = np.array(['A', 'C', 'G', 'T'], dtype='|S1')
        return np.random.choice(bases, size=length).tobytes().decode('ascii')

    def generate_random_quality(length=${length}):
        quality_ints = np.random.randint(0, 42, size=length) + 33
        return ''.join(chr(q) for q in quality_ints)

    def generate_fake_fastq(total_reads, file_index, output_file):

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

    def calculate_md5(file_path):
        hash_md5 = hashlib.md5()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()

    output_file = f"random_sample_${file_index}.fastq"

    generate_fake_fastq(${total_reads}, ${file_index}, output_file)

    checksum = calculate_md5(output_file)

    with open(f"checksum.txt", 'w') as checksum_file:
        checksum_file.write(f"{checksum}  {output_file}\\n")
    """
}

process ZERO_FILES {

    input:
    tuple val(num_files), val(size)

    output:
    path "file_*.bin", emit: files
    path 'checksum.txt', emit: checksum

    script:
    """
    for i in \$(seq 1 ${num_files}); do
        dd if=/dev/zero of=file_\$i.bin bs=1M count=${size}
    done

    # Generate MD5 checksums
    md5sum file_* > checksum.txt
    """
}

process CONCATENATE_FILES {

    input:
    path input_files

    output:
    path 'concatenated.*'

    script:
    def extension = input_files[0].extension
    """
    cat ${input_files} > concatenated.${extension}
    """
}

process COMPRESS_FILES {

    tag "${input_file}"

    container 'community.wave.seqera.io/library/pigz:2.8--cc287835d69f818b'

    input:
    path input_file

    output:
    path "${input_file}.gz", emit: compressed_file

    script:
    """
    pigz -p ${task.cpus} -c ${input_file} > ${input_file}.gz
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

process TAR_FILES {
    input:
    path "files/*"

    output:
    path 'compressed_files.tar.gz'

    script:
    """
    tar -czvhf compressed_files.tar.gz -C files .
    """
}


process UNTAR_FILES {
    input:
    path compressed_file
    path original_checksum

    output:
    path "verification_results.txt"

    script:
    """
    mkdir uncompressed_files
    tar -xzvf ${compressed_file} -C uncompressed_files

    # Verify checksums
    cd uncompressed_files
    md5sum -c ../${original_checksum} > ../verification_results.txt
    if grep -q 'FAILED' verification_results.txt; then
        echo "Checksum verification FAILED for some files"
        exit 1
    else
        echo "All checksums verified successfully"
    fi
    """
}

workflow {


    mixed_files   = Channel.empty()
    checksum_file = Channel.empty()

    if ( params.enable_fastq_files ) {
        // Create a channel with the parameters for each GENERATE_FAKE_FASTQ process
        generate_params = Channel.from(1..params.fastq_n_files)
                            .map { it -> tuple(params.fastq_n_reads, it, params.fastq_read_length) }

        // Run GENERATE_FAKE_FASTQ processes in parallel
        GENERATE_FAKE_FASTQ(generate_params)

        if ( params.process_fastq_files ) {
            mixed_files = mixed_files.mix( GENERATE_FAKE_FASTQ.out.fastq.filter{ params.process_fastq_files } )
            checksum_file = checksum_file.mix( GENERATE_FAKE_FASTQ.out.checksum.filter{ params.process_fastq_files } )
        }
    }

    if ( params.enable_zero_files ) {
        // Generate many small files in a single process
        ZERO_FILES([params.zero_n_files, params.zero_file_size])

        if ( params.process_zero_files ) {
            mixed_files = mixed_files.mix( ZERO_FILES.out.files.filter{ params.process_zero_files } )
            checksum_file.mix( ZERO_FILES.out.checksum.filter { params.process_zero_files } )
        }
    }

    // Compress the files
    compressed_files = COMPRESS_FILES(mixed_files.flatten())

    // Collect all generated files
    collected_files = mixed_files.collect()

    // Concatenate all files
    CONCATENATE_FILES(collected_files)

    // Count how many files are generated
    COUNT_FILES(collected_files) | view { "Number of small files: $it" }

    // Rename all these files
    RENAME_FILES(collected_files)

    TAR_FILES(collected_files)

    UNTAR_FILES(TAR_FILES.out, checksum_file.collectFile())

}