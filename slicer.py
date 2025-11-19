from tifffile import imread, imwrite
import os 
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

def main():
  
  timelapse_raw_dir = '/lustre/fsn1/projects/rech/jsy/uzj81mi/Mari_Data_Oneat/Mari_Test_Dataset_Analysis/seg_membrane_timelapses/'
  save_raw_dir = '/lustre/fsn1/projects/rech/jsy/uzj81mi/Mari_Data_Oneat/Mari_Test_Dataset_Analysis/split_seg_timelapses/'
  Path(save_raw_dir).mkdir(exist_ok=True)
  acceptable_formats = [".tif", ".TIFF", ".TIF", ".png"] 
  nthreads = os.cpu_count()
  def slicer(path, save_dir, dtype):
              
              files = os.listdir(path)
              for fname in files:
                if any(fname.endswith(f) for f in acceptable_formats):
                    print(fname)
                    image = imread(os.path.join(path,fname)) 
                    print(image.shape)
                    for i in range(image.shape[0]):

                        imwrite(save_dir + '/' + os.path.splitext(fname)[0] + '_' + str(i) + '.tif' , image[i,:].astype(dtype))
  
  futures = []                   
  with ThreadPoolExecutor(max_workers = nthreads) as executor:
                    futures.append(executor.submit(slicer, timelapse_raw_dir, save_raw_dir, 'uint16')) 

  [r.result() for r in futures]  

if __name__=='__main__':

  main()  