'''
Author: Csaba Veraszto
Date: 15/05/2018
Content: Ca-imaging script, calculates dF/F by normalizing with baseline values from the control measurement. It creates csv files with normalized data and plots them as png.
This script should be run line by line. It recognizes your files based on their names in the specified folder. 
'''

mypath = ("/where/your/files/are/")  #Where your files are

import numpy as np
import os
from os import listdir
from os.path import isfile, join
import re
from os import chdir
maxvalue = 0
minvalue = 0

chdir(mypath)
onlyfiles = [f for f in listdir(mypath) if isfile(join(mypath, f))] #Grab all files from folder
convertedfiles = [x.encode('UTF8') for x in [f for f in listdir(mypath) if isfile(join(mypath, f))]] #Convert all filenames to UTF-8 to be safe
convertedfiles2 = [s for s in convertedfiles if ('.txt') in s] #Remove non-text files from the list.
cafiles = [s for s in convertedfiles2 if ('dt_') in s] #Remove files that does not contain dt_.
#cafiles = [s for s in convertedfiles2 if ('fps_') in s] #For some old fiji macros, this is what you need. See to timerate line too. 
osxbug = [s for s in cafiles if s[0:2]=="._" in s]
cafiles = [filename for filename in cafiles if filename not in osxbug]
cafiles = [s for s in cafiles if "Normalized_Neuron." not in s] #Avoid running the script on normalized data.

#Looking for the controlarea for normalization
controlfile = [s for s in cafiles if ('control') in s]
control = np.genfromtxt(controlfile[0], usecols=[1], skip_header=1)
cafiles = [s for s in cafiles if "control" not in s]

#Looking for UV
UVfile = [s for s in cafiles if ('UV') in s]
UV = np.genfromtxt(UVfile[0], usecols=[1], skip_header=1)
UVnorm = (UV-np.min(UV))/(np.max(UV)-np.min(UV))
np.savetxt("UV.csv", UVnorm, delimiter=",")

cafiles = [s for s in cafiles if "UV" not in s]
n=len(cafiles)


#Batch process list of files
for source_filename in cafiles:
	#source_filename = cafiles[0]
	output_filename = source_filename[source_filename.rfind('dt_')+3:source_filename.rfind('Values')] + ".csv"
	timerate = float(re.findall("[-+]?\d+[\.]?\d*[eE]?[-+]?\d*", source_filename[source_filename.find('_dt'):len(source_filename)])[0]) 
	#timerate = float(re.findall("[-+]?\d+[\.]?\d*[eE]?[-+]?\d*", source_filename[source_filename.find('_fps'):len(source_filename)])[0])                     
	raw = np.genfromtxt(source_filename, usecols=[1], skip_header=1)
	dF_F = ((raw-control)/control)
	#print dF_F
	np.savetxt(output_filename, dF_F, delimiter=",")

#Look for min/max values for plotting.
csvz = [os.path.join(root, name) for root, dirs, files in os.walk(mypath) for name in files if name.endswith(".csv")]
for files in csvz:
    output_imagename = files
    dF_F = np.genfromtxt(output_imagename,delimiter=',')
    if np.max(dF_F) > maxvalue:
        maxvalue = np.max(dF_F)*1.1
if np.min(dF_F) < minvalue:
        minvalue = np.min(dF_F)


def drawer(files, maxvalue):
   ......:     '''Takes a filename and a value (for the y axis) to draw an image'''
   ......:     output_imagename = files[(files.rfind('/')+1):]
   ......:     dF_F = np.genfromtxt(output_imagename,delimiter=',')
   ......:     y_range_low= minvalue
   ......:     y_range_high= maxvalue-1
   ......:     timerate = 1.11
   ......:     import matplotlib.pyplot as plt
   ......:     plt.ioff()
   ......:     fig, ax = plt.subplots()
   ......:     #plt.ylim([y_range_low,y_range_high]) #set y axis range
   ......:     plt.ylim([minvalue,maxvalue])
   ......:     plot_range=dF_F.shape[0]
   ......:     plt.xlim([0,plot_range]) #set x axis range
   ......:     #plt.xlim([0,plot_range])
   ......:     #ax.set_aspect(plot_range/(y_range_high-y_range_low))  #uncomment this if you doesn't want to resizeable image
   ......:     #Plotted data comes next
   ......:     ax.plot(np.arange(len(dF_F)), dF_F, linewidth=2, color='black', label='''neuron_in_question''') #label='normalized original'
   ......:     fig.suptitle(output_imagename)
   ......:     #ax.legend(loc=8) 
   ......:     #import matplotlib.pyplot as plt  
   ......:     #ax.legend(loc='best') # chooses an optimal position for the legend such that it does not block lines/bars of the plot
   ......:     #remove ticks and axes
   ......:     ax.spines['right'].set_visible(False)
   ......:     ax.spines['left'].set_visible(False)
   ......:     ax.spines['top'].set_visible(False)
   ......:     ax.spines['bottom'].set_visible(False)
   ......:     ax.xaxis.set_ticks_position('bottom')
   ......:     ax.yaxis.set_ticks_position('left')
   ......:     ax.set_xticks([])
   ......:     ax.set_yticks([])
   ......:     font = {'family' : 'Arial',
   ......:             'color'  : 'black',
   ......:             'weight' : 'normal',
   ......:             'size'   : 12,
   ......:             }
   ......:     # draw vertical line from (70,100) to (70, 250)
   ......:     ax.arrow(0, y_range_high, 60/timerate, 0, head_width=0, head_length=0, fc='k', ec='k', lw=1.5)
   ......:     plt.text(30, y_range_high+0.02, '60 s', fontdict=font)
   ......:     ax.arrow(0, y_range_high, 0, 0.5, head_width=0, head_length=0, fc='k', ec='k', lw=1.5)
   ......:     plt.text(0.3, y_range_high+0.25, '0.5\n'r'$\Delta$F/F', fontdict=font)
   ......:     plt.savefig(output_imagename[:-4] + ".png", format='png', dpi=300, bbox_inches='tight', pad_inches=0, frameon=None, transparent=True)
   ......:     plt.close()
   ......:     return


for files in csvz:
   ......:     drawer(files, maxvalue)





