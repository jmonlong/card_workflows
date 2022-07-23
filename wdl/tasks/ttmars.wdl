version 1.0

## run TT-Mars
task ttmars_t {
  input {
      File reference_file
      File svs_file
      File hap1_file
      File hap2_file
      File centromere_file
      File trf_file
      File non_cov_reg_1_file
      File non_cov_reg_2_file
      File lo_pos_assem1_file
      File lo_pos_assem2_file
      File lo_pos_assem1_0_file
      File lo_pos_assem2_0_file
      Int nb_x_chr=2
	  Int memSizeGb = 8
  }

  Int disk_size = round(5*(size(reference_file, 'G') + 2*size(hap1_file, 'G') + 2*size(non_cov_reg_1_file, 'G') + 4*size(lo_pos_assem1_file, 'G'))) + 30
  
  command <<<
    set -o pipefail
    set -e
    set -u
    set -o xtrace

    
    ## unzip fastas is necessary
    REF=~{reference_file}
    if [[ $REF == *.gz ]]
    then
        gunzip $REF -c > ref.fa
        REF=ref.fa
    fi
    HAP1=~{hap1_file}
    if [[ $HAP1 == *.gz ]]
    then
        gunzip $HAP1 -c > hap1.fa
        HAP1=hap1.fa
    fi
    HAP2=~{hap2_file}
    if [[ $HAP2 == *.gz ]]
    then
        gunzip $HAP2 -c > hap2.fa
        HAP2=hap2.fa
    fi

    mkdir output_files
    
    python /build/TT-Mars/ttmars.py output_files \
           ~{centromere_file} \
           ~{non_cov_reg_1_file} \
           ~{non_cov_reg_2_file} \
           ~{svs_file} \
           $REF $HAP1 $HAP2 \
           ~{lo_pos_assem1_file} \
           ~{lo_pos_assem2_file} \
           ~{lo_pos_assem1_0_file} \
           ~{lo_pos_assem2_0_file} \
           ~{trf_file} \
           -s
       
    python /build/TT-Mars/combine.py output_files ~{nb_x_chr}
  >>>

  output {
	File tsvOutput = "output_files/ttmars_combined_res.txt"
  }

  runtime {
    docker: "quay.io/jmonlong/ttmars@sha256:57bba0cb8c45acb840b1daf3ada9f2141ae8ab55e7c4aadd58403d3defeba6e6"
    cpu: 1
	memory: memSizeGb + " GB"
	disks: "local-disk " + disk_size + " SSD"
  }
}

## make liftover files from LRA alignment between haplotypes and the reference
task liftover_t {
  input {
      File hap1_lra_file
      File hap2_lra_file
	  Int memSizeGb = 8
  }

  Int disk_size = round(10*(size(hap1_lra_file, 'G') + size(hap2_lra_file, 'G'))) + 30
  
  command <<<
    set -o pipefail
    set -e
    set -u
    set -o xtrace
    
    mkdir -p liftover_output

    samtools index ~{hap1_lra_file}
    samtools index ~{hap2_lra_file}
    
    samtools view -h -O sam -o liftover_output/assem1_nool_sort.sam ~{hap1_lra_file}
    samtools view -h -O sam -o liftover_output/assem2_nool_sort.sam ~{hap2_lra_file}

    #liftover using samLiftover (https://github.com/mchaisso/mcutils): ref to asm lo
    python /build/TT-Mars/lo_assem_to_ref.py liftover_output ~{hap1_lra_file} ~{hap2_lra_file}

    samLiftover liftover_output/assem1_nool_sort.sam liftover_output/lo_pos_assem1.bed liftover_output/lo_pos_assem1_result.bed --dir 1
    samLiftover liftover_output/assem2_nool_sort.sam liftover_output/lo_pos_assem2.bed liftover_output/lo_pos_assem2_result.bed --dir 1

    #liftover using samLiftover (https://github.com/mchaisso/mcutils): asm to ref lo
    python /build/TT-Mars/lo_assem_to_ref_0.py liftover_output ~{hap1_lra_file} ~{hap2_lra_file}

    samLiftover liftover_output/assem1_nool_sort.sam liftover_output/lo_pos_assem1_0.bed liftover_output/lo_pos_assem1_0_result.bed --dir 0
    samLiftover liftover_output/assem2_nool_sort.sam liftover_output/lo_pos_assem2_0.bed liftover_output/lo_pos_assem2_0_result.bed --dir 0    

    python /build/TT-Mars/compress_liftover.py liftover_output lo_pos_assem1_result.bed lo_pos_assem1_result_compressed.bed
    python /build/TT-Mars/compress_liftover.py liftover_output lo_pos_assem2_result.bed lo_pos_assem2_result_compressed.bed
    python /build/TT-Mars/compress_liftover.py liftover_output lo_pos_assem1_0_result.bed lo_pos_assem1_0_result_compressed.bed
    python /build/TT-Mars/compress_liftover.py liftover_output lo_pos_assem2_0_result.bed lo_pos_assem2_0_result_compressed.bed

    python /build/TT-Mars-tweaked/get_conf_int.py liftover_output ~{hap1_lra_file}  ~{hap2_lra_file}
  >>>

  output {
	  File non_cov_reg_1_file = "liftover_output/assem1_non_cov_regions.bed"
      File non_cov_reg_2_file = "liftover_output/assem1_non_cov_regions.bed"
      File lo_pos_assem1_file = "liftover_output/lo_pos_assem1_result_compressed.bed"
      File lo_pos_assem2_file = "liftover_output/lo_pos_assem2_result_compressed.bed"
      File lo_pos_assem1_0_file = "liftover_output/lo_pos_assem1_0_result_compressed.bed"
      File lo_pos_assem2_0_file = "liftover_output/lo_pos_assem2_0_result_compressed.bed"
  }

  runtime {
    docker: "quay.io/jmonlong/ttmars@sha256:57bba0cb8c45acb840b1daf3ada9f2141ae8ab55e7c4aadd58403d3defeba6e6"
    cpu: 1
	memory: memSizeGb + " GB"
	disks: "local-disk " + disk_size + " SSD"
  }
}

## align an haplotype to the reference with LRA
task lra_t {
  input {
      File reference_file
      File hap_file
	  Int memSizeGb = 16
      Int threads=16
  }

  Int disk_size = round(5*(size(reference_file, 'G') + size(hap_file, 'G'))) + 30
  
  command <<<
    set -o pipefail
    set -e
    set -u
    set -o xtrace

    
    ## unzip reference fasta is necessary
    REF=~{reference_file}
    if [[ $REF == *.gz ]]
    then
        gunzip $REF -c > ref.fa
        REF=ref.fa
    fi
    HAP=~{hap_file}
    if [[ $HAP == *.gz ]]
    then
        gunzip $HAP -c > hap.fa
        HAP=hap.fa
    fi

    mkdir -p output_files
    
    #use lra (https://github.com/ChaissonLab/LRA) to align asm to ref
    lra index -CONTIG $REF
    lra align -CONTIG $REF $HAP -t ~{threads} -p s | samtools sort -o output_files/assem_sort.bam
    samtools index output_files/assem_sort.bam

    #trim overlapping contigs
    python /build/TT-Mars-tweaked/trim_overlapping_contigs.py output_files/assem_sort.bam output_files
    samtools sort output_files/assem_sort_nool.bam -o output_files/assem_nool_sort.bam
  >>>

  output {
	File bamOutput = "output_files/assem_nool_sort.bam"
  }

  runtime {
    docker: "quay.io/jmonlong/ttmars@sha256:57bba0cb8c45acb840b1daf3ada9f2141ae8ab55e7c4aadd58403d3defeba6e6"
    cpu: threads
	memory: memSizeGb + " GB"
	disks: "local-disk " + disk_size + " SSD"
  }
}