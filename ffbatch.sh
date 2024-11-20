#!/bin/bash

###########
# Options #
###########
# Set the video codec, pixel format, bitrate, etc
video_params='-map 0:v:0 -c:v libx264 -crf 17 -pix_fmt yuv420p -profile:v high -bf 6 -tune animation -preset slow -aq-mode 3 -aq-strength 0.75 -rc-lookahead 200 -level:v 4.2'

# Set the audio codec and bitrate. Will be ignored if the source's codec is AAC
audio_params='-c:a aac -b:a 256k'

# Optional parameters
other_params='-movflags faststart -metadata title= '

# Set the subtitle language to burn into the video.
# The subtitle stream should be properly tagged with the desired language code (e.g. using mkvtoolnix).
# If there are multiple subtitles for the same language, the first one that matches will be chosen.
subs_lang='eng'

# Set the audio language to use.
# The audio stream should be properly tagged with the desired language code (e.g. using mkvtoolnix).
# If there are multiple audio streams for the same language, all of them will be transcoded.
audio_lang='jpn'

# Transcode even if no subs are found
always_transcode=false

# Enable or disable transcoding in a temp directory 
# --------------------------------------
# If true, copies the original file to a temp directory
# (can be useful for network shares)
copy2dir=false
# If true, writes the transcoded file to a temp directory before
# moving it to its final destination (can be useful for network shares)
write2dir=false
# Determines the temp directory to use. Won't be removed on completion.
tmpdir="/tmp"


##########
# Script #
##########
# Don't modify anything below unless you know what you're doing

print_usage () {
	echo "[USAGE]"
	echo "ffbatch.sh [OPTIONS] <output path>"
	echo ""
	echo "Execute the script inside a folder with a bunch of MKVs"
	echo "You have to specify an output path where the encoded files will be placed"
	echo ""
	echo "[OPTIONS]"
	echo " -l | --list <file>     : Lists available subtitles for a certain file with their stream number, language and name."
	echo " -c | --copy2dir        : Copies each MKV to a temporary directory before transcoding (default is '/tmp')"
	echo " -w | --write2dir       : Writes the MP4 to a temporary directory before moving it to its final destination"
	echo "                          (default is '/tmp')."
	echo " -d | --tmpdir <dir>    : Changes the temporary directory to copy the files to if -c or -w is used."
	echo " -f | --force           : Always transcodes the video, even if no subtitles are found."
	echo " -v | --videoParams <p> : Pass your own ffmpeg parameters (in quotes) for transcoding the video."
	echo " -u | --audioParams <p> : Pass your own ffmpeg parameters (in quotes) for transcoding the audio."
	echo " -p | --otherParams <p> : Pass your own miscellaneous ffmpeg parameters (in quotes)."
	echo " -s | --subLang <lang>  : Try to burn subtitles matching a specific language code."
	echo " -n | --subName <name>  : Try to burn subtitles matching a specific name. Check available names with -l. Overrides -S"
	echo " -a | --audioLang <lang>: Try to encode audio tracks matching a specific language code."
	echo " -h | --help            : Print this help text."
}

if [[ $# -lt 1 ]]
then
	print_usage
	exit 2
fi


# Functions

check_audio_transcode () {
	stream="a:0"
	if [ "$audiomap" != "-map 0:a:0" ]; then
		stream="a:m:language:$audio_lang"
	fi

	get_audio_codec="$(ffprobe -v error -select_streams "$stream" -show_entries \
		stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$tmpdir"/"$base".mkv | tr -d '\n' | tr -d ' ')"

	if [[ "$get_audio_codec" = "aac" ]]; then
		audio_parameters="-map 0:$stream -c:a copy"
	else
		audio_parameters="$audio_params -map 0:$stream"
	fi
}


select_audio_stream () {
	audiomap="-map 0:a:0"
	audio_exists="$(ffprobe -i "$tmpdir"/"$base".mkv -hide_banner -v quiet -show_streams -select_streams a:m:language:"$audio_lang")"
	if [ -n "$audio_exists" ]; then
		audiomap="-map 0:a:m:language:$audio_lang"
	else
		echo "The requested audio language could not be found. Picking the first audio track available."
	fi
}


list_subs () {
	# TODO)) Possibly rewrite as a regular expression, to not rely on the "title" metadata being always 2 lines after the subtitle stream number
	ffprobe -i "$1" 2>&1 | grep -A 2 "Subtitle" | cut -d':' -f2 | awk 1 ORS=' ' | sed -e "s# -- #\n#g" -e "s#)   #) · #g"
}


get_sub_index_by_name () {
	subs_total=$(list_subs "$tmpdir/$base.mkv" | grep -i "$subname")
	if [ "$(echo "$subs_total" | wc -l)" -lt 2 ]; then
		index="$(echo "$subs_total" | cut -d "(" -f1 | tr -d "\n")"
	else
		# TODO)) Allow choosing something other than the first matching subs
		index="$(echo "$subs_total" | head -1 | cut -d "(" -f1 | tr -d "\n")"
	fi
	echo "$index"
}


extract_subs () {
	if [ -n "$subname" ]; then
		subs_index="$(get_sub_index_by_name)"
	else
		subs_exists="$(ffprobe -i "$tmpdir"/"$base".mkv -hide_banner -v quiet -show_streams -select_streams s:m:language:"$subs_lang")"
	fi
	if [ -n "$subs_exists" ] || [ -n "$subs_index" ]; then
		echo "Extracting subs..."
		if [ -n "$subname" ]; then
			$(which ffmpeg) -v quiet -stats -i "$tmpdir/$base.mkv" -map 0:"$subs_index" "$subsdir/.subs/$base.ass"
		else
			# Use mkvmerge to prevent problems if there are PGS subs present.
			# We grab an audio track too, to prevent the subtitles from weirdly desyncing themselves.
			first_audio_track="$(mkvmerge --identify "$tmpdir/$base.mkv" | grep 'audio' | head -1 | cut -d' ' -f3 | tr -d ':')"
			mkvmerge -o "$subsdir/.subs/$base.mkv" -D -a "$first_audio_track" --no-chapters -s "$subs_lang" "$tmpdir/$base.mkv"
			$(which ffmpeg) -v quiet -stats -i "$subsdir/.subs/$base.mkv" -map 0:s:0 "$subsdir/.subs/$base.ass"
			rm -f "$subsdir/.subs/$base.mkv"
		fi
	else
		if [ -n "$subname" ]; then
			echo "The requested subtitle name could not be found. Trying to pick the first subtitle track available."
		else
			echo "The requested subtitle language could not be found. Trying to pick the first subtitle track available."
		fi
		$(which ffmpeg) -v quiet -stats -i "$tmpdir/$base.mkv" -map 0:s:0 "$subsdir/.subs/$base.ass"
	fi
}


cleanup () {
	rm -rf "$subsdir"/.subs
	rm -rf "$tmpdir"/.fonts
	if [[ ! "$tmpdir" = "." ]];then
		rm -f "$tmpdir/$base.mkv"
	fi
}


# trap ctrl-c and call ctrl_c()
trap ctrl_c INT
ctrl_c () {
	cleanup
	rm -f "$outputdir"/"$base.mp4"
	exit 2
}


check_if_copy_to_dir () {
	# Set subsdir to the default
	subsdir="$tmpdir"
	copy_info_text="Copying file to dir '$tmpdir' before transcoding"
	transcode_info_text="The transcoded file will be written to '$tmpdir' first."

	if [[ $copy2dir = true ]] && [[ $write2dir = true ]]; then
		echo "$copy_info_text"
		echo "$transcode_info_text"
		outputdir="$tmpdir"
	elif [[ $copy2dir = true ]] && [[ $write2dir = false ]]; then
		echo "$copy_info_text"
		outputdir="$final_dir"
	elif [[ $write2dir = true ]] && [[ $copy2dir = false ]]; then
		echo "$transcode_info_text"
		outputdir="$tmpdir"
		tmpdir="."
	else
		tmpdir="."
		outputdir="$final_dir"
		# Set subsdir to the current working directory
		subsdir="$tmpdir"
	fi
}


extract_fonts () {
	work_dir="$(pwd)"
	echo "Extracting fonts..."
	mkdir -p "$tmpdir"/.fonts
	cd "$tmpdir"/.fonts || exit
	ffmpeg -y -dump_attachment:t "" -i ../"$base".mkv &>/dev/null
	cd "$work_dir" || exit
}


choose_ffbin () {
	which ffpb &> /dev/null
	if [[ $? -eq 0 ]]
	then
		ffbin=$(which ffpb)
	else
		ffbin=$(which ffmpeg)
	fi
}


transcode () {
	if [[ -f "$subsdir/.subs/$base.ass" ]]; then
		echo "Subtitles extracted. Transcoding..."
		$ffbin -i "$tmpdir"/"$base".mkv -vf "subtitles='$subsdir/.subs/$base.ass:fontsdir=$tmpdir/.fonts'" \
			$audio_parameters $video_params $other_params "$outputdir"/"$base".mp4
	else
		if [ $always_transcode = true ]; then
			echo "No subtitles found. Converting to MP4 anyways..."
			$ffbin -i "$tmpdir"/"$base".mkv $audio_parameters \
				$video_params $other_params "$outputdir"/"$base".mp4
		else
			echo "No subtitles found. Skipping file..."
			echo ""
		fi
	fi
}


move2final_dest () {
	if [[ ! $tmpdir = "." ]];then
		rm -f "$tmpdir"/"$base".mkv
		if [[ $write2dir = true ]]; then
			if [ -f "$tmpdir/$base.mp4" ]; then
				mv "$tmpdir"/"$base".mp4 "$final_dir"/"$base".mp4 &
			fi
		fi
	elif [[ $write2dir = true ]] && [[ $copy2dir = false ]]; then
		if [ -f "$outputdir/$base.mp4" ]; then
			mv "$outputdir"/"$base".mp4 "$final_dir"/"$base".mp4 &
		fi
	fi
}

main () {
	count=$(ls -1 *.mkv 2>/dev/null | wc -l)
	if [ "$count" == 0 ]; then
		echo "No files to transcode in this directory"
		exit 1
	fi

	final_dir=$(realpath "$final_dir")
	mkdir -p "$final_dir"
	choose_ffbin

	# Check if we want to work with files on a temp dir
	check_if_copy_to_dir "$final_dir"

	for video in *.mkv; do
		if [[ $copy2dir = true ]]; then
			cp -v "$video" "$tmpdir"
			if ! [[ $? -eq 0 ]]; then
				echo "An error ocurred while copying the video file to '$tmpdir'."
				echo "Make sure you have read/write permissions"
				cleanup
				exit 1
			fi
		fi

		base=$(basename "$video" .mkv)
		mkdir -p "$subsdir"/.subs

		echo ""	

		# Extract fonts embedded in the mkv file. Ensures effects are rendered properly
		extract_fonts
		# Try to select the subtitle language
		extract_subs
		# Try to select the audio language
		select_audio_stream
		# Determine if transcoding the audio is necessary
		check_audio_transcode
		# Transcode the file
		transcode
		# Remove the mkv from the temp dir and move the MP4
		move2final_dest
		rm -rf "$tmpdir"/.fonts
	done

	cleanup
	echo "All done!"
	exit 0
}
# End functions
#
# Process arguments
subname=""
while [ "$1" != "" ]; do
	case "$1" in
		-l | --list)
			shift
			if [ -f "$1" ]; then
				list_subs "$1"
			elif [ "$#" -eq 0 ]; then
				echo "$0: No file specified."
				echo ""
				print_usage >&2
				exit 2
			else
				echo "$0: $1 is not a valid file" >&2
				exit 2
			fi
			exit 0
			;;
		-c | --copy2ram)
			copy2dir=true
			;;
		-w | --write2ram)
			write2dir=true
			;;
		-d | --ramdir)
			shift
			if [ -d "$1" ] && [ "$#" -gt 1 ]; then
				tmpdir="$1"
			elif [ "$#" -eq 1 ]; then
				echo "$0: No output directory specified."
				echo ""
				print_usage >&2
				exit 2
			elif [ "$#" -eq 0 ]; then
				echo "$0: No temporary directory specified."
				echo ""
				print_usage >&2
				exit 2
			else
				echo "$0: $1 is not a valid directory" >&2
				exit 2
			fi
			echo
			;;
		-f | --force)
			always_transcode=true
			;;
		-v | --videoParams)
			shift
			video_params="$1"
			;;
		-u | --audioParams)
			shift
			audio_params="$1"
			;;
		-p | --otherParams)
			shift
			other_params="$1"
			;;
		-s | --subLang)
			shift
			subs_lang="$1"
			;;
		-a | --audioLang)
			shift
			audio_lang="$1"
			;;
		-n | --subName)
			shift
			subname="$1"
			;;
		-h | --help)
			print_usage
			exit
			;;
		*)
			if [ "$#" -eq 1 ]; then
				if [ "$1" != "" ]; then
					final_dir="$1"
				else
					echo "$0: No output path specified."
					echo ""
					print_usage >&2
					exit 2
				fi
			else
				echo "$0: '$1' invalid argument."
				echo ""
				print_usage >&2
				exit 2
			fi
			;;
	esac
	shift
done

# Execute
main
