#!/usr/bin/env python3
import os
import sys
import re
import argparse

def scan_fastq_directory(fastq_dir):
    # Supported extensions
    extensions = ['.fastq.gz', '.fq.gz', '.fastq', '.fq']
    
    # List all files in directory
    files = [f for f in os.listdir(fastq_dir) if os.path.isfile(os.path.join(fastq_dir, f))]
    
    # Group files by their prefix and detect R1 / R2
    paired_files = {}
    
    # Pattern matching read indicator: _1, _2, _R1, _R2, .1, .2, etc. before the extension
    # We look for _1, _2, _R1, _R2, -1, -2, -R1, -R2
    pattern = re.compile(r'([._-](R1|R2|1|2))([._-]\d+)?(\.fastq\.gz|\.fq\.gz|\.fastq|\.fq)$', re.IGNORECASE)
    
    for filename in files:
        # Check if it has a fastq extension
        has_ext = False
        for ext in extensions:
            if filename.lower().endswith(ext):
                has_ext = True
                break
        if not has_ext:
            continue
            
        match = pattern.search(filename)
        if match:
            # We found a read number!
            read_indicator = match.group(2) # "R1", "R2", "1", "2"
            
            # Extract sample name by removing the read indicator and the rest of the string
            span = match.span(1)
            sample_name = filename[:span[0]]
            
            # Group by sample_name
            if sample_name not in paired_files:
                paired_files[sample_name] = {}
                
            read_key = "R1" if "1" in read_indicator else "R2"
            paired_files[sample_name][read_key] = os.path.abspath(os.path.join(fastq_dir, filename))
            
    return paired_files

def main():
    parser = argparse.ArgumentParser(description="Create a samples sheet for the WGS pipeline.")
    parser.add_argument("-i", "--input-dir", default="data", help="Directory containing raw fastq files (default: data)")
    parser.add_argument("-o", "--output", default="samples.tsv", help="Path to output TSV file (default: samples.tsv)")
    parser.add_argument("-g", "--genus", default="", help="Optional default genus for Bakta annotation")
    parser.add_argument("-s", "--species", default="", help="Optional default species for Bakta annotation")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.input_dir):
        print(f"Error: Input directory '{args.input_dir}' does not exist.")
        sys.exit(1)
        
    paired_files = scan_fastq_directory(args.input_dir)
    
    if not paired_files:
        print(f"No paired fastq files found in '{args.input_dir}'.")
        sys.exit(0)
        
    # Write to output file
    with open(args.output, "w") as out:
        out.write("name\tpath_R1\tpath_R2\tgenus\tspecies\n")
        for sample, paths in sorted(paired_files.items()):
            r1 = paths.get("R1", "")
            r2 = paths.get("R2", "")
            if r1 and r2:
                out.write(f"{sample}\t{r1}\t{r2}\t{args.genus}\t{args.species}\n")
                print(f"Added sample: {sample} (R1: {os.path.basename(r1)}, R2: {os.path.basename(r2)})")
            elif r1:
                print(f"Warning: Found R1 but no R2 for {sample}. Skipped.")
            elif r2:
                print(f"Warning: Found R2 but no R1 for {sample}. Skipped.")
                
    print(f"Samples sheet successfully created at '{args.output}'.")

if __name__ == "__main__":
    main()
