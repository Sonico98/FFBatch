#!/bin/bash

###########
# Options #
###########
# Set the video codec, pixel format, bitrate, etc
video_params='-map 0:v:0 -c:v libx264 -crf 20 -pix_fmt yuv420p -profile:v high -bf 2 -tune animation'

# Set the audio codec and bitrate. Will be ignored if the source's codec is AAC
audio_params='-map 0:a:0 -c:a libfdk_aac -profile:a aac_low -vbr 5' 

# Optional parameters
other_params='-movflags -faststart -metadata title= '

# Enable or disable transcoding with RAM
# MAKE SURE YOU HAVE ENOUGH SPACE
# --------------------------------------
# If true, copies the original file to ram
copy2ram=false
# If true, writes the transcoded file to ram before
# moving it to its final destination
write2ram=false
# Determines the directory that points to RAM
ramdir="/tmp"


##########
# Script #
##########
# Don't modify anything below unless you know what you're doing

if [[ $# -ne 1 ]]
then
	echo "[ USAGE ]"
	echo "Execute the script inside a folder with a bunch of MKVs"
	echo ""
	echo "ffbatch.sh [output path]"
	echo ""
	echo "You have to specify where to place the encoded files"
	echo "The script only accepts one parameter"
	exit 2
fi


# Functions
check_audio_transcode () {
	get_audio_codec="$(ffprobe -v error -select_streams a:0 -show_entries \
		stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$ramdir"/"$base".mkv)"

	if [[ "$get_audio_codec" = aac ]]; then
		audio_parameters='-map 0:a:0 -c:a copy'
	fi
}


cleanup () {
	rm -rf "$ramdir"/subs
	rm -rf "$HOME"/.local/share/fonts/ffbatch_fonts
	if [[ ! "$ramdir" = "." ]];then
		rm -f "$ramdir/$base.mkv"
	fi
}


copy_to_ram () {
	if [[ $copy2ram = true ]] && [[ $write2ram = true ]]; then
		echo "Copying file to RAM, to minimize disk usage."
		echo "The transcoded file will be written to RAM first."
		cp -v "$video" "$ramdir"
		outputdir="$ramdir"
		status=$?
	elif [[ $copy2ram = true ]] && [[ $write2ram = false ]]; then
		echo "Copying file to RAM, to minimize disk usage."
		cp -v "$video" "$ramdir"
		outputdir="$1"
		status=$?
	elif [[ $write2ram = true ]] && [[ $copy2ram = false ]]; then
		echo "The transcoded file will be written to RAM first."
		outputdir="$ramdir"
		ramdir="."
		status=$?
	else
		ramdir="."
		outputdir="$1"
		status=0
	fi
}


extract_fonts () {
	work_dir="$(pwd)"
	echo "Extracting fonts..."
	mkdir -p "$ramdir"/.fonts
	cd "$ramdir"/.fonts
	ffmpeg -y -dump_attachment:t "" -i ../"$base".mkv &>/dev/null

	mv ./* "$HOME"/.local/share/fonts/ffbatch_fonts &>/dev/null
	cd .. && rm -rf .fonts
	cd "$work_dir"
	# clear
}


set_ffbin () {
	which ffpb &> /dev/null
	if [[ $? -eq 0 ]]
	then
		ffbin=$(which ffpb)
	else
		ffbin=$(which ffmpeg)
	fi
}
# End functions

# If set to false, fonts will be extracted
FONTS_EX=false
set_ffbin
mkdir -p "$1"
mkdir -p "$HOME"/.local/share/fonts/ffbatch_fonts

for video in *.mkv; do
	audio_parameters="$audio_params"
	base=$(basename "$video" .mkv)

	# Check if we want to work with files on RAM
	copy_to_ram "$1"
	mkdir -p "$ramdir"/subs

	# If there were no problems copying to RAM, proceed
	if [[ $status -eq 0 ]]; then
		echo ""	
		if [[ $FONTS_EX = false ]]; then
			extract_fonts
			FONTS_EX=true
		fi

		# Determine if transcoding the audio is necessary
		check_audio_transcode

		echo "Attempting to extract subs..."
		$(which ffmpeg) -v quiet -stats -y -i "$ramdir"/"$base".mkv "$ramdir"/subs/"$base".ass
		subs_state="$?"

		# Transcode the file
		if [[ $subs_state -eq 0 ]]; then
			echo "Subtitles extracted. Transcoding..."
			$ffbin -i "$ramdir"/"$base".mkv  -vf "ass='$ramdir/subs/$base.ass'" \
				$audio_parameters $video_params $other_params "$outputdir"/"$base".mp4
		else
			echo "No subtitles found. Converting to MP4 anyways..."
			$ffbin -i "$ramdir"/"$base".mkv $audio_parameters \
				$video_params $other_params "$outputdir"/"$base".mp4
		fi

		# Remove the mkv from RAM and move the MP4
		if [[ ! $ramdir = "." ]];then
			rm -f "$ramdir"/"$base".mkv
			if [[ $write2ram = true ]]; then
				mv "$ramdir"/"$base".mp4 "$1"/"$base".mp4 &
			fi
		elif [[ $write2ram = true ]] && [[ $copy2ram = false ]]; then
			mv "$outputdir"/"$base".mp4 "$1"/"$base".mp4 &
		fi

	else
		echo "An error ocurred"
		cleanup
		exit 1
	fi
done

cleanup
echo "All done!"
exit 0