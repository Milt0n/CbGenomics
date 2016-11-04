#!/bin/bash

readonly SOFTWARE_REQUIRED=(fastq-dump spades.py bbduk.sh fastqc quast.py )
readonly SRA_ACCESSION="SraAccList.txt"
readonly ARG="$1"
readonly SRA_FOLDER="/mnt/data/CbGenomics"

# progress prompt
progress_prompt(){
    echo -e "\n######  $1 ######"
}

usage(){
    echo "Usage : $0 [retrieve_sra | qc_fastq | assembly | annotation ]"
}

# checks if a given software is available on the system (not testing for specific version)
is_installed() {
    local software=$1
    command -v $software >/dev/null 2>&1 || { return 1; }
    return 0
}

# checks if all software required are available
software_checklist() {
    progress_prompt "software checklist"
    for software in "${SOFTWARE_REQUIRED[@]}"
    do
	echo -n "Checking if ${software} is installed..........."
 	if is_installed "${software}"; then
	    echo "OK"
	else
	    echo "NOK, $software not installed or not in PATH - exiting"
	    exit -1
	fi
    done
}

# retrieves all the fastq files
retrieve_sra(){
    progress_prompt "retrieving SRA files"
    while IFS= read -r line; do
	# Added adhoc to restart analysis after a failure (if post
	# folder exists, then files have already been processed).
	if [ -d "$SRA_FOLDER/$line" ]; then
	    echo "done"
	    continue
	fi
	
	fastq-dump -v --split-files --outdir $SRA_FOLDER/$line $line
    done < "$SRA_ACCESSION"
}

# performs the QC of the reads
qc_fastq() {
    while IFS= read -r line; do
	# Added adhoc to restart analysis after a failure (if post
	# folder exists, then files have already been processed).
	if [ -d "$SRA_FOLDER/$line/post" ]; then
	    echo "done"
	    continue
	fi
	
	# Reports of pre-processing quality control of fastq files
	progress_prompt "pre-processing quality control"
	mkdir $SRA_FOLDER/$line/pre
	fastqc --outdir $SRA_FOLDER/$line/pre --extract --threads 4 \
	       $SRA_FOLDER/$line/${line}_1.fastq \
	       $SRA_FOLDER/$line/${line}_2.fastq

	# QC of the reads (Clipping adapters)
	progress_prompt "Clipping remaining adapters "
	bbduk.sh in=$SRA_FOLDER/$line/${line}_1.fastq \
		 in2=$SRA_FOLDER/$line/${line}_2.fastq \
		 out=$SRA_FOLDER/$line/${line}_1_trim.fastq \
		 out2=$SRA_FOLDER/$line/${line}_2_trim.fastq \
		 ref=adapters.fa \
		 ktrim=l k=23 mink=11 hdist=2 tpe tbo

	# QC of the reads (size exclusion)
	progress_prompt "Base calling quality control and size exclusion"
	bbduk.sh in=$SRA_FOLDER/$line/${line}_1_trim.fastq \
		 in2=$SRA_FOLDER/$line/${line}_2_trim.fastq \
		 out=$SRA_FOLDER/$line/${line}_1_final.fastq \
		 out2=$SRA_FOLDER/$line/${line}_2_final.fastq \
		 qtrim=r trimq=28 minlen=50
	
	# Reports of post-processing QC of the fastq files
	progress_prompt "post-processing quality control"
	mkdir $SRA_FOLDER/$line/post
	fastqc --outdir $SRA_FOLDER/$line/post --extract --threads 4 \
	       $SRA_FOLDER/$line/${line}_1_final.fastq \
	       $SRA_FOLDER/$line/${line}_2_final.fastq 

	# Clean up folder fastq files (unless you have 1Tb+ free space)
	rm $SRA_FOLDER/$line/${line}_1_trim.fastq \
	   $SRA_FOLDER/$line/${line}_2_trim.fastq \
	   $SRA_FOLDER/$line/${line}_1.fastq \
	   $SRA_FOLDER/$line/${line}_2.fastq
    done < "$SRA_ACCESSION"
}

# denovo assembly with spades and QC with quast
assembly(){
    while IFS= read -r line; do
	# Added adhoc to restart analysis after a failure (if post
	# folder exists, then files have already been processed).
	if [ -d "$SRA_FOLDER/$line/asm" ]; then
	    echo "done"
	    continue
	fi

	# Assembly with spades
	spades.py -t 8 -k 21,33,45,55 --careful \
		  --pe1-1 $SRA_FOLDER/$line/${line}_1_final.fastq \
		  --pe1-2 $SRA_FOLDER/$line/${line}_2_final.fastq \
		  -o $SRA_FOLDER/$line/asm
	
	# QC of the assembly
	quast.py -t 8 -o $SRA_FOLDER/$line/quast_contig \
		 $SRA_FOLDER/$line/asm/contigs.fasta
	quast.py -t 8 -o $SRA_FOLDER/$line/quast_scaf \
		 $SRA_FOLDER/$line/asm/scaffolds.fasta

    done < "$SRA_ACCESSION"
}

# Annotation with prokka
annotation(){
    echo "todo"
}

main() {
    if [ -z "$ARG" ]
    then
     	usage ; exit ;
    fi

    software_checklist

    case "$ARG" in
	"retrieve_sra")
	    retrieve_sra ;;
	"qc_fastq")
	    qc_fastq ;;
	"assembly")
	    assembly ;;
	"annotation")
	    annotation ;;
	*)
	    usage ; exit ;;
    esac
}
main
