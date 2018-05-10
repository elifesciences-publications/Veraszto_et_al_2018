
/////////////////////////////////////////////////////////
// This file is best viewed with a monospaced font.    //
/////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////
// ImageJ macro to extract the tracks and the          //
// distribution of the larvae from the raw videos.     //
/////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////
// Asks the user where the input video files are, and  //
// into which directory the output files should go.    //
// The user can give the input directory first and     //
// then the output directory. Or the user can give a   //
// text file that contains on each line an input       //
// directory and an output directory seperated by a    //
// space, for batch processing.                        //
/////////////////////////////////////////////////////////
macro "Extract Tracks"
{
	if(getBoolean("Choose an input and output directory otherwise give a text file containing a list of input and output directories"))
	{
		inputDir = getDirectory("Choose the input directory (where the files are)");
		outputDir = getDirectory("Choose the output directory (where the files should go)");
		extractTracks(inputDir, outputDir);
	}
	else
	{
		fileList = File.openDialog("Open a text file containing a list of input and output directories");
		lines = split(File.openAsString(fileList), "\n");
		for(i = 0; i < lines.length; i++)
		{
			dirs = split(lines[i], " ");
			extractTracks(dirs[0], dirs[1]);
		}
	}
}

/////////////////////////////////////////////////////////
// Extracts the tracks from the videos that are all in //
// the folder inputDir via mTrack2. All files in the   //
// folder inputDir must be video files that ImageJ can //
// read. Otherwise this macro aborts with an error     //
// message. And will not analyse more videos.          //
/////////////////////////////////////////////////////////
function extractTracks(inputDir, outputDir)
{
	// These three parameters can be adjusted
	// depending on video length and frame rate
	numFramesToProcess          = 240;  // 15s with 16fps
	startFrame                  = 1;
	lastFrame                   = numFramesToProcess;

	print (inputDir);
	print (outputDir);

	// Do not show all the calculation steps on the
	// ImageJ user interface, this saves time and memory.
	setBatchMode(true);

	// Get all the files in the input directory.
	list=getFileList(inputDir);
	Array.sort(list);
	print(list.length);

	// Track the number of files that have been read
	files = 0;

	for (k=0; k<list.length; k++)
	{
		print(list[k]); 
		open(inputDir + list[k]);
		imageTitle = getTitle();
		imageTitle = replace(imageTitle, " ", "_"); // Replace spaces by underscores to avoid problems with file writing

		// Remove the first n frames, to synchronize with the phototaxis protocol start.
		// Has to be adjusted for each video.
		// Can be done for several input files individually.
		// This is needed to synchronize the start of the AxioVision
		// protocol and the start of the video, which was started a few
		// seconds before the start of the protocol.
		// For now all set to 0.
		if(files == 0)
		{
			run("Slice Remover", "first=1 last=0 increment=1");
		}
		else if(files == 1)
		{
			run("Slice Remover", "first=1 last=0 increment=1");
		}
		else if(files == 2)
		{
			run("Slice Remover", "first=1 last=0 increment=1");
		}
		else if(files == 3)
		{
			run("Slice Remover", "first=1 last=0 increment=1");
		}
		else if(files == 4)
		{
			run("Slice Remover", "first=1 last=0 increment=1");
		}
		else
		{
			run("Slice Remover", "first=1 last=0 increment=1");
		}

		files++;

		run("8-bit");
		rename("video");

		// Cut the video into smaller parts and give each part an index.
		// Start with 100 to aviod problems with file sorting
		m=100;
		while (nSlices > 1)
		{
			// Process the first n frames of the video so that different points in time can be checked.
			nSlices
			run("Duplicate...", "title=stack duplicate range=" + startFrame + "-" + lastFrame);
			selectWindow("stack");
			processImage();
			selectWindow("stack");
			threshold();

			createDistributionImage(m);
			trackParticles2(m);
			close();

			// Delete the first n frames of the video so that the next n frames can be processed.
			selectWindow("video");
			if(nSlices > numFramesToProcess)
			{
				run("Slice Remover", "first=1 last=" + numFramesToProcess + " increment=1");
			}
			else
			{
				run("Slice Remover", "first=1 last=" + (nSlices-1) + " increment=1");
			}
			selectWindow("video");

			m++;
		}
		close();

	}

	setBatchMode(false);
	print ("End");
}

/////////////////////////////////////////////////////////
// Creates an image of the distribution of the larvae  //
// and saves it to a file in the text image format.    //
/////////////////////////////////////////////////////////
function createDistributionImage(laneNumber)
{
	selectWindow("stack");
	run("Z Project...", "start=1 stop=-1 projection=[Average Intensity]");
	selectWindow("AVG_stack");

	outputFilename= imageTitle + "_lane_" + laneNumber +"_vertical"+".text_image";
	fullPathResults = outputDir + outputFilename;
	saveAs("Text image", fullPathResults);
	close();
}

/////////////////////////////////////////////////////////
// Removes the background so that the moving larvae    //
// are left as dot in the video that can be tracked.   //
// These thing can be adjusted according to the        //
// contrast in the video.                              //
/////////////////////////////////////////////////////////
function processImage()
{
	// Subtract the average projection (Remove background)
	run("Z Project...", "start=1 stop=-1 projection=[Average Intensity]");
	imageCalculator("Subtract stack", "stack","AVG_stack");
	selectWindow("AVG_stack");
	close();
	selectWindow("stack");

	// Apply some filters
	run("Invert", "stack");

	// Adjust the contrast
	run("Max...", "value=253 stack");
	run("Enhance Contrast", "saturated=0.35");
	run("Apply LUT", "stack");
	run("Remove Outliers...", "radius=4 threshold=0 which=Dark stack");
}

/////////////////////////////////////////////////////////
// Thresholds an 8 bit grayscale image, and converts   //
// all pixel above the threshold to 255 (i.e. white).  //
// Otherwise it converts all values to 0 (i.e. black). //
/////////////////////////////////////////////////////////
function threshold()
{
	setThreshold(0, 230);
	run("Convert to Mask", " ");
}

/////////////////////////////////////////////////////////
// Tracks the larvae with mTrack2, and writes the      //
// output to a file, with .res extension.              //
/////////////////////////////////////////////////////////
function trackParticles2(laneNumber)
{
	run("Clear Results");
	outputFilename = imageTitle + "_lane_" + laneNumber + ".res";
	fullPathResults = outputDir + outputFilename;
	run("MTrack2 ", "minimum=3 maximum=100 maximum_=15 minimum_=15 display save save=" + fullPathResults);

	run("Clear Results");
}
