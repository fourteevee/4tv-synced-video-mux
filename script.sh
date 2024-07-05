#!/bin/bash

# Define an array with the video files
videos=(*.mp4)
valid_videos=()
target_height=1080
target_width=1920
max_videos_per_row=4
fps=30

# Function to check if a file is a valid video
is_valid_video() {
  ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1" > /dev/null 2>&1
}

# Check each video for validity
for video in "${videos[@]}"; do
  if is_valid_video "$video"; then
    valid_videos+=("$video")
  else
    echo "Skipping invalid video file: $video"
  fi
done

# Create filter_complex argument for ffmpeg
filter_complex=""
inputs=""
base_offset=0

# Calculate the offsets and create the filter_complex string
for ((i=0; i<${#valid_videos[@]}; i++)); do
  creation_time=$(ffprobe -v quiet -print_format json -show_entries format_tags=creation_time "${valid_videos[i]}" | jq -r '.format.tags.creation_time')
  offset=$(date -d "$creation_time" +%s)
  if [ $i -eq 0 ]; then
    base_offset=$offset
  fi
  offset=$(($offset - $base_offset))
  inputs+="-i ${valid_videos[i]} "
  filter_complex+="[$i:v]scale=$target_width:$target_height,fps=$fps,setsar=1,setpts=PTS-STARTPTS+${offset}/TB[v$i];"
done

# Concatenate videos in groups of max_videos_per_row
group_index=0
row=""
rows=()
row_count=0
video_count=0

for ((i=0; i<${#valid_videos[@]}; i++)); do
  row+="[v$i]"
  ((video_count++))
  
  if ((video_count == max_videos_per_row)) || ((i == ${#valid_videos[@]} - 1)); then
    filter_complex+="${row}hstack=inputs=$video_count[vstack$group_index];"
    rows+=("[vstack$group_index]")
    group_index=$((group_index + 1))
    row=""
    video_count=0
  fi
done

# Stack the rows vertically
final_stack=""
for ((i=0; i<${#rows[@]}; i++)); do
  final_stack+="${rows[$i]}"
done

filter_complex+="${final_stack}vstack=inputs=${#rows[@]}[v]"

# Run ffmpeg command
ffmpeg $inputs -filter_complex "$filter_complex" -map "[v]" -r $fps output.mp4
