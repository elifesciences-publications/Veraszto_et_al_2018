#!/usr/bin/perl -w

########################################################
# This script takes as input two files from the ImageJ #
# macro. The first file contains the coordinates for   #
# each track: x, y, and time encoded as frame number.  #
# The second file contains the vertical distribution   #
# of the larvae in text-image format.                  #
# The second file is implicitly given by the name of   #
# the first file, which is appended by                 #
# _vertical.text_image.txt to form the name of the     #
# second file.                                         #
# This script takes additional input parameters, see   #
# below or start the script with insufficient input    #
# parameters.                                          #
# This script generates several output file. One is a  #
# larval distribution image as png file. It also       #
# generates a track plot of the single tracks, which   #
# is useful for debugging and trouble shooting, for    #
# more details see below where the code generates the  #
# image.                                               #
# Another file contains the summary of various         #
# measurements, like the average displacement of the   #
# larvae across the vertical axis. This file can be    #
# appended when more measurements come in.             #
########################################################

use strict;
use warnings;

# Get the directory of this script:
use FindBin qw($Bin);
use lib $FindBin::Bin;
FindBin::again(); # Just to be sure that it hasn't been called in another script before

use Statistics::Descriptive;
use Math::BigFloat;
use Math::Trig;
use MTrack;
use File::Basename;

use Storable qw<dclone>;

########################################################
# NormalizeToCount divides a value by count, which     #
# should be positive. Returns zero if count is not     #
# bigger zero.                                         #
########################################################
sub NormalizeToCount
{
	my $value = $_[0];
	my $count = $_[1];
	
	if($count > 0)
	{
		return $value / $count;
	}
	else
	{
		return 0;
	}
}

########################################################
# Determine the best distance between the single       #
# ticks, so that the plots are the most readable and   #
# scalable.                                            #
########################################################
sub BestTick
{
    my $largest   = $_[0];
    my $mostticks = $_[1];
    my $minimum = $largest / $mostticks;
    my $magnitude = 10 ** floor(log($minimum) / log(10));
    my $residual = $minimum / $magnitude;

    if    ($residual > 5) { return 10 * $magnitude;}
    elsif ($residual > 2) { return  5 * $magnitude;}
    elsif ($residual > 1) { return  2 * $magnitude;}
    else                  { return      $magnitude;}
}

########################################################
# Min, Max, and Round functions                        #
########################################################
sub max ($$) { $_[$_[0] < $_[1]] }
sub min ($$) { $_[$_[0] > $_[1]] }

# Perl doesn't have round, so let's implement it
sub round
{
    my($number) = shift;
    return int($number + .5 * ($number <=> 0));
}

use POSIX qw(ceil floor);
use GD::Simple;

########################################################
# Deal with script input                               #
########################################################
my $usage  = "usage: perl program.pl infile.res fps column_width_in_px air_at_top_in_px not_visible_bottom_in_px (mTrackVersion), (column_width_in_mm), (display_left_right), (printFramesMode), (printFramesBackground), (particleSize), (trackImageStyle) \n\n"
           . "perl:                     Start perl\n"
           . "program.pl:               This script\n"
           . "infile.res:               mTrack output file: Do not use files containing spaces, unless you escape the spaces\n"
           . "fps:                      The frame rate the video was recorded with\n"
           . "column_width_in_px:       The width of the view field on screen in pixels\n"
           . "air_at_top_in_px:         Number of pixels that should be removed from the top\n"
           . "not_visible_bottom_in_px: Number of pixels that should be cut from the bottom\n"
           . "mTrackVersion:            The version of mTrack that was used to generate the tracks, default value 2\n"
           . "                          Use 2 for mTrack2, and any other value for mTrack3.\n"
           . "column_width_in_mm:       The width of the view field on screen in mm, default value 31 mm\n"
           . "                          If not default value is used, isMTrack3 must be specified.\n"
           . "display_left_right:       If 0 distinguishes upward and downward tracks by color,\n"
           . "                          Otherwise distinguishes leftward and rightward tracks by color.\n"
           . "                          Default value is 0.\n"
           . "printFramesMode:          If bigger 0, it generates for each frame points and track images.\n"
           . "                          If 1 it encodes the tracks and dots by time.\n"
           . "                          If 2 it encodes the tracks and dots by angel.\n"
           . "                          If bigger 2, it encodes the tracks and dots by up and down, and time.\n"
           . "                          Default value is 0.\n"
           . "printFramesBackground:    If printFramesMode bigger 0, it makes the background white.\n"
           . "                          If it is 1 it makes the background black. Otherwise does not create frames.\n"
           . "                          Default value is 0.\n"
           . "particleSize:             If printFramesMode bigger 0, it specifies the size of the particles to be printed.\n"
           . "                          The default size is 10.\n"
           . "trackImageStyle:          Defines how the images for the tracks are layouted:\n"
           . "                          0 is debug style and default,\n"
           . "                          1 is presentation style,\n"
           . "                          otherwise is thesis style.\n"
           . "\n";


# Check that everything is okay, sometimes tabs, spaces, and newlines make trouble. The number of arguments could hint about this.
print scalar(@ARGV), "\n";

die $usage unless (@ARGV > 4 and @ARGV < 13);

my $infile = $ARGV[0];
print $infile, "\n";

my $mTrackVersion = (@ARGV > 5) ? $ARGV[5] : 2;
print "mTrack version used: ", $mTrackVersion, "\n";

# Variable parameters fetched from the script arguments:
my $frame_rate                        = $ARGV[1];
my $columnWidth_in_px                 = $ARGV[2];
my $columnWidth_in_mm                 = (@ARGV > 6) ? $ARGV[6] : 31;
my $mm_per_pixel                      = $columnWidth_in_mm/$columnWidth_in_px;
my $pixels_air                        = $ARGV[3];
my $pixels_bottom                     = $ARGV[4];
my $is_left_right                     = (@ARGV > 7) ? $ARGV[7] != 0 : 0;
my $printFramesMode                   = (@ARGV > 8) ? $ARGV[8] : 0;
my $printFramesBackground             = (@ARGV > 9) ? $ARGV[9] : 0;
my $particleSize                      = (@ARGV > 10) ? $ARGV[10] : 10;
my $trackImageStyle                   = (@ARGV > 11) ? $ARGV[11] : 0;

# Print input parameters on screen, to display that everything is right.
print "Frame Rate: ",               $frame_rate,
      "\nColumn Width in pixel: ",  $columnWidth_in_px,
      "\nColumn Width in mm: ",     $columnWidth_in_mm,
      "\nmm per pixel: ",           $mm_per_pixel,
      "\nPixels air: ",             $pixels_air,
      "\nPixels bottom: ",          $pixels_bottom,
      "\nIs left right: ",          $is_left_right,
      "\nPrint Frame Mode: ",       $printFramesMode,
      "\nPrint Frame Background: ", $printFramesBackground,
      "\nParticle Size: ",          $particleSize,
      "\nTrack Image Style: ",      $trackImageStyle,
      "\n";

########################################################
# Initialize variables                                 #
########################################################

my $delta                              = 0;
my @Array_of_Scalar_Products           = ();
my @Array_of_All_Track_Scalar_Products = ();
my $size                               = 0;
my $sum_cosine_tracks                  = 0;
my $avg_cosine_tracks                  = 0;
my @All_X_Moves                        = ();
my @All_Y_Moves                        = ();
my $avg_Y_move_tracks                  = 0;
my $sum_Y_move_tracks                  = 0;
my @positions                          = ();
my $pos_move_counter                   = 0;
my $neg_move_counter                   = 0;
my $Total_Y_Pos_Move                   = 0;
my $Total_Y_Neg_Move                   = 0;
my $Total_Y_Abs_Move                   = 0;
my $Total_Y_Move                       = 0;
my $Total_X_Move                       = 0;
my $Total_Move                         = 0;
my $Total_Pos_Move                     = 0;
my $Total_Neg_Move                     = 0;
my $Total_Abs_Move                     = 0;
my $Total_Plot_X_Move                  = 0;
my $Total_Plot_Y_Move                  = 0;
my @full_vector_angles                 = ();
my @trackStart                         = ();
my @averageDistances                   = ();
my @average_X_Moves                    = ();
my @average_X_Moves_Counter            = ();
my @average_Y_Moves                    = ();
my @average_Y_Moves_Counter            = ();
my @average_distances                  = ();
my @average_distances_Counter          = ();
my $median_X_Moves                     = 0;
my $median_Y_Moves                     = 0;
my $Total_Single_X_Move                = 0;
my $Total_Single_X_Move_Counter        = 0;
my $Total_Single_X_Pos_Move            = 0;
my $Total_Single_X_Pos_Move_Counter    = 0;
my $Total_Single_X_Neg_Move            = 0;
my $Total_Single_X_Neg_Move_Counter    = 0;
my $Total_Single_X_Abs_Move            = 0;
my $Total_Single_X_Abs_Move_Counter    = 0;
my $Total_Single_X_Straightness        = 0;
my $Total_Single_Y_Move                = 0;
my $Total_Single_Y_Move_Counter        = 0;
my $Total_Single_Y_Pos_Move            = 0;
my $Total_Single_Y_Pos_Move_Counter    = 0;
my $Total_Single_Y_Neg_Move            = 0;
my $Total_Single_Y_Neg_Move_Counter    = 0;
my $Total_Single_Y_Abs_Move            = 0;
my $Total_Single_Y_Abs_Move_Counter    = 0;
my $Total_Single_Y_Straightness        = 0;
my $Total_Single_Distance              = 0;
my $Total_Single_Distance_Counter      = 0;
my $all_track_pieces                   = 0;
my $upward_track_pieces                = 0;
my $downward_track_pieces              = 0;
my $rightward_track_pieces             = 0;
my $leftward_track_pieces              = 0;
my $top_track_pieces                   = 0;
my $bottom_track_pieces                = 0;
my $right_track_pieces                 = 0;
my $left_track_pieces                  = 0;

########################################################
# Create Results file if there is none.                #
########################################################

# Get input file name without suffix
my($filename, $path, $suffix) = fileparse($infile, qr/\.[^.]*/);
my $basefile = File::Spec->catfile($path, $filename);

# Put the output result file into the same folder as the input files
my $ResultsFile = File::Spec->catfile($path, "Results.txt");

# Create the results file if it does not exist and write a header to it
if(! -e $ResultsFile)
{
	open (RESULTS, ">$ResultsFile") or die "Error: ", print "\nCannot open file!\n$ResultsFile! \n";
	print RESULTS  "File Name",
	               "\t#Vectors",
	               "\t#upward Vectors",
	               "\t#downward Vectors",
	               "\t#leftward Vectors",
	               "\t#rightward Vectors",
	               "\t%upward Vectors",
	               "\t%downward Vectors",
	               "\t%leftward Vectors",
	               "\t%rightward Vectors",
	               "\t#Average x Displacement", # Horizontal displacement
	               "\t#Average y Displacement", #   Vertical displacement
	               "\t#Average x positive Displacement",
	               "\t#Average y positive Displacement",
	               "\t#Average x negative Displacement",
	               "\t#Average y negative Displacement",
	               "\t#Average x absolute Displacement",
	               "\t#Average y absolute Displacement",
	               "\t#Average x Movement",
	               "\t#Average y Movement",
	               "\t#Average positive y Movement",
	               "\t#Average negative y Movement",
	               "\t#Average absolute y Movement",
	               "\t#Average Movement",
	               "\t#Average positive Movement",
	               "\t#Average negative Movement",
	               "\t#Average absolute Movement",
	               "\t#Larvae", # Number of larvae
	               "\t#Larvae Upper",
	               "\t#Larvae Lower",
	               "\t#Larvae % Upper",
	               "\t#Larvae % Lower",
	               "\t#Upward Speed (mm per sec)",
	               "\t#Downward Speed (mm per sec)",
	               "\t#Absolute Speed (mm per sec)",
	               "\t#Single Sum Speed (mm per sec)",
	               "\t#Sum Speed (mm per sec)",
	               "\t#Speed (mm per sec)", # Speed of the larvae
	               "\t#Median depth (mm from surface)",# Median depth
	               "\t#Median depth (in %)",# Median depth percentage from top to bottom
	               "\t#Median left/right (mm from middle)",
	               "\t#Median left/right (in % from middle)",
	               "\t#Simple X straightness",
	               "\t#Simple Y straightness",
	               "\t#Single X straightness",
	               "\t#Single Y straightness",
	               "\t#Average Angel",
	               "\t#Top Vectors",
	               "\t#Bottom Vectors",
	               "\t#Left Vectors",
	               "\t#Right Vectors",
	               "\t%Top Vectors",
	               "\t%Bottom Vectors",
	               "\t%Left Vectors",
	               "\t%Right Vectors",

	               "\t#Track Pieces",
	               "\t#Upward track pieces",
	               "\t#Downward track pieces",
	               "\t#Leftward track pieces",
	               "\t#Rightward track pieces",
	               "\t#Top track pieces",
	               "\t#Bottom track pieces",
	               "\t#Left track pieces",
	               "\t#Right track pieces",

	               "\t%Upward track pieces",
	               "\t%Downward track pieces",
	               "\t%Leftward track pieces",
	               "\t%Rightward track pieces",
	               "\t%Top track pieces",
	               "\t%Bottom track pieces",
	               "\t%Left track pieces",
	               "\t%Right track pieces",

	               "\t#Median X Movement",
	               "\t#Median Y Movement",

	               "\n";

	close RESULTS;
}

########################################################
# Calculate the vertical and horizontal distributions. #
########################################################
open (RESULTS_IN, "<$basefile"."_vertical.text_image.txt") or die "Error: ", print "\nCannot open file!\n$! \n";

# Open and run through, to get the number of lines
while (<RESULTS_IN>) {}

my $no_of_lines = $.; # Get the number of lines
my $lineNumber = 0;
my @vertical_distribution = ();
my @horizontal_distribution = ();
my $sum_of_all_vertical_values = 0;
my $column_width = 0;

# Open the text-image from mTrack output
close RESULTS_IN;
open (RESULTS_IN, "<$basefile"."_vertical.text_image.txt") or die "Error: ", print "\nCannot open file!\n$! \n";

# Calculate normalized distribution from the text-image
while (defined (my $line = <RESULTS_IN>))    # Sums up the pixel values in the text_image file for each line separately
{
	my $sum=0;
	my @pixel_values = split (/\t/, $line);

	if($column_width == 0){ $column_width = scalar(@pixel_values); }

	if
	  (
	       $lineNumber >= $pixels_air
	    && $lineNumber <= $no_of_lines - $pixels_bottom
	  )
	{
		my $i = 0;
		foreach (@pixel_values)
		{
			$sum += $_;
			$horizontal_distribution[$i] += $_;
			$i++;
		}

		$sum_of_all_vertical_values+=$sum;
	}

	$lineNumber++;

	push (@vertical_distribution, $sum);
}

# Normalize the vertical distribution
foreach (@vertical_distribution)
{
	# $_ is a reference
	if($sum_of_all_vertical_values > 0)
	{
		$_=$_/$sum_of_all_vertical_values;
	}
}

# Normalize the horizontal distribution
foreach (@horizontal_distribution)
{
	# The sum of all vertical values is identical to the sum of all horizontal values
	if($sum_of_all_vertical_values > 0)
	{
		$_=$_/$sum_of_all_vertical_values;
	}
}

########################################################
# Read in tracks and distances from mTrack output      #
########################################################

# Read in all the tracks from the mTRack output file.
my @tracks = MTrack::ReadTracks($infile, $mTrackVersion);

# Figure out the length of the longest track in the dataset
my $track_length                       = 0;

for(my $t = 0; $t < scalar(@tracks); $t++)
{
	if($track_length < $#{$tracks[$t]}+1)
	{
		$track_length = $#{$tracks[$t]}+1;
	}
}

########################################################
# Invalidate all the parts of the tracks that reach    #
# beyond the cutoff pixel values at the top and the    #
# bottom of the column. Split the tracks if necessary. #
########################################################
for(my $t = scalar(@tracks)-1; $t >= 0; $t--)
{
	my $frameCounter = 0;
	my $continiousCounter = 0;
	my $continuity = 0;
	for(my $f = $#{$tracks[$t]}; $f >= 0; $f--)
	{
		# Save this into a local variable,
		# and use that for the testing. Otherwise
		# we run out of memory with big data sets.
		# Bug in perl.
		my $pos = $tracks[$t][$f];
		if
		(
		     $pos->{isValid}
		  && 
		     (
		          $pos->{y} < $pixels_air
		       || $pos->{y} > $no_of_lines - $pixels_bottom
		     )
		)
		{
			$pos->{isValid} = 0;
		}
		
		if($pos->{isValid})
		{
			$frameCounter++;
			$continiousCounter++;
		}
		elsif(!$pos->{isValid} && $continiousCounter == 1)
		{
			my $pos2 = $tracks[$t][$f+1];
			$pos2->{isValid} = 0;
			$continiousCounter = 0;
			$frameCounter--;
		}
		elsif(!$pos->{isValid})
		{
			$continuity = max($continuity, $continiousCounter);
			$continiousCounter = 0;
		}
	}

	$continuity = max($continuity, $continiousCounter);

	if($frameCounter <= 1)
	{
		splice @tracks, $t, 1;
		next;
	}

	if($continuity < $frameCounter)
	{
		# Copy subarray, including its elements and not only the references to those elements
		my @tracks_copy = @{dclone($tracks[$t])};
		
		$frameCounter      = 0;
		$continiousCounter = 0;

		for(my $f = $#{$tracks[$t]}; $f >= 0; $f--)
		{
			my $pos      = $tracks[$t][$f];
			my $pos_copy = $tracks_copy[$f];

			if($pos->{isValid})
			{
				$frameCounter++;
				$continiousCounter++;

				if($frameCounter == $continiousCounter)
				{
					$pos_copy->{isValid} = 0;
				}
				else
				{
					$pos->{isValid} = 0;
				}
			}
			else
			{
				$continiousCounter = 0;
			}
		}
		unshift(@tracks, \@tracks_copy); # Insert at the beginning
		$t++; # Correct index, after insert
	}
}

# Exit if we have no tracks, but record the current input file in the results file.
if(scalar(@tracks) == 0)
{
	open (RESULTS, ">>$ResultsFile") or die "Error: ", print "\nCannot open file!\n$! \n";

	# Write the data to the results file.
	print RESULTS $infile, "\n";
	close RESULTS;
	
	print "Exit: No tracks found\n";
	exit;
}

########################################################
#                                                      #
# Create an image. It contains:                        #
# - The larval tracks in the column                    #
#   - The tracks are colored depending on time         #
#     - Red to yellow for upward tracks                #
#     - Blue to cyan for downward tracks               #
#   - The start and end points are connected by        #
#     vectors                                          #
# - The larval tracks aligned to a common origin       #
# - The larval vectors aligned to a common origin and  #
#   an average vector                                  #
# - The tracks broken into frame by frame pieces       #
#   multiplied by 10, with the end points plotted      #
#   around a common origin.                            #
# - The y component multiplied by 10 of the tracks     #
#   broken into frame by frame pieces plotted in       #
#   reference to a time axis.                          #
# - Average of the tracks broken into frame by frame   #
#   pieces over time per frame and multiplied by 10.   #
# - Culminated average multiplied by 10of the tracks   #
#   broken into frame by frame pieces over time.       #
# - Collect movement information for quantification.   #
#                                                      #
########################################################
my $no_of_tracks                       = scalar(@tracks);

# Scale the output image size according to the original video dimensions, so that everything has space on it
my $img;
if($trackImageStyle == 0 || $trackImageStyle == 1)
{
	# For standart styles
	$img = GD::Simple->new(max($column_width*5 +50, $track_length + 50 + $column_width), $lineNumber*2 + 50, 1);
}
else
{
	# Use for thesis
	$img = GD::Simple->new($column_width*3.2 + 50, $lineNumber, 1);
}

# Scale the elements on the picture relatively to each other
my $averageOffset  = ({x => 0.5*$column_width+10, y => $lineNumber*1.8});
my $speedOffset    = ({x => 0.5*$column_width+10, y => $lineNumber*1.5});
my $scaleOffset    = ({x => 1.0*$column_width+10, y => 0});

my $centerOffset;
my $vectorOffset;
	
if($trackImageStyle == 0)
{
	# Use for debugging and trouble shooting:
	$centerOffset   = ({x => 2.0*$column_width+20, y => $lineNumber+25});
	$vectorOffset   = ({x => 3.5*$column_width+30, y => $lineNumber+25});
}
elsif($trackImageStyle == 1)
{
	# Use for presentations:
	$centerOffset   = ({x => 2.7*$column_width+20, y => $lineNumber/2+25});
	$vectorOffset   = ({x => 4.4*$column_width+30, y => $lineNumber/2+25});
}
else
{
	# Use for thesis:
	$centerOffset   = ({x => 1.9*$column_width+20, y => $lineNumber/2+25});
	$vectorOffset   = ({x => 2.8*$column_width+30, y => $lineNumber/2+25});
}
	
print "Number of tracks: ", $no_of_tracks, "\n";
print "Track length: ", $track_length, "\n";

# Print the axes crossing at the center of the tracks starting from a common origin
$img->bgcolor(0,0,0);
$img->fgcolor(0,0,0);
$img->penSize(1);
$img->moveTo($speedOffset->{x},     $speedOffset->{y}+200);
$img->lineTo($speedOffset->{x},     $speedOffset->{y}-200);
$img->moveTo($speedOffset->{x}-200, $speedOffset->{y});
$img->lineTo($speedOffset->{x}+200, $speedOffset->{y});


$img->moveTo($averageOffset->{x}*2,     $averageOffset->{y});
$img->lineTo(max($column_width*4 +50, $track_length + 50 + $column_width),     $averageOffset->{y});

# Draw temporal axes with ticks and labels after every 30 seconds
for(my $i = 0; $i < $track_length; $i += $frame_rate * 30)
{
	$img->moveTo($averageOffset->{x}*2 + $i,     $averageOffset->{y}+200);
	$img->lineTo($averageOffset->{x}*2 + $i,     $averageOffset->{y}-200);
	$img->moveTo(  $speedOffset->{x}*2 + $i,     $speedOffset->{y}+200);
	$img->lineTo(  $speedOffset->{x}*2 + $i,     $speedOffset->{y}-200);
	$img->moveTo(  $speedOffset->{x}*2 + $i +10, $speedOffset->{y}+200);
	$img->string($i . " frame");
	$img->moveTo(  $speedOffset->{x}*2 + $i +10, $speedOffset->{y}+180);
	$img->string($i/$frame_rate . "\'");
	$img->moveTo(  $speedOffset->{x}*2 + $i +10, $speedOffset->{y}+160);
	$img->string($i/$frame_rate/60 . "\'\'");
}

# Set the size before, saves expansive resizing
$averageDistances[scalar(@tracks)-1] = 0;
      $trackStart[scalar(@tracks)-1] = 0;

$average_X_Moves          [$track_length-1] = 0;
$average_X_Moves_Counter  [$track_length-1] = 0;
$average_Y_Moves          [$track_length-1] = 0;
$average_Y_Moves_Counter  [$track_length-1] = 0;
$average_distances        [$track_length-1] = 0;
$average_distances_Counter[$track_length-1] = 0;

# Init values
for(my $f = 0; $f < $track_length; $f++)
{
	$average_X_Moves          [$f] = 0;
	$average_X_Moves_Counter  [$f] = 0;
	$average_Y_Moves          [$f] = 0;
	$average_Y_Moves_Counter  [$f] = 0;
	$average_distances        [$f] = 0;
	$average_distances_Counter[$f] = 0;
}

# Draw the tracks and the vectors
for(my $t = 0; $t < scalar(@tracks); $t++)
{
	my $lastPos           = ({x => 0, y => 0});
	my $initPos           = ({x => 0, y => 0});
	my $gotFirstFrame     = 0;
	my $distanceCounter   = 0;
	$averageDistances[$t] = 0;

	for(my $f = 0; $f < $#{$tracks[$t]}+1; $f++)
	{
		# Put this into a local variable, so that perl does not freak out at big data sets.
		my $pos = $tracks[$t][$f];
		# Get the start frame of the current track
		if($pos->{isValid} && !$gotFirstFrame)
		{
			$trackStart[$t] = $f;

			$gotFirstFrame = 1;
			$lastPos = ({x => $pos->{x}, y => $pos->{y} - $pixels_air});
			$initPos = ({x => $pos->{x}, y => $pos->{y} - $pixels_air});

			# Go to next loop iteration
			next;
		}
		
		# Last frame with track reached, so leave the inner loop
		if(!$pos->{isValid} && $gotFirstFrame)
		{
			# Leave loop
			last;
		}

		# Paint the tracks in the column and from a common origin
		if($gotFirstFrame)
		{
			my $thisPos = ({x => $pos->{x}, y => $pos->{y} - $pixels_air});

			my $x = $thisPos->{x} - $lastPos->{x};
			my $y = $thisPos->{y} - $lastPos->{y};

			my $gamma = atan2(-$y, $x);
			$all_track_pieces++;

			# Score the number of up and down, and right and left track pieces from the angles
			if($gamma < 7*pi/12 && $gamma > 5*pi/12)
			{
				$top_track_pieces++;
			}
			if($gamma > -7*pi/12 && $gamma < -5*pi/12)
			{
				$bottom_track_pieces++;
			}
			if(abs($gamma) - pi/2 < 7*pi/12 && abs($gamma) - pi/2 > 5*pi/12)
			{
				$left_track_pieces++;
			}
			if(abs($gamma) - pi/2 > -7*pi/12 && abs($gamma) - pi/2 < -5*pi/12)
			{
				$right_track_pieces++;
			}

			# Score the number of upward and downward pointing track pieces from the vector angles
			if($gamma > 0)
			{
				$upward_track_pieces++;
			}
			else
			{
				$downward_track_pieces++;
			}

			# Correct way to turn the angle:
			# If $_ >= 0:   $_ - pi/2
			# If $_ <  0: -($_ + pi/2)
			# But the result is the same
			if(abs($gamma) - pi/2 > 0)
			{
				$leftward_track_pieces++;
			}
			else
			{
				$rightward_track_pieces++;
			}

			my $distance = sqrt($x**2 + $y**2);

			# Average the distances the larvae traveled 
			$averageDistances[$t] += $distance;
			$distanceCounter++;

			# Average the x component the larvae traveled 
			$average_X_Moves[$f] += $x;
			$average_X_Moves_Counter[$f]++;
			# Average the y component the larvae traveled 
			$average_Y_Moves[$f] += $y;
			$average_Y_Moves_Counter[$f]++;
			# Average the distances the larvae traveled 
			$average_distances[$f] += $distance;
			$average_distances_Counter[$f]++;
			push (@All_X_Moves, $x);
			push (@All_Y_Moves, $y);

			if($x >= 0)
			{
				$Total_Single_X_Pos_Move += $x;
				$Total_Single_X_Pos_Move_Counter++;
			}
			else
			{
				$Total_Single_X_Neg_Move += $x;
				$Total_Single_X_Neg_Move_Counter++;
			}

			# Up is positive, but the y-axis is reversed on screen. So change sign.
			if($y <= 0)
			{
				$Total_Single_Y_Pos_Move -= $y;
				$Total_Single_Y_Pos_Move_Counter++;
			}
			else
			{
				$Total_Single_Y_Neg_Move -= $y;
				$Total_Single_Y_Neg_Move_Counter++;
			}

			$Total_Single_X_Abs_Move += abs($x);
			$Total_Single_X_Abs_Move_Counter++;
			$Total_Single_Y_Abs_Move += abs($y);
			$Total_Single_Y_Abs_Move_Counter++;

			$Total_Single_X_Straightness += NormalizeToCount($x, $distance);
			$Total_Single_Y_Straightness -= NormalizeToCount($y, $distance);
			$Total_Single_Distance += $distance;
			$Total_Single_Distance_Counter++;

			# This disturbs the vector plotting with some tracks
			# But this seems to be a problem of the GD::Simple library
			# Color tracks pointing upwards from red to yellow depending on time
			# Color tracks pointing downwards from blue to cyan depending on time
			my $red;
			my $green;
			my $blue;

			if($is_left_right)
			{
				$red   = ($x >= 0) ? 255 : 0;
				$green = round($f*(255/($track_length)));
				$blue  = ($x <  0) ? 255 : 0;
			}
			else
			{
				$red   = ($y <= 0) ? 255 : 0;
				$green = round($f*(255/($track_length)));
				$blue  = ($y >  0) ? 255 : 0;
			}

			$img->penSize(2);
			$img->fgcolor($red, $green, $blue);
			$img->bgcolor($red, $green, $blue);

			# Draw the frame by frame vector ends from a common origin multiplied by 10
			$img->moveTo($speedOffset->{x} + $x*10, $speedOffset->{y} + $y*10);
			$img->ellipse(2,2);
			# Draw the frame by frame vector ends over time multiplied by 10
			$img->moveTo($speedOffset->{x}*2 + $f, $speedOffset->{y} + $y*10);
			$img->ellipse(2,2);

			# Draw the tracks in the column, multiply by 10 for debugging
			$img->moveTo($lastPos->{x}, $lastPos->{y});
			$img->lineTo($thisPos->{x}, $thisPos->{y});
	#		$img->moveTo($lastPos->{x}*10, $lastPos->{y}*10);
	#		$img->lineTo($thisPos->{x}*10, $thisPos->{y}*10);

			# Prepare to draw the tracks starting from a common point
			$thisPos->{x} -= $initPos->{x};
			$thisPos->{y} -= $initPos->{y};
			$lastPos->{x} -= $initPos->{x};
			$lastPos->{y} -= $initPos->{y};

			# Multiply by 10 for debugging
	#		$thisPos->{x} *= 10;
	#		$thisPos->{y} *= 10;
	#		$lastPos->{x} *= 10;
	#		$lastPos->{y} *= 10;

			$thisPos->{x} += $centerOffset->{x};
			$thisPos->{y} += $centerOffset->{y};
			$lastPos->{x} += $centerOffset->{x};
			$lastPos->{y} += $centerOffset->{y};

			# Draw the tracks starting from a common point
			$img->moveTo($lastPos->{x}, $lastPos->{y});
			$img->lineTo($thisPos->{x}, $thisPos->{y});

			$lastPos = ({x => $pos->{x}, y => $pos->{y} - $pixels_air});
		}
	}

	$averageDistances[$t] /= $distanceCounter;

	# Note y coordinate 0 is on top of the screen, and next pixel line down is 1
	if($lastPos->{y} - $initPos->{y} > 0)
	{
		$averageDistances[$t] = -$averageDistances[$t];
	}

	# Plot the vectors in the column
	$img->penSize(1);
	$img->bgcolor('gray'); # British spelling!!!
	$img->fgcolor('gray'); # British spelling!!!
	$img->moveTo($initPos->{x}, $initPos->{y}); #we move to the beginning of each track
	$img->lineTo($lastPos->{x}, $lastPos->{y}); #draw a line to the end of each track

	my $X_move  = $lastPos->{x};
	my $Y_move  = $lastPos->{y};
	   $X_move -= $initPos->{x};
	   $Y_move -= $initPos->{y};

	# Plot the vectors starting from a common origin
	$img->moveTo($vectorOffset->{x}, $vectorOffset->{y});
	$img->lineTo($vectorOffset->{x} + $X_move, $vectorOffset->{y} + $Y_move);

	$Total_Plot_X_Move     += $X_move;
	$Total_Plot_Y_Move     += $Y_move; # See note below

	$X_move /= $distanceCounter;
	$Y_move /= $distanceCounter;

	# Calculate the angle of the vector with respect to a horizontal (0,-1) line
	# Take the negative of $Y_move, since bigger y values mean on a screen go down, while in geometry mean go up
	my $gamma = atan2(-$Y_move, $X_move) - atan2(0,1); # atan2(0,1) actually 0
	push (@full_vector_angles, $gamma); 
	#here we calculate the total movement
	$Total_X_Move     += $X_move;
	$Total_Y_Move     -= $Y_move; # See note below
	$Total_Y_Abs_Move += abs($Y_move);

	my $move = sqrt($X_move**2 + $Y_move**2);
	$Total_Abs_Move += $move;

	# Collect movement information
	# Note the line of pixels at the top has y value 0, next line below has 1, so the signs must be revered
	if($Y_move <= 0)
	{
		$Total_Move       += $move;
		$Total_Pos_Move   += $move;
		$Total_Y_Pos_Move -= $Y_move;
		$pos_move_counter++;
	}
	else
	{
		$Total_Move       -= $move;
		$Total_Neg_Move   -= $move;
		$Total_Y_Neg_Move -= $Y_move;
		$neg_move_counter++;
	}

	# Print a red dot at the end of the current track
	$img->bgcolor(255,0,0);
	$img->fgcolor(255,0,0);
	$img->moveTo($lastPos->{x}, $lastPos->{y});
	$img->ellipse(4,4);

	# Print a red dot at the end of the current track starting from a common point
	$lastPos->{x} -= $initPos->{x};
	$lastPos->{y} -= $initPos->{y};
	$lastPos->{x} += $centerOffset->{x};
	$lastPos->{y} += $centerOffset->{y};

	$img->moveTo($lastPos->{x}, $lastPos->{y});
	$img->ellipse(4,4);
}

#here we print the axes crossing at the center of the tracks starting from a common point
$img->bgcolor(0,0,0);
$img->fgcolor(0,0,0);
$img->penSize(1);
$img->moveTo($centerOffset->{x},     $centerOffset->{y}+200);
$img->lineTo($centerOffset->{x},     $centerOffset->{y}-200);

if($trackImageStyle == 0 || $trackImageStyle == 1)
{
	# Use for debugging or presentation
	$img->moveTo($centerOffset->{x}-200, $centerOffset->{y});
	$img->lineTo($centerOffset->{x}+200, $centerOffset->{y});
}
else
{
	# Use for thesis
	$img->moveTo($centerOffset->{x}-50, $centerOffset->{y});
	$img->lineTo($centerOffset->{x}+50, $centerOffset->{y});
}

# Draw the bottom of the column
$img->penSize(1);
$img->bgcolor('gray'); # British spelling!!!
$img->fgcolor('gray'); # British spelling!!!
$img->moveTo(0  , $no_of_lines - $pixels_bottom);
$img->lineTo($column_width, $no_of_lines - $pixels_bottom);

# Plot the average movement vector
$img->penSize(3);
$img->bgcolor('red');
$img->fgcolor('red');
$img->moveTo($vectorOffset->{x},$vectorOffset->{y});

if($no_of_tracks == 0){ $no_of_tracks = 1;}
$img->lineTo($vectorOffset->{x} + $Total_Plot_X_Move / $no_of_tracks, $vectorOffset->{y} + $Total_Plot_Y_Move / $no_of_tracks);


# Calculate the number of ticks needed
my $numLabels       = 10;
my $depth_mm        = $lineNumber * $mm_per_pixel;
my $tick_interval   = BestTick($depth_mm, $numLabels);
my $max_tick        = floor($depth_mm / $tick_interval);
my $pixels_per_tick = $tick_interval/$mm_per_pixel;

# Draw the axes
$img->penSize(3);
$img->bgcolor('black');
$img->fgcolor('black');
$img->moveTo($scaleOffset->{x},$scaleOffset->{y});
$img->lineTo($scaleOffset->{x},$lineNumber);

$img->penSize(3);
$img->font('Arial Bold');
$img->fontsize(16);

# Draw the ticks
for(my $i = 0; $i <= $max_tick; $i++)
{
	my $ypos = $scaleOffset->{y} + $pixels_per_tick*$i;
	$img->moveTo($scaleOffset->{x}+5, $ypos);
	$img->lineTo($scaleOffset->{x},   $ypos);
	$img->moveTo($scaleOffset->{x}+10,$ypos + (($i==0)?14:8));
	$img->string($i*$tick_interval);
}

# Draw averages by frame and cumulative average by frame, and save file final average for later use.
for(my $f = 0; $f < $track_length; $f++)
{
	$Total_Single_X_Move         += $average_X_Moves[$f];
	$Total_Single_X_Move_Counter += $average_X_Moves_Counter[$f];
	$Total_Single_Y_Move         -= $average_Y_Moves[$f]; # 0 on y-axis is on top, so reverse sign
	$Total_Single_Y_Move_Counter += $average_Y_Moves_Counter[$f];

	my $y  = $average_Y_Moves[$f];
	if($average_Y_Moves_Counter[$f] > 0)
	{
		$y /= $average_Y_Moves_Counter[$f];
	}
	else
	{
		$y = 0;
	}

	my $red   = ($y <= 0) ? 255 : 0;
	my $green = round($f*(255/($track_length)));
	my $blue  = ($y >  0) ? 255 : 0;

	$img->penSize(2);
	$img->fgcolor($red, $green, $blue);
	$img->bgcolor($red, $green, $blue);

	$img->moveTo($averageOffset->{x}*2 + $f, $averageOffset->{y} + $y*10);
	$img->ellipse(2,2);

	$y = -$Total_Single_Y_Move;
	if($Total_Single_Y_Move_Counter > 0)
	{
		$y /= $Total_Single_Y_Move_Counter;
	}
	else
	{
		$y = 0;
	}

	$red   = ($y <= 0) ? 255 : 0;
	$green = round($f*(255/($track_length)));
	$blue  = ($y >  0) ? 255 : 0;

	$img->penSize(2);
	$img->fgcolor($red, $green, $blue);
	$img->bgcolor($red, $green, $blue);

	$img->moveTo($averageOffset->{x}*2 + $f, $averageOffset->{y}+150 + $y*10);
	$img->ellipse(2,2);

	$average_X_Moves  [$f]         = NormalizeToCount( $average_X_Moves[$f],           $average_X_Moves_Counter[$f]);
	$average_Y_Moves  [$f]         = NormalizeToCount(-$average_Y_Moves[$f],           $average_Y_Moves_Counter[$f]);
	$average_distances[$f]         = NormalizeToCount( $average_distances[$f],         $average_distances_Counter[$f]);
}

my $stats = Statistics::Descriptive::Full->new();
$stats->add_data(@All_X_Moves);
$median_X_Moves = $stats->median();
$stats = Statistics::Descriptive::Full->new();
$stats->add_data(@All_Y_Moves);
$median_Y_Moves = $stats->median();

$Total_Single_X_Move         = NormalizeToCount($Total_Single_X_Move,           $Total_Single_X_Move_Counter);
$Total_Single_Y_Move         = NormalizeToCount($Total_Single_Y_Move,           $Total_Single_Y_Move_Counter);
$Total_Single_X_Pos_Move     = NormalizeToCount($Total_Single_X_Pos_Move,       $Total_Single_X_Pos_Move_Counter);
$Total_Single_Y_Pos_Move     = NormalizeToCount($Total_Single_Y_Pos_Move,       $Total_Single_Y_Pos_Move_Counter);
$Total_Single_X_Neg_Move     = NormalizeToCount($Total_Single_X_Neg_Move,       $Total_Single_X_Neg_Move_Counter);
$Total_Single_Y_Neg_Move     = NormalizeToCount($Total_Single_Y_Neg_Move,       $Total_Single_Y_Neg_Move_Counter);
$Total_Single_X_Abs_Move     = NormalizeToCount($Total_Single_X_Abs_Move,       $Total_Single_X_Abs_Move_Counter);
$Total_Single_Y_Abs_Move     = NormalizeToCount($Total_Single_Y_Abs_Move,       $Total_Single_Y_Abs_Move_Counter);
$Total_Single_Distance       = NormalizeToCount($Total_Single_Distance,         $Total_Single_Distance_Counter);
$Total_Single_X_Straightness = NormalizeToCount($Total_Single_X_Straightness,   $Total_Single_Distance_Counter);
$Total_Single_Y_Straightness = NormalizeToCount($Total_Single_Y_Straightness,   $Total_Single_Distance_Counter);

# Write the image data just created to a file
open (IMAGE_OUT, ">$basefile"."_tracks.png") or die "Error: ", print "\nCannot open file!\n$! \n";
print IMAGE_OUT $img->png;
close IMAGE_OUT;

########################################################
# Count the upward and downward pointing vectors and   #
# write the results to a file.                         #
########################################################
my $upward_vectors    = 0;
my $downward_vectors  = 0;
my $rightward_vectors = 0;
my $leftward_vectors  = 0;
my $top_vectors       = 0;
my $bottom_vectors    = 0;
my $right_vectors     = 0;
my $left_vectors      = 0;

foreach (@full_vector_angles)
{
	if($_ < 7*pi/12 && $_ > 5*pi/12)
	{
		$top_vectors++;
	}
	if($_ > -7*pi/12 && $_ < -5*pi/12)
	{
		$bottom_vectors++;
	}
	if(abs($_) - pi/2 < 7*pi/12 && abs($_) - pi/2 > 5*pi/12)
	{
		$left_vectors++;
	}
	if(abs($_) - pi/2 > -7*pi/12 && abs($_) - pi/2 < -5*pi/12)
	{
		$right_vectors++;
	}
	
	# Score the number of upward and downward pointing vectors from the vector angles
	if($_ > 0)
	{
		$upward_vectors++;
	}
	else
	{
		$downward_vectors++;
	}

	# Correct way to turn the angle:
	# If $_ >= 0:   $_ - pi/2
	# If $_ <  0: -($_ + pi/2)
	# But the result is the same
	if(abs($_) - pi/2 > 0)
	{
		$leftward_vectors++;
	}
	else
	{
		$rightward_vectors++;
	}
}

########################################################
# Find the depth corresponding to the median of the    #
# distribution                                         #
########################################################
my $density_till_mean=0;
my $mean_depth_counter=0;
for (my $i=0; $i<$no_of_lines; $i++)
{
	$density_till_mean+=$vertical_distribution[$i];
	$mean_depth_counter++;
	if ($density_till_mean>=0.5)
	{
		last;
	}
}

########################################################
# Find the center corresponding to the median of the   #
# distribution                                         #
########################################################
$density_till_mean=0;
my $mean_left_right_counter=0;
for (my $i=0; $i < scalar(@horizontal_distribution); $i++)
{
	$density_till_mean+=$horizontal_distribution[$i];
	$mean_left_right_counter++;
	if ($density_till_mean>=0.5)
	{
		last;
	}
}

########################################################
# Create an image of the larval depth distribution     #
# with a median distribution bar. The image is scaled  #
# according to the original dimensions of the input    #
# video. The distribution image is mainly useful for   #
# debugging.                                           #
########################################################
my $depthScaleOffset    = ({x => 50, y => 50});

# Crate a drawing object
$img = GD::Simple->new(325, $depthScaleOffset->{y}*2 + $lineNumber);

# Draw the distribution
$img->penSize(3);
$img->bgcolor('red');
$img->fgcolor('red');

my $y_offset = $depthScaleOffset->{y} - $pixels_air;
my $counter  = 0;

# Go trough the image line by line and draw
foreach (@vertical_distribution)
{
	$counter++;
	unless ($_==0)
	{
		$img->moveTo($depthScaleOffset->{x}         , $y_offset + $counter);
		$img->lineTo($depthScaleOffset->{x}+$_*10000, $y_offset + $counter);
	}
}

# Draw the line corresponding to the median depth
$img->penSize(3);
$img->bgcolor('black');
$img->fgcolor('black');
$img->moveTo($depthScaleOffset->{x}+ 70,$y_offset + $mean_depth_counter);
$img->lineTo($depthScaleOffset->{x}+150,$y_offset + $mean_depth_counter);

# Draw the bottom of the column
$img->penSize(1);
$img->bgcolor('gray'); # British spelling!
$img->fgcolor('gray'); # British spelling!
$img->moveTo($depthScaleOffset->{x} , $y_offset + $no_of_lines - $pixels_bottom);
$img->lineTo($depthScaleOffset->{x} + 200, $y_offset + $no_of_lines - $pixels_bottom);

# Draw of the axes
$img->penSize(3);
$img->bgcolor('black');
$img->fgcolor('black');
$img->moveTo($depthScaleOffset->{x},$depthScaleOffset->{y});
$img->lineTo($depthScaleOffset->{x},$depthScaleOffset->{y}+$lineNumber);
$img->moveTo($depthScaleOffset->{x},$depthScaleOffset->{y}+$lineNumber);
$img->lineTo($depthScaleOffset->{x}+200,$depthScaleOffset->{y}+$lineNumber);

# Draw the ticks
$img->font('Arial Bold');
$img->fontsize(30); 
for(my $i = 0; $i <= $max_tick; $i++)
{
	my $ypos = $depthScaleOffset->{y} + $pixels_per_tick*$i;
	$img->moveTo($depthScaleOffset->{x}-5, $ypos);
	$img->lineTo($depthScaleOffset->{x},   $ypos);
	$img->moveTo($depthScaleOffset->{x}-49,$ypos+14);# + (($i==0)?14:8));
	$img->string($i*$tick_interval);
}

$img->moveTo($depthScaleOffset->{x}+100,$depthScaleOffset->{x}+$lineNumber);
$img->lineTo($depthScaleOffset->{x}+100,$depthScaleOffset->{x}+5+$lineNumber);
$img->moveTo($depthScaleOffset->{x}+200,$depthScaleOffset->{x}+$lineNumber);
$img->lineTo($depthScaleOffset->{x}+200,$depthScaleOffset->{x}+5+$lineNumber);

# Draw the x-axis labels, not scalable
$img->font('Arial Bold');
$img->fontsize(20);
$img->moveTo($depthScaleOffset->{x}-8,$depthScaleOffset->{y}+27+$lineNumber);
$img->string("0");
$img->moveTo($depthScaleOffset->{x}-8+80,$depthScaleOffset->{y}+27+$lineNumber);
$img->string("0.01");
$img->moveTo($depthScaleOffset->{x}-8+180,$depthScaleOffset->{y}+27+$lineNumber);
$img->string("0.02");

# Write the image data to a file
open (IMAGE_OUT, ">$basefile"."_distr".".png") or die "Error: ", print "\nCannot open file!\n$! \n";
print IMAGE_OUT $img->png;
close IMAGE_OUT;

if($printFramesMode > 0)
{
	open (RESULTS_FRAMES, ">$basefile"."_displacement.txt") or die "Error: ", print "\nCannot open file!\n$! \n";

	$img = GD::Simple->new($column_width, $lineNumber, 1);
	$img->penSize(3);

	my $img_points = GD::Simple->new($column_width, $lineNumber, 1);
	$img_points->penSize(3);

	if($printFramesBackground)
	{
		$img->bgcolor('black');
		$img->fgcolor('black');
	}
	else
	{
		$img->bgcolor('white');
		$img->fgcolor('white');
	}

	$img->rectangle(0, 0, $column_width, $lineNumber);

	for(my $f = 0; $f < $track_length; $f++)
	{
		if($printFramesBackground)
		{
			$img_points->bgcolor('black');
			$img_points->fgcolor('black');
		}
		else
		{
			$img_points->bgcolor('white');
			$img_points->fgcolor('white');
		}

		$img_points->rectangle(0, 0, $column_width, $lineNumber);

		for(my $t = 0; $t < scalar(@tracks); $t++)
		{
			my $pos = $tracks[$t][$f];
			if($pos->{isValid})
			{
				my $x = $pos->{x};
				my $y = $pos->{y};

				if($particleSize < 5)
				{
		#			$x = round($x);
		#			$y = round($y);
				}

				my $red   = 0;
				my $green = 0;
				my $blue  = 0;

				# Temporal encoding
				if($printFramesMode == 1)
				{
					my $numOpts = 5;
					my $denom = $track_length/$numOpts;
					my $variableValue = round(($f % $denom)*(255/$denom));

					if($f < $denom)
					{
						$red   = 255;
						$green = $variableValue;
						$blue  = 0;
					}
					elsif($f < 2*$denom)
					{
						$red   = 255 - $variableValue;
						$green = 255;
						$blue  = 0;
					}
					elsif($f < 3*$denom)
					{
						$red   = 0;
						$green = 255;
						$blue  = $variableValue;
					}
					elsif($f < 4*$denom)
					{
						$red   = 0;
						$green = 255 - $variableValue;
						$blue  = 255;
					}
					elsif($f < 5*$denom)
					{
						$red   = $variableValue;
						$green = 0;
						$blue  = 255;
					}

					#if($f < $denom)
					#{
					#	$red   = 0;
					#	$green = 255 - $variableValue;
					#	$blue  = 255;
					#}
					#elsif($f < 2*$denom)
					#{
					#	$red   = $variableValue;
					#	$green = 0;
					#	$blue  = 255;
					#}
					#elsif($f < 3*$denom)
					#{
					#	$red   = 255;
					#	$green = 0;
					#	$blue  = 255 - $variableValue;
					#}
					#elsif($f < 4*$denom)
					#{
					#	$red   = 255;
					#	$green = $variableValue;
					#	$blue  = 0;
					#}
					#elsif($f < 5*$denom)
					#{
					#	$red   = 255 - $variableValue;
					#	$green = 255;
					#	$blue  = 0;
					#}
				}
				# Angular encoding
				elsif($printFramesMode == 2)
				{
					my $x1 = 0;
					my $y1 = 0;

					if($f > 0)
					{
						my $lastPos = $tracks[$t][$f-1];
						if($lastPos->{isValid})
						{
							$x1 = $lastPos->{x};
							$y1 = $lastPos->{y};
						}
					}

					my $gamma = 0;
					if($is_left_right == 0)
					{
						$gamma = round((atan2(($y-$y1), $x-$x1) + pi) * 1000000000);
					}
					else
					{
						$gamma = round((atan2(-($y-$y1), $x-$x1) + pi) * 1000000000)
					}
		#			my $gamma = round((atan2(-($y-$y1), $x-$x1) + pi) * 1000000000); # Integerize
		#			my $gamma = round((atan2(($y-$y1), $x-$x1) + pi) * 1000000000); # Integerize
					my $numOpts = 6;
					my $denom = round(2*pi / $numOpts * 1000000000); # Integerize
					my $variableValue = round(($gamma % $denom)*(255/$denom));

		#			print $f, "\t";
		#			print $x-$x1, "\t";
		#			print $y-$y1, "\t";
		#			print $gamma, "\t";
		#			print $numOpts, "\t";
		#			print $denom, "\t";
		#			print $variableValue, "\n";

					if($gamma < $denom)
					{
						$red   = 255;
						$green = $variableValue;
						$blue  = 0;
					}
					elsif($gamma < 2*$denom)
					{
						$red   = 255 - $variableValue;
						$green = 255;
						$blue  = 0;
					}
					elsif($gamma < 3*$denom)
					{
						$red   = 0;
						$green = 255;
						$blue  = $variableValue;
					}
					elsif($gamma < 4*$denom)
					{
						$red   = 0;
						$green = 255 - $variableValue;
						$blue  = 255;
					}
					elsif($gamma < 5*$denom)
					{
						$red   = $variableValue;
						$green = 0;
						$blue  = 255;
					}
					elsif($gamma < 6*$denom)
					{
						$red   = 255;
						$green = 0;
						$blue  = 255 - $variableValue;
					}
				}
				# Temporal up and down encoding
				elsif($printFramesMode > 2)
				{
					my $x1 = 0;
					my $y1 = 0;

					if($f > 0)
					{
						my $lastPos = $tracks[$t][$f-1];
						if($lastPos->{isValid})
						{
							$x1 = $lastPos->{x};
							$y1 = $lastPos->{y};
						}
					}

					if($is_left_right)
					{
						$red   = ($x-$x1 >= 0) ? 255 : 0;
						$green = round($f*(255/($track_length)));
						$blue  = ($x-$x1 <  0) ? 255 : 0;
					}
					else
					{
						$red   = ($y-$y1 <= 0) ? 255 : 0;
						$green = round($f*(255/($track_length)));
						$blue  = ($y-$y1 >  0) ? 255 : 0;
					}
				}
				# Crate a drawing object
				$img->moveTo($x, $y);

				$img->fgcolor($red, $green, $blue);
				$img->bgcolor($red, $green, $blue);

				$img->ellipse($particleSize, $particleSize);

				$img_points->moveTo($x, $y);

				$img_points->fgcolor($red, $green, $blue);
				$img_points->bgcolor($red, $green, $blue);

				$img_points->ellipse($particleSize, $particleSize);

				# Write the image data just created to a file
			}
		}

		if($printFramesBackground < 2)
		{
			open (IMAGE_OUT, ">$basefile"."_tracks_$f.png") or die "Error: ", print "\nCannot open file!\n$! \n";
			print IMAGE_OUT $img->png;
			close IMAGE_OUT;

			open (IMAGE_OUT, ">$basefile"."_track_points_$f.png") or die "Error: ", print "\nCannot open file!\n$! \n";
			print IMAGE_OUT $img_points->png;
			close IMAGE_OUT;
		}

		print RESULTS_FRAMES $f, "\t",
		                     $average_X_Moves[$f]   * $mm_per_pixel * $frame_rate, "\t",
		                     $average_Y_Moves[$f]   * $mm_per_pixel * $frame_rate, "\t",
		                     $average_distances[$f] * $mm_per_pixel * $frame_rate, "\n";
	}
	close RESULTS_FRAMES;
}

########################################################
# Estimate the number of larvae in the column. The     #
# maximum number of tracks in any frame gives the      #
# minimum number of larvae in the column.              #
########################################################
my $number_of_larvae_in_column = 0;

for(my $f = 0; $f < $track_length; $f++)
{
	my $validCounter = 0;
	for(my $t = 0; $t < scalar(@tracks); $t++)
	{
		# That's now really ridiculous, do you really need
		# to use up all the memory for dereferencing?
		my $pos = $tracks[$t][$f];
		if
		(
		     $pos->{isValid}
		)
		{
			$validCounter++;
		}
	}

	if($validCounter > $number_of_larvae_in_column)
	{
		$number_of_larvae_in_column = $validCounter;
	}
}

########################################################
# Calculate the number of larvae in the upper half of  #
# the column and the lower half, write the results to  #
# a file.                                              #
########################################################

# Calculate the larvae in the upper half of the chamber, using the $no_of_lines/2 and the number of larvae as estimated by the short tracks
my $larvae_in_upper_half=0;
for (my $i=$pixels_air; $i < round(($no_of_lines - $pixels_bottom - $pixels_air)/2 + $pixels_air); $i++)
{
	$larvae_in_upper_half+=$vertical_distribution[$i];
}

my $larvae_in_upper_half_percent = $larvae_in_upper_half;
$larvae_in_upper_half=round($larvae_in_upper_half*$number_of_larvae_in_column);

# Calculate the larvae in the upper lower of the chamber, using the $no_of_lines/2 and the number of larvae as estimated by the short tracks
my $larvae_in_lower_half=0;
for (my $i=round(($no_of_lines - $pixels_bottom - $pixels_air)/2 + $pixels_air); $i<$no_of_lines - $pixels_bottom; $i++)
{
	$larvae_in_lower_half+=$vertical_distribution[$i];
}

my $larvae_in_lower_half_percent = $larvae_in_lower_half;
$larvae_in_lower_half=round($larvae_in_lower_half*$number_of_larvae_in_column);

########################################################
# Calculate means for later saving to a results file.  #
########################################################
my $positiveDistance = 0;
my $negativeDistance = 0;
my $absoluteDistance = 0;
my $sumDistance      = 0;
my $posCounter       = 0;
my $negCounter       = 0;
my $absCounter       = 0;

for(my $t = 0; $t < scalar(@tracks); $t++)
{
	if($averageDistances[$t] >= 0)
	{
		$positiveDistance += $averageDistances[$t];
		$posCounter++;
	}
	else
	{
		$negativeDistance += $averageDistances[$t];
		$negCounter++;
	}

	$absoluteDistance += abs($averageDistances[$t]);
	$sumDistance      += $averageDistances[$t];
	$absCounter++;
}

if($posCounter > 0) { $positiveDistance /= $posCounter; }
if($negCounter > 0) { $negativeDistance /= $negCounter; }
if($absCounter > 0) { $absoluteDistance /= $absCounter; }
if($absCounter > 0) {      $sumDistance /= $absCounter; }
if($pos_move_counter > 0) { $Total_Y_Pos_Move /= $pos_move_counter; $Total_Pos_Move /= $pos_move_counter;}
if($neg_move_counter > 0) { $Total_Y_Neg_Move /= $neg_move_counter; $Total_Neg_Move /= $neg_move_counter;}
if($no_of_tracks     > 0)
{
	$Total_Move       /= $no_of_tracks;
	$Total_Abs_Move   /= $no_of_tracks;
	$Total_X_Move     /= $no_of_tracks;
	$Total_Y_Move     /= $no_of_tracks;
	$Total_Y_Abs_Move /= $no_of_tracks;
}

########################################################
# Write the data to the results file; data from        #
# different calls of this script can go to the same    #
# results file                                         #
########################################################

# We made sure that the file exists
open (RESULTS, ">>$ResultsFile") or die "Error: ", print "\nCannot open file!\n$! \n";
print "Column width: ",  $column_width, "\n";

my $numOfVectors     = scalar(@full_vector_angles);
if($numOfVectors     == 0){ $numOfVectors     = 1;}
if($all_track_pieces == 0){ $all_track_pieces = 1;}

# Write the data to the results file.
print RESULTS       $infile,                                                                             # File Name
              "\t", scalar(@full_vector_angles),                                                         # #Vectors
              "\t", $upward_vectors,                                                                     # #upward Vectors
              "\t", $downward_vectors,                                                                   # #downward Vectors
              "\t", $leftward_vectors,                                                                   # #leftward Vectors
              "\t", $rightward_vectors,                                                                  # #rightward Vectors
              "\t", $upward_vectors / $numOfVectors,                                                     # %upward Vectors
              "\t", $downward_vectors / $numOfVectors,                                                   # %downward Vectors
              "\t", $leftward_vectors / $numOfVectors,                                                   # %leftward Vectors
              "\t", $rightward_vectors / $numOfVectors,                                                  # %rightward Vectors
              "\t", $Total_Single_X_Move * $mm_per_pixel * $frame_rate,                                  # #Average x Displacement
              "\t", $Total_Single_Y_Move * $mm_per_pixel * $frame_rate,                                  # #Average y Displacement
              "\t", $Total_Single_X_Pos_Move * $mm_per_pixel * $frame_rate,                              # #Average x positive Displacement
              "\t", $Total_Single_Y_Pos_Move * $mm_per_pixel * $frame_rate,                              # #Average y positive Displacement
              "\t", $Total_Single_X_Neg_Move * $mm_per_pixel * $frame_rate,                              # #Average x negative Displacement
              "\t", $Total_Single_Y_Neg_Move * $mm_per_pixel * $frame_rate,                              # #Average y negative Displacement
              "\t", $Total_Single_X_Abs_Move * $mm_per_pixel * $frame_rate,                              # #Average x absolute Displacement
              "\t", $Total_Single_Y_Abs_Move * $mm_per_pixel * $frame_rate,                              # #Average y absolute Displacement
              "\t", $Total_X_Move * $mm_per_pixel * $frame_rate,                                         # #Average x Movement
              "\t", $Total_Y_Move * $mm_per_pixel * $frame_rate,                                         # #Average y Movement
              "\t", $Total_Y_Pos_Move * $mm_per_pixel * $frame_rate,                                     # #Average positive y Movement
              "\t", $Total_Y_Neg_Move * $mm_per_pixel * $frame_rate,                                     # #Average negative y Movement
              "\t", $Total_Y_Abs_Move * $mm_per_pixel * $frame_rate,                                     # #Average absolute y Movement
              "\t", $Total_Move * $mm_per_pixel * $frame_rate,                                           # #Average Movement
              "\t", $Total_Pos_Move * $mm_per_pixel * $frame_rate,                                       # #Average positive Movement
              "\t", $Total_Neg_Move * $mm_per_pixel * $frame_rate,                                       # #Average negative Movement
              "\t", $Total_Abs_Move * $mm_per_pixel * $frame_rate,                                       # #Average absolute Movement
              "\t", $number_of_larvae_in_column,                                                         # #Larvae
              "\t", $larvae_in_upper_half,                                                               # #Larvae Upper
              "\t", $larvae_in_lower_half,                                                               # #Larvae Lower
              "\t", $larvae_in_upper_half_percent,                                                       # #Larvae % Upper
              "\t", $larvae_in_lower_half_percent,                                                       # #Larvae % Lower
              "\t", $positiveDistance * $mm_per_pixel * $frame_rate,                                     # #Upward Speed (mm per sec)
              "\t", $negativeDistance * $mm_per_pixel * $frame_rate,                                     # #Downward Speed (mm per sec)
              "\t", $absoluteDistance * $mm_per_pixel * $frame_rate,                                     # #Absolute Speed (mm per sec)
              "\t",      $sumDistance * $mm_per_pixel * $frame_rate,                                     # #Single Sum Speed (mm per sec)
              "\t", ($positiveDistance + $negativeDistance) * $mm_per_pixel * $frame_rate,               # #Sum Speed (mm per sec)
              "\t", $Total_Single_Distance * $mm_per_pixel * $frame_rate,                                # #Speed (mm per sec)
              "\t", ($mean_depth_counter - $pixels_air) * $mm_per_pixel,                                 # #Median depth (mm from surface)
              "\t", ($mean_depth_counter - $pixels_air) / ($no_of_lines - $pixels_bottom - $pixels_air), # #Median depth (in %)
              "\t", $mean_left_right_counter - ($column_width/2) * $mm_per_pixel,                        # #Median left/right (mm from middle)
              "\t", ($mean_left_right_counter - ($column_width/2)) / $column_width,                      # #Median left/right (in % from middle)
              "\t", $Total_Single_X_Move / $Total_Single_Distance,                                       # #Simple X straightness
              "\t", $Total_Single_Y_Move / $Total_Single_Distance,                                       # #Simple Y straightness
              "\t", $Total_Single_X_Straightness,                                                        # #Single X straightness
              "\t", $Total_Single_Y_Straightness,                                                        # #Single Y straightness
              "\t", atan2($Total_Single_X_Move, $Total_Single_Y_Move),                                   # #Average Angel
              "\t", $top_vectors,                                                                        # #Top Vectors
              "\t", $bottom_vectors,                                                                     # #Bottom Vectors
              "\t", $left_vectors,                                                                       # #Left Vectors
              "\t", $right_vectors,                                                                      # #Right Vectors
              "\t", $top_vectors / $numOfVectors,                                                        # %Top Vectors
              "\t", $bottom_vectors / $numOfVectors,                                                     # %Bottom Vectors
              "\t", $left_vectors / $numOfVectors,                                                       # %Left Vectors
              "\t", $right_vectors / $numOfVectors,                                                      # %Right Vectors

              "\t", $all_track_pieces,                                                                   # #Track Pieces
              "\t", $upward_track_pieces,                                                                # #Upward track pieces
              "\t", $downward_track_pieces,                                                              # #Downward track pieces
              "\t", $rightward_track_pieces,                                                             # #Leftward track pieces
              "\t", $leftward_track_pieces,                                                              # #Rightward track pieces
              "\t", $top_track_pieces,                                                                   # #Top track pieces
              "\t", $bottom_track_pieces,                                                                # #Bottom track pieces
              "\t", $left_track_pieces,                                                                  # #Left track pieces
              "\t", $right_track_pieces,                                                                 # #Right track pieces

              "\t", $upward_track_pieces / $all_track_pieces,                                            # %Upward track pieces
              "\t", $downward_track_pieces / $all_track_pieces,                                          # %Downward track pieces
              "\t", $rightward_track_pieces / $all_track_pieces,                                         # %Leftward track pieces
              "\t", $leftward_track_pieces / $all_track_pieces,                                          # %Rightward track pieces
              "\t", $top_track_pieces / $all_track_pieces,                                               # %Top track pieces
              "\t", $bottom_track_pieces / $all_track_pieces,                                            # %Bottom track pieces
              "\t", $left_track_pieces / $all_track_pieces,                                              # %Left track pieces
              "\t", $right_track_pieces / $all_track_pieces,                                             # %Right track pieces

              "\t", $median_X_Moves * $mm_per_pixel * $frame_rate,                                       # #Median X Movement
              "\t", $median_Y_Moves * $mm_per_pixel * $frame_rate,                                       # #Median Y Movement

              "\n";
close RESULTS;
