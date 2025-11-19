import os
import math
from tqdm import tqdm
from tifffile import imread
from napatrackmater.clustering import Clustering
import pandas as pd

segmentation_directory = '/lustre/fsn1/projects/rech/jsy/uzj81mi/Mari_Data_Oneat/Mari_Test_Dataset_Analysis/split_seg_timelapses/'

files = os.listdir(segmentation_directory)

axes = 'ZYX'

xcalibration = 1
ycalibration = 1
zcalibration = 1

# --- collect rows here ---
rows = []

for fname in tqdm(files):

    if not fname.lower().endswith(('.tif', '.tiff')):
        continue

    seg_image = imread(os.path.join(segmentation_directory, fname))
    time_key = 0 

    cluster_eval = Clustering(
        pretrainer=None,
        accelerator=None,
        devices=1,
        label_image=seg_image,
        axes=axes,
        num_points=2048,
        compute_with_autoencoder=False,
        model=None,
        key=time_key
    )

    cluster_eval._create_cluster_labels()
    timed_cluster_label = cluster_eval.timed_cluster_label
    
    (
        output_labels,
        output_cluster_centroid,
        output_cloud_eccentricity,
        output_eigenvectors,
        output_eigenvalues,
        output_dimensions,
        output_cloud_surface_area,
    ) = timed_cluster_label[str(time_key)]

    # loop over detected clusters
    for i in range(len(output_cluster_centroid)):

        centroid = output_cluster_centroid[i]  # (z,y,x)

        # Check validity of this cluster
        if isinstance(output_eigenvalues[i], int):
            continue

        quality = math.pow(
            output_eigenvalues[i][2] *
            output_eigenvalues[i][1] *
            output_eigenvalues[i][0],
            1.0 / 3.0,
        )

        ecc = output_cloud_eccentricity[i]  # COM first, second, third
        ecc_dim = output_dimensions[i]
        if isinstance(ecc_dim, int):
            continue

        surface_area = (
            output_cloud_surface_area[i]
            * zcalibration * ycalibration * xcalibration
        )

        radius = quality * math.pow(
            zcalibration * xcalibration * ycalibration,
            1.0 / 3.0,
        )

        # --- Add row to list ---
        rows.append({
            "filename": fname,
            "centroid_z": centroid[0],
            "centroid_y": centroid[1],
            "centroid_x": centroid[2],
            "ecc_first": ecc[0],
            "ecc_second": ecc[1],
            "ecc_third": ecc[2],
            "surface_area": surface_area,
            "radius": radius,
        })

# --- Build dataframe ---
df = pd.DataFrame(rows)

# --- Save to CSV in the same directory ---
csv_path = os.path.join(segmentation_directory, "segmentation_measurements.csv")
df.to_csv(csv_path, index=False)

print("Saved CSV to:", csv_path)
