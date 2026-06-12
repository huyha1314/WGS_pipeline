import os
import glob

def read_fasta_headers(fasta_path):
    headers = []
    with open(fasta_path, 'r') as f:
        for line in f:
            if line.startswith('>'):
                header = line.strip()[1:].split()[0] # get first word after '>'
                headers.append(header)
    return headers

def read_depth_file(depth_path):
    depth_dict = {}
    if not os.path.exists(depth_path):
        return depth_dict
    with open(depth_path, 'r') as f:
        header = f.readline() # read header
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 3:
                contig_name = parts[0]
                length = int(parts[1])
                depth = float(parts[2])
                depth_dict[contig_name] = (length, depth)
    return depth_dict

def calculate_bin_depth(fasta_path, depth_dict):
    headers = read_fasta_headers(fasta_path)
    total_len = 0
    weighted_depth_sum = 0.0
    contig_count = 0
    missing_contigs = 0
    
    for h in headers:
        if h in depth_dict:
            length, depth = depth_dict[h]
            total_len += length
            weighted_depth_sum += (length * depth)
            contig_count += 1
        else:
            missing_contigs += 1
            
    avg_depth = weighted_depth_sum / total_len if total_len > 0 else 0.0
    return avg_depth, total_len, contig_count, missing_contigs

if __name__ == '__main__':
    binning_dir = '/worker_data2/huyha/precisiongene/suran_wgs/results/binning'
    assemblies_dir = '/worker_data2/huyha/precisiongene/suran_wgs/results/collected_assemblies'
    
    fasta_files = sorted(glob.glob(os.path.join(assemblies_dir, '*.fasta')))
    
    print("=== Depth Analysis for All Collected Assemblies ===")
    
    for fasta_path in fasta_files:
        bin_name = os.path.basename(fasta_path)
        # Determine sample name from bin name
        # E.g. "85_maxbin.001.fasta" -> sample "85"
        # E.g. "243.fasta" -> sample "243"
        sample_name = bin_name.split('_')[0].split('.')[0]
        
        depth_file = os.path.join(binning_dir, sample_name, f"{sample_name}_depth.txt")
        depth_dict = read_depth_file(depth_file)
        
        if not depth_dict:
            # Try without underscore
            depth_file = os.path.join(binning_dir, sample_name, f"{sample_name}_depth.txt")
            print(f"Warning: Depth file not found for sample {sample_name} at {depth_file}")
            continue
            
        avg_depth, total_len, contig_count, missing = calculate_bin_depth(fasta_path, depth_dict)
        print(f"\nBin: {bin_name} (Sample: {sample_name})")
        print(f"  Total Contigs: {contig_count}")
        print(f"  Total Length: {total_len:,} bp")
        print(f"  Length-weighted Average Depth: {avg_depth:.2f}x")
        if missing > 0:
            print(f"  Warning: {missing} contigs from this bin were not found in the depth file.")
