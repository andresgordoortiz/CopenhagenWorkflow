import os
import math
from tqdm import tqdm 
from tifffile import imread
from napatrackmater.clustering import Clustering


segmentation_directory = '/lustre/fsn1/projects/rech/jsy/uzj81mi/Mari_Data_Oneat/Mari_Test_Dataset_Analysis/split_seg_timelapses/'


files = os.listdir(segmentation_directory)

axes = 'ZYX'

xcalibration = 1
ycalibration = 1
zcalibration = 1


for fname in tqdm(files):
        
        seg_image = imread(os.path.join(segmentation_directory, fname))
        time_key = 0 

        cluster_eval = Clustering(
                        pretrainer = None,
                        accelerator = None,
                        devices = 1,
                        label_image = seg_image,
                        axes = axes,
                        num_points = 2048,
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
        ) = timed_cluster_label[time_key]

        for i in range(len(output_cluster_centroid)):
                centroid = output_cluster_centroid[i]
                if not isinstance(output_eigenvalues[i], int):
                    quality = math.pow(
                        output_eigenvalues[i][2]
                        * output_eigenvalues[i][1]
                        * output_eigenvalues[i][0],
                        1.0 / 3.0,
                    )
                    eccentricity_comp_firstyz = output_cloud_eccentricity[i]
                    eccentricity_dimension = output_dimensions[i]
                    if not isinstance(eccentricity_dimension, int):

                        cell_axis_x = output_eigenvectors[i][2]
                        cell_axis_y = output_eigenvectors[i][1]
                        cell_axis_z = output_eigenvectors[i][0]

                        surface_area = (
                            output_cloud_surface_area[i]
                            * zcalibration
                            * ycalibration
                            * xcalibration
                        )
                       
                        radius = quality * math.pow(
                            zcalibration * xcalibration * ycalibration,
                            1.0 / 3.0,
                        )

                        print(centroid, eccentricity_comp_firstyz, surface_area, radius)        
                       
